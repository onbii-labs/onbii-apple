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

The app should use a system open panel for the source and a user-selected local
or iCloud Drive folder for the archive. It should remember access using
security-scoped bookmarks where sandboxing requires it. Import must copy the
source; it must not move or modify the user's original file.

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

## Target And Dependency Direction

The future `OnbiiMac` Xcode app target should depend on:

- `OnbiiCore` for the logical model;
- `OnbiiArchive` for bundle writing and reading;
- a later `OnbiiCapture` target for explicit live acquisition;
- a later `OnbiiTranscription` target for replaceable transcription providers.

The first app target should not be generated until its signing identity,
sandbox model, entitlements, and minimum deployment target are recorded. The
Swift libraries and import flow can be validated independently in the meantime.

## Immediate Follow-Up

1. Add an Xcode macOS app shell and archive-folder selection.
2. Wire audio import to `OnbiiImportRequest` and `OnbiiBundleWriter`.
3. Add a bundle reader/inspector and Finder reveal.
4. Add a visible microphone capture prototype.
5. Run a ScreenCaptureKit feasibility spike before choosing the first
   meeting/system-audio capture promise.
6. Add on-device transcription as a separate processing stage.
