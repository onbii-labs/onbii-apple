# Localization

Status: **Not started.** The apps are English-only, and the development region is
the default `en`. There is no String Catalog, no `.lproj`, no
`defaultLocalization` on the package, and not one `String(localized:)` in the
repository. Recorded now because a Dutch localization is wanted, and because the
first decision in it is one that could quietly damage every object a person owns.

## The line that matters: interface, not objects

**Onbii's own text is localizable. What Onbii writes into an object is not.**

`content.md`, the manifest, provenance actions, resource identifiers and the
generated recording title are **format**, not interface. They live in the
person's folder, they are read by Finder, Quick Look, a future CLI and other
people's tools, and they must read identically no matter which app wrote them or
what language that app was running in.

Localizing `OnbiiContentMarkdown` would mean an object captured on a Dutch Mac
had different headings from one captured on an English iPhone — the same archive,
split by the language of whichever device happened to be nearest. That is not a
translation feature, it is a format fork, and it contradicts *applications are
views*: the object would stop being the stable thing and start carrying a
property of the app.

So, concretely, these stay in English and are not strings to translate:

- `OnbiiContentMarkdown` — `## Transcript`, `- Created:`, `_Transcription pending._`
- `OnbiiRecordingName` — the `YYYYMMDD-HHMM Recording` title
- provenance `action` values — `captured`, `imported`, `transcribed`,
  `superseded`, `corrected`, `found-nothing`
- resource identifiers — `source-recording`, `derived-transcript`, …

A person's *own* words are already in their own language; the scaffolding around
them is structure. If the readable facet should ever speak the reader's language,
that is a rendering concern for a view, not a change to what is written.

## What the interface side actually costs

Measured on 28 July, so the estimate is not a guess:

| | count | state |
|---|---|---|
| `Text("literal")` | ~35 | **Already localizable.** SwiftUI takes a `LocalizedStringKey`, so a String Catalog picks these up with no code change. |
| `Text("a " + "b")` | ~20 blocks | **Not localizable as written** — see below. |
| Strings in view models and libraries | ~67 | Need `String(localized:)`. |

**The concatenation trap, which is self-inflicted.** Much of this app's longer
copy is written as adjacent string literals joined with `+` to stay inside the
line width:

```swift
Text("Onbii writes ordinary folders you own — no vendor backend. "
    + "To share objects with iPhone, choose iCloud Drive → Onbii → Onbii Archive.")
```

`"a" + "b"` is a `String` *expression*, not a literal, so this selects
`Text(_ content: some StringProtocol)` — the initializer that does **not**
localize. It compiles, it looks identical on screen, and it silently produces a
string no catalog will ever see. Every one of these has to become a single
literal (or an explicit `String(localized:)`) before it can be translated, and
the failure mode if they are missed is an app that is half translated with no
warning anywhere.

`OnbiiUI` additionally needs `defaultLocalization` in `Package.swift` and its own
catalog: a package's strings resolve against the package bundle, not the app's.

## Not decided

- Whether Dutch ships before a public alpha or after.
- Whether the Watch app is localized at all — it has very little text.
- Whether the *transcription language* default should follow the interface
  language. It should probably not: which language a recording is in is a
  property of the recording, which is why Milestone 1.6 moved that choice onto
  the object.
