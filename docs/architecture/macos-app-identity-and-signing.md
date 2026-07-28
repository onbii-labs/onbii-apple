# macOS App Identity And Signing

Status: Accepted for development; distribution channel remains open

Date: 2026-07-23

## Update (2026-07-24)

The Yepyr Apple Developer team (`S52C3W4ZB8`) is now configured, and the app
bundle identifier is **`com.yepyr.onbii`**, shared across macOS, iOS, and watchOS
(watch: `com.yepyr.onbii.watchkitapp`). This is deliberate — a single vendor
identity lets the App Store treat Onbii as one cross-platform app rather than
separate products. It supersedes the `org.onbii.OnbiiMac[.dev]` identifiers in
the Decision below.

The exported format type remains **`org.onbii.bundle`** — a deliberately
vendor-neutral namespace that matches the open spec and is independent of the
app's `com.yepyr.*` identifier. The distribution channel (Mac App Store vs
notarized Developer ID) remains open.

**The Xcode targets are now named `Onbii`** on both macOS and iOS, superseding
"the Xcode target and module remain `OnbiiMac`" in the Decision below. The
*modules* still are: `PRODUCT_MODULE_NAME` stays `OnbiiMac` and `OnbiiIOS`, so no
Swift module name changed and nothing had to be touched in any source file.

Two reasons, and the second is the practical one:

- A person installing a public alpha should see *Onbii*, not *OnbiiMac*.
- XcodeGen names a target's product file reference after the target, so a target
  called `OnbiiMac` producing `Onbii.app` left Xcode "correcting" the generated
  project on every open. That was the last remaining source of that churn — the
  recommended-settings and `LastUpgradeCheck` half was fixed in `ab32529`.

The Watch target keeps the name `OnbiiWatch`: it is embedded rather than
installed, and nobody ever reads it.

## What it takes to distribute — measured 28 July

Milestone 1.5 finished, so "can this go to TestFlight" stopped being rhetorical.
It was checked rather than assumed, and the answer is *not yet, for two specific
reasons*.

**An archive succeeds and proves nothing.** `xcodebuild archive` on the iOS
scheme in Release reports `ARCHIVE SUCCEEDED` — and signs with
**Apple Development** and the *iOS Team Provisioning Profile*. That is a
development signature. It is exactly the case this document's own rule was
written for: a build is not distributable merely because it archives locally.

**The export is the real test, and it fails.** Exporting that archive with
`method: app-store-connect` gives:

```
error: exportArchive No profiles for 'com.yepyr.onbii' were found
error: exportArchive No profiles for 'com.yepyr.onbii.watchkitapp' were found
```

The keychain holds three `Apple Development` certificates and **no
`Apple Distribution` certificate**, and all six installed profiles are
development profiles. Nothing for distribution exists yet for either bundle
identifier.

### What TestFlight actually requires — and what it does not

Worth separating, because the App Store's requirements are much larger than
TestFlight's and it is easy to assume they are the same list.

**Not needed for TestFlight at all:** screenshots, app previews, the App Store
description, keywords, categories, pricing. Those belong to an App Store
*listing* and are only demanded when submitting for release. TestFlight has its
own, much smaller metadata.

**Internal testing** — up to 100 people who hold a role on the App Store Connect
team — needs only: the app record, a processed build, and an export-compliance
answer. No review, no screenshots.

**External testing** — up to 10,000 people by link or email — adds a **Beta App
Review** on the first build, a beta description and "what to test" notes, a
feedback email, and a **privacy policy URL**. Onbii does not have one yet, and
for a local-first app it is a short document, but it has to exist.

**Export compliance is declared in the repository** rather than answered by hand
on every upload: all three `Info.plist` files carry
`ITSAppUsesNonExemptEncryption = false`. That is accurate today — the app makes
no network calls at all and uses no custom cryptography, verified by there being
zero `URLSession` call sites in the whole repository. **It is a legal declaration
about the app, so it needs re-checking the day anything talks to a server.**

### What is missing, in order

1. An **Apple Distribution** certificate for the team.
2. **App Store provisioning profiles** for `com.yepyr.onbii` and
   `com.yepyr.onbii.watchkitapp`. Passing `-allowProvisioningUpdates` to
   `xcodebuild` creates both — note that this *writes* to the Apple Developer
   account rather than only reading it.
3. An **App Store Connect app record** for `com.yepyr.onbii`. Automatic signing
   does not create this and an upload is rejected without it.
4. The **iCloud container** `iCloud.com.yepyr.onbii` enabled on the App ID for
   distribution, not only for development. The app resolves it at runtime on
   iPhone, so a distribution profile that omits it would fail in a way that only
   appears once installed from TestFlight.

The reproduction, which stays read-only and creates nothing:

```sh
xcodebuild -workspace OnbiiApple.xcworkspace -scheme OnbiiIOSApp \
  -destination 'generic/platform=iOS' -configuration Release \
  -archivePath /tmp/Onbii.xcarchive archive
xcodebuild -exportArchive -archivePath /tmp/Onbii.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath /tmp/export
```

with `method: app-store-connect`, `signingStyle: automatic`,
`destination: export`. Leaving `-allowProvisioningUpdates` off is what keeps it a
diagnosis instead of a change.

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
