# Watch Capture Modes

Status: Direction. Not scoped, not built, and gated on a measurement.

## The problem

An Apple Watch app has no runtime once it stops being frontmost unless it holds
a sanctioned claim on one. The first field test lost twenty-five minutes of a
walk to exactly that: watchOS offered to record an outdoor walk, attention moved
to the Workout app, Onbii was suspended, and the recorder stopped without anyone
noticing. See [Milestone 1.6](../milestones/milestone-1.6.md).

Making the app honest about that is 1.6's job. Giving it a legitimate claim on
the runtime is this note's.

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

## The risk that decides the shape

**watchOS runs one workout session at a time.** If Onbii holds one, the Watch's
own offer to record an outdoor walk becomes a conflict rather than a
coincidence — and that offer is precisely what killed the first field test's
recording. Whichever session starts second displaces or is refused.

So the person cannot have Onbii's reflection walk *and* the Workout app's walk.
That is not obviously bad: if Onbii saves the workout, the walk is still
credited, by Onbii instead of by Apple's app. But it means Onbii is writing
fitness data, which is a role this project would rather not take on, and it must
not silently cost someone the walk they thought they were recording.

Untested, and testable in the same walk that answers the runtime question:

- Does starting an Onbii session block, or get blocked by, the Workout app?
- What actually lands in Health when the session is saved?
- Does `.mindAndBody` credit differently from `.walking`?
- Does audio recording survive inside a workout session at all?

## The gate

None of this is scoped until one number is known: **how long a Watch recording
survives today, with no new entitlement at all.** That is Spike A in
[Milestone 1.6](../milestones/milestone-1.6.md).

- If the answer is around twenty minutes, a stated limit is a perfectly good
  answer for now, and this becomes a deliberate enhancement.
- If it is a couple of minutes, the Watch is effectively broken for the use case
  that matters most, and this becomes urgent.

Design the UX after that number exists, not before.
