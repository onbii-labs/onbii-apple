# Milestone 1: I Am Not Losing This

The Apple proving ground should implement the first capture-certainty loop for Onbii.

## Initial Scope

- macOS start/stop capture around meetings or desktop audio where practical.
- macOS import of existing audio files.
- Apple Watch start/stop recording and transfer.
- Simple iPhone record/import/receive flow.
- Shared `.onbii` bundle creation.
- Original recording preservation.
- Basic transcript and rough speaker turns.
- Human-readable Markdown facet.
- Basic metadata: title, date, location where available, source, people, and object identity.
- Basic provenance for derived artefacts.
- User-controlled archive storage.
- Ordinary inspection or lightweight preview.

## Current Implementation Slice

The first slice establishes:

- `OnbiiCore`, containing the draft logical manifest and validation;
- `OnbiiArchive`, containing a staged, non-overwriting directory bundle writer;
- preservation of imported source audio plus an inspectable Markdown facet;
- explicit import and rendering provenance;
- a SwiftUI macOS development app with archive selection, audio import, progress
  and error state, and Finder reveal;
- explicit, visibly active microphone start/stop capture through a separate
  `OnbiiCapture` boundary, converging on the same bundle writer;
- validated in-app inspection for imported packages and packages opened from
  Finder;
- preservation of staged microphone audio before its temporary source is
  removed, with failure recovery reporting;
- macOS audio import and microphone recording as the first acquisition slices.
- one-action macOS call capture preserving system output and microphone as
  separate source tracks;
- explicit on-device English transcription with timestamped JSON and Markdown
  artefacts, conservative cross-track echo suppression, and atomic bundle
  enrichment;
- a compile-verified iPhone producer shell for explicit microphone capture,
  Files audio import, local Files-visible bundle storage, and package sharing;
- an Apple Watch companion with explicit record/stop, Watch Connectivity
  transfer of the original recording, and retry when the iPhone is unreachable;
- unified AAC (`.m4a`) capture across macOS, iPhone, and Watch (see spec
  [Decision 0029](../spec/docs/decisions/0029-compact-audio-originals.md)).

## Known Milestone Gaps

- Source-role labels such as `Microphone` and `System audio` are track
  attribution, not speaker turns. Rough speaker turns remain unmet (true
  diarization stays post-Milestone-1).
- Transcription quality is uneven across languages, because two recognisers are
  in play. `AppleOnDeviceTranscriber` prefers `SpeechTranscriber`, the newer
  long-form model, and falls back to `DictationTranscriber` for locales
  `SpeechTranscriber` does not yet cover — Dutch among them. Dutch therefore
  works, but through the older dictation path and at noticeably lower quality.
  Nothing to fix here until Apple adds the language to the newer stack; the
  fallback is the right behaviour in the meantime.
- Location and known-people metadata are not yet captured.
- The human-readable `content.md` still reads "Transcription pending" after a
  successful transcription; the transcript lives in a separate `transcript.md`.
- The iPhone and Apple Watch flows are implemented but still require
  physical-device validation, including the Watch → iPhone transfer path and
  iCloud appearance.
- Longer desktop sessions, timing drift, and additional audio routes need
  broader validation.

After rudimentary iPhone and Watch parity, mid-sentence language changes and
genuine “who said what, when” speaker attribution are the next core processing
priorities. They are not treated as polish on the Apple Speech spike.

See the [Milestone 1 Bundle Profile](../architecture/milestone-1-bundle-profile.md)
and [macOS Capture And Import
Direction](../architecture/macos-capture-import-direction.md).

## Spec Context

See [`../spec/docs/MILESTONE_1_BREAKDOWN.md`](../spec/docs/MILESTONE_1_BREAKDOWN.md) and [`../spec/docs/IMPLEMENTATION_ARCHITECTURE.md`](../spec/docs/IMPLEMENTATION_ARCHITECTURE.md).
