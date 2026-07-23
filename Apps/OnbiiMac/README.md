# OnbiiMac

The Milestone 1 macOS producer is a native SwiftUI app generated with XcodeGen.
XcodeGen 2.46 or newer is required to regenerate the project after changing
`project.yml`:

```sh
cd Apps/OnbiiMac
xcodegen generate
```

Open `OnbiiMac.xcodeproj` and run the `OnbiiMacApp` scheme.

The app lets the user choose an archive folder, import an existing audio file
through `OnbiiArchive`, and reveal the completed `.onbii` bundle in Finder.
The selected archive is retained across launches using a security-scoped
bookmark.

Explicit live capture follows as a separate capture-adapter path. The agreed
direction is documented in [macOS Capture And Import
Direction](../../docs/architecture/macos-capture-import-direction.md).
