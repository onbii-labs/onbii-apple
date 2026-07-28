# Milestone 1.5: Ready To Show

Status: **Feature-complete, 28 July.** Every roadmap requirement is built. What
remains is a device pass over the always-ready half and two brand items with the
designer — see *What Is Left*.

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
| A macOS menu-bar service that is always at the ready | **Done** |
| An explicit offer to record when a chosen application becomes active | **Done** |
| Background processing of new recordings and files on the desktop | **Done** |

Beyond the roadmap, one gap found while using it: transcription could be started
on iPhone but the result could not be read without leaving the app. A transcript
reader was added on both platforms.

The milestone was **half delivered** for three days: the identity-and-home half
shipped on 25 July, and the always-ready half — menu-bar service, activation
prompt, background processing — landed on 28 July once
[Milestone 1.6](milestone-1.6.md) had made the pieces it needed possible.

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

**The watcher was a precondition, not a nice-to-have** — background processing
cannot process what it never notices, and field test 2 showed the Mac does not
notice. It is now built; see *What Is Left*.

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

## What Was Left, And What Still Is

The four that were not in the first slice, in the order they depend on each
other. All four are built; what each one refuses to do is usually the part worth
reading.

**1. A watcher on the archive — done.** `OnbiiArchiveWatcher` in `OnbiiArchive`
reports that the archive may have changed; the apps re-read when it does. It
carries no objects and holds no state about them, so `OnbiiArchiveIndex` remains
the only thing that reads and the filesystem remains the truth every time it is
asked. Deleting it would cost freshness and nothing else.

It picks its mechanism by inspection rather than configuration, because an
archive is not always one kind of place. Where the app has its **own ubiquity
container** and the archive is inside it, `NSMetadataQuery` is right: it is the
only API that reports an item that exists but has not been downloaded, which is
the state an object is in shortly after another device made it. Everywhere else a
directory watch is right. Reports are coalesced over a short quiet period,
because iCloud narrates a single arriving object as a stream of progress updates.

**The test is the app's container, not "is this iCloud Drive"** — and getting
that wrong broke the Mac completely for an afternoon.
`NSMetadataQueryUbiquitousDocumentsScope` searches the app's own container, and
the Mac app has none: it holds no `ubiquity-container-identifiers` entitlement
and reaches iCloud Drive purely as a user-selected folder through a
security-scoped bookmark. A ubiquitous query there is a query over nothing. It
never fired, so a recording that arrived from the iPhone was never noticed —
which is the exact bug the watcher was built to fix, reintroduced by the watcher.

The iPhone does have the container, so it uses the query. Both are covered by
falling back on what the app can actually see.

The second half of the same finding went with it: `OnbiiArchiveIndex` used to
skip a folder it could not read, which is right for a damaged object and wrong
for one still arriving. `contents(in:)` now returns both lists, the apps ask
iCloud for anything present but not downloaded, and both say *"N objects are
still arriving from iCloud"* rather than quietly presenting an incomplete list as
a complete one.

Both apps also re-read on becoming active, as a backstop that needs no
mechanism at all. The iPhone did **not** do this before — an earlier version of
this note claimed it did, and it only re-verified the recorder. A Watch recording
can be preserved while the app is suspended or launched in the background, before
the archive has even been resolved, so the reload that happens on receiving it
can be a no-op; nothing looked again until someone pulled to refresh.

**2. Background processing of new archive files — done.** An object that arrives
while Onbii is running gets transcribed without being asked, in the language the
person chose, with the choice recorded on the result (`0033`).

What it will not do is the more important half, and all of it is a rule rather
than a tuning choice:

- **Only what arrives.** The first read of the archive records what is there and
  queues none of it. Opening the app once must not begin transcribing an archive
  somebody built up over months; working through a backlog is a deliberate act.
- **Only a first transcript.** `0032` makes a second one safe — it supersedes and
  retains — but it also says reprocessing is deliberate, and safe is not the same
  as permitted.
- **Never the same silence twice.** An object already transcribed and found empty
  carries a `found-nothing` event, so it is not queued again. This is 1.6 paying
  for itself: without that record, every re-read would queue the same quiet walk
  forever.
- **Never a permission prompt on Onbii's own initiative.** If speech recognition
  has not been authorised, the queue is dropped rather than a dialog raised for
  work nobody asked for.
- **Always yielding.** It waits for any capture, import or transcription a person
  started themselves, and it holds a `ProcessInfo` activity while it runs so App
  Nap does not throttle a twenty-minute recording.

The rule for what needs work is `OnbiiManifest.awaitsFirstTranscript` in
`OnbiiArchive`, so it is one definition and tested. A Settings toggle turns the
whole thing off, and each finished object sends a notification, because the
premise is that nobody was watching.

**3. The macOS menu-bar service — done.** A `MenuBarExtra` alongside the window,
not instead of it: the window is the inspector, the menu bar is the always-ready
capture surface. Starting a recording never requires finding an app first, which
matters because a conversation does not wait while somebody hunts through Mission
Control.

It is a view over the same view model, not a second app — one archive access, one
set of security-scoped bookmarks, one answer to what Onbii is doing. The menu-bar
icon itself shows the recording state, because an app that is recording and does
not look like it is the failure Milestone 1.6 is named for. Closing the window no
longer means quitting; the menu-bar item brings it back.

**4. The application-activation prompt — done.** Naming an application in
Settings means Onbii *offers* to record when it starts playing audio. It posts a
notification with a Record button and does nothing else: ignoring it records
nothing, and there is no buffer anywhere in the app to record retrospectively
from even if someone wanted it.

Spec decision
[`0023`](../spec/docs/decisions/0023-no-hidden-retrospective-recording.md) is the
design rather than a constraint on it — "contextual detection may suggest
capture, but actual audio capture should be explicit". Three consequences worth
keeping:

- **The notification action is the only route from a suggestion to a recording.**
  A delegate that started on delivery rather than on the press would quietly turn
  a suggestion into surveillance.
- **A notification rather than an alert**, because an alert would steal focus
  from the application the person just switched to.
- **An ignored offer stands for half an hour** before the same application asks
  again, and nothing is offered while a capture, import or transcription is
  already running.

**The trigger is audio, not activation, and that was a correction.** The first
build offered whenever a watched application became frontmost, which meant being
asked on launch and on every glance. A window sitting open is not a conversation;
a window making sound usually is. `OnbiiAudioProcessProbe` — already built for
dual-source call capture — is polled every five seconds, and a watched
application has to be producing output audio across two consecutive polls before
anything is offered, so a single notification chime does not count as a meeting.

That also removed a dependency that was never confirmed: whether
`NSWorkspace.didActivateApplicationNotification` reaches a sandboxed app. It is
no longer used.

**The suggestion is a notification, so it needs permission to exist at all.**
Asked when watching starts rather than only when a capture does — the first build
asked in the wrong place, and setting up a watched application without ever
having recorded left the feature silently doing nothing. Settings now says so
when notifications are off, with a shortcut to the switch.

The Settings wording is part of the feature: someone reading it must come away
certain that naming an application does not mean Onbii is listening while it is
open.

### Still outstanding

**A device pass over the rest of the always-ready half.** The menu bar and the
capture suggestion have now been used and corrected. Two things still have not
been watched working: whether an `NSMetadataQuery` on the iCloud container
reports an object arriving from iPhone, and whether background transcription
picks up a Watch recording as it lands.

**Sweeping the archive**, inherited from 1.6: running `OnbiiObjectRepair` across
everything rather than offering it one object at a time. Background processing
now provides the place for it to live. Related and deliberately separate:
transcribing the *backlog*, which automatic processing pointedly does not do —
an explicit "transcribe everything not yet transcribed" is the honest shape.

**Whether `OnbiiNotifier` becomes a shared package.** The condition 1.6 set has
been met — the desktop background-processing caller now exists, and so does the
capture-suggestion one. It is still app-local; the decision can now be made on
evidence rather than deferred.

**Done, with the branding pass:** the app targets are renamed `OnbiiMac` /
`OnbiiIOS` → **`Onbii`**, with `PRODUCT_MODULE_NAME` unchanged so no Swift module
name moved and no source file needed touching. XcodeGen names a target's product
file reference after the target, so a target called `OnbiiMac` producing
`Onbii.app` was the last thing making Xcode "correct" the generated projects on
open — the recommended-settings and `LastUpgradeCheck` half went in `ab32529`.
The Watch target keeps its name: it is embedded rather than installed. Bundle
identifiers, schemes and directory names are all unchanged.

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
