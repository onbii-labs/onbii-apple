# Milestone 1.5: Ready To Show

Status: **Half delivered, resumed 28 July.** The identity-and-home half shipped;
the always-ready half is what remains. See *What Is Left* for the order
it should be built in.

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

**Paused 27 July, resumed 28 July.** The first field test
([27 July 2026](../field-tests/2026-07-27-field-test-1.md)) found that the loop
was presentable but not yet honest, and the work that answers it changes the
object format — which this milestone explicitly says it does not do. That work
became [Milestone 1.6](milestone-1.6.md), which is **complete**. This strand is
live again.

On the "no change to the object format" row: it still reads **Held** for this
milestone's own work. The format did change — retained generations, configuration
in provenance, a `found-nothing` event — but that was 1.6's declared job under
decisions `0032` and `0033`, and separating the two is exactly why 1.6 exists as
its own milestone rather than as more of this one.

## What Milestone 1.6 Changed For This Strand

Worth reading before picking the next item up, because three of these turn a
"deferred" bullet into something substantially easier and one of them adds a
hazard that did not exist before.

**Background processing is now mostly assembly.** It was previously blocked on
something structural: the transcribe → diarize → render → attach run lived inside
each app's view model, so there was no way to run it without a window. It is now
`OnbiiProcessing.OnbiiTranscriptionRun`, an ordinary library call. What is left is
deciding *when* to call it, not how.

**macOS already knows how to stay awake.** 1.6 gave capture a
`ProcessInfo.beginActivity(.userInitiated)` so App Nap and idle sleep cannot stop
a recording. Background transcription wants the same assertion for the same
reason, and the pattern is in the repository rather than to be invented.

**The notification question is now live.** 1.6 deliberately kept `OnbiiNotifier`
app-local, with the stated condition: *don't build an `OnbiiNotifications`
package before the desktop background-processing user exists.* That user is this
strand. Processing that happens without a window is useless if it cannot say it
finished — so this is the point to decide, not to keep deferring.

**Repairing the whole archive belongs here.** `OnbiiObjectRepair` exists and is
offered per object. 1.6 explicitly deferred sweeping the archive to "the desktop
background-processing strand that Milestone 1.5 still owes". That is this.

**An empty result is expressible.** Processing that runs unattended will
sometimes recognise nothing. It can now record that as a `found-nothing` event
rather than either failing or writing an empty transcript, which is what makes
unattended processing safe to leave running.

**The hazard: automatic reprocessing is not the same as automatic processing.**
Reprocessing now *supersedes and retains* (`0032`), which makes a second run safe
where it used to be destructive — but `0032` also says reprocessing is deliberate,
and `0023`'s spirit is that Onbii does not do things to a person's knowledge
because it felt like it. Background processing should therefore transcribe
objects that have **no** transcript and stop there. Anything that would create a
second generation needs someone to ask for it. This is a constraint on the
feature, not a detail of it.

**The watcher is a precondition, not a nice-to-have.** Background processing
cannot process what it never notices, and field test 2 showed the Mac does not
notice. See the gap below.

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

## What Is Left

These were not in the first slice, and they are what is left to build. In the
order they depend on each other:

**1. A watcher on the archive.** The macOS home currently refreshes after every
write, on archive selection, at window appearance, when the window becomes active
again, and on ⌘⇧R. The activation refresh was added after
[field test 2](../field-tests/2026-07-28-field-test-2.md), where an object made on
a walk was missing from a freshly launched window. It is not the whole answer,
because a window left in front for an hour still will not notice — and background
processing cannot process what it never notices, which is why this comes first.

The archive is an iCloud container, so the right instrument is an
`NSMetadataQuery` rather than a local filesystem watcher: a filesystem watcher
reports nothing until a remote object has already materialised, and an object
that exists but has not been downloaded is precisely the case that needs
handling. It should also stop the listing silently skipping an object it can see
but cannot read — `OnbiiArchiveIndex` swallows an unreadable bundle today, which
is right for a corrupt folder and wrong for one that is still arriving.

**2. Background processing of new archive files.** Transcribing what arrives,
without a window. Constrained as described above: first transcript only, never an
automatic second generation. It needs a `ProcessInfo` activity while it runs, a
way to say what it did when nobody is looking, and a rule for what happens when
the machine is on battery or the person is mid-recording.

**3. The macOS menu-bar service.** Always at the ready, which is the roadmap's
phrase and the point of the strand: capture should not require finding a window.
This is also where a background-processing indicator naturally lives.

**4. The application-activation prompt** that *offers* to record when a chosen
app becomes active. Never hidden and never automatic — spec decision
[`0023`](../spec/docs/decisions/0023-no-hidden-retrospective-recording.md) governs
this one directly, and the offer is the feature.

**Also owed here, inherited from 1.6:** sweeping the archive with
`OnbiiObjectRepair` rather than offering it one object at a time, and deciding
whether `OnbiiNotifier` becomes a shared package now that a second real caller
exists.

Carried over from Milestone 1 and **now closed**: physical-device validation of
the iPhone and Watch capture paths. Two field tests did it in conditions no desk
run reproduces — [27 July](../field-tests/2026-07-27-field-test-1.md) and
[28 July](../field-tests/2026-07-28-field-test-2.md).

Carried over and **worse than it was written**: the gap between the two
recognisers. The original note said "Dutch works, but through the older dictation
model until Apple adds it to `SpeechTranscriber`", which is right about the
mechanism. Field test 2 measured the consequence: on quiet audio
`DictationTranscriber` returns *nothing* where `SpeechTranscriber` returns words —
on the same file, in the same language. It does not degrade, it goes silent, and
Dutch is on it permanently. That belongs to the recognition thread
([Capture Situations And Processing](../architecture/capture-situations-and-processing.md)),
not to this milestone, but it matters here for one reason: **unattended
background transcription would produce silent empty results for Dutch objects
without anyone watching.** The `found-nothing` record is what keeps that
inspectable.

Two brand items are with the designer rather than the code: the wordmark's `ii`
stems still carry the pre-correction copper, and the slogan lockup uses values
outside the palette. Neither is used in the apps — only the icon, the mark and
the wordmark on the iPhone launch screen are.

Verification notes, including how to re-check the app icon after artwork changes,
are in [Visual Identity](../architecture/visual-identity.md).
