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
  system language each launch, and the transcript view states what the transcript
  assumed and what earlier generations assumed.

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

- **Declared background runtime on watchOS.** Shape decided by the spike below.
- **Declared background runtime on iPhone** (`UIBackgroundModes`), pending the
  same measured-vs-wall-clock check.
- **System notifications** for capture interruption and for a Watch recording
  that has not reached the iPhone. In-app honesty landed; reaching a pocketed
  phone did not.
- **Recognition and capture tuning** — the largest open question, and the one
  most likely to change what people think of the product.

## The spikes

### A. watchOS background capture runtime

What, if anything, lets an Onbii Watch recording survive losing the foreground,
and for how long? The Watch declares no `WKBackgroundModes` and takes no
`WKExtendedRuntimeSession`, so watchOS was entitled to suspend it. What it
*could* claim must be measured on watchOS 27, not assumed.

One configuration per run, ~45 minutes each, with another app deliberately taking
the foreground at T+5 min. The instrument is one number: file-measured duration
against wall-clock elapsed — which the writer now provides for free.

| Config | What it tests |
|---|---|
| Nothing declared | Reproduces the 1200 s failure; a run without touching the workout prompt also answers whether 1200 s is a real ceiling |
| `WKBackgroundModes: [audio]` | On iOS this is the answer; on watchOS the audio mode has historically been playback-oriented |
| `WKExtendedRuntimeSession` `.mindfulness` | Does it start, does recording continue, what is the real cap, what happens on losing the foreground |
| `WKExtendedRuntimeSession` `.selfCare` | Same, different declared purpose |
| `HKWorkoutSession` (control) | Establishes the ceiling to compare against; not a candidate |

**On the self-care framing.** A system whose purpose is to let someone stop
holding thoughts in their head has a real claim on that territory, and for the
use case above it may be a truthful description rather than a workaround. But it
is a *positioning* claim. If it is used to justify a background mode it belongs
in the spec's decision log next to
[`0023`](../spec/docs/decisions/0023-no-hidden-retrospective-recording.md)
(recording is always explicit, never hidden), which stays true either way. The
spike reports what is grantable and what each mode costs; the positioning choice
is made deliberately, and recorded.

### B. iPhone background capture

`UIBackgroundModes: [audio]` is the well-trodden answer and almost certainly
works. The point is to have it measured with the same harness rather than
assumed: record, lock the screen, wait, stop, compare.

### C. Recognition and capture tuning

**Step zero, and it decides everything downstream:** listen to 25–44 s of the
09:02 source. Nine continuous seconds of −13 to −18 dBFS produced no words at
all. If that is intelligible Dutch, recognition is dropping real speech. If it is
traffic and chairs, the 66% figure is inflated and the question moves to the
walking recordings.

Then split by what is actually testable. The record suggests testing the
`.record`/`.measurement` change against the three fixtures; that works for the
recognition half and is impossible for the capture half, because changing the
audio session changes what gets recorded.

- **Recognition-side, testable on the fixtures.** Locale form, module choice
  (`DictationTranscriber` against `SpeechTranscriber` — worth re-checking whether
  Dutch has landed in the better model), content hints, and audio
  pre-normalisation. First run: re-transcribe 09:02 today. If the stop at 25.2 s
  does not reproduce, the original run terminated early and that is a bug in
  `AppleOnDeviceTranscriber.analyze`, not a tuning problem.
- **Capture-side, needs new recordings.** `.record` + `.measurement` against
  today's `.playAndRecord` + `.spokenAudio` + `.defaultToSpeaker`; sample rate;
  explicit input and data-source selection instead of expecting the hardware to
  help unasked. Needs an A/B protocol: same room, same people, same script, back
  to back.

What the fixtures already settle: in all three, `formattedText` word count equals
the timed-segment count exactly, so nothing is lost between the recogniser and
our extraction — the loss is inside recognition. And 08:57 produced words to
143.0 s of a 143.4 s file, so there is no fixed cutoff. Note also that 09:02's
ambient floor is 13 dB above either Watch recording, so the coverage script's
"+8 dB above floor" margin is not comparable across the two devices.

## Deliberately not yet

- **Automatic language detection.** `0033` does not require it, and Apple's
  capability here is an assumption worth checking rather than a finding. Spike C
  checks it; the decision comes after.
- **Mixed Dutch/English within one object.** The *record* can already hold
  several languages, because `0033` requires that. The technique is not built.
- **A person choosing which generation is current** — `0032` defers it.
- **Derived work recording which generation it came from** — `0032` defers it,
  but it gates Milestone 2: do not build summaries, tasks or links on transcripts
  until it exists, or they drift silently the first time a transcript is
  superseded.
- **Backfilling the three field-test objects.** Correcting a manifest fact is a
  human edit under `0010` and needs its own provenance shape. The field-test
  record preserves what they say. Now that supersession exists, repair can become
  a normal provenanced action rather than an ad-hoc rewrite.
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

Supersession was also run against a real field-test object copied out of the
archive: the reader accepted it before and after, the current generation stayed
at `derived/transcript.json`, and the earlier one landed under
`superseded/<timestamp>/` with the object's own layout mirrored.

What remains is device work. The gate on this milestone is a **second field
test** — the same walk, the same conditions, written up per
[the field-test conventions](../field-tests/README.md). A green suite is not the
same as a morning outdoors.
