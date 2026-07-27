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

- **How long does a Watch recording actually survive today?** One number, and a
  lot hangs on it: whether a stated limit is a good enough answer for now, or
  whether [Watch Capture Modes](watch-capture-modes.md) becomes urgent. Needs
  measurement on a real device — or possibly just the Watch's own logs from
  27 July, which is cheaper and decays by the day. Spike A in
  [Milestone 1.6](../milestones/milestone-1.6.md).
- Does `.record` with `.measurement` recover the speech recognition is currently
  dropping? Note that this cannot be tested against the existing field-test
  fixtures — changing the audio session changes what gets recorded — so it needs
  an A/B recording protocol. And note the warning in
  [Capture Situations And Processing](capture-situations-and-processing.md):
  tuning one configuration against the worst recordings risks the desk case,
  which currently works.
- **How should processing vary with the situation an object was captured in?**
  Measured across a real archive, the same code produces 0% missed speech at a
  desk and 58–66% outdoors, on the same devices. That is an architectural
  question, not a tuning one.
- Does the Core Audio system-audio probe work reliably for the first
  meeting applications tested?
- What should the start/stop capture surface feel like on macOS? (Milestone 1.5
  put it in the window toolbar; the menu-bar service is still to come.)
- Should the macOS app become a menu-bar service, and how should the
  application-activation record prompt be presented? (Milestone 1.5, deferred.)
- Should the first transcript path use Apple on-device capabilities directly, and where should future third-party or server processing settings live?
- Where should the user's first Onbii archive live by default on Apple platforms?
- What permissions, entitlements, and user-facing consent flows are required for capture, location, and transcription?
- How should human corrections be represented before full versioning is designed?
  Partly answered for *machine* corrections: `OnbiiObjectRepair` re-derives facts
  an object records about itself and writes them under a `corrected` provenance
  event, refusing to displace anything a person could have set. What a human
  correction looks like — editing a title, fixing a speaker, rewriting a line of
  transcript — is still open.
