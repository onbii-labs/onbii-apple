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
or explicitly start and stop a microphone recording. Both acquisition paths
create a `.onbii` bundle through `OnbiiArchive`. The selected archive is
retained across launches using a security-scoped bookmark. Completed packages
can be revealed in Finder and inspected in the app; packages opened from Finder
use the same validated inspector.

The first recording prompts for microphone permission and remains visibly
active until stopped. The captured source is staged inside the app sandbox,
removed only after it has been preserved in a completed bundle, and retained
with its path reported if bundle creation fails.

This prototype records microphone input only. Meeting or desktop system audio
is not yet a supported recording path. The app includes a bounded Core Audio
process-tap probe that reports whether audible system output arrives, but
deliberately does not save it. It does not capture or present a screen-sharing
picker. Its scope and validation criteria are documented in the
[Core Audio System-Audio
Spike](../../docs/architecture/core-audio-system-audio-spike.md).
