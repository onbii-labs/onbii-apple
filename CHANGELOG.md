# Changelog

All notable changes to Onbii Apple will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this repository should follow Semantic Versioning once releases begin.

## [Unreleased]

### Added

- Milestone 1.5 visual identity: app icons on macOS, iPhone, and Apple Watch, and
  an `OnbiiUI` package carrying the adaptive Onbii palette, the Prata display
  face, the brand mark, and a shared object-status badge.
- A browsable home on macOS: searchable object sidebar with status indicators,
  object detail pane, capture and import in the toolbar, and a Settings scene for
  the archive and transcription language.
- A browsable home on iPhone: object rows with status badges pushing to a detail
  view, a persistent capture bar, a Settings sheet, and pull-to-refresh.
- A branded iPhone launch screen: the Onbii wordmark on a Forest field, replacing
  the empty system default.
- A full Forest brand field on the Apple Watch, carrying a Watch-specific
  solid-fill Onbii mark, a Champagne primary button, and brand text colours — kept
  as local assets so the Watch takes no dependency on the archive. The palette is
  the shared one; only the mark artwork is Watch-specific, because a pale colour
  needs area to read on a small screen — see
  `docs/architecture/visual-identity.md`.
- `OnbiiArchiveIndex` and `OnbiiObjectStatus` in `OnbiiArchive`: one shared,
  read-only listing of archive objects and one derivation of an object's status
  from its manifest.
- Initial repository scaffold.
- Public repository documents.
- MPL-2.0 license.
- Spec submodule at `docs/spec`.

### Changed

- `NOTICE.md` now names the vendored brand asset paths explicitly and records the
  SIL Open Font License attribution for Prata.

### Deprecated

_None._

### Removed

_None._

### Fixed

- An object carrying only the Markdown transcript artefact is no longer reported
  as untranscribed. Three call sites disagreed about which resource identifiers
  count as a transcript; there is now one definition.
- Filled brand buttons no longer draw a white label on the accent, which measured
  1.4:1 in dark mode and 3.2:1 in light. `OnbiiProminentButtonStyle` pairs the
  fill with a new `onbiiOnAccent` token for 13.1:1 and 5.1:1.

### Security

_None._
