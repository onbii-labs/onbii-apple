# Watch Capture Modes

Status: Direction, and the reason for it has changed. Gathered into
[Milestone 1.7](../milestones/milestone-1.7.md).

## The problem — restated after field test 2

This note was written to solve a runtime problem, and **that problem does not
exist.** [Field test 2](../field-tests/2026-07-28-field-test-2.md) recorded for
nineteen minutes on the wrist with no `WKBackgroundModes` declared at all,
through app switches and through the Workout app starting mid-walk. The Watch
grants an ordinary app enough runtime to record a walk.

What actually ends a recording is **another app taking the audio session**. On
that walk it was Apple Fitness announcing the first split — and it will do that
roughly every kilometre, so on a longer walk the recording is cut again and
again.

That relocates this note's value entirely. A reflection-walk mode is not a way to
buy runtime the Watch already gives. It is a way for Onbii to **own the walk**,
so the Workout app never offers to record one and never speaks over the
recording. It removes the cause instead of surviving it.

The original problem statement, kept because the reasoning below was built on it:
an Apple Watch app was assumed to have no runtime once it stopped being
frontmost. The first field test lost twenty-five minutes of a walk and that was
read as watchOS suspending an unentitled app. It was the Workout app all along.

## What was considered and rejected

**`WKExtendedRuntimeSession` with `.mindfulness` or `.selfCare`.** Tempting,
because a system whose purpose is to let someone stop holding thoughts in their
head has some claim on that territory. Rejected on the merits: those session
types are shaped around a bounded, stationary practice — meditation, a breathing
exercise — and a reflection walk is neither. They also cap out well short of a
long walk. Stretching the definition to fit would be exactly the kind of claim
this project should not make.

**A workout session for something that is not a workout.** Declaring
`workout-processing` to keep recording at a desk is taking runtime under a
description that is not true. Rejected for the same reason.

## The direction

Two modes, distinguished by what the person is actually doing, and honest in
both cases.

**A short note.** Stationary — at a desk, cooking, standing still. Bounded, on
the order of ten minutes. No workout claim, because there is no workout. This
mode lives inside whatever runtime the Watch grants an ordinary app, and the
honest thing is to state that limit up front rather than discover it.

**A reflection walk.** The person is walking, deliberately, to think. Onbii owns
an `HKWorkoutSession` for the duration, records the audio, **and saves the
workout**. The claim is true because a walk is happening, and saving it is what
makes it true rather than a pretext — a session that takes workout runtime and
produces no workout is the dishonest version.

The framing, in the words that prompted this:

> Onbii supports intentional reflection walks. The user explicitly starts a
> session on Apple Watch, records thoughts during the walk, and ends the session
> when finished. Onbii preserves the user's chosen audio and processes it later
> into private, user-owned notes and connections.

That avoids a medical claim, avoids pretending a walk is silent meditation, and
takes a platform-native reason for a long-lived session. It is also, notably, a
**feature** rather than a plist entry: a mode a person chooses, with its own UX,
a HealthKit entitlement, usage descriptions, and a write path.

### `.walking` or `.mindAndBody`

Unresolved, and there is a genuine tension.

`HKWorkoutActivityType.walking` is the most literal and least arguable claim
while someone is walking, and it produces the Health record a person actually
wants for a walk. But people stop and sit on a bench and keep talking, and a
walking workout recorded stationary is the wrong claim.

`.mindAndBody` matches the purpose — walking reflection, a decompression walk —
and is robust to the bench. It is a softer claim, and it likely credits
differently in Health.

## The exclusivity, which is now the point rather than the risk

**watchOS runs one workout session at a time.** This note originally listed that
as the risk that might sink the idea. Field test 2 turned it into the argument
for it: if Onbii holds the session, the Watch never offers to record an outdoor
walk, so Fitness never announces a split, so nothing interrupts the recording.
The exclusivity *is* the mechanism.

The cost is unchanged and still real. The person cannot have Onbii's reflection
walk *and* the Workout app's walk. If Onbii saves the workout the walk is still
credited — by Onbii rather than by Apple's app — but that means Onbii writes
fitness data, a role this project would rather not take on, and it must never
silently cost someone the walk they thought they were recording.

**Answered by field test 2:**

- *Does audio recording survive inside a workout session at all?* **Yes.** A
  Fitness-owned outdoor walk ran alongside an Onbii recording for the rest of the
  walk with the microphone live throughout. Only the spoken split announcement
  interrupted it, and that is audio output, not the workout.
- *Does starting an Onbii session block, or get blocked by, the Workout app?*
  Still untested — but the walk showed the two coexist when Fitness owns the
  session, which is the easier half of the answer.

**Still untested:**

- What actually lands in Health when Onbii saves the session?
- Does `.mindAndBody` credit differently from `.walking`?
- Does holding the session actually suppress the Watch's own walk offer, or does
  it appear anyway?
- Does Fitness still announce splits for a workout Onbii owns? If it does, the
  mechanism above fails and the mode is worth much less.

## Where this sits now

The gate this note waited on — how long a Watch recording survives with no
entitlement — was answered by field test 2, and the answer removed the urgency
rather than creating it. Nothing here is a fix for a broken thing.

It is now one half of [Milestone 1.7](../milestones/milestone-1.7.md), whose
other half is segmented continuation. The two do different jobs and both are
needed: segmented continuation handles *any* interruption and cannot be avoided,
this removes the one predictable, recurring interruption on the walk that matters
most.

Design the UX against the questions above once they have answers, not before.
