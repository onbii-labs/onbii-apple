# On-device transcription spike

Status: Milestone 1 implementation direction

## Decision

The macOS proving-ground app transcribes only after an explicit user action. It
uses Apple's Speech framework with `requiresOnDeviceRecognition` enabled and
does not fall back to server recognition. If the current locale has no
available on-device recognizer, the operation fails without changing the
bundle.

This spike uses `SFSpeechURLRecognitionRequest` because the Milestone 1 app
supports macOS 14. The API gives the prototype timestamped recognition
segments while retaining that deployment target.

Milestone 1 validates English transcription using the Mac's active recognizer.
The legacy API does not provide dependable automatic spoken-language
identification, and a locale selector would not solve language changes within
one recording or sentence. Automatic multilingual recognition, code-switch
segmentation, and the choice of a suitable engine are explicitly deferred.

## Track handling

System output and microphone recordings remain separate source resources. Each
track is transcribed independently, then its word timestamps are placed on a
shared timeline using the capture start times in the manifest.

Speaker labels describe the captured source, not an inferred person:

- `system-audio`
- `microphone`
- `recording` for a single imported or captured source

These labels are track attribution only and are not diarization. The rough
speaker-turn criterion is met by a separate voice-embedding diarization pass over
the source audio — see [Rough Speaker Turns](rough-speaker-turns.md). Track
labels are the pre-diarization fallback the Markdown facet uses when a recording
has not (or could not) be diarized.

The merged text timeline conservatively suppresses probable speaker echo from
the microphone track only when at least three consecutive normalized words
also occur on the system-audio track within a narrow timing window. Short
matches remain because they may be real conversational overlap.

This heuristic is derived output handling. It never removes or rewrites source
audio.

A track on which the recognizer detects no speech produces an empty track
result rather than aborting the object. This matters for calls where only the
microphone or only the system-output recording contains intelligible speech.

## Bundle artifacts

A successful transcription atomically adds:

- `derived/transcript.json`, a machine-readable document containing the
  per-track results and merged timestamped timeline
- `transcript.md`, a readable timestamped transcript

The existing `content.md` is not rewritten. The source audio resources are
copied byte-for-byte into a staged package, the staged manifest is validated,
and the original package is replaced only after the complete staged bundle is
read successfully.

The appended provenance event records:

- action: `transcribed`
- agent: `Apple Speech on-device`
- inputs: all transcribed source resource IDs
- outputs: the JSON and Markdown transcript resource IDs

## Permission and failure behavior

The app declares `NSSpeechRecognitionUsageDescription` and requests Speech
authorization only when the user chooses **Transcribe On Device**. Progress is
shown per source track.

macOS uses a generic Speech-framework authorization message that may describe
sending audio to Apple even for on-device-only requests. Before that system
prompt, the app explains that every request requires the on-device recognizer
and that processing stops if it is unavailable. This is enforced both by
checking recognizer support and by setting `requiresOnDeviceRecognition`.

Recognition, serialization, or bundle-enrichment failures are surfaced in the
app and state explicitly that source recordings were not changed. Runtime
permission prompts, installed locale support, recognition quality, and the
resulting package still require validation on a real Mac.
