# Visual Identity

**Milestone 1.5 implementation direction — implemented.**

Onbii's visual identity is defined in the brand guidelines that live outside this
repository. This note records how it is *implemented* here, and — more usefully —
which of the implementation choices were forced, which were measured, and which
are still open.

## Where the design layer lives

A hybrid, and the split is forced rather than stylistic:

| Layer | Location | Why there |
|---|---|---|
| Colour tokens, typography, status badge, brand mark, empty state | `Packages/OnbiiUI` | Shared by Mac and iPhone; one definition, no drift |
| App icon, global accent colour | `Apps/<App>/Resources/Assets.xcassets` | `ASSETCATALOG_COMPILER_APPICON_NAME` and `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` only resolve against a catalog compiled **into the app target itself** — a package resource bundle cannot serve them |

**The Watch takes no `OnbiiUI` dependency**, and the reason is architectural
rather than about size: `OnbiiUI` depends on `OnbiiArchive`, and the Watch has no
business reading or writing bundles — it captures and transfers, and the iPhone
creates the object. So the Watch carries a small local copy of what it needs
(a Forest field, a fieldless mark, an on-accent colour, a secondary text colour)
plus a duplicated prominent button style. That duplication is deliberate and
bounded; taking the dependency to remove it would breach a boundary the whole
project rests on.

### The Watch is the one all-brand surface

Where the Mac and iPhone follow the system's light or dark background, the Watch
app sits on a full **Forest** field. It has one screen and one job, so a single
brand surface costs nothing in navigation, and it is what turns the Watch from
"an app with our accent colour" into something recognisably Onbii.

The mark there is a **Watch-specific drawing** (`brand/onbii-icon-applewatch.png`):
the leaf as a solid Champagne body with the tree knocked out in Forest, and the
stroke weights roughly doubled. The Mac and iPhone keep the outline mark.

That is not decoration — it is the fix for the problem described below. Champagne
covers **26% of the Watch mark's canvas against 3% of the outline one**, and area
is the variable that decides whether a pale colour reads as itself on a small
screen.

Like every brand raster here it is **opaque**, with the Forest field baked in, so
it sits on the Forest screen with no seam and no alpha channel to be misread.

Contrast on Forest `#21382F`, all measured: Champagne button 8.8:1, Graphite
label on that button 13.1:1, secondary text 6.1:1. Disabled lifts the field with
white at 15% rather than fading the Champagne, which would go muddy brown.

**Known invariant — the accent is defined five times.** Once in the package
(`OnbiiAccent.colorset`), once per app (`AccentColor.colorset` ×3), plus a
hard-coded pair in the Quick Look extension (see below). `OnbiiOnAccent` is
duplicated onto the Watch as well. Nothing enforces that they match. If you
change one, change all of them.

## Colour

Eleven adaptive colour sets in
`Packages/OnbiiUI/Sources/Resources/OnbiiBrand.xcassets`, each carrying a light
value and a dark (`luminosity`) value, exposed through `Color.onbii*` accessors
in `OnbiiColor.swift`. That file is the only place the asset names appear as
strings, so a rename is a compile error rather than a black rectangle.

**The usage rule from the guidelines, so it is not relitigated per screen:**

- In **light** mode, headings stay `.onbiiPrimaryText`. The accent is reserved
  for small, dense elements — all-caps sub-headers, buttons, borders, badges —
  where block density carries the colour better than thin strokes.
- In **dark** mode, a Prata title in `.onbiiAccent` on `.onbiiBackground` is the
  signature look and passes AAA.
- Because the accent set already darkens to `#B88552` in light mode, small
  accented elements are safe unconditionally. Only a hero title would need to
  branch on `\.colorScheme`.
- **The record indicator stays literal red** on every platform. A red record dot
  is a platform convention, not a brand decision.

### Never tint a filled control without `onbiiOnAccent`

`.buttonStyle(.borderedProminent).tint(.onbiiAccent)` is **broken with this
palette** and must not be used. The system prominent style assumes a dark,
saturated tint and draws its label white. Measured against our accent:

| Fill | White label | `onbiiOnAccent` label |
|---|---|---|
| Light `#B88552` | 3.22:1 — below AA | **5.11:1** |
| Dark `#E7D5BE` | 1.43:1 — invisible | **13.09:1** |

Use `.buttonStyle(.onbiiProminent)`, which pairs the fill with
`Color.onbiiOnAccent` (Ink in light, Graphite in dark). Destructive buttons keep
the system red fill and white label, where the platform convention is correct.

That style also **swaps the fill when disabled** rather than fading it: Champagne
at 40% over a dark background is a muddy brown with an illegible label, so
disabled uses `.onbiiElevated` with `.onbiiSecondaryText`.

## Typography

Only **Prata** is embedded, and only for display: the empty-state hero, an
object's title, a detail section title. Body, controls, labels and **navigation
titles stay SF Pro** — a serif in a system navigation bar reads as a bug, not as
brand. The guidelines call the geometric sans "the system font bridge" to SF Pro;
on Apple platforms, SF Pro *is* that bridge, so Manrope is not embedded at all.

Registration is `CTFontManagerRegisterFontsForURL(_:.process:_:)` from
`Bundle.module`, held in a lazily-initialised `static let` that every font
accessor touches. That makes it impossible to request Prata before it has been
registered — the usual failure of runtime registration. It was chosen over
Info.plist embedding because that route needs three divergent mechanisms
(`ATSApplicationFontsPath` on macOS, `UIAppFonts` twice) and three copies of a
licensed font, in a repo where two targets use checked-in plists and one uses
`GENERATE_INFOPLIST_FILE: true`.

`Font.custom(_:size:relativeTo:)` keeps Prata inside Dynamic Type on iOS.

`Prata-Regular.ttf` ships with `OFL.txt` beside it, which is why the `Fonts`
directory is declared `.copy` and not `.process`.

## App icons: classic appiconset, and what we measured

We use a classic `AppIcon.appiconset`, **not** an Icon Composer `.icon` file,
because XcodeGen 2.46.0 has no `.icon` file type — its type table knows
`folder.assetcatalog` and `folder.iconset` but not `folder.iconcomposer.icon` —
and `CLAUDE.md` forbids fixing that by hand-editing the generated `.xcodeproj`.
Xcode 27's own new-project template *does* default to `.icon`, so this is a
deliberate choice, not an oversight.

The upgrade path is real and better than expected: `brand/onbii-icon-mark.svg` is
already separated into `background` / `seed` / `growth` / `trunk` / `pip tree`
groups, which import into Icon Composer as genuine layers when we want the
Liquid Glass treatment.

Three findings from building it, each of which cost time to discover:

1. **macOS single-size does not work.** An appiconset with one
   `{"idiom": "universal", "platform": "macos", "size": "1024x1024"}` entry
   compiles **silently to nothing** — `BUILD SUCCEEDED`, no actool warning, and
   an `Assets.car` containing the accent colour and no icon. macOS needs the
   classic ten-slot ladder (16/32/128/256/512 at 1x and 2x, `"idiom": "mac"`),
   generated with `sips -Z`. iOS and watchOS single-size 1024 *do* work.
2. **macOS 26 masks legacy appiconsets to the unified rounded rectangle.** This
   was the milestone's real open question, and it is settled empirically rather
   than by reasoning: rendering `NSWorkspace.shared.icon(forFile:)` for the built
   app produces the same squircle shape and inset as a system app. Our full-bleed
   source art is therefore correct, and it must **not** be pre-shaped — pre-shaping
   *and* system masking would give a visibly double-inset icon.
3. **The watchOS circular mask does not clip the mark.** Verified by rendering
   the art through a circular clip before trusting it to a device.

The source PNG was 1024×**1026**. It is **cropped**, not scaled — scaling would
distort the mark by 0.2%, cropping removes one pixel of solid Forest.

To re-verify after changing the artwork:

```sh
xcodebuild -workspace OnbiiApple.xcworkspace -scheme OnbiiMacApp build
APP="…/Build/Products/Debug/Onbii.app"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$APP/Contents/Info.plist"  # expect AppIcon
assetutil --info "$APP/Contents/Resources/Assets.car" | grep -c 'Icon Image'     # expect 10 on macOS
```

An empty `CFBundleIconName` or a missing `Icon Image` means the catalog compiled
to nothing — see finding 1.

## The iPhone launch screen

`UILaunchScreen` in `Apps/OnbiiIOS/Info.plist` is a Forest field with the
wordmark centred — no storyboard, no code, two keys:

```xml
<key>UILaunchScreen</key>
<dict>
    <key>UIColorName</key><string>OnbiiForest</string>
    <key>UIImageName</key><string>OnbiiWordmark</string>
</dict>
```

Both assets must live in the **app target's** catalog, the same constraint as the
app icon — a launch screen resolves against the main bundle and cannot see a
package resource bundle.

`OnbiiForest` is a single value rather than a light/dark pair on purpose: a
launch screen that changed colour with the system appearance would read as two
different apps. Copper on Forest is 4.8:1, comfortable for a mark at this size.

The wordmark is the alpha export, trimmed of its baked padding (the content sits
at x 147–1654, y 159–662 in the 1800×799 canvas) and sliced to 300/600/900 px
for 1x/2x/3x, giving roughly 300pt on screen. `UIImageName` centres the image at
its natural size and does not scale it, so the slices decide how large it reads.

## Champagne does not survive at hairline widths

On a real Apple Watch the Champagne mark read as pure white. It cost several
wrong diagnoses — rendering intent, alpha channels, colour profiles, display
accuracy — before a swatch drawn directly on the Watch (pure white, Champagne
and Copper side by side) showed all three rendering **correctly**. Nothing was
broken.

The cause is size, not colour management. Champagne is a 68%-luminance
near-neutral, and the eye resolves hue far worse than luminance at fine detail.
The mark's strokes are ~10px in the 512px source, so at 82pt on a @2x Watch they
landed at **3.2 device pixels** — too narrow to carry a hue that pale, so it
collapsed to white. The Copper pips in the same image, at 35% luminance and much
higher chroma, stayed visibly gold throughout.

What follows from that:

- **A pale colour on a small screen needs area.** Champagne is fine on the Watch
  wherever it has mass — the button pill (8.8:1 on Forest) and the solid mark —
  and unusable for hairlines. The accent stays Champagne on every platform.
- **The fix was artwork, not a hex value.** The Watch-specific mark is a solid
  fill with doubled stroke weights: 26% Champagne coverage against the outline
  mark's 3%.
- **The mark is drawn at 120pt.** Do not shrink it without checking on a real
  Watch.

An intermediate build made the Watch accent Copper, on the theory that Champagne
could not survive that display at all. The swatch test disproved it, and the
solid mark made it unnecessary. Recorded here because the reasoning is easy to
rediscover and get wrong in the same direction.

Two process lessons, both of which cost real time here:

- **A Simulator screenshot cannot answer a perceived-colour question.** Nor can
  a photograph of a screen: a phone camera's white balance turned the Forest
  field teal and every warm tone neutral, which produced a completely wrong
  diagnosis. Put a **known reference in the frame** — the swatch strip settled in
  one glance what four rounds of measurement could not.
- **Prefer the artwork as supplied.** A transparent Watch-only variant was
  invented to avoid a seam that did not exist, and it added an alpha channel and
  dropped the colour profile for no benefit. All platforms now use the same
  opaque file. Brand imagesets still set `"template-rendering-intent": "original"`
  and `.renderingMode(.original)` — cheap insurance, though it was not the bug.

```sh
assetutil --info "<built>/OnbiiWatch.app/Assets.car" | grep -A3 OnbiiMark
```

Want `Opaque=True` and `Template Mode=None`. An incremental build can report the
*previous* value, so `clean` matters.

## Auditing brand colours: read the file, not a rendering

If you ever need to check that artwork matches the palette, decode the PNG
directly. Sampling through AppKit — `NSImage` → `tiffRepresentation` →
`NSBitmapImageRep.colorAt` — re-renders the image through a display colour space
and shifts every value. It reported this repository's icon as `#2B483E` when the
bytes in the file, and Affinity, both say `#21382F`. A whole "the artwork drifts
from the guidelines" conclusion came out of that, and it was wrong.

`sips -g profile` confirms the tag; a short `zlib`-based PNG reader that reverses
the per-scanline filters gives the stored values with no conversion at all.

For the record, the delivered artwork **matches** the guidelines: Forest
`#21382F`, Champagne `#E7D5BE`, and — since the 27 Jul 2026 re-export — Copper
`#C99663` in the icon.

One known artwork issue remains, in the **wordmark** only: the two `ii` stems
are still the pre-correction Copper `#CB9D6B` while the rest of the word and the
`ii` dots are `#C99663`. That is ΔE 3.4 between adjacent flat areas of the same
word, which most people can see. It does not affect the app icon.

## The menu bar mark: a template, and why it must be a third asset

The macOS menu-bar item added in Milestone 1.5 cannot use `OnbiiMark`. A menu bar
image is a **template**: macOS discards every colour channel and uses the alpha
alone as a mask, painting the glyph black on a light menu bar, white on a dark
one, and inverting it while the menu is open. Handing it the supplied mark puts a
Forest tile in the menu bar that ignores all three states.

**Monochrome and see-through is the standard here, not a compromise.** Every
first-party menu bar glyph on macOS is a template, and a coloured tile is what
dates an app on sight. The constraint and the preference point the same way, so
there is nothing to trade off.

Note this is a *different* question from the app icon, which stays full-colour —
see [App icons](#app-icons-classic-appiconset-and-what-we-measured). Modern macOS
wants a colourful icon in the Dock and a monochrome glyph in the menu bar; the
Liquid Glass light / dark / clear / tinted variants belong to the former and are
tracked there as an upgrade path, not here.

This is *not* the mistake recorded above under
[Champagne does not survive at hairline widths](#champagne-does-not-survive-at-hairline-widths).
That one was a transparent Watch variant invented to fix a seam that did not
exist. Here the variant is forced by the platform, and the same reasoning that
produced the Watch's solid-fill mark applies more strongly: the menu bar is
18 pt where the Watch mark is 120 pt.

It is a **separate imageset**, not a second slot on `OnbiiMark`. The brand
imagesets set `"template-rendering-intent": "original"` as deliberate insurance,
and this one needs the opposite; keeping them apart means neither has to be
qualified.

### The spec

- **Name:** `OnbiiMenuBarMark`, in `OnbiiUI`'s `OnbiiBrand.xcassets`.
- **Format:** PDF or SVG with vector data preserved — one file at any scale
  beats maintaining `@1x`/`@2x`. PNG is acceptable as `18×18` and `36×36`.
- **Canvas:** 18 × 18 pt, the standard menu bar glyph size.
- **Glyph area:** about 16 × 16 pt, leaving roughly 1 pt of breathing room.
  Centre the *optical* mass of the droplet, not its bounding box.
- **Colour:** pure black, `#000000`, everywhere the glyph is opaque. The value is
  discarded, but black is the convention and keeps the file readable.
- **Background:** fully transparent. No Forest field, no rounded rectangle — the
  rounded tile belongs to the app icon and reads as a foreign object in a menu
  bar.
- **Weight:** the outline mark is 3% coverage and will disappear at this size.
  Treat it like the Watch mark — solid fill or substantially thickened strokes,
  with a minimum stroke of roughly 1.5 pt at 18 pt (about 8% of the width).
- **The two copper dots** lose their colour here and join the same silhouette.
  Worth checking at actual size that they stay separate from the leaf edge rather
  than merging into it.

### White is not transparent — the mistake to avoid

The first draft of `onbii-icon-applemenubar.svg` was a solid black droplet with
the pip tree **painted white** on top of it. On any normal surface that is the
right picture. In a template it is a featureless blob: `#FFFFFF` has an alpha of
1, so the tree is exactly as opaque as the droplet and disappears into it.

Anything meant to read as see-through has to be **knocked out** — a Boolean
subtract from the droplet, leaving real transparency — not filled with the
background colour.

Two consequences for the drawing:

- Once the tree is negative space it reads thinner than the same shape in
  positive, so it may want slightly heavier strokes than the white version did.
- The knockout is the whole design at this size. There is no second colour to
  fall back on.

### Verified about the pipeline, 28 July

An SVG imports and compiles correctly on this toolchain — worth knowing, because
the app icon could not use a modern format and it would be easy to assume the
same here. An imageset with

```json
"properties": {
  "preserves-vector-representation": true,
  "template-rendering-intent": "template"
}
```

produced no `actool` warning and compiled to `Template Mode: template`,
`Opaque: False`, with the vector representation retained. The check, which mirrors
the app-icon recipe above:

```sh
assetutil --info "<built>/OnbiiApple_OnbiiUI.bundle/Contents/Resources/Assets.car" \
  | grep -A6 OnbiiMenuBarMark
```

To see what the menu bar will actually draw before shipping it, load the image
out of the built bundle and check `isTemplate`, rather than looking at the source
file — the source looks correct in every editor regardless.

### What stays a system symbol

**Recording state does not need a second variant.** While a capture is running
the menu bar shows the system's red record dot, for the reason already settled
elsewhere in the apps: a red record dot is a platform convention, not a brand
decision, and it stays red. The mark says *Onbii is here*; the record dot says
*this machine is listening*, and that second statement should look the same in
every app on the system.

## The other two rendering surfaces

**`OnbiiContentMarkdown.swift` is deliberately untouched.** It writes `content.md`
*into the user's object*. The milestone says the format does not change;
applications are views; and restyling it would split objects written before and
after 1.5, reconcilable only by rewriting files the person already has.

**The Quick Look extension takes no package dependency.** It is sandboxed to
read-only access to the previewed file, and pulling in SwiftUI plus a resource
bundle to colour two headings is a bad trade. It carries a ten-line
`NSColor(name:dynamicProvider:)` copy of the accent instead, and its type scale
is named rather than anonymous. Two constraints stay: **keep AppKit** (a
WKWebView cannot launch its helper processes in that sandbox and hangs), and
**do not register Prata there**.

## What this does not do

Nothing here changes what an Onbii object is, where it lives, or what is written
into it. The status a person sees is derived from the manifest at read time
(`OnbiiObjectStatus` in `OnbiiArchive`); the "transcribing right now" state is
session-only memory in a view model (`OnbiiObjectActivity`) and is never encoded.
Delete the whole design layer and every object is unchanged.
