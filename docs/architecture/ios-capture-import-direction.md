# iPhone Capture And Import Direction

Status: Milestone 1 implementation direction

## Purpose

The first iPhone app is a narrow producer of the same `.onbii` objects as the
macOS app. It is not a second archive model, transcription service, or durable
database.

Its Milestone 1 responsibilities are:

- explicit start/stop microphone recording;
- audio import through the Files picker;
- original-source preservation through `OnbiiArchive`;
- basic inspection of locally created objects;
- sharing an object onward as one package.

## Local archive

The initial archive is `Documents/Onbii Archive` inside the app container.
`UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` expose the
Documents area through Files under **On My iPhone → Onbii**.

iOS does not provide the same persistent arbitrary-folder security-scoped
bookmark used by the macOS app. This local Documents boundary gives the first
phone producer durable storage that is visible to the user without pretending
that sync has been designed. A future iCloud container or explicit transfer
workflow can change the archive location without changing the logical object
or shared writer.

## Capture and import flow

Both acquisition paths converge on the shared writer:

```text
iPhone microphone capture --\
                             -> OnbiiImportRequest
Files audio import ----------/   -> OnbiiBundleWriter
                                 -> Documents/Onbii Archive
```

Microphone capture configures an iOS spoken-audio session, remains visibly
active until stopped, and writes a temporary M4A. The temporary file is removed
only after the bundle preserves it successfully. Import retains the source
file's extension and MIME type.

The provenance source agent distinguishes `iPhone microphone capture` from
`iPhone Files import`.

## Processing boundary

The phone does not transcribe in this first slice. A package shared or synced
to the Mac can use the already-proven processing boundary there. This keeps
the initial phone work focused on capture certainty while allowing a later
mobile transcription decision to consider multilingual and speaker-aware
engines instead of duplicating the English-only spike.

## Validation boundary

The target and its shared dependencies are compile-checked against the iOS
Simulator SDK. Microphone permission, real recording, Files visibility, package
sharing, and source preservation still require validation on a physical
iPhone.

## Next mobile step

The Watch surface should record explicitly and transfer its original audio and
capture metadata to the phone. The phone should then normalize that transfer
through the same `OnbiiImportRequest` path rather than introducing a
Watch-specific bundle format.
