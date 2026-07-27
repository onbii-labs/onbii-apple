# Architecture

Apple-specific architecture notes for the Milestone 1 proving ground.

Current implementation direction:

- [Milestone 1 Bundle Profile](milestone-1-bundle-profile.md)
- [macOS Capture And Import Direction](macos-capture-import-direction.md)
- [macOS App Identity And Signing](macos-app-identity-and-signing.md)
- [iPhone Capture And Import Direction](ios-capture-import-direction.md)
- [On-device Transcription Spike](on-device-transcription-spike.md)
- [Rough Speaker Turns](rough-speaker-turns.md)
- [Core Audio System-Audio Spike](core-audio-system-audio-spike.md)
- [Visual Identity](visual-identity.md)

Open questions still to answer here:

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
