# macOS App Identity And Signing

Status: Accepted for development; distribution channel remains open

Date: 2026-07-23

## Context

The Milestone 1 macOS app needs a stable development identity so document-type
registration, sandbox bookmarks, privacy permissions, and local testing do not
change accidentally. It does not yet have an Apple Developer team or a chosen
distribution channel recorded in this repository.

The `.onbii` type identity is part of the file-format integration and must not
depend on which application happens to open it.

## Decision

- The product and Finder display name is **Onbii**.
- The Xcode target and module remain `OnbiiMac`.
- Local development builds use `org.onbii.OnbiiMac.dev`.
- The intended distribution bundle identifier is `org.onbii.OnbiiMac`, subject
  to registration by the owning Apple Developer team before the first signed
  archive.
- The exported bundle type remains `org.onbii.bundle`. It is independent of the
  app bundle identifier and is not renamed between development and release.
- Debug builds remain ad-hoc signed so a fresh checkout can build without a
  developer account.
- No team identifier, signing certificate, or provisioning profile is committed
  until the owning team and distribution channel are chosen.
- A build is not described as distributable merely because it archives locally.
  Distribution requires the release bundle identifier, an explicit team, a
  valid signing identity, and the appropriate notarization or App Store path.
- Capture entitlements and privacy usage descriptions are added only for
  implemented, explicit user-facing capture paths.

## Consequences

- Development privacy grants are associated with the `.dev` identity and may
  need to be granted again when testing a distribution-signed build.
- The current Release configuration is useful for local build verification but
  is not a distribution-signing configuration.
- Choosing Mac App Store distribution versus a notarized Developer ID build
  remains a release decision. The choice may affect sandbox capabilities,
  provisioning, packaging, and update delivery, but not the `.onbii` format.
- The repository must validate the intended production identifier with the
  owning Apple Developer account before changing the Xcode project to use it.

## Distribution Checklist

Before the first external build:

1. Confirm control of the Apple Developer team and register
   `org.onbii.OnbiiMac`.
2. Choose Mac App Store, notarized Developer ID distribution, or both.
3. Add a non-secret release signing configuration without committing
   certificates or credentials.
4. Archive, sign, and verify the app’s entitlements.
5. Exercise archive bookmarks, `.onbii` document opening, microphone permission,
   and system-audio capture permission using the distribution identity.
