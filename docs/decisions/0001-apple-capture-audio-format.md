# 0001: Capture Audio As AAC On Every Apple Platform

Status: Accepted

Date: 2026-07-24

## Context

The Apple apps capture microphone audio as the preserved original source of an
`.onbii` object. Until now the iPhone and Mac recorded compressed AAC (`.m4a`),
while the Apple Watch used a bespoke `AVAudioEngine` tap that wrote uncompressed
16-bit linear PCM WAV.

The Watch is the most constrained device and the only one that must ship its
recording elsewhere — over Watch Connectivity to the iPhone — before the shared
archive pipeline can create the object. Yet it produced the largest files:
16-bit mono PCM is roughly 10–15× larger than AAC (~5.5 MB/min versus
~0.4 MB/min), which lengthens the transfer, drains battery, and delays the point
at which a recording is safely off the Watch. That works against capture
certainty.

Onbii's requirement is only that the *original recording is retained* so it can
be transcribed and reprocessed later — including possible future paralinguistic
analysis (intonation, mood, stress). There is no requirement for lossless
originals. "Small enough, good enough, and uniform" serves the product better
than per-platform formats.

## Decision

Record microphone audio as AAC in an `.m4a` container on every Apple platform
(iOS, macOS, watchOS) through one shared `AVAudioRecorder` configuration:

- format `kAudioFormatMPEG4AAC`
- 44.1 kHz sample rate
- mono
- `AVAudioQuality.high` (≈ 64–96 kbps)

The Watch's bespoke `AVAudioEngine` / PCM / WAV recorder is removed in favour of
the same `AVAudioRecorder` path the iPhone and Mac already use. Source resources
carry media type `audio/mp4`.

## Consequences

- Watch recordings shrink ~10–15×, transferring to the iPhone faster and using
  less battery and storage — improving capture certainty.
- A single recording code path across platforms: less code, one provenance and
  processing story, and removal of a fragile hand-written WAV writer (and its
  latent tap-buffer-lifetime bug).
- The retained original is lossy. This is acceptable for transcription and is
  expected to stay good enough for later reprocessing, provided the quality is
  not lowered further and derived steps never re-encode the original.
- The `high` / 44.1 kHz / mono settings are a deliberate floor chosen to
  preserve prosody and voice-quality cues for future analysis, not the minimum
  that would merely satisfy transcription.
- If a later capture mode needs richer signal — e.g. spatial or multi-microphone
  capture on an iPhone Pro to map who spoke where in a room — it can define its
  own format for that specific mode without changing this default.
