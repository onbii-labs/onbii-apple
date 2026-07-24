# iPhone Capture And Import Direction

Status: Milestone 1 implementation direction

## Purpose

The first iPhone app is a narrow producer of the same `.onbii` objects as the
macOS app. It is not a second archive model, transcription service, or durable
database.

Its Milestone 1 responsibilities are:

- explicit start/stop microphone recording;
- audio import through the Files picker;
- receipt of original Watch recordings through Watch Connectivity;
- original-source preservation through `OnbiiArchive`;
- basic inspection of created objects;
- sharing an object onward as one package.

## Archive

The preferred archive is `Documents/Onbii Archive` in the app-owned iCloud
Drive container `iCloud.com.yepyr.onbii`. This exposes new objects through
**iCloud Drive → Onbii → Onbii Archive** and makes the same packages available
to the user's other Apple devices.

If iCloud Drive is unavailable, the app falls back to
`Documents/Onbii Archive` in its local container. `UIFileSharingEnabled` and
`LSSupportsOpeningDocumentsInPlace` expose that fallback under
**On My iPhone → Onbii**. The app also continues to list objects created in
this local fallback after iCloud becomes available.

## Capture and import flow

All acquisition paths converge on the shared writer:

```text
iPhone microphone capture --\
Files audio import -----------+--> OnbiiImportRequest
Watch microphone transfer ---/    -> OnbiiBundleWriter
                                  -> preferred archive
```

Microphone capture configures an iOS spoken-audio session, remains visibly
active until stopped, and writes a temporary M4A. The temporary file is removed
only after the bundle preserves it successfully. Import retains the source
file's extension and MIME type.

The provenance source agent distinguishes `iPhone microphone capture`,
`iPhone Files import`, and `Apple Watch microphone capture`.

## Watch transfer flow

The embedded Watch companion records explicitly to a local linear PCM audio file
in its own Documents directory. On stop it queues the original file and minimal capture metadata
with `WCSession.transferFile`. The source stays on the Watch until Watch
Connectivity reports a successful transfer.

The iPhone receiver immediately moves the temporary incoming file into its
Application Support directory before the delegate callback returns. It then
uses the shared writer to create the same `.onbii` package as every other
capture path. The staged iPhone file is removed only after that package has
been written successfully. Invalid metadata or a failed bundle write leaves
the staged source in place and reports the failure in the iPhone app.

The transfer metadata carries the capture start and duration. It does not
define a second archive format: only the iPhone creates the `.onbii` object.

## Processing boundary

The phone does not transcribe in this first slice. A package shared or synced
to the Mac can use the already-proven processing boundary there. This keeps
the initial phone work focused on capture certainty while allowing a later
mobile transcription decision to consider multilingual and speaker-aware
engines instead of duplicating the English-only spike.

## Validation boundary

The iPhone target, Watch companion, and shared dependencies are compile-checked
against their simulator SDKs, including the embedded Watch product. Microphone
permission, real Watch recording, background transfer, package creation, and
iCloud appearance still require validation on a paired physical Watch and
iPhone. Watch Connectivity does not deliver file transfers between simulators.

## Next mobile step

Validate the complete Watch-to-iPhone preservation path on paired hardware,
including delayed/background delivery and a temporarily unavailable iCloud
container.
