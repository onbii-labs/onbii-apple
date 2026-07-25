# Rough Speaker Turns

Status: Milestone 1 implementation direction — implemented

This note documents how `onbii-apple` produces **rough speaker turns** (the
Milestone 1 exit criterion: *"who said what, even if speakers start as
`Speaker 1` and `Speaker 2`"*). This is an Apple-implementation choice, not part
of the `.onbii` format specification: the spec defines the object/format; how we
diarize a recording is ours to decide and revise.

## The constraint

macOS/iOS 26 ship **no on-device speaker-diarization API**. The `SpeechAnalyzer`
stack (`SpeechTranscriber`, `DictationTranscriber`, `SpeechDetector`) exposes
only `audioTimeRange` and `transcriptionConfidence` — nothing about *who* is
speaking. The only first-party acoustic signal is the legacy `SFVoiceAnalytics`
(pitch/jitter/shimmer/voicing), tied to the old recognition API we no longer use.

So diarization is something we build ourselves. The core requirement is to
recognize *that a recording contains different voices* — including several people
on a single microphone (an in-person meeting or voice note), not just separating
capture legs.

## Approach: voice-embedding diarization

We derive speaker turns from the preserved source audio with a self-contained,
on-device pipeline. It is **derived, best-effort data**: on any failure the
transcript is still produced and simply falls back to track labels; diarization
never blocks preserving a source. All logic lives in `OnbiiTranscription`
(`OnbiiSpeakerDiarization.swift`, `OnbiiCoreMLSpeakerEmbedder.swift`).

### The model

A **VoxCeleb-trained CAM++** speaker-embedding network (3D-Speaker,
`iic/speech_campplus_sv_en_voxceleb_16k`, Apache-2.0, ~7.2 M params) converted to
Core ML. VoxCeleb (English/European speech) suits our English + Dutch use better
than the default CN-Celeb variant. The Kaldi-fbank front end is **baked into the
Core ML graph** (matmul DFT, no FFT op), so Swift feeds only raw 16 kHz mono
samples; the model takes a fixed 3.0 s (48 000-sample) window and returns a
512-d embedding. It ships compiled to `CAMPlusEmbedder.mlmodelc` as an
`OnbiiTranscription` resource via git-LFS. Conversion is reproducible from
`Tools/diarization-model/` (including the four coremltools-safe model patches).

### The pipeline

Per source track, after transcription:

1. **Window** the transcript segments into speaker-analysis windows
   (`OnbiiSpeakerWindowing`): split into runs on silence longer than
   `maxGapSeconds` (1.0 s), then pool words into windows of at least
   `minWindowSeconds` (2.5 s), folding short remainders back.
2. **Embed** each window (`OnbiiCoreMLSpeakerEmbedder`): the track is loaded once
   as 16 kHz mono; each window is embedded by averaging L2-normalized embeddings
   over 3.0 s sub-windows (1.5 s hop). Core ML predictions are serialized (it can
   hand back a pooled output buffer a concurrent prediction would clobber).
3. **Cluster** the embeddings (`OnbiiSpeakerClustering.cluster`): average-linkage
   agglomerative clustering on cosine distance, merging until the nearest pair
   exceeds `distanceThreshold` (0.65). The speaker count is discovered, not
   assumed.
4. **Consolidate** (`OnbiiSpeakerClustering.consolidate`): a cluster counts as a
   real speaker only if it holds at least `max(minSpeakerWindows,
   minSpeakerFraction × windowCount)` windows (4, or 2%); every window is then
   reassigned to the nearest speaker centroid. This absorbs the noisy fragment
   clusters that raw threshold clustering leaves on conversational audio.
5. **Attribute**: each track is diarized under its own label namespace, so voices
   from different capture legs (microphone vs system-audio) are never merged —
   the strongest prior that they are different people. Speaker IDs are opaque and
   per-object (`t0s1`, `t0s2`, …). The Markdown facet renders them as
   `Speaker 1`, `Speaker 2`, … numbered by first appearance; a new block begins
   only on a speaker change, never on a pause.

Provenance: `OnbiiTranscriptDocument.speakerModel` records the embedding model
that produced the speaker turns, keeping the derived diarization distinguishable
and attributable.

## Tuning (why these numbers)

The thresholds were tuned on real recordings, not guessed. On clean read
utterances the same-speaker cosine distance was ~0.25 and different-speaker ~1.1
— a wide margin. But on **real conversational speech** the two speakers of a
single-mic recording sat only **~0.48 apart**, so the initial 0.5 threshold
shattered each speaker into ~18 fragments while 0.75 merged the two. 0.65 with
the consolidation pass resolves this, and the exact threshold becomes uncritical
across ~0.58–0.70.

The fractional floor came from a four-meeting sweep (2, 2, and 4 speakers). At
the window level the smallest *real* speaker held ~4% of windows while spurious
fragments stayed under ~1% — a consistent gap. A 2% floor (scaling with
recording length so long meetings don't accrue phantom speakers) sits centrally
in it, taking the results from 2/**4**/4 to a correct **2/2/4**.

## Known limits and future direction

- Tuned on a handful of recordings; a genuinely brief-but-distinct speaker (under
  the ~2% floor) is absorbed. This is the deliberate trade that removes
  fragments.
- No cross-object identity: `Speaker 2` here is unrelated to `Speaker 2`
  elsewhere. A later milestone adds a **person resolver** with reusable voice
  signatures and a UI to rename/**merge** speakers — mapping an object's
  `Speaker N` to a stable person as a separately provenanced step, which is why
  the IDs are kept opaque now.
- A **privacy-preserving** extension is envisaged: learn speaker signals locally
  and share only those derived signals with Onbii, never the recording.
- Re-diarizing an existing object in place is not yet supported (the app
  transcribes once); re-testing currently needs a fresh import.
