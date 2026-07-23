# Milestone 1: I Am Not Losing This

The Apple proving ground should implement the first capture-certainty loop for Onbii.

## Initial Scope

- macOS start/stop capture around meetings or desktop audio where practical.
- macOS import of existing audio files.
- Apple Watch start/stop recording and transfer.
- Simple iPhone record/import/receive flow.
- Shared `.onbii` bundle creation.
- Original recording preservation.
- Basic transcript and rough speaker turns.
- Human-readable Markdown facet.
- Basic metadata: title, date, location where available, source, people, and object identity.
- Basic provenance for derived artefacts.
- User-controlled archive storage.
- Ordinary inspection or lightweight preview.

## Current Implementation Slice

The first slice establishes:

- `OnbiiCore`, containing the draft logical manifest and validation;
- `OnbiiArchive`, containing a staged, non-overwriting directory bundle writer;
- preservation of imported source audio plus an inspectable Markdown facet;
- explicit import and rendering provenance;
- a SwiftUI macOS development app with archive selection, audio import, progress
  and error state, and Finder reveal;
- validated in-app inspection for imported packages and packages opened from
  Finder;
- macOS audio import as the first vertical slice, followed by explicit capture.

See the [Milestone 1 Bundle Profile](../architecture/milestone-1-bundle-profile.md)
and [macOS Capture And Import
Direction](../architecture/macos-capture-import-direction.md).

## Spec Context

See [`../spec/docs/MILESTONE_1_BREAKDOWN.md`](../spec/docs/MILESTONE_1_BREAKDOWN.md) and [`../spec/docs/IMPLEMENTATION_ARCHITECTURE.md`](../spec/docs/IMPLEMENTATION_ARCHITECTURE.md).
