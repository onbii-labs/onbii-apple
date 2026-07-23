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
Conversation.onbii/
  manifest.json
  content.md
  source/
    recording.m4a
```

The writer stages the complete directory beside its destination and moves it
into place after the manifest validates. It refuses to replace an existing
bundle.

JSON is used because it is inspectable, deterministic to encode, and supported
without dependencies. This does not decide the future shared manifest format.

## Draft Manifest

The `0.1.0-draft` manifest records:

- an opaque stable object identity;
- object type, title, and creation time;
- explicit resource IDs, roles, paths, media types, sizes, and original names;
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

The placeholder Markdown is deliberately not presented as a transcript.
Transcription will later add a derived resource and its own provenance event.

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
