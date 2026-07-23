# Architecture

Apple-specific architecture notes for the Milestone 1 proving ground.

Current implementation direction:

- [Milestone 1 Bundle Profile](milestone-1-bundle-profile.md)
- [macOS Capture And Import Direction](macos-capture-import-direction.md)

Open questions still to answer here:

- Which macOS audio capture path is practical for the first meeting-oriented prototype?
- What should the start/stop capture surface feel like on macOS?
- Should the first transcript path use Apple on-device capabilities directly, and where should future third-party or server processing settings live?
- How should Apple Watch recordings transfer into the Onbii object flow?
- What should the simple iPhone record/import/receive flow include?
- Where should the user's first Onbii archive live by default on Apple platforms?
- What permissions, entitlements, and user-facing consent flows are required for capture, location, and transcription?
- How should human corrections be represented before full versioning is designed?
