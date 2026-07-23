# OnbiiMac

The Milestone 1 macOS producer is a native SwiftUI app generated with XcodeGen.
XcodeGen 2.46 or newer is required to regenerate the project after changing
`project.yml`:

```sh
cd Apps/OnbiiMac
xcodegen generate
```

Open `OnbiiMac.xcodeproj` and run the `OnbiiMacApp` scheme.

The app lets the user choose an archive folder, import an existing audio file,
explicitly start and stop a microphone recording, or start a dual-source call
capture. Every acquisition path creates a
`.onbii` bundle through `OnbiiArchive`. The selected archive is retained across
launches using a security-scoped bookmark. Completed packages can be revealed
in Finder and inspected in the app; packages opened from Finder use the same
validated inspector.

The first recording prompts for microphone permission and remains visibly
active until stopped. The captured source is staged inside the app sandbox,
removed only after it has been preserved in a completed bundle, and retained
with its path reported if bundle creation fails.

For call capture, press **Start Call Capture**. The app records the global
system-output mix to `source/system-audio.caf` and the current default
microphone to `source/microphone-audio.m4a`. It does not capture a screen or
present a screen-sharing picker. Application filtering, microphone selection,
and proactive meeting triggers are deferred. This path is a device-validation
prototype, not yet a blanket support claim for meeting applications. Its scope
and validation criteria are documented in the
[Core Audio System-Audio
Spike](../../docs/architecture/core-audio-system-audio-spike.md).
