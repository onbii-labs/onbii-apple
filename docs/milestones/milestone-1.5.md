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

## Known Milestone Gaps

The remaining roadmap bullets are deliberately not in this slice:

- the macOS **menu-bar service**;
- the **application-activation prompt** that offers to record when a chosen app
  becomes active;
- **background processing** of new archive files (for example auto-transcription),
  and with it a filesystem watcher — the macOS home currently refreshes after
  every write, on archive selection, at window appearance, and on ⌘⇧R.

Carried over from Milestone 1 and still open: English-only on-device
transcription, and physical-device validation of the iPhone and Watch paths.

Verification notes, including how to re-check the app icon after artwork changes,
are in [Visual Identity](../architecture/visual-identity.md).
