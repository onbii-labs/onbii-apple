# Milestone 1.6: It Doesn't Lie To Me

Milestone 1 proved the capture-certainty loop and
[Milestone 1.5](milestone-1.5.md) made it presentable. The first field test —
[27 July 2026](../field-tests/2026-07-27-field-test-1.md) — found that it was not
yet honest.

Two of that test's five findings are failures of honesty rather than capability.
The app claimed to be recording for twenty-five minutes while watchOS had it
suspended, and a manifest recorded `durationSeconds: 0` for a twenty-minute
source. An object was permanently degraded by a language guess nobody made and
nothing disclosed. A person should be able to say:

> "If it says it recorded, it recorded. If it got something wrong, it tells me,
> and I can do it again."

## Why this is its own milestone

Milestone 1.5's roadmap entry says, in its own words, "none of this changes the
object format, and the user's own archive remains the source of truth." Spec
decisions [`0032`](../spec/docs/decisions/0032-reprocessing-supersedes-and-retains.md)
and [`0033`](../spec/docs/decisions/0033-derived-results-record-their-configuration.md)
require format-level work — retained generations, supersession in provenance,
configuration recorded in the manifest. That cannot sit inside 1.5 without
contradicting what 1.5 is.

Milestone 1.5 is **paused with its always-ready strand intact** — the menu-bar
service, the application-activation prompt, and desktop background processing —
not abandoned. Those resume after this.

## The use case that raises the stakes

The long solo walk-and-talk is a **primary** case, not an edge case: someone
walking, talking through ideas so they can stop holding them, and linking them
later. That is the vision's "it is in there, I can deal with it later, and I will
not lose it," almost word for word.

It makes silent capture death on the Watch the worst failure Onbii has, and it
is the reason the watchOS runtime question is the first thing to answer rather
than the last.

## Scope

### Delivered

**Capture records what is true.**

- `OnbiiBundleWriter` re-derives `durationSeconds` from the file it just
  preserved, overriding whatever capture reported. A disagreement is returned to
  the caller as an `OnbiiSourceDurationMismatch` and surfaced in both apps rather
  than silently corrected. Measurement never blocks preserving a source.
- `OnbiiMicrophoneRecorder` observes what it previously did not: an
  `AVAudioRecorderDelegate`, `AVAudioSession.interruptionNotification`, and
  media-services resets, published as an `interruptions` stream. Its `duration`
  stops reporting `0` once a recording ends — it holds the last value read while
  genuinely running.
- `verifyStillRecording()` is the answer to the failure that actually happened. A
  suspended process cannot notice its own suspension; no callback runs, no timer
  fires. All three apps call it on becoming active, which is the first honest
  opportunity.
- An interruption preserves what reached the file and says so. It is never a
  reason to discard audio.
- **The iPhone declares `UIBackgroundModes: [audio]`.** A recording has to
  survive the ordinary things people do while talking: a screen that locks
  itself, and looking something up mid-conversation. Without it the system
  suspends the app and the recorder stops — which is why the 09:02 recording is
  44 seconds long. Onbii's use of the mode is literal, and recording stays
  explicit (`0023`).
- **macOS holds a `ProcessInfo` activity for the length of a capture.** There is
  no background mode to declare there, but there are two ways to stop a
  recording that look exactly like the mobile failure: App Nap throttling an app
  that is no longer frontmost, and the machine reaching its idle sleep timer
  while two people are still talking. `.userInitiated` prevents both. The
  display is still allowed to sleep, and closing the lid still sleeps the
  machine — no assertion changes that.

**Derived results can be made again, and say what made them.**

- `OnbiiProcessing`, a new library holding `OnbiiTranscriptionRun` — recognise →
  diarize → render → attach. This existed twice, once in each app's view model,
  and the copies had drifted. It is the *processing pipeline* stage the shared
  principles already name.
- Reprocessing supersedes (`0032`). `canTranscribe` no longer treats a transcript
  as terminal; a second run retains the first. See
  [the bundle profile](../architecture/milestone-1-bundle-profile.md#retained-generations)
  for the layout, which stays provisional under `0025`.
- Derived results record their configuration (`0033`):
  `OnbiiDerivationConfiguration` on the provenance event carries the language or
  languages, whether they were chosen or detected, and the model identity. On the
  event rather than the resource, so a retained generation keeps what it was made
  with.
- The transcription language is remembered instead of silently resetting to the
  system language each launch, and it is chosen **on the object** rather than
  only in Settings — which language a recording is in is a property of the
  recording, and switching between a Dutch note and an English one should not
  mean a trip to Settings. The transcript view states what the transcript
  assumed and what earlier generations assumed.

**Objects can be corrected, not only regenerated.**

- `OnbiiObjectRepair` re-derives what an object records *about itself* and fixes
  what its own contents contradict: a duration the preserved audio disproves, a
  place name that was never resolved. This is distinct from supersession —
  `0032` governs derived *results*, and there is no earlier generation of a
  duration to retain, only a wrong number. The correction is recorded as a
  `corrected` provenance event, and `content.md` is regenerated so the readable
  facet stops repeating what was wrong (retaining what it used to say, since a
  rendering *is* a resource).
- It only fills gaps and corrects demonstrable falsehoods. A place name already
  present is never replaced: a person may have typed it, and `0010` requires that
  reprocessing never displaces a human edit.
- Deliberate, never automatic. An object offers the correction and says what is
  wrong; it is not rewritten because someone opened it.
- Verified against a copy of the real 08:02 object: `durationSeconds: 0` became
  1200.098, `"name": ""` became "Breda, Netherlands", and its `content.md` went
  from `Location: 51.5810, 4.7777` to the named place — with the transcript still
  current and both earlier generations intact.

**Smaller findings.**

- Empty is absent for best-effort fields. `OnbiiLocation.resolvedName` is the one
  definition; the geocoder filters each fallback for emptiness rather than only
  the first, which is what let `""` short-circuit a working chain.
- `OnbiiTranscriptTurns` is the single turn shaping, replacing two copies that had
  each grown the same bug. An unplaced word now joins its neighbouring turn
  instead of appearing as a speaker called "Recording"; track labels are reserved
  for transcripts with no diarization, where they are the truth.
- The windower gives the embedder a wider *audio* range around a too-short
  window, bounded by the neighbouring words so it only ever borrows silence.

### Still to do

Gated on evidence, not on effort:

- **An honest limit on the Watch.** Find what a recording actually survives
  today (Spike A), then say it before recording rather than after: state the
  limit, tap the wrist as it approaches, stop cleanly with everything preserved.
  The Watch's Info.plist is authored now so `WKBackgroundModes: [audio]` can be
  declared if it turns out to help; nothing is declared until it is measured.
  Giving the Watch a *longer* claim on runtime is a feature, not a declaration —
  see [Watch Capture Modes](../architecture/watch-capture-modes.md) — and is not
  in this milestone.
- **Confirmation that the iPhone and Mac claims hold in practice.** Both are
  declared and correct on paper. Spike B measures whether a locked phone and a
  napping Mac actually keep recording — the declaration is the prerequisite for
  that measurement, not a substitute for it.
- **System notifications** for capture interruption and for a Watch recording
  that has not reached the iPhone. In-app honesty landed; reaching a pocketed
  phone did not.

## The spikes

### A. How long does a Watch recording actually survive?

One question, and everything else waits on its answer:

> **How long does a Watch recording survive today — with nothing declared, and
> with `WKBackgroundModes: [audio]`?**

The extended-runtime session types (`.mindfulness`, `.selfCare`) are off this
spike: they describe a bounded stationary practice, which a reflection walk is
not, and stretching them to fit would be the kind of claim this project should
not make. `HKWorkoutSession` is off it too — it is the right answer for a
*walking* session, and it is a feature rather than a declaration, so it belongs
to [Watch Capture Modes](../architecture/watch-capture-modes.md) and not here.

What is left is small:

| Config | What it tests |
|---|---|
| Nothing declared | What the Watch grants an ordinary app today. Reproduces the field-test failure, and a run that does *not* touch the workout prompt also answers whether 1200 s was a ceiling or just when the Workout app took over |
| `WKBackgroundModes: [audio]` | On iOS this is the answer. On watchOS the audio mode has historically been playback-oriented — verify, do not assume |

The instrument is one number per run: file-measured duration against wall-clock
elapsed. The writer provides the first half for free, and an interrupted capture
now announces itself.

**Reading it out of the Watch's logs does not work. Do not spend time on it.**
Tried on 27 July: `devicectl diagnose` fails with an opaque
`DiagnoseError error 0` even with the Developer Disk Image mounted, and
`log collect --device-udid` fails with *Device not configured*, because it
expects a USB-attached device and a Watch only ever connects over a network
tunnel. An on-device sysdiagnose retrieved through the paired iPhone remains
theoretically possible, and is more work than the experiment below, which answers
the question directly.

**First result, 27 July evening: the Watch records in the background with no
declaration at all.** The shipped binary contains no `WKBackgroundModes` — it was
deliberately left out — and the microphone stays live after leaving the app, with
the system's own recording indicator visible. Invoking Siri and setting a timer
did not stop it, and tapping the indicator returns to Onbii.

That contradicts part of the field test's diagnosis, which reasoned that with no
declared mode "watchOS was entitled to suspend it". Entitled, perhaps; it does
not appear to exercise the entitlement immediately. The observed fact this
morning was 1200.098 s of audio and then nothing — and the alternative
explanation the record already offered, that the Workout app took over, is now
the more likely one.

So the question narrows again, and the honest form of it is:

> Does the Watch keep recording indefinitely, or until something else claims the
> microphone or the runtime?

**The measurement**, because the app is now the instrument: an interrupted
capture announces itself and the preserved object records the true duration. One
run is enough — no need to bisect, the file says where it stopped.

1. Start a recording on the Watch.
2. Press the Digital Crown to leave the app, or drop the wrist.
3. Wait — and, on a walk, **let the workout prompt do whatever it wants**. That
   is the variable now, not the clock.
4. Return to Onbii and stop.

The Watch must be running a build that reports interruptions. Its build number is
the check, which is why it was bumped away from 1 — an experiment run against the
old build fails silently and looks exactly like the app failing to report.

**If it survives a walk with the workout running**, the Watch needs no new claim
on runtime, `WKBackgroundModes` stays undeclared, and
[Watch Capture Modes](../architecture/watch-capture-modes.md) becomes a
genuinely optional feature rather than a fix. **If the workout kills it**, that
is the specific thing to solve, and it is exactly the collision that note
predicts: one workout session at a time, and Onbii does not hold it.

**What it decides.** Around twenty minutes means a stated limit is a good enough
answer for now and the Watch stays useful. A couple of minutes means the Watch is
effectively broken for the use case that matters most, and
[Watch Capture Modes](../architecture/watch-capture-modes.md) stops being an
enhancement and becomes urgent.

**Either way, 1.6's answer is the same shape:** find the limit, state it before
recording rather than after, tap the wrist as it approaches, and stop cleanly
with everything preserved. An app that says "you have about four minutes left" is
honest. One that stops silently is the failure this milestone exists to remove.

### B. iPhone and Mac background capture — closed, 27 July

Both claims were declared, and both hold.

- **iPhone: confirmed working, 27 July.** A recording survives the screen
  locking and continues while the phone is closed. iOS shows its own microphone
  indicator throughout, which is a better honesty guarantee than anything Onbii
  can offer for itself — the system tells the person the microphone is live,
  independently of whether the app is telling the truth. `UIBackgroundModes:
  [audio]` does what it says on iPhone Air / iOS 26.
  *Method, for repeating it:* record, lock the screen, switch to another app,
  wait, stop, compare measured duration against wall clock.
- **Mac: confirmed working, 27 July.** A capture continues with the app in the
  background, with the system's recording indicator visible. The `ProcessInfo`
  activity holds.

  *Method, for repeating it:* record, put the window behind another app, leave
  the machine to reach its idle sleep timer, stop, compare. The lid stays open —
  closing it sleeps the machine regardless, and the app should be honest about
  that rather than pretend otherwise.

Worth noting what both platforms do for free: the system shows its own recording
indicator. That is a better guarantee than anything Onbii can offer about itself,
because it is the operating system telling the person the microphone is live,
whether or not the app is telling the truth.

## Not in this milestone: recognition quality

The field test's fourth finding — most audible speech producing no words — is
deliberately **not** scoped here, and not treated as a tuning task.

Measuring every transcribed object in the archive reframed it. The same code
produces 0% missed speech at a desk and 58–66% outdoors, on the same devices;
the ambient floor predicts the outcome and the hardware does not. That is not
"make the recogniser better", it is "one fixed processing configuration cannot
serve a walk, a desk and a table on a main road" — and it carries a warning:
tuning that single configuration against three walking fixtures would likely cost
the desk case, which currently works.

The learnings live where they belong rather than as a milestone item:

- the measurement and what it showed, in
  [the field test record](../field-tests/2026-07-27-field-test-1.md) and its
  addendum, with the scripts beside them;
- the direction it points to, in
  [Capture Situations And Processing](../architecture/capture-situations-and-processing.md).

That work is its own thing, and it starts from the architecture question rather
than from a knob.

## Deliberately not yet

- **Automatic language detection.** `0033` does not require it, and Apple's
  capability here is an assumption worth checking rather than a finding. It also
  belongs with the recognition-quality work rather than here — detecting a
  language is a determination made in the processing pipeline, the same shape as
  detecting a situation.
- **Mixed Dutch/English within one object.** The *record* can already hold
  several languages, because `0033` requires that. The technique is not built.
- **A person choosing which generation is current** — `0032` defers it.
- **Derived work recording which generation it came from** — `0032` defers it,
  but it gates Milestone 2: do not build summaries, tasks or links on transcripts
  until it exists, or they drift silently the first time a transcript is
  superseded.
- **Repairing every object at once.** The correction exists and is offered per
  object; sweeping the whole archive is a different thing, and it wants the
  desktop background-processing strand that Milestone 1.5 still owes.
- **Compressing or pruning retained generations** — `0032` is explicit that this
  is a later size optimisation and never a reason to discard.
- **Promoting the supersession layout into the spec** — `0025` is open.
- **An `OnbiiNotifications` package** — keep it app-local until there is a second
  real user for it.

## Verification

Package tests cover the writer's measurement and its refusal to let an
unmeasurable file block preservation, empty-as-absent, the embed range never
falling below the minimum or crossing a neighbouring word, unplaced words joining
their neighbouring turn while track labels survive an undiarized transcript, and
supersession end to end — earlier generation retained, declared, on disk and
provenanced; new generation at the stable path; reader still validating; retired
identifiers not counting as a transcript.

Both format changes were also run against real field-test objects copied out of
the archive rather than only synthetic ones. Supersession: the reader accepted
the object before and after, the current generation stayed at
`derived/transcript.json`, and the earlier one landed under
`superseded/<timestamp>/` with the object's own layout mirrored. Correction: the
08:02 object's `durationSeconds: 0` became 1200.098, its empty place name became
a real one, and its `content.md` stopped showing coordinates — with the
transcript still current.

What remains is device work, and the gate on this milestone is a **second field
test** — the same walk, the same conditions, written up per
[the field-test conventions](../field-tests/README.md). A green suite is not the
same as a morning outdoors.

Note that the second field test now has two jobs, and they should not be confused
in the write-up. It verifies this milestone: did the recording survive the whole
walk, and where it did not, did the app say so. It also produces fresh evidence
for the recognition-quality work, which is a separate thread. A walk where
capture holds for the full duration is the first recording that can say anything
useful about the second question.
