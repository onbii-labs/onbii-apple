# Speaker-embedding Core ML model

This directory reproduces the on-device speaker-embedding model used for **rough
speaker turns** (`OnbiiCoreMLSpeakerEmbedder` in `OnbiiTranscription`). The
compiled model ships in the repo at
`Packages/OnbiiTranscription/Sources/Resources/CAMPlusEmbedder.mlmodelc`
(git-LFS). This is a build tool, not part of the app.

## What the model is

- **Architecture / weights:** 3D-Speaker **CAM++ trained on VoxCeleb** —
  ModelScope `iic/speech_campplus_sv_en_voxceleb_16k`, revision `v1.0.2`,
  checkpoint `campplus_voxceleb.bin` (Apache-2.0). ~7.2 M params. VoxCeleb
  (English/European interview speech) suits our English + Dutch use better than
  the default CN-Celeb (Chinese) CAM++.
- **Input:** raw **16 kHz mono float** waveform, fixed **48 000 samples (3.0 s)**.
  The Kaldi-fbank front end (80-mel, 25/10 ms, povey window, preemphasis 0.97,
  per-utterance mean normalization) is **baked into the Core ML graph** as a
  matmul DFT, so the Swift side only supplies samples. Validated against
  `torchaudio.compliance.kaldi.fbank` to < 6e-4.
- **Output:** a 512-d speaker embedding. Cluster by cosine distance; on the
  model's own example utterances, same-speaker distance ≈ 0.25 and
  different-speaker ≈ 1.1.

## Why the model source is patched

`convert.py` bakes the fbank in and traces the model to Core ML (`mlprogram`,
FP16). Four ops in the upstream model do not convert correctly with coremltools;
`3d-speaker-coreml.patch` rewrites them to numerically-identical, Core ML-safe
forms (verified end-to-end at cosine 1.000000 vs PyTorch):

- `Tensor.unfold` framing → strided identity `conv1d`.
- `FCM.forward` dynamic-size `reshape` → `flatten(1, 2)`.
- `statistics_pooling` `aten::std` (miscompiled) → explicit unbiased std.
- `CAMLayer.seg_pooling` `avg_pool1d(ceil_mode=True)` (silently miscompiled —
  the real bug) → constant block-average matmul.

## Reproduce

```sh
# Python 3.12; torch 2.7 pinned (coremltools frontend compatibility)
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python torch==2.7.0 torchaudio==2.7.0 coremltools numpy soundfile

git clone --depth 1 https://github.com/modelscope/3D-Speaker.git
git -C 3D-Speaker apply ../3d-speaker-coreml.patch

# checkpoint (28 MB, Apache-2.0)
curl -L -o campplus_voxceleb.bin \
  "https://modelscope.cn/models/iic/speech_campplus_sv_en_voxceleb_16k/resolve/master/campplus_voxceleb.bin"

.venv/bin/python convert.py                       # -> CAMPlusEmbedder.mlpackage (FP32) + validation

# FP16 + compile to the shipped .mlmodelc
#   (see convert.py; then: xcrun coremlcompiler compile CAMPlusEmbedder_fp16.mlpackage <dest>)
```

`convert.py` prints the fbank-vs-reference diff, the Core ML-vs-PyTorch cosine,
and the real-speech same/different distances.
