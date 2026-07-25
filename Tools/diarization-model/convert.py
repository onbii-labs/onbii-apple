"""
Convert the VoxCeleb-trained CAM++ speaker-embedding model to Core ML, with the
Kaldi-fbank front end baked into the graph (matmul DFT, no FFT op) so the Swift
side only ever supplies raw 16 kHz mono float samples. Every stage is validated
numerically against the torchaudio Kaldi reference before conversion.
"""
import math
import os
import sys

import numpy as np
import torch
import torch.nn.functional as F
import torchaudio.compliance.kaldi as K
import coremltools as ct

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "3D-Speaker"))
from speakerlab.models.campplus.DTDNN import CAMPPlus  # noqa: E402

SR = 16000
N_MELS = 80
FRAME_LEN = 400          # 25 ms @ 16 kHz
FRAME_SHIFT = 160        # 10 ms
N_FFT = 512              # next pow2 of 400
PREEMPH = 0.97
EPS = torch.finfo(torch.float32).eps  # matches torchaudio log floor


def mel_scale(f):
    return 1127.0 * math.log(1.0 + f / 700.0)


def make_mel_matrix(num_bins=N_MELS, n_fft=N_FFT, sr=SR, low_freq=20.0, high_freq=0.0):
    num_fft_bins = n_fft // 2                     # 256 (Nyquist bin excluded)
    nyquist = 0.5 * sr
    if high_freq <= 0.0:
        high_freq = nyquist + high_freq
    fft_bin_width = sr / n_fft
    mel_low, mel_high = mel_scale(low_freq), mel_scale(high_freq)
    delta = (mel_high - mel_low) / (num_bins + 1)
    bins = torch.zeros(num_bins, num_fft_bins)
    for b in range(num_bins):
        left = mel_low + b * delta
        center = mel_low + (b + 1) * delta
        right = mel_low + (b + 2) * delta
        for i in range(num_fft_bins):
            mel = mel_scale(fft_bin_width * i)
            if left < mel < right:
                w = (mel - left) / (center - left) if mel <= center \
                    else (right - mel) / (right - center)
                bins[b, i] = w
    # Pad the Nyquist column with zeros so it lines up with rfft's 257 bins.
    return F.pad(bins, (0, 1), value=0.0)         # (80, 257)


class KaldiFbank(torch.nn.Module):
    """torchaudio-Kaldi-compatible log-mel fbank via matmul DFT + mean_nor."""

    def __init__(self):
        super().__init__()
        povey = torch.hann_window(FRAME_LEN, periodic=False).pow(0.85)
        self.register_buffer("window", povey.view(1, FRAME_LEN))
        k = torch.arange(N_FFT // 2 + 1).view(-1, 1)
        n = torch.arange(N_FFT).view(1, -1)
        angle = 2.0 * math.pi * k * n / N_FFT     # (257, 512)
        self.register_buffer("dft_cos", torch.cos(angle).t().contiguous())  # (512,257)
        self.register_buffer("dft_sin", torch.sin(angle).t().contiguous())  # (512,257)
        self.register_buffer("mel", make_mel_matrix().t().contiguous())     # (257,80)
        # Framing as a strided identity conv (Tensor.unfold is not Core ML-able).
        self.register_buffer("frame_weight", torch.eye(FRAME_LEN).unsqueeze(1))  # (400,1,400)

    def forward(self, wav):
        x = wav.reshape(1, 1, -1)
        frames = F.conv1d(x, self.frame_weight, stride=FRAME_SHIFT)  # (1, 400, F)
        frames = frames.squeeze(0).transpose(0, 1)            # (F, 400)
        frames = frames - frames.mean(dim=1, keepdim=True)    # remove DC
        shifted = torch.cat([frames[:, :1], frames[:, :-1]], dim=1)
        frames = frames - PREEMPH * shifted                  # preemphasis (replicate)
        frames = frames * self.window                         # povey window
        frames = F.pad(frames, (0, N_FFT - FRAME_LEN))        # 400 -> 512
        real = frames @ self.dft_cos
        imag = frames @ self.dft_sin
        power = real * real + imag * imag                     # (F, 257)
        mel = power @ self.mel                                # (F, 80)
        mel = torch.clamp(mel, min=EPS).log()
        mel = mel - mel.mean(dim=0, keepdim=True)             # mean_nor
        return mel.unsqueeze(0)                               # (1, F, 80)


class CAMPlusEmbedder(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.fbank = KaldiFbank()
        self.model = model

    def forward(self, wav):
        return self.model(self.fbank(wav))


def main():
    torch.manual_seed(0)

    # --- Load model ---
    state = torch.load(os.path.join(HERE, "campplus_voxceleb.bin"), map_location="cpu")
    model = CAMPPlus(feat_dim=80, embedding_size=512)
    model.load_state_dict(state)
    model.eval()
    print("[ok] loaded CAM++ VoxCeleb, params:",
          sum(p.numel() for p in model.parameters()))

    fbank = KaldiFbank().eval()

    # --- Validate fbank against torchaudio Kaldi reference ---
    wav = (torch.randn(1, 3 * SR) * 0.05).clamp(-1, 1)
    with torch.no_grad():
        ref = K.fbank(wav, num_mel_bins=N_MELS, sample_frequency=SR, dither=0.0)
        ref = ref - ref.mean(0, keepdim=True)             # mean_nor
        mine = fbank(wav).squeeze(0)
    fb_diff = (ref - mine).abs().max().item()
    print(f"[fbank] shapes ref={tuple(ref.shape)} mine={tuple(mine.shape)} "
          f"max_abs_diff={fb_diff:.3e}")
    assert ref.shape == mine.shape and fb_diff < 1e-2, "fbank mismatch"

    # --- Validate combined torch model vs reference pipeline ---
    embedder = CAMPlusEmbedder(model).eval()
    with torch.no_grad():
        ref_feat = K.fbank(wav, num_mel_bins=N_MELS, sample_frequency=SR, dither=0.0)
        ref_feat = (ref_feat - ref_feat.mean(0, keepdim=True)).unsqueeze(0)
        ref_emb = model(ref_feat).squeeze(0)
        my_emb = embedder(wav).squeeze(0)
    cos = torch.nn.functional.cosine_similarity(ref_emb, my_emb, dim=0).item()
    print(f"[embed] torch-combined vs reference cosine_sim={cos:.6f}")
    assert cos > 0.9999, "combined model diverges from reference"

    # --- Trace + convert to Core ML (fixed 3.0 s window, float32) ---
    win = 3 * SR
    example = (torch.randn(1, win) * 0.05).clamp(-1, 1)
    traced = torch.jit.trace(embedder, example)
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="waveform", shape=(1, win), dtype=np.float32)],
        outputs=[ct.TensorType(name="embedding", dtype=np.float32)],
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT32,
        convert_to="mlprogram",
        compute_units=ct.ComputeUnit.CPU_ONLY,
    )
    out_path = os.path.join(HERE, "CAMPlusEmbedder.mlpackage")
    mlmodel.save(out_path)
    print("[ok] saved", out_path, "| window samples:", win)

    # --- Validate Core ML vs torch on fresh 3.0 s inputs ---
    for trial in range(3):
        w = (torch.randn(1, win) * 0.05).clamp(-1, 1)
        with torch.no_grad():
            t_emb = embedder(w).squeeze(0).numpy()
        c_emb = np.array(mlmodel.predict({"waveform": w.numpy()})["embedding"]).reshape(-1)
        c = float(np.dot(t_emb, c_emb) /
                  (np.linalg.norm(t_emb) * np.linalg.norm(c_emb)))
        print(f"[coreml] trial {trial}  coreml-vs-torch cosine_sim={c:.6f}")


if __name__ == "__main__":
    main()
