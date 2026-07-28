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

## Retained Generations

Spec decision [`0032`](../spec/docs/decisions/0032-reprocessing-supersedes-and-retains.md)
requires reprocessing to **supersede**: the newest result becomes current, and
earlier results are retained with their own provenance. It deliberately leaves
the on-disk representation open under
[`0025`](../spec/docs/decisions/0025-onbii-package-format-open.md).

This profile makes the smallest reversible choice. The incoming generation takes
the **stable path and resource ID**, and the outgoing one is moved aside into a
mirror of the object's own layout:

```text
20260727-0802 Recording.onbii/
  manifest.json
  content.md              # current
  transcript.md           # current
  derived/
    transcript.json       # current
  source/
    recording.m4a
  superseded/
    20260727T065217Z/     # what the object looked like before
      content.md
      transcript.md
      derived/
        transcript.json
```

Why this shape:

- **Current results never move.** Finder, Quick Look, Obsidian, a CLI and both
  apps go on finding the current transcript exactly where they already look,
  with no change at all. That is "applications are views" doing its job, and it
  is also how a reader tells which generation is current without guessing.
- **A retained generation is inspectable as what it was.** Opening the package
  shows the earlier object, laid out the way objects are laid out, rather than a
  pile of suffixed files.
- **No generation numbers anywhere.** Ordering is expressed by provenance
  timestamps, which the manifest already has. A `generation: 2` field would
  imply an ordering the shared specification has not settled.
- **Retired resource IDs are prefixed** (`superseded-20260727T065217Z-…`) so they
  cannot be mistaken for a current result. `OnbiiObjectStatus` matches the
  current identifiers exactly, and an object holding only superseded transcripts
  is not a transcribed object.

Provenance carries a `superseded` event whose inputs are the retired resource
IDs and whose outputs are the ones that replaced them, plus — per
[`0033`](../spec/docs/decisions/0033-derived-results-record-their-configuration.md)
— the configuration each generation was produced under, on the event that
produced it. Putting configuration on the event rather than the resource is what
makes a retained generation keep the assumptions it was made with instead of
inheriting the current ones.

Retention is the default. Compressing or pruning old generations is a size
optimisation available later and is never in itself a reason to discard.

**None of this is promoted to the shared specification.** It is one concrete
Milestone 1 profile choice, and `0025` remains open.

## Processing That Produced Nothing

Not every run has a result. A recording of a quiet walk, transcribed in the
right language by a working model, can legitimately yield no words at all —
which is what [field test 2](../field-tests/2026-07-28-field-test-2.md) found.

The object records that as a **`found-nothing`** provenance event: the action,
when it happened, the sources it read, and — the part that matters — the
configuration it ran under. It declares no resource, and its `outputResourceIDs`
are empty.

- **No empty artefact is written.** An empty `derived/transcript.json` would make
  the object claim to be transcribed, and `content.md` would show a transcript
  heading with nothing under it. Neither is true.
- **The object's status is unchanged.** It is still awaiting transcription,
  because it is.
- **The language is the useful part.** Without it, an object that has been
  through Dutch twice is indistinguishable from one nobody has opened, and the
  person is left to remember what they already ruled out. This is `0033`'s
  reasoning applied to the case where there is no result to attach it to.
- **It is not an error.** Nothing failed and nothing needs attention. An
  application that presents it as damage is describing the situation as a defect
  in the recording.

`OnbiiBundleEnricher` accepts such a request only when the caller sets
`recordsOutcomeOnly` — an enrichment that changes nothing is otherwise a caller
mistake worth surfacing rather than an empty event worth writing.

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
