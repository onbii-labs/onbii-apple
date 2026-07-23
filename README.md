# Onbii Apple

## Open in Xcode

Open `OnbiiApple.xcworkspace`.

This is the single development entry point for the Apple implementation. It
contains:

- `OnbiiMacApp`, the macOS producer and inspector;
- `OnbiiIOSApp`, the iPhone producer;
- the shared Swift packages;
- the Watch app when that surface is added.

The `.xcodeproj` files under `Apps/` are generated implementation details. Do
not open them directly. Regenerate a platform project from its directory with
`xcodegen generate`, then return to the root workspace.

Apple-family implementation work for Onbii.

This repository contains the macOS, iOS, and watchOS implementation surfaces, shared Apple platform packages, extensions, tools, and implementation notes for Onbii.

The shared Onbii specification is included at [`docs/spec`](docs/spec). Product direction, principles, object model, bundle model, provenance, linking, and roadmap live there.

## Current Status

This repository is just getting started.

The initial work is focused on the Apple proving ground for the first useful Onbii experience. See the spec roadmap for the current milestone context: [`docs/spec/docs/ROADMAP.md`](docs/spec/docs/ROADMAP.md).

The first implementation includes Swift libraries for the draft logical object
model and directory-backed `.onbii` bundles. The choices are documented as a
provisional Apple implementation profile, not a final shared specification:
[`docs/architecture/milestone-1-bundle-profile.md`](docs/architecture/milestone-1-bundle-profile.md).

Run the package tests with:

```sh
swift test --package-path Packages
```

## Repository Shape

```text
docs/
  spec/
  architecture/
  milestones/
Packages/
  OnbiiCore/
  OnbiiArchive/
  OnbiiCapture/
  OnbiiTranscription/
Apps/
  OnbiiMac/
  OnbiiIOS/
  OnbiiWatch/
Extensions/
  QuickLook/
  ShareExtension/
Tools/
  onbii-dev/
```

## Spec

The spec repository is included as a submodule at [`docs/spec`](docs/spec).

```sh
git submodule update --init --recursive
```

## License

Source code in this repository is licensed under the Mozilla Public License 2.0 unless otherwise noted. See [`LICENSE`](LICENSE).

The specification in [`docs/spec`](docs/spec) is licensed separately.

## Docs

Apple-specific implementation direction belongs in [`docs`](docs).

The spec should remain the source for shared product and format decisions. This repository should hold Apple-specific architecture, app target notes, platform decisions, and implementation details.
