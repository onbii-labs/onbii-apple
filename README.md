# Onbii Apple

Apple implementation proving ground for Onbii Milestone 1: **I Am Not Losing This**.

This repository is for the first Apple-family capture surfaces and shared implementation code. It should stay aligned with the Onbii specification included at [`docs/spec`](docs/spec).

## Milestone 1 Focus

The first useful Apple implementation should help a person trust that an important recording, memo, or conversation has been captured into something they own.

Initial surfaces:

- macOS start/stop capture for meetings or desktop audio where practical;
- macOS import of existing audio files;
- Apple Watch start/stop recording and transfer;
- simple iPhone record/import/receive flow.

Each surface should feed the same Onbii object flow:

```text
capture or import
  -> preserve original recording
  -> create one manageable .onbii bundle
  -> create basic transcript
  -> represent rough speaker turns
  -> create human-readable Markdown facet
  -> record title, date, location where available, source, people, and provenance
  -> store in user-controlled archive
  -> allow ordinary inspection or lightweight preview
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

The spec repository is included as a submodule at `docs/spec`.

```sh
git submodule update --init --recursive
```
