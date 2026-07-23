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
- Start Capture, initially unavailable until the capture adapter exists;
- the chosen archive location;
- an explicit progress/error state;
- Reveal in Finder after success.

## Explicit Capture

Live capture is the next acquisition path and remains separate from import.
Recording must be explicit and visibly active. There is no hidden retrospective
audio buffer.

The first capture prototype should prove microphone recording before promising
meeting/system-audio capture. Desktop/system audio needs a separate technical
spike around ScreenCaptureKit, app/audio filtering, permissions, consent, and
the behavior of major meeting applications.

Both capture paths should converge after acquisition:

```text
file import --------\
                     -> source adapter -> OnbiiArchive -> user archive
explicit recording -/
```

Capture adapters acquire live media. Source adapters normalize the acquired
file and metadata. Neither owns transcription or durable storage.

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

The app consumes `OnbiiArchive` from the sibling local Swift package rooted at
`Packages/`, which in turn depends on `OnbiiCore`. Keeping the package outside
the app project avoids an ambiguous nested-project/package workspace in Xcode.
Later work should add:

- `OnbiiCapture` for explicit live acquisition;
- `OnbiiTranscription` for replaceable transcription providers.

Development builds are signed ad hoc to run locally. The project enables the
hardened runtime, which requires a real signing identity for distribution.
Distribution signing remains open.

## Immediate Follow-Up

The development shell now provides archive-folder selection, audio import
through `OnbiiBundleWriter`, progress and error state, collision-safe bundle
names, and Finder reveal.

Next:

1. Add a bundle reader and in-app inspector.
2. Record the distributable app identity and signing decisions.
3. Add a visible microphone capture prototype.
4. Run a ScreenCaptureKit feasibility spike before choosing the first
   meeting/system-audio capture promise.
5. Add on-device transcription as a separate processing stage.
