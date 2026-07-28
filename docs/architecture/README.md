# Architecture

Apple-specific architecture notes for the Milestone 1 proving ground.

Current implementation direction:

- [Milestone 1 Bundle Profile](milestone-1-bundle-profile.md)
- [macOS Capture And Import Direction](macos-capture-import-direction.md)
- [macOS App Identity And Signing](macos-app-identity-and-signing.md)
- [iPhone Capture And Import Direction](ios-capture-import-direction.md)
- [On-device Transcription Spike](on-device-transcription-spike.md)
- [Rough Speaker Turns](rough-speaker-turns.md)
- [Capture Situations And Processing](capture-situations-and-processing.md)
- [Watch Capture Modes](watch-capture-modes.md)
- [Core Audio System-Audio Spike](core-audio-system-audio-spike.md)
- [Visual Identity](visual-identity.md)

Open questions still to answer here:

- ~~**How long does a Watch recording actually survive today?**~~ **Answered
  28 July, and the premise was wrong.** A Watch recording survives losing the
  foreground indefinitely as far as
  [field test 2](../field-tests/2026-07-28-field-test-2.md) goes — nineteen
  minutes with no `WKBackgroundModes` declared, through app switches and a
  workout starting. What ends a recording is another app taking the audio
  session. The open question that replaces it is what to do about that:
  [Milestone 1.7](../milestones/milestone-1.7.md).
- **Does holding an `HKWorkoutSession` stop the Watch offering to record a
  walk — and does Fitness still announce splits over a workout Onbii owns?**
  The whole value of [Watch Capture Modes](watch-capture-modes.md) now rests on
  these two, and neither is tested.
- Does `.record` with `.measurement` recover the speech recognition is currently
  dropping? Note that this cannot be tested against the existing field-test
  fixtures — changing the audio session changes what gets recorded — so it needs
  an A/B recording protocol. And note the warning in
  [Capture Situations And Processing](capture-situations-and-processing.md):
  tuning one configuration against the worst recordings risks the desk case,
  which currently works.
- **How should processing vary with the situation an object was captured in —
  and with which recogniser is running?** Measured across a real archive, the
  same code produces 0% missed speech at a desk and 58–66% outdoors, on the same
  devices. Field test 2 added the second axis: on the same file, in the same
  language, `DictationTranscriber` returned nothing where `SpeechTranscriber`
  returned six words, and audio treatments that recovered words for one made the
  other worse. Both are architectural questions, not tuning ones.
- Does the Core Audio system-audio probe work reliably for the first
  meeting applications tested?
- ~~What should the start/stop capture surface feel like on macOS?~~ Answered by
  building it: the window toolbar for when a window is open, and a `MenuBarExtra`
  for when one is not. The menu-bar icon carries the recording state.
- ~~How should the application-activation record prompt be presented?~~ As a
  notification with a *Record* action, not an alert — an alert would steal focus
  from the application the person just switched to, and the action being the only
  route to a recording is what keeps it an offer (`0023`). Built in Milestone 1.5;
  **not yet confirmed on a device** that workspace activation notifications reach
  a sandboxed app.
- Should the first transcript path use Apple on-device capabilities directly, and where should future third-party or server processing settings live?
- Where should the user's first Onbii archive live by default on Apple platforms?
  Partly answered by building the archive watcher: iCloud is the easiest default
  but not a requirement. The macOS watcher falls back to a plain directory watch
  wherever the app has no ubiquity container, and a directory watch does not care
  what puts files in the folder — so Dropbox, Syncthing, a NAS share or an
  external disk all work. **The iPhone is the constraint**: it resolves the
  iCloud container or a local one and offers no picker, so "any shared folder" is
  real on the desktop and notional on iPhone.
- What permissions, entitlements, and user-facing consent flows are required for capture, location, and transcription?
- How should human corrections be represented before full versioning is designed?
  Partly answered for *machine* corrections: `OnbiiObjectRepair` re-derives facts
  an object records about itself and writes them under a `corrected` provenance
  event, refusing to displace anything a person could have set. What a human
  correction looks like — editing a title, fixing a speaker, rewriting a line of
  transcript — is still open.
