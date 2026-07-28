# OnbiiUI resources

## `OnbiiBrand.xcassets`

Colour sets and the brand mark used by the Mac and iPhone apps.

Every colour set carries a light value and a dark (`luminosity`) value taken
row-for-row from the Onbii brand guidelines. Nothing here is looked up by
string at a call site — `OnbiiColor.swift` is the only file that names these
assets, so a rename breaks the build rather than silently falling back.

`OnbiiMark.imageset` is an Onbii brand asset. It is **not** covered by the
repository's MPL-2.0 grant; see `NOTICE.md`. Replace it if you distribute a
modified build.

`OnbiiOnAccent` is the text and symbol colour for anything drawn **on** an accent
fill. It is not optional decoration: white on the accent measures 1.4:1 in dark
and 3.2:1 in light. Use `.buttonStyle(.onbiiProminent)` rather than
`.borderedProminent` + `.tint(.onbiiAccent)`.

### The accent is defined twice, on purpose

`OnbiiAccent.colorset` here, and `AccentColor.colorset` in each app target's own
`Assets.xcassets`. This duplication cannot be removed:
`ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` (and
`ASSETCATALOG_COMPILER_APPICON_NAME`) only resolve against a catalog compiled
into the app target itself, never against a package resource bundle. The app
copies are what tint stock SwiftUI controls; this one is what `.onbiiAccent`
resolves to. **If you change one, change all four.**

## `Fonts`

`Prata-Regular.ttf` is the brand display serif, registered at runtime by
`OnbiiFont.swift` via `CTFontManagerRegisterFontsForURL`. It is third-party
software under the SIL Open Font License 1.1; `OFL.txt` sits beside it because
the licence requires the two to travel together. Do not separate them.

The directory is declared with `.copy` rather than `.process` in
`Package.swift` for that reason — `.process` would flatten and could strip the
licence file out of the bundle.
