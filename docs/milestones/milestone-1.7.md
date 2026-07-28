# Milestone 1.7: A Walk Is One Thing

Status: Captured, not scoped. Nothing here is being built yet, and
[Milestone 1.5](milestone-1.5.md)'s always-ready strand resumes first.

[Milestone 1.6](milestone-1.6.md) made capture honest: when a recording stops
without being asked to, the app says so and loses nothing. Field test 2 confirmed
it on a real walk — and in confirming it, showed what honesty is not enough for.

A walk was interrupted after nineteen minutes because Apple Fitness announced a
kilometre split. Onbii preserved everything, notified, and stopped cleanly. That
is the right behaviour and it is still the wrong outcome: Fitness announces a
split every kilometre, so an hour's reflection walk becomes six objects, cut at
arbitrary points, none of them the thing that happened.

A person went for one walk. They should get one object.

## Why this is its own milestone

It is capture-architecture work on three platforms, and it needs its own field
test. Bolting it onto 1.6 would mean shipping the thing 1.6 exists to prevent —
a capture change nobody has walked with.

It also cannot be built until 1.6 is done, for a reason worth stating: **the
interruption is only tractable because the app now notices it.** The notification
that reported the split is the same signal segmented continuation would resume
from. Milestone 1.6 built the sensor; this uses it.

## The use case, unchanged

The long solo walk-and-talk — someone walking, talking through ideas so they can
stop holding them, and linking them later. It is
[a primary case](milestone-1.6.md#the-use-case-that-raises-the-stakes), and it is
the one this milestone exists for. Every decision below should be read against a
person who is a kilometre from home with a thought they do not want to lose.

## Two halves, doing different jobs

They are not alternatives and the difference matters.

### 1. Segmented continuation — general, and admittedly not great

When another app takes the audio session, keep the object open and start a **new
`source` resource** when the session comes back, rather than ending the
recording.

- The walk stays one object. Each stretch of audio is preserved as its own
  original with its own `captureStartedAt`.
- The gap is declared by construction — it is the space between one resource
  ending and the next beginning. Nothing is mixed, appended or inferred.
- Onbii is already shaped for this. Dual-source call capture already puts two
  `source` resources in one object; `OnbiiTranscriptionRun` already transcribes
  every audio source and merges them onto one timeline by `captureStartedAt`
  offset; `OnbiiImportRequest` already takes an array of sources. A walk
  interrupted three times is the same shape as a call with two legs. What is
  missing is the capture side: noticing an interruption ended, reclaiming the
  session, and starting the next segment.

**What it explicitly is not.** Appending across the seam into one file is not
available: it makes a discontinuous recording look continuous and silently shifts
every timestamp after the join. That is a source lying about itself.

**And it is a mitigation, not a solution.** The audio during the interruption is
gone — whatever was said while Fitness was speaking is not recoverable by any
means. Segmentation makes the loss honest, bounded and inspectable. It does not
prevent it. It earns its place by working for *every* interruption, including the
ones nothing can anticipate: a phone call, Siri, an alarm.

### 2. A reflection walk mode — specific, and removes the cause

The other half is [Watch Capture Modes](../architecture/watch-capture-modes.md),
which field test 2 reframed. It was written to buy runtime the Watch turns out to
grant anyway; its value now is different and better.

**watchOS runs one workout session at a time.** If Onbii owns it for the duration
of a reflection walk, the Watch never offers to record an outdoor walk, so
Fitness never announces a split, so the recurring interruption does not happen at
all. What was listed there as the risk that might sink the idea is the mechanism
that justifies it.

This is also where the background-mode question finally settles. Onbii declares
no `WKBackgroundModes` and does not need to; a workout session is not a
declaration but a **feature the person chooses**, with its own UX, a HealthKit
entitlement, and a walk that actually gets saved. Taking workout runtime and
producing no workout is the dishonest version, and the note already rejects it.

**The open questions are in that note and several are load-bearing** — chiefly
whether holding the session actually suppresses the Watch's own offer, and
whether Fitness still announces splits for a workout Onbii owns. If it does, this
half is worth much less and segmented continuation carries the milestone alone.

## What this milestone should be careful about

- **It must not make Onbii a fitness app.** Saving a workout is what makes the
  claim true; it is not a feature to grow. The moment this note starts discussing
  pace or heart rate, it has drifted.
- **Segmentation must not become mixing.** The temptation to produce one
  continuous file for convenience will recur. Two preserved originals and a
  declared gap is the honest shape; a mixdown is derived data with its own
  provenance and never a replacement (`0003`, and Milestone 1's writer
  invariants).
- **Recording stays explicit** (`0023`). A reflection-walk mode is a thing a
  person starts, not something that begins because they went outside.
- **A segmented object must read correctly everywhere.** `content.md`, Quick
  Look, the transcript view and any future CLI all need to present a walk with
  three segments as one walk with a gap in it, not as a broken object.

## Deliberately not in this milestone

- **Recovering the interrupted audio.** It does not exist.
- **Pausing the *workout* to protect the recording.** Onbii does not get to
  decide what other apps do.
- **Automatic situation detection**, which belongs with
  [Capture Situations And Processing](../architecture/capture-situations-and-processing.md).
- **The recognition-treatment stage** from the same field test. Different thread,
  different evidence, same note.

## Verification

The gate is a walk, as it was for 1.6, and it has one job: **an hour outdoors
with the workout prompt accepted, producing one object.** Success is a single
object whose segments account for the whole hour, with each gap matching an
interruption the app reported at the time.

Written up per [the field-test conventions](../field-tests/README.md), as field
test 3.
