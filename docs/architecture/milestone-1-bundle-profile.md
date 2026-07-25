# Milestone 1 Bundle Profile

Status: Provisional implementation profile

This document defines the first format implemented by `onbii-apple`. It is a
learning vehicle for Milestone 1, not a normative Onbii specification.

The shared specification intentionally leaves the exact `.onbii` package
representation, manifest format, and identifier scheme open. This profile makes
the smallest reversible choices needed to build and test a real producer.

## Boundaries

The first Swift package exposes two libraries:

- `OnbiiCore` describes the logical object, resources, and provenance.
- `OnbiiArchive` writes the provisional directory-backed representation.

Capture, import UI, transcription, and archive selection stay outside these
libraries. A source adapter hands normalized input to `OnbiiArchive`.

## Physical Representation

The initial Apple implementation writes a directory with an `.onbii` extension:

```text
Imported Recording.onbii/
  manifest.json
  content.md
  source/
    recording.m4a
```

Call capture preserves the two independently acquired originals:

```text
Conversation.onbii/
  manifest.json
  content.md
  source/
    system-audio.caf
    microphone-audio.m4a
```

After transcription and speaker turns, derived facets are added and the content
view is regenerated to present the transcript:

```text
Conversation.onbii/
  manifest.json
  content.md          # regenerated to present the transcript
  transcript.md       # readable, timestamped, speaker-attributed transcript
  derived/
    transcript.json   # machine-readable transcript + merged timeline + speaker turns
  source/
    system-audio.caf
    microphone-audio.m4a
```

The macOS app exports `org.onbii.bundle` as a package type for the `.onbii`
extension. Finder therefore presents the directory as one knowledge object.
People can still inspect its ordinary files using **Show Package Contents**.
This Finder presentation does not decide whether the eventual cross-platform
container is directory-backed, ZIP-backed, or supports both.

The writer stages the complete directory beside its destination and moves it
into place after the manifest validates. It refuses to replace an existing
bundle.

The reader validates the manifest and confirms every declared resource exists
before presenting the object. A malformed manifest or incomplete bundle is
reported as an error rather than partially presented as trustworthy.

JSON is used because it is inspectable, deterministic to encode, and supported
without dependencies. This does not decide the future shared manifest format.

## Draft Manifest

The `0.1.0-draft` manifest records:

- an opaque stable object identity;
- object type, title, and creation time;
- explicit resource IDs, roles, paths, media types, sizes, and original names;
- optional capture start and duration metadata on live source resources;
- optional capture context — location (coordinates plus a best-effort place
  name) and the source application(s) for system-audio captures (see spec
  decision `0030`);
- provenance events with actions, agents, inputs, outputs, and timestamps.

Resource paths must be safe bundle-relative paths. Provenance may only refer to
resources declared by the same manifest.

New objects currently receive UUID identifiers. Readers must treat the value as
opaque because the shared identifier scheme remains open.

## Initial Import Result

File import:

1. copies the original audio bytes into `source/`;
2. writes a basic `content.md` that exposes metadata and a transcription-pending
   state;
3. records separate `imported` and `rendered` provenance events;
4. writes and validates `manifest.json`;
5. moves the staged bundle into the user-selected archive.

The placeholder Markdown is deliberately not presented as a transcript. It is
regenerated to present the transcript once one exists (see below).

## Transcription And Speaker Turns

Transcription is an explicit, on-device action that enriches an existing object
without touching its sources. It:

1. transcribes each source track on-device;
2. derives rough speaker turns by clustering voices — opaque, per-object labels
   (`Speaker 1`, `Speaker 2`; see spec decision `0031`), never merged across
   capture legs (see `rough-speaker-turns.md`);
3. writes `derived/transcript.json` (per-track results plus a merged, timestamped,
   speaker-attributed timeline) and a readable `transcript.md`;
4. regenerates `content.md` to present the transcript instead of the pending
   placeholder, recording the speaker model as provenance;
5. appends a `transcribed` provenance event linking the source inputs to the
   derived outputs.

Every change goes through the same validated, atomic whole-bundle replacement as
the writer. Diarization is best-effort: if voices cannot be separated the
transcript falls back to honest track labels rather than inventing speakers, and
a failure never prevents producing the transcript.

## Initial Call-Capture Result

The dual-source prototype records the global system-output mix through a Core
Audio tap while recording the default microphone independently. The writer
stores both files under `source/`, records each source's start time and duration,
and links both to one `captured` provenance event.

The files are not mixed during capture. This keeps the remote/application leg
and local microphone leg available for later alignment, transcription, and
speaker-turn work. Their timing metadata is sufficient for the first prototype;
sample-clock drift and long-session alignment remain to be validated.

A later processing stage should produce an aligned transcription input as a
derived resource. Most transcription engines will benefit from a conventional
mixdown; a multi-track container remains an option for providers that can use
channel separation. Either form must retain provenance back to both originals
and must not replace them.

## Deferred Questions

This profile does not settle:

- ZIP or other cross-platform container representations;
- the normative manifest schema or media-type registration;
- the final object identifier scheme;
- checksums and durability/fsync guarantees;
- resource revisions and protected human edits;
- external source references for media that cannot be embedded;
- sync conflicts and concurrent editing.

These should be informed by real Milestone 1 bundles before being promoted into
the shared specification.
