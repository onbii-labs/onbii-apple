# Milestone 1.5: Ready To Show

Milestone 1 proved the capture-certainty loop. Milestone 1.5 turns that loop into
something presentable enough to put in front of early users as a public alpha —
product, not new capability. See the spec roadmap:
[`../spec/docs/ROADMAP.md`](../spec/docs/ROADMAP.md).

## Initial Scope

From the roadmap:

- a defined visual identity — app icon and colour scheme — applied consistently;
- a real, browsable home on desktop and iPhone: the objects in the archive, their
  state, and settings, rather than a bare capture screen;
- clear visual indicators of an object's status at a glance;
- on macOS, a menu-bar service that is always at the ready;
- an explicit offer to record when a chosen application becomes active
  (never hidden or automatic capture — see spec Decision 0023);
- background processing of new recordings and files on the desktop;
- the same presentable home and status view on iPhone;
- no change to the object format; the person's archive stays the source of truth.

## Status Against The Roadmap

| Roadmap requirement | State |
|---|---|
| A defined visual identity — icon and colour scheme — applied consistently | **Done** |
| A real, browsable home on desktop and iPhone: objects, their state, settings | **Done** |
| Clear visual indicators of an object's status at a glance | **Done** |
| The same presentable home and status view on iPhone | **Done** |
| No change to the object format; the archive stays the source of truth | **Held** |
| A macOS menu-bar service that is always at the ready | Deferred |
| An explicit offer to record when a chosen application becomes active | Deferred |
| Background processing of new recordings and files on the desktop | Deferred |

Beyond the roadmap, one gap found while using it: transcription could be started
on iPhone but the result could not be read without leaving the app. A transcript
reader was added on both platforms.

The milestone is therefore **half delivered**. What remains — the menu-bar
service, the activation prompt, background processing — is the "always-ready"
strand, and it is a coherent second slice rather than leftovers.

## Current Implementation Slice

The identity and home half:

- **`OnbiiUI`**, a new shared presentation package holding the eleven adaptive
  colour sets, the Prata display face, the status badge, the brand mark, and the
  shared empty state. See
  [Visual Identity](../architecture/visual-identity.md) for why the design layer
  is split between a package and per-app catalogs.
- **App icons on all three targets**, and a Champagne accent colour that reaches
  the Watch with no Swift change at all.
- **`OnbiiObjectStatus`** in `OnbiiArchive` — status derived from the manifest at
  read time (`transcribed` / `awaitingTranscription` / `sourceOnly`), paired in
  the UI with session-only `OnbiiObjectActivity` for what the app is doing right
  now. This also resolved a real inconsistency: three call sites previously
  disagreed about whether `transcript-markdown` on its own counted as a
  transcript, so an object could be offered "Transcribe" after it had been
  transcribed.
- **`OnbiiArchiveIndex`** in `OnbiiArchive` — one best-effort listing of `.onbii`
  objects across archive directories, replacing hand-rolled enumeration on
  iPhone and filling a gap where macOS had no listing at all.
- **macOS**: a `NavigationSplitView` home — searchable object sidebar with status
  and the archive path always visible, a detail pane for the selected object,
  capture and import in the toolbar with a compact status pill, and a real
  `Settings` scene for the archive and the transcription language.
- **iPhone**: objects are now browsable — each row carries a status badge and
  pushes to a detail view; capture sits in a persistent bottom bar; the language
  picker moved out of the object list into a Settings sheet; pull-to-refresh
  re-reads the archive.
- **Quick Look**: the accent on section sub-headers and a named type scale, with
  no package dependency added to the sandboxed extension.
- **Apple Watch**: a full Forest brand field with a Watch-specific solid-fill
  mark. The mark is the one place the artwork diverges by platform, because a
  pale colour needs area to read on a small screen — see
  [Visual Identity](../architecture/visual-identity.md).
- **A transcript reader**, on both platforms. Transcription could be started but
  its result could not be read without leaving the app. `OnbiiTranscriptView`
  reads the derived transcript back as speaker turns with timestamps, falling
  back to the human-readable `transcript.md` when the structured artefact is
  absent. It states when the transcript was generated, that the sources were
  unchanged, and that speaker labels are opaque per-object groupings rather than
  people — numbered for reading, never showing the internal diarization label.
  On both platforms the transcript sits directly under the title, with details
  and resources folded away.

## Known Milestone Gaps

The remaining roadmap bullets are deliberately not in this slice:

- the macOS **menu-bar service**;
- the **application-activation prompt** that offers to record when a chosen app
  becomes active;
- **background processing** of new archive files (for example auto-transcription),
  and with it a filesystem watcher — the macOS home currently refreshes after
  every write, on archive selection, at window appearance, and on ⌘⇧R.

Carried over from Milestone 1 and still open: physical-device validation of the
iPhone and Watch capture paths, and the quality gap between the two recognisers
(Dutch works, but through the older dictation model until Apple adds it to
`SpeechTranscriber`).

Two brand items are with the designer rather than the code: the wordmark's `ii`
stems still carry the pre-correction copper, and the slogan lockup uses values
outside the palette. Neither is used in the apps — only the icon, the mark and
the wordmark on the iPhone launch screen are.

Verification notes, including how to re-check the app icon after artwork changes,
are in [Visual Identity](../architecture/visual-identity.md).
