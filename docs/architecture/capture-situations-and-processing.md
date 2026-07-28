# Capture Situations And Processing

Status: Observation and direction. Nothing here is decided or built.

## The observation

Onbii has one processing configuration. `OnbiiTranscriptionRun` recognises with
one recogniser, diarizes with one set of thresholds, and the capture side offers
one audio session configuration per platform. That was a reasonable place to
start, and the first field test showed it is the wrong long-run model.

Every transcribed object in one real archive, sorted by how noisy the recording
is against its own floor. Produced by
[`archive-coverage.py`](../field-tests/2026-07-27-field-test-1/evidence/archive-coverage.py),
output preserved as
[`archive-coverage.txt`](../field-tests/2026-07-27-field-test-1/evidence/archive-coverage.txt):

| Object | Captured by | Ambient floor | Speech-level | Of that, no words |
|---|---|---|---|---|
| 20260726-2349 | Apple Watch | −60.0 dBFS | 67% | 12% |
| 20260725-1448 | macOS | −58.5 dBFS | 35% | **0%** |
| 20260724-2338 | macOS | −58.3 dBFS | 77% | 17% |
| 20260725-1453 | macOS | −56.9 dBFS | 54% | **0%** |
| 20260724-2242 | macOS | −56.0 dBFS | 50% | **0%** |
| 20260726-2347 | iPhone | −53.4 dBFS | 48% | **0%** |
| 20260724-2349 | iPhone | −50.4 dBFS | 73% | 12% |
| 20260727-0802 | Apple Watch | −44.3 dBFS | 45% | **58%** |
| 20260727-0857 | Apple Watch | −42.3 dBFS | 56% | **54%** |
| 20260727-0902 | iPhone | −31.3 dBFS | 60% | **66%** |

The cliff is between −50.4 dBFS and −44.3 dBFS, and it is not gradual: 0–17% on
one side, 54–66% on the other.

**The device does not predict the outcome.** The Watch appears at both ends —
12% missed at −60 dBFS, 58% at −44. So does the iPhone: 0% at −53, 66% at −31.
The same hardware and the same code produce a usable transcript indoors and an
unusable one outdoors. What changed was the situation.

Two caveats, because the measure is imperfect. "Speech-level" is 8 dB above each
recording's *own* floor, so a noisy recording counts more traffic and wind as
speech-level and its missed figure is overstated. And a device applying automatic
gain lifts its own floor, so a high floor is not purely a property of the room —
09:02's −31.3 dBFS is partly the iPhone's input chain, not only the street.

The direction survives both caveats. The re-transcription in
[the field-test addendum](../field-tests/2026-07-27-field-test-1.md#addendum--27-july-evening-the-first-object-was-transcribed-again)
confirms it independently: 531 words across 1200 seconds is 0.44 words per
second, against the 2.3 per second the same recogniser managed in the stretches
it did cover. Real speech is being lost, not just wind being counted.

## What this asks of the architecture

A walk, a desk, a table on a terrace, and a call-centre floor are different
problems. They differ in distance to the microphone, in movement, in how many
people are speaking, in what else is making noise, and in whether the device is
worn, held, or laid down. Expecting one configuration to serve all of them is the
same mistake as expecting one language to.

That points at **processing that varies with the situation an object was
captured in**, across both boundaries:

- **Capture.** Audio session category and mode, microphone and data-source
  selection, polar pattern, sample rate. A session tuned for speakerphone is not
  the one you want for two people at a table.
- **Processing.** Which recogniser, whether to pre-normalise, voice-activity
  handling, and the diarizer's thresholds — which were tuned on real *meetings*
  and have no reason to be right for a windy walk.

The format is already most of the way there. Objects record capture context —
location and source applications, per spec decision
[`0030`](../spec/docs/decisions/0030-capture-context-location-and-application.md)
— and now record the configuration a derived result was produced under, per
[`0033`](../spec/docs/decisions/0033-derived-results-record-their-configuration.md).
`0033` deliberately constrains the *record* and not the technique, so a profile
fits without changing the format at all: an object can say which situation it was
captured in and which profile produced its transcript.
[`0011`](../spec/docs/decisions/0011-bring-your-own-components.md) means a profile
might select an entirely different provider rather than only different parameters.

## The warning this carries

**Do not tune the current single configuration against the walking recordings.**

Four objects in that table are at 0% missed. They are the desk case, and the desk
case works. Optimising one configuration for −44 dBFS outdoors, using three
fixtures from one morning, would almost certainly cost something at −58 dBFS
indoors — and the indoor case is the one in daily use. A single knob turned to
suit the worst recording is not an improvement; it is a different set of
recordings that now fail.

This is the argument for capturing the finding rather than fixing it, and for
keeping it out of Milestone 1.5 and 1.6.

## Open questions

None of these are answered, and the shape of the eventual design depends on them.

- **What is a situation?** Named by the person ("walking", "at my desk", "in a
  call")? Inferred from what the device can observe — motion, ambient level,
  which microphone, whether the screen is locked? Some of both?
- **Who chooses the profile?** Leaning, from the person whose archive this is:
  **not the user, by default.** Asking someone to classify their own acoustics
  before they talk is the friction Onbii exists to remove, and they are not the
  best judge of it anyway. The likelier shape is an **analysis stage over the
  audio itself** that determines which treatment to apply, with a manual
  override kept for advanced settings rather than put in the way. That would make
  the choice a derivation like any other — and under
  [`0033`](../spec/docs/decisions/0033-derived-results-record-their-configuration.md)
  it would be recorded as *detected* rather than *chosen*, exactly as a language
  is. Not decided; a direction to design against.
  Spec decision
  [`0023`](../spec/docs/decisions/0023-no-hidden-retrospective-recording.md) says
  capture is never hidden; whether the same standard applies to choosing how
  something is processed is a separate question, and
  [`0032`](../spec/docs/decisions/0032-reprocessing-supersedes-and-retains.md)
  already requires reprocessing to be deliberate.
**Where the analysis runs is settled, as far as this note is concerned: in the
processing pipeline, not at capture.** Analysing the preserved file can be re-run
later with better methods, needs nothing to be got right in the moment, and keeps
capture doing the one job it must not fail at. Capture stays as simple and as
robust as it can be; everything clever happens to a file that is already safe.
That also fits the shape Onbii already has — a stage between the source and the
derived result, which is what `OnbiiProcessing` is.

It leaves a real limitation, worth stating rather than discovering later: a
processing stage cannot undo a capture-side decision. If the audio session
applied speakerphone processing or automatic gain while recording, no later
analysis recovers what that removed. Choosing a *capture* profile is therefore a
separate question, and a harder one, because it has to be answered before anyone
knows what the recording will contain.
- **Does a profile span capture and processing, or are they separate things?**
  They are separate boundaries and separately replaceable, but a person thinks
  "I am going for a walk" once, not twice.
- **Does an object record the situation as a fact of the capture, or only the
  profile that was used?** The first is more useful later — it would let a better
  model reprocess old objects appropriately — and it is a claim about the world
  that Onbii would be asserting, which deserves care.
- **How would a profile be evaluated?** The archive is the test set, and
  `archive-coverage.py` is the beginning of a way to see whether a change helps
  overall or only helps one situation at the expense of another.
- **Are two languages even comparable?** Dutch is not among `SpeechTranscriber`'s
  supported locales, so it falls through to `DictationTranscriber` while English
  gets the long-form model — a gap
  [Milestone 1.5](../milestones/milestone-1.5.md#known-milestone-gaps) already
  noted and [field test 2](../field-tests/2026-07-28-field-test-2.md#2-dutch-never-gets-the-better-recogniser--known-now-measured)
  first measured on a real object. A profile tuned against Dutch fixtures is
  tuned against a different recogniser than the English ones use, and an
  evaluation that mixes them will read a model difference as a situation
  difference.

## Where this came from

The first field test, [27 July 2026](../field-tests/2026-07-27-field-test-1.md),
and the archive-wide measurement its addendum prompted.
