# macOS Capture And Import Direction

Status: Milestone 1 implementation direction

The first macOS app should be a small producer and inspector over user-owned
objects. It must not become the durable knowledge store.

## First Vertical Slice: Audio Import

File import is the first executable path because it exercises source
preservation, bundle creation, archive selection, metadata, provenance, and
inspection with controlled inputs.

The flow is:

```text
choose audio file
  -> confirm title and destination archive
  -> normalize as an import request
  -> create a draft .onbii bundle
  -> reveal the completed object in Finder
```

The app uses system open panels for the source and a user-selected local or
iCloud Drive folder for the archive. It remembers archive access across
launches using a security-scoped bookmark and refreshes the bookmark when it
becomes stale. Import copies the source; it does not move or modify the user's
original file.

The first UI can be one window with:

- Import Audio;
- Start Capture and a visibly active Stop Capture control;
- the chosen archive location;
- an explicit progress/error state;
- Reveal in Finder after success.

## Explicit Capture

Live capture is the next acquisition path and remains separate from import.
Recording must be explicit and visibly active. There is no hidden retrospective
audio buffer.

The first capture prototype records microphone input through `OnbiiCapture`.
The permission request follows an explicit user action, and the UI remains
visibly active until the user stops recording. The captured file is staged in
the app container and sent through the same bundle-writing pipeline as an
import. It is deleted only after the completed object has preserved it; on
failure, the UI reports the retained staging path.

This proves the explicit recording boundary but does not promise meeting or
system-audio capture. Desktop/system audio needs a separate technical spike
around Core Audio process taps, app/audio filtering, permissions, consent, and
the behavior of major meeting applications.

Both capture paths should converge after acquisition:

```text
file import --------\
                     -> source adapter -> OnbiiArchive -> user archive
explicit recording -/
```

Capture adapters acquire live media. Source adapters normalize the acquired
file and metadata. Neither owns transcription or durable storage.

Meeting capture has two live inputs rather than one: remote participants arrive
through the meeting application's audio output, while the local participant
arrives through the microphone. The first real meeting-capture session must
acquire both concurrently, preserve them as separate source resources, and
treat any combined mix as derived data.

## Processing

Bundle completion must not wait on advanced intelligence.

The initial import creates a safe, inspectable object with transcription marked
as pending. A later processing job should add:

- a machine-derived transcript resource;
- rough speaker-turn data when available;
- a readable Markdown projection;
- provenance naming the input, tool/model, configuration where useful, time,
  and local or external processing location.

Processing failure must leave the preserved source bundle intact and retryable.
Reprocessing must add or supersede derived resources rather than silently
overwrite human edits.

## Current Development Target

`OnbiiMac` is a native macOS 14 SwiftUI application. Its Xcode project is
generated from a checked-in XcodeGen specification.

The app has the provisional development bundle identifier
`org.onbii.OnbiiMac.dev`. It uses the App Sandbox and grants read/write access
only to locations the user selects. This identifier is not a commitment to the
eventual distribution identity.

The app consumes `OnbiiArchive` and `OnbiiCapture` from the sibling local Swift
package rooted at `Packages/`. `OnbiiArchive` depends on `OnbiiCore`, while
`OnbiiCapture` remains an acquisition boundary. Keeping the package outside the
app project avoids an ambiguous nested-project/package workspace in Xcode.
Later work should add:

- `OnbiiTranscription` for replaceable transcription providers.

Development builds are signed ad hoc to run locally. The project enables the
hardened runtime, which requires a real signing identity for distribution.
The stable development identity and the remaining distribution choices are
recorded in [macOS App Identity And
Signing](macos-app-identity-and-signing.md).

## Immediate Follow-Up

The development shell now provides archive-folder selection, audio import
through `OnbiiBundleWriter`, progress and error state, collision-safe bundle
names, Finder reveal, and a validated inspector for newly imported packages or
packages opened from Finder. It also provides explicit, visibly active
microphone capture that converges on the same bundle creation and inspection
path. A bounded Core Audio process-tap probe now tests whether audible system
output can be received without saving it.

Next:

1. Add application selection and simultaneous microphone/application-output
   capture, preserving both source tracks.
2. Validate the dual-source session with real meeting applications and common
   audio output routes.
3. Add on-device transcription as a separate processing stage.
