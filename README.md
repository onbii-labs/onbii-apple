# Onbii Apple

Apple-family implementation work for Onbii.

This repository contains the macOS, iOS, and watchOS implementation surfaces, shared Apple platform packages, extensions, tools, and implementation notes for Onbii.

The shared Onbii specification is included at [`docs/spec`](docs/spec). Product direction, principles, object model, bundle model, provenance, linking, and roadmap live there.

## Current Status

This repository is just getting started.

The initial work is focused on the Apple proving ground for the first useful Onbii experience. See the spec roadmap for the current milestone context: [`docs/spec/docs/ROADMAP.md`](docs/spec/docs/ROADMAP.md).

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

## Docs

Apple-specific implementation direction belongs in [`docs`](docs).

The spec should remain the source for shared product and format decisions. This repository should hold Apple-specific architecture, app target notes, platform decisions, and implementation details.
