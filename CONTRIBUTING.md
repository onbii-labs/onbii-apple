# Contributing to Onbii Apple

Thank you for your interest in contributing to Onbii.

This repository contains Apple-family implementation work for Onbii: macOS, iOS, watchOS, shared Apple platform packages, extensions, tools, and implementation notes.

## Before You Start

Please read:

- [`README.md`](./README.md)
- [`docs/spec/README.md`](./docs/spec/README.md)
- [`docs/spec/docs/VISION.md`](./docs/spec/docs/VISION.md)
- [`docs/spec/docs/PRINCIPLES.md`](./docs/spec/docs/PRINCIPLES.md)
- [`docs/spec/docs/ROADMAP.md`](./docs/spec/docs/ROADMAP.md)

The spec repository is the source for shared product direction, object model, bundle model, provenance, linking, and roadmap context. Apple-specific implementation details belong in this repository.

## Ways To Contribute

Contributions are welcome in many forms, including:

- improving Apple implementation documentation;
- clarifying architecture notes;
- implementing macOS, iOS, or watchOS surfaces;
- improving shared packages;
- adding tests;
- reporting issues;
- improving developer tooling.

## Discuss First

For significant changes, please open a GitHub Issue or Discussion before starting implementation.

Early discussion is especially useful for changes involving capture behaviour, storage, bundle format assumptions, transcription, provenance, privacy, permissions, or cross-device transfer.

## Pull Requests

When submitting a pull request:

- keep changes focused on a single topic;
- explain the motivation behind the change;
- link to relevant spec documents or decisions where appropriate;
- update documentation when behaviour or architecture changes;
- include tests for implementation changes where practical;
- be respectful during discussion and review.

## Guiding Principles

Implementation work should align with the Onbii principles:

- local-first;
- user-owned storage;
- knowledge objects over loose files;
- source preservation;
- derived data is not truth;
- human edits are first-class;
- applications are views;
- clear boundaries between capture, source normalisation, processing, storage, and views.

## License

Unless otherwise noted, source code in this repository is licensed under the Mozilla Public License 2.0. See [`LICENSE`](./LICENSE).

The Onbii name and logo are not licensed under MPL-2.0. See [`NOTICE.md`](./NOTICE.md).

## Code of Conduct

By participating in this project, you agree to abide by the project's [`CODE_OF_CONDUCT.md`](./CODE_OF_CONDUCT.md).
