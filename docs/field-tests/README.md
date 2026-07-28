# Field Tests

Records of using Onbii for real, away from a development machine, and what that
use revealed.

- [Field Test 1 — 27 July 2026](2026-07-27-field-test-1.md) — a walk through a
  city and a conversation at a table. Watch and iPhone. Found silent capture
  death, a permanently mis-transcribed object, and most audible speech missing
  from the transcripts. Its addendum records the first reprocessing of a real
  object: correcting the language recovered 43% more words and was still not
  enough, which separated the language problem from the recognition one.
- [Field Test 2 — 28 July 2026](2026-07-28-field-test-2.md) — a second walk on
  the Milestone 1.6 builds. Capture held for nineteen minutes through a workout
  and announced itself when another app took the microphone, which closed the
  watchOS runtime question. Found that an empty recognition result is reported
  as a broken object, and that the Mac reads the archive once and then never
  again. Eight runs over one source established that the recogniser rather than
  the language produced the empty result, and gave a treatment stage its first
  evidence — and its first warning, since the filters that rescued one recogniser
  damaged another. It leaves one open decision: whether an interruption should
  end a recording or continue it into a new segment.

## Why these are kept

A field test is not QA. It is the only way to learn things that cannot be
produced at a desk: another app taking the foreground, a screen that locks
itself, a place the geocoder has no name for, a system language set for
something else, a road full of traffic, a conversation that does not wait.

Milestone 1 was validated on real devices and was genuinely complete. The first
walk still produced five findings in an hour, two of them serious. That gap is
the point.

These records also serve a second purpose. The objects a field test produces are
**fixtures** — real, messy, and reproducible — and they are worth more for
tuning capture and recognition than anything that can be recorded deliberately.

## How to write one

Keep it a record of what happened, not a task list. Findings become work
elsewhere: implementation direction in [`../architecture`](../architecture),
settled decisions in the spec's
[decision log](../spec/docs/decisions), scope in
[`../milestones`](../milestones).

- Name the file `YYYY-MM-DD-field-test-N.md`. State the date, the devices, and
  the real conditions.
- **Say what held.** A field test that only lists failures misreports the system.
- For each finding: what was observed, the evidence, the root cause where it was
  actually found, and what it asks of the implementation — not a patch.
- **Preserve evidence beside the record**, in `YYYY-MM-DD-field-test-N/evidence/`.
  Manifests, transcripts and measurement scripts are small, text, and reviewable.
- **Reference objects by stable object ID.** The archive is where objects live;
  a repository is a view like any other, and copying source audio here would
  make a second home for something that already has one. It would also commit
  other people's conversations to a git history they never agreed to.
- Prefer a measurement to an impression. Commit the script that produced it so
  the next test can be compared against this one.
- End by separating two different kinds of unanswered question. **Decisions**
  belong to the person whose knowledge this is; put their answer in the record
  and note where it will be formalised. **Empirical questions** belong to the
  next test, not to anyone's judgement — do not put those to a person, design a
  test for them.
