# UI_REDESIGN.md — Murmur visual redesign, v2 "Paper & Clay" (master prompt)

Put this file in the repo root next to `SPEC.md` (the original spec, `claude-code-prompt.md`), replacing any earlier `UI_REDESIGN.md`. Put the `Design/` folder that came with it in the repo root too. Read this file, `SPEC.md` and `Design/README.md` before writing code.

Murmur is functionally finished. This task changes how it **looks, moves and sounds**. **No dictation behavior changes.**

**Where files disagree:** `SPEC.md` hard rules win, then this file, then the board source in `Design/reference/html/`, then the renders in `Design/reference/*.png`, then your own taste. Where this file deliberately differs from a board (the contrast fixes in §3.2), this file wins.

**This replaces v1.** v1 (black Flow Bar with white bars, Source Sans 3, the Anthropic-measured paper tokens, the "Personal" plan badge, emoji stat chips) is retired. If any v1 milestone was already built on the `ui-redesign` branch, keep its infrastructure (snapshot tool, Design Gallery, token lint, `ThemeProvider`, the token-file split, the debug panel) and replace the values and visuals. List what you reused in the U0 report.

---

## 0. What's in `Design/`

| Path | What it is | How to use it |
| --- | --- | --- |
| `Design/tokens.json` | Every color, type style, spacing and radius in this file, light and dark | Generate or check `Tokens+*.swift` against it |
| `Design/brand/murmur-mark.svg` | The logo lockup, one path, `viewBox 0 0 1002 378`, clay `#B54C3C` | Becomes the `BrandMark` shape |
| `Design/brand/murmur-mark-dark.svg` | Same path in `#D9705F` for dark surfaces | Color reference |
| `Design/brand/app-icon.svg`, `app-icon-dark.svg` | 1024 × 1024 tiles: the M, one big lobe, then the logo's own tapering tail | Source for the `.iconset` |
| `Design/brand/menubar-template.svg` | 36 × 36 viewBox, black stroke on transparent: the M with one short wave | Source for the status item template image |
| `Design/brand/logo-murmur.png` | The owner's original raster | Reference only |
| `Design/motion/murmur-motion.js` | Working reference code for the waveform, processing dots, countdown ring and mic level meter | Port the math to SwiftUI; never ship JS |
| `Design/reference/*.png` | 2× renders of all eight boards | The visual answer key for snapshot comparison |
| `Design/reference/html/*.dc.html` | The boards' source. Every exact value is in inline styles | Look here for any number this file doesn't give |

---

## 1. Sources and tags

- **[BOARD]** The owner's Claude Design canvas "Murmur UI Kit": 01–02 Flow Bar & menu bar, 03.1–03.5 Hub (Home, Style, Dictionary, Snippets, Settings), 04 Onboarding, 05 Components. Values tagged BOARD were read from its source.
- **[LOGO]** Sampled from the owner's logo: clay `#B54C3C`, cream `#F6EEE4`.
- **[DERIVED]** Computed by me: contrast fixes, pressed states, the dark sunken fill.
- **[ASSUMED]** On no board. Use the stated value and add a `// MEASURE` comment.

The boards are 1 CSS px = 1 pt. Never present an assumed value as measured.

---

## 2. Hard rules

1. **Original assets only.** No name, logo, icon art, sound files or copy from the reference app. Fonts are Geist and Geist Mono (SIL OFL, by Vercel) and Newsreader (SIL OFL). Bundle them with their license files.
2. **No hidden magic numbers.** Every size, color, radius, border width, duration, spring and sound parameter is a named token in `Sources/UI/Tokens*.swift`. Views reference tokens only. The lint script (§8) fails on raw literals in view files.
3. **The Flow Bar never takes focus.** Non-activating `NSPanel`, all Spaces, full-screen auxiliary, above the Dock. SPEC's "never takes focus in 50 trials" test must still pass.
4. **Reduce Motion, Reduce Transparency and Increase Contrast** are honored (§6.3).
5. **Light and dark both ship.** Hub colors resolve from the `\.theme` environment (Appearance setting: System, Light, Dark). The Flow Bar follows the **system** appearance: `flow-fill` is ink in light and raised ink in dark.
6. **No system chrome for Hub content.** No stock `List`, `Form`, `GroupBox`, `Toggle`, `Picker(.segmented)`, `TextField`, `Button` styles or `NavigationSplitView` vibrancy. Build the §4 components. **Menus stay native `NSMenu`**: the menu bar dropdown, its Microphone submenu, and the Flow Bar right-click menu. Don't fake their paper styling; the boards show their content and order, not a custom look.
7. **Flat.** No gradients. Shadows only on things that float above content: the paper toast and popovers (`shadow-float`, §3.4). The Flow Bar has no shadow; its 1 pt `flow-ring` edge separates it.
8. **One accent.** Clay is used for exactly three things: the single primary action on a surface, the live mic (Flow Bar while listening, recording menu bar icon), and the brand mark. Everything else interactive is ink. **Errors are never red**: ink, an icon, and words.
9. **No emoji anywhere.** v1's stat-chip exception is gone.
10. **Copy.** Sentence case, plain, warm, short. Errors say what happened and what to do. Board copy is final except bracketed placeholders (§9).
11. **Performance budget unchanged** (SPEC §7). Nothing animates while the Hub is hidden or the Flow Bar is idle. The waveform is one `Canvas`.
12. **Fail closed on fonts.** If a bundled font fails to load, fall back to the system face, log once, keep working.

---

## 3. Design system

### 3.1 Principles

- **Paper, ink, one clay.** An ivory window, a raised paper panel inside it, sunken wells for samples and illustrations. Ink type and ink controls. Clay only where §2.8 allows.
- **Three voices.** Newsreader (serif) speaks: page titles, quotes of what you said, samples of finished writing. Geist works: labels, buttons, body. Geist Mono reports data: keys, times, counts, captions, versions.
- **The ink Flow Bar.** A matte ink pill. The logo's waveform tail becomes the live waveform. Clay appears only while the mic is live.
- **Hairlines, not shadows.** Separation comes from paper layers and 1 pt lines.
- **Short, physical motion.** One spring on the Flow Bar's width; elsewhere small rises, fades and a check that draws itself.

### 3.2 Color tokens

All sRGB. Same names as `Design/tokens.json`.

**Hub, brand and controls**

| Token | Light | Dark | Source | Use |
| --- | --- | --- | --- | --- |
| `bg-window` | `#F6EEE4` | `#1F1E1D` | BOARD / LOGO | Window, sidebar, onboarding step |
| `bg-panel` | `#FBF7F1` | `#2C2A27` | BOARD | Raised content panel, cards, fields, paper toast |
| `bg-sunken` | `#EDE3D6` | `#191817` | BOARD / DERIVED | Feature card, style samples, illustration wells, info card |
| `fill-hover` | ink 3.5% | ivory 5% | BOARD / DERIVED | Hovered list row |
| `fill-selected` | ink 7% | ivory 8% | BOARD | Selected sidebar row, segmented track, small chip fill |
| `fill-chip` | ink 6% | ivory 7% | BOARD | Home stat strip |
| `text-primary` | `#1F1E1D` | `#F6EEE4` | BOARD | Titles, labels, body, icons |
| `text-secondary` | `#5E5A54` | `#A39E95` | BOARD | Descriptions and paragraphs under titles |
| `text-tertiary` | `#6F6A62` | `#9A958C` | DERIVED | Captions, mono meta, timestamps, row hints |
| `stone` | `#8A857C` | `#8A857C` | BOARD | Decoration only: off-toggle knob, swatches. **Never text** |
| `border-hairline` | ink 16% | ivory 14% | BOARD | Cards, list containers, window edge (decorative) |
| `border-divider` | ink 8% | ivory 10% | BOARD | Rows inside lists and settings groups |
| `border-control` | `#8A857C` | `#8F8A81` | DERIVED | Field outlines, empty radios, off toggles, select buttons |
| `accent-clay` | `#B54C3C` | `#D9705F` | LOGO / BOARD | §2.8 only |
| `accent-clay-pressed` | `#9E4234` | `#DF8678` | DERIVED | Primary pressed |
| `on-clay` | `#F6EEE4` | `#1F1E1D` | BOARD | Text on clay |
| `ink-fill` | `#1F1E1D` | `#F6EEE4` | BOARD | Solid secondary buttons, toggle on, selected ring, filled radio |
| `ink-fill-pressed` | `#2F2D2C` | `#E6DDD1` | DERIVED | Ink button pressed |
| `on-ink` | `#F6EEE4` | `#1F1E1D` | BOARD | Text and knobs on `ink-fill` |
| `focus-ring` | `#1F1E1D` | `#F6EEE4` | BOARD | 2 pt ring, 2 pt gap |

"ink n%" means `#1F1E1D` at n% opacity; "ivory n%" means `#F6EEE4` at n% opacity.

**Flow Bar** (follows the system appearance)

| Token | Light appearance | Dark appearance | Use |
| --- | --- | --- | --- |
| `flow-fill` | `#1F1E1D` | `#2C2A27` | Pill, Flow Bar toasts and alerts |
| `flow-ring` | ivory 12% | ivory 18% | 1 pt inset edge on every Flow Bar surface |
| `flow-text` | `#F6EEE4` | same | Text and icons |
| `flow-text-secondary` | ivory 55% | same | Sub-lines, word counts |
| `flow-idle-mark` | ivory 45% | same | The idle dash |
| `flow-live` | `#D9705F` | same | Live waveform, live dot, stop button |
| `flow-stop-glyph` | `#1F1E1D` | same | Square in the stop button |
| `flow-cancel` | `#34312E` | same | Cancel circle |
| `flow-button` / `flow-button-text` | `#F6EEE4` / `#1F1E1D` | same | Primary button in a toast |
| `flow-button-ring` | ivory 22% | same | Secondary button in a toast (ring only) |

**Contrast fixes vs the boards** (deliberate; this file wins):

1. **Small gray text.** The boards set captions and hints in stone `#8A857C`: 3.2:1 on ivory, 2.9:1 on sunken. It fails AA. Use `text-tertiary` `#6F6A62` (4.7:1 ivory, 5.0:1 panel). On `bg-sunken` or `fill-selected`, use `text-secondary`. The difference is barely visible.
2. **Control edges.** The boards draw field outlines, empty radios and off toggles with 18–35% ink rings (1.4–2.1:1). A control's edge needs 3:1. Use `border-control` (3.2:1 ivory, 3.4:1 panel). Cards and list containers keep the light hairline; it's decorative.
3. **Text on clay.** Ivory on `#B54C3C` is exactly 4.5:1. Use it only for 14 pt medium or larger (buttons). Never small text on clay.

**Verified contrast** (encode as tests, §8):
Light: ink on ivory 14.5, on panel 15.6, on sunken 13.1; `text-secondary` 6.0 / 6.4 / 5.4; `text-tertiary` 4.7 / 5.0; `border-control` 3.2 / 3.4; on-clay 4.5; on-ink 14.5; focus ring 14.5.
Dark: ivory on window 14.5, on panel 12.5; `text-secondary` 6.3 / 5.4; `text-tertiary` 5.6 / 4.8; `border-control` 4.9 / 4.2; ink on clay-light 5.1.
Flow Bar: `flow-text` 14.5; `flow-text-secondary` 5.3; `flow-live` 5.1; stop glyph on `flow-live` 5.1; X on `flow-cancel` 11.2; idle mark 4.0 (non-text).

**Swift sketch**

```swift
public struct ThemeColors: Sendable {
    public let bgWindow, bgPanel, bgSunken, fillHover, fillSelected, fillChip: Color
    public let textPrimary, textSecondary, textTertiary, stone: Color
    public let borderHairline, borderDivider, borderControl: Color
    public let accentClay, accentClayPressed, onClay, inkFill, inkFillPressed, onInk, focusRing: Color
    public static let light = ThemeColors(/* §3.2 */)
    public static let dark  = ThemeColors(/* §3.2 */)
}
public struct FlowBarColors: Sendable { /* §3.2, .light and .dark by system appearance */ }
extension EnvironmentValues { @Entry public var theme = Theme.light }
```

A `ThemeProvider` root view reads `\.colorScheme` plus the Appearance setting and injects `\.theme`. The Flow Bar panel and status item map the same tokens to `NSColor` and pick by `NSApp.effectiveAppearance`.

### 3.3 Typography

Bundle static instances in `Sources/UI/Resources/Fonts/` with licenses: **Geist** 400, 500, 600; **Geist Mono** 400, 500; **Newsreader** 400, 400 Italic, 500. If only variable fonts are available, cut static instances with `fontTools.varLib.instancer` and commit them. Register at launch with `CTFontManagerRegisterFontsForURLs(..., .process, ...)`. Unit-test that every token font resolves to a non-fallback `NSFont`. If the network blocks the download, stop and ask the owner to drop the files in.

| Token | Font | Size / line | Tracking | Use |
| --- | --- | --- | --- | --- |
| `page-title` | Newsreader 400 | 40 / 42 | −0.015 em | Hub titles; one word may be italic ("Welcome back, *Swarit*") |
| `welcome-title` | Newsreader 400 | 34 / 37 | −0.01 em | Onboarding welcome |
| `feature-title` | Newsreader 400 | 30 / 33 | −0.01 em | Feature card, one italic word |
| `step-title` | Newsreader 400 | 28 / 32 | 0 | Onboarding steps |
| `card-title` | Newsreader 400 | 22 / 22 | 0 | Style names |
| `trigger` | Newsreader 400 Italic | 18 / 24 | 0 | Snippet triggers, in curly quotes |
| `quote` | Newsreader 400 Italic | 16 / 22 | 0 | What you said, sounds-like, practice lines |
| `sample` | Newsreader 400 | 15 / 21 | 0 | Finished-writing samples |
| `body` | Geist 400 | 14 / 22 | 0 | Paragraphs, history rows |
| `nav` | Geist 400 (500 selected) | 14 / 20 | 0 | Sidebar |
| `button` | Geist 500 | 14 / 20 | 0 | 40 pt buttons |
| `label` | Geist 500 | 13 / 18 | 0 | Settings labels, Flow Bar text, menu header |
| `control` | Geist 500 | 13 / 18 | 0 | Segmented controls (12 in the small size) |
| `hint` | Geist 400 | 12 / 17 | 0 | Row hints, card descriptions, 28 pt buttons |
| `flow-sub` | Geist 400 | 11 / 14 | 0 | Second line in Flow Bar toasts |
| `caption` | Geist Mono 500 | 11 / 14 | +0.08 em, uppercase | "TODAY", "DICTATION" |
| `meta` | Geist Mono 400 | 11 / 22 | 0 | Times, counts, "Mail · 15 w", versions |
| `keycap` | Geist Mono 500 | 10–13 by size | 0 | Key caps |
| `stat` | Geist Mono 500 | 12 / 16 | 0 | Home stat strip |
| `tag` | Geist Mono 400 | 10 / 14 | 0 | Badges, card descriptors |

Minimum text size 10 (tags only); everything else 11 or larger. Expose `Tokens.type.scale` and a Settings row "Text size: Default / Large" (1.0 / 1.15); nothing may clip at 1.15.

### 3.4 Geometry [BOARD]

**Spacing scale** (pt): 4, 8, 10, 12, 14, 16, 20, 24, 28, 32, 44, 56.

**Radii:** key cap small 5, key cap 7, control 8, button 10, card 12, card-lg 14, feature 16, pill full.

**Shadow:** `shadow-float` = y 12, blur 32, spread −14, ink 30%. Paper toast and popovers only.

**Hub window**

| Element | Value |
| --- | --- |
| Window | Default 1180 × 740, min 880 × 560 [ASSUMED]; `bg-window`; transparent title bar, full-size content |
| Sidebar | 232 wide; padding 14 top, 12 sides and bottom; items stacked with 2 gap |
| Traffic lights zone | 16 tall at the top of the sidebar (system controls) |
| Brand mark | 22 tall, inset 22 top and bottom, 10 left |
| Sidebar item | 36 high, radius 8, padding 0 × 10, icon 18 (stroke 1.6), 10 gap, `nav` type; selected: `fill-selected` + weight 500 |
| Sidebar bottom | Settings, Help & setup, then a status card: radius 12, padding 12, `bg-panel`, 1 pt ink 12%; "Ready" `label` + "on-device" `tag`; "Hold [HOTKEY] to dictate" `hint` with an inline key cap; mic name `meta` |
| Content panel | Inset 8 from top, right and bottom; radius 12; `bg-panel`; 1 pt ink 12% |
| Panel top bar | 48 high (Home only): 32 × 32 icon buttons, radius 8 (search, bell). Bell dot: 7 pt ink with a 2 pt `bg-panel` ring |
| Page padding | 44 top (8 on Home, under the top bar), 56 sides |
| Section gap | 28 on Home, 22 on other pages |

### 3.5 Flow Bar geometry [BOARD]

The bar sits 8 pt above the Dock (SPEC placement rules unchanged). Every surface gets the 1 pt inset `flow-ring`.

| Element | Value |
| --- | --- |
| Idle pill | 52 × 12, centered dash 20 × 1.5, radius 2, `flow-idle-mark` |
| Hover pill | 76 × 28; still waveform 44 × 12 at level 0.35, ivory 60% |
| Tooltip | 28 high pill, padding 0 × 10, 6 above the pill; `hint` 12/500 in `flow-text`; inline key cap 18 high, radius 5, mono 10, ivory rings |
| Active pill | 36 high, full radius |
| Live dot | 6, `flow-live` |
| Waveform | 112 × 22 (hold-to-talk), 96 × 22 (hands-free) |
| Round buttons | 24 diameter. Cancel: `flow-cancel` with a 12 pt X, stroke 2.2. Stop: `flow-live` with an 8 × 8 square, radius 2, `flow-stop-glyph` |
| Processing pill | 144 × 36 with five 5 pt dots, gap 3.75 |
| Toast / alert card | Radius 16; padding and content per state (§5.1); buttons 26–28 high, radius 8, padding 0 × 10, `hint` 12/500 |
| Countdown ring | 22, stroke 2, track at 22%, center number mono 9 |

### 3.6 Icons and brand

**UI icons.** An original line set on a 24 pt grid, **1.6 pt stroke, round caps and joins**, drawn as SwiftUI `Shape`s from the SVG path strings in the boards. The 24 core icons and their exact paths are in `Design/reference/html/Components.dc.html` (the `ICONS` array): mic, wave, stop, cancel, check, retry, clipboard, alert, textfield, hotkey, hands-free, history, home, dictionary, snippet, style, settings, cleanup, local, shield, globe, branch, star, download. The Hub boards add: search, bell, copy, trash, edit, plus, chevrons, info, help, mail, chat, lines (work chat), code, note, mic-off. Their paths are inline in the Hub `.dc.html` files. Use an `Icon` enum. Anything you can't find maps to an SF Symbol at `.regular` and is logged in `docs/ui-todo.md`.

**The mark** (`Design/brand/murmur-mark.svg`, aspect 2.65 : 1, one path). Build `BrandMark` as a `Shape` from the path. `accent-clay` on light, `#D9705F` on dark. Never stretch or recolor outside these; keep clear space at least the M's stroke width.
- *Sidebar:* 22 tall.
- *Onboarding welcome:* the app icon at 128, not the lockup.

**App icon.** Generate the full `.iconset` (16 to 1024 at 1× and 2×) from `Design/brand/app-icon.svg` and build `Assets.xcassets/AppIcon`. The icon is a cream rounded tile with the M, one big lobe, then the logo's own tapering tail; it reads at 16 px. `app-icon-dark.svg` is for marketing and the dark Components board only; macOS uses one icon.

**Menu bar glyph.** From `Design/brand/menubar-template.svg`: 18 pt, `isTemplate = true`, at 1×, 2× and 3×. States:
- *Idle:* template, system-tinted.
- *Recording:* a non-template copy in `accent-clay` plus a 5 pt clay dot to its right, 4 pt gap.
- *Processing:* template at 45% opacity plus five 2.5 pt rippling dots.
- *Error:* template plus a 9 pt ink badge with a white "!" (bold 7 pt) at the bottom-right, cut out from the glyph by a 1.5 pt ring of the menu bar color. Never red.

---

## 4. Components

Build all in `Sources/UI/Components/` and show every state in the Design Gallery, light and dark.

Every interactive component has default, hover, pressed, focused and disabled states. **Hover** changes fill only. **Pressed** moves down 1 pt and uses the `*-pressed` fill. **Focused** draws the 2 pt `focus-ring` with a 2 pt gap, always visible on keyboard focus. **Disabled** uses `fill-selected` with `text-tertiary`, no hover.

| Component | Spec [BOARD unless tagged] |
| --- | --- |
| `MButton` | **primary:** `accent-clay`, `on-clay` text, radius 10, 40 high, padding 0 × 18–20, `button` type, optional 15 pt leading icon with 8 gap. **ink:** `ink-fill` / `on-ink`, same shape (Add word, New snippet, Save). **outline:** lg has a 1 pt solid `text-primary` ring (View on GitHub); sm has a 1 pt `border-control` ring (Change). **link:** text only, underline offset 4, underline color ink 30% (Not now, Skip, Undo in paper toasts). **icon:** 28 or 32 square, radius 7–8, `aria`-labelled. Small size: 28 high, radius 8, padding 0 × 12, 12/500. One primary per surface. |
| `MToggle` | 40 × 24 (small 34 × 20). On: `ink-fill` track, 18 pt `on-ink` knob inset 3. Off: no fill, 1 pt `border-control` ring, `stone` knob. Knob moves on a spring (§6). Whole row is the hit target. |
| `MSegmented` | Track `fill-selected`, radius 10, padding 2. Segment 30 high, radius 8, padding 0 × 14, `control` type. Selected: `bg-panel` + 1 pt ink 14% ring, `text-primary`. Unselected: `text-tertiary`. Small: 26 high, radius 7, padding 0 × 10, 12 pt. Selection slides (`matchedGeometryEffect`). Arrow keys move it. Used for tabs and for value pickers. |
| `MTextField`, `MSearchField` | 34–36 high, radius 8, `bg-panel`, 1 pt `border-control`, 13 pt text. Focus: 1 pt `text-primary` border plus a 3 pt halo at ink 8%. Search has a 14 pt leading icon, 8 gap. A "sounds like" field uses the `quote` style. |
| `MSelect` | 30 high, radius 8, `bg-panel`, 1 pt `border-control`, 12 pt text, trailing up/down chevrons (10 pt, stroke 2.4). Opens a native menu. A "navigate" variant has a right chevron. |
| `MKeycap` | Inline: 18–22 high, radius 5, mono 10–11. Standard: 28–32 high, radius 7, mono 12–13, padding 0 × 10. Fill `bg-panel` (or `bg-window` inside panels), inset 1 pt ink 25% plus a 2 pt bottom inset at ink 14%. Pressed: `ink-fill` with `on-ink` text, 1 pt down. On the Flow Bar: no fill, ivory 30% ring plus a 1.5 pt bottom ring at ivory 20%. |
| `MRadio` | 14 pt. Empty: 1 pt `border-control`. Selected: 4.5 pt `ink-fill` inset ring. |
| `MSelectableCard` | Radius 14 (12 for snippets), `bg-panel`, 1 pt ink 16% ring. Selected: 1.5 pt `ink-fill` ring and a filled `MRadio` top-right. Never clay. |
| `MFeatureCard` | `bg-sunken`, radius 16, padding 28, 32 gap between text and visual. At most one per page. |
| `MList` / `MListRow` | Container: radius 12, 1 pt ink 14%, rows divided by `border-divider`. Hover: `fill-hover` and trailing action buttons fade in over 100 ms. |
| `MTag` | 20 high, radius 5, padding 0 × 7, `tag` type. Outline variant ("added"): 1 pt ink 20% ring. Filled variant ("learned"): `bg-sunken`. |
| `MStatStrip` | 32 high pill, `fill-chip`, `stat` type, groups padded 0 × 14, divided by 1 × 14 lines at ink 18%. Hide any stat that can't be computed. |
| `MAppTile` | 24 square, radius 6, 1 pt ink 20% ring, 13 pt icon (stroke 1.8). Identifies the app a dictation went into. |
| `MPaperToast` | `bg-panel`, radius 14, padding 10 × 14, 1 pt ink 18%, `shadow-float`, 16 pt icon, `label` + `text-tertiary` detail, link-style Undo. Bottom-center of the panel, 22 above its edge. |
| `MSidebarItem`, `MStatusCard` | §3.4. |
| `MStepFrame` | Onboarding step (§5.4). |
| `MEmptyState` [ASSUMED] | A `bg-sunken` well with the idle Flow Bar pill, one `body` line, an optional primary button. |
| Flow Bar parts | `FlowPill`, `FlowWaveform` (one `Canvas`), `FlowDots`, `FlowRing`, `FlowToast`, `FlowTooltip`. §5.1. |
| `FocusRing` modifier | The one place focus is drawn. |

---

## 5. Screens

### 5.1 Flow Bar (the signature surface; every state reachable from the debug menu)

The panel frame is **fixed at the largest state** and transparent. Animate the SwiftUI content inside it, never the `NSWindow` frame (it jitters). Hit-testing passes through everywhere except the visible pill, tooltip and toast. Toasts and alerts replace the pill in place, bottom-anchored on the same edge, morphing from the pill's width [ASSUMED morph].

| # | State | Visual [BOARD] | Timing |
| --- | --- | --- | --- |
| 1 | Idle | 52 × 12 pill, centered dash | Fades to 40% opacity after 10 s idle |
| 2 | Idle hover | 76 × 28 with a still hairline wave; tooltip above: "Hold [HOTKEY] to dictate" with the user's key as an inline key cap. A click starts hands-free | Tooltip after 400 ms |
| 3 | Listening, hold-to-talk | 36 high, padding 0 × 16, gap 10: live dot + 112 × 22 live waveform | Width springs 240 ms from idle on key-down; waveform at display rate |
| 4 | Listening, hands-free | Padding 0 × 6, gap 10: cancel button, 96 × 22 waveform, timer (mono 11/500, ivory 70%), stop button. ✕ discards; ■ stops and transcribes | Timer appears after 3 s; at 5 min the pill nudges (one 4% scale pulse) [ASSUMED nudge] |
| 5 | Processing | 144 × 36, five ivory dots rippling left to right. Clay leaves: the mic is off | Period 1.1 s; key-up to text ≈ 400 ms |
| 6 | Inserted | Padding 0 × 16 left 12, gap 8: 16 pt check (stroke 2), "Inserted" `label` + "24 words" `flow-text-secondary` | Check draws 180 ms, holds 1.2 s, then shrinks to idle |
| 7 | Cancelled | Card, padding 8 / 8 / 8 / 12, gap 10: countdown ring, "Cancelled", **Undo** (`flow-button`), **Open History** (`flow-button-ring`). Undo transcribes the discarded audio | Ring drains over 5 s, pauses on hover; audio kept until then |
| 8 | Paste error | 40 high card, padding 0 × 14 left 12, gap 10: clipboard icon, "Copied to clipboard — press" + ⌘ V key caps (20 high, mono 11) | 4 s; slides up 8 pt and fades |
| 9 | Transcription error | Card, padding 6 / 6 / 6 / 12, gap 10: alert icon; "Couldn't transcribe that" / "Engine timed out · audio saved" (`flow-sub`, secondary); **Retry** (`flow-button` with a 12 pt retry icon). Retry re-runs the same recording | Sticky 8 s; 2 pt horizontal shake on entry; no red |
| 10 | No text box | Card like #9: text-field icon; "No text box selected" / "Saved to History and clipboard"; **Dismiss** (ring button) | Until dismissed |
| 11 | No audio | 276-wide card, padding 10, column gap 10: mic-off icon + "We couldn't hear you" / "No speech from <mic name>"; **Switch microphone** (`flow-button`) and **Test mic** (ring), 26 high. Test mic opens the onboarding mic test as a sheet | Sticky 8 s |
| 12 | Right-click menu | Native `NSMenu`: Start hands-free · Paste last transcript ⌃⌥V · Hide for 1 hour · Settings… ⌘, | — |

### 5.2 Menu bar

Status item glyph and states per §3.6. The dropdown is a native `NSMenu` in this order:

1. **Header** (custom `NSMenuItem.view`): "Murmur is ready" `label` / "Hold [HOTKEY] to dictate · double-tap for hands-free" `hint`. While listening: a 7 pt `flow-live` dot, "Listening…", the mic name, and a mono timer. After an error: the error with a one-line fix.
2. Open Murmur ⌘O · Paste last transcript ⌃⌥V · Copy last transcript ⌃⌥C
3. Microphone ▸ (Automatic (Built-in) ✓, each input device, separator, Sound Settings…) · Hide Flow Bar for 1 hour
4. Shortcuts… · Settings… ⌘, · Check permissions (shows "1 missing" when Microphone, Accessibility or Input Monitoring is missing)
5. Quit Murmur ⌘Q
6. **Footer** (custom view): mono "v[VERSION] · on-device engine".

Separators between groups. Highlight is the system's; don't restyle it.

### 5.3 Hub window

Chrome and sidebar per §3.4. Sidebar items: Home, Dictionary, Snippets, Style; at the bottom Settings, **Help & setup** (opens a sheet: shortcuts, check permissions, re-run onboarding, version), then the status card. Page switch: 160 ms cross-fade with a 6 pt rise. Keyboard navigation per SPEC.

**Home** (Design/reference/hub-home.png)
- Caption: today's date ("MONDAY, 5 OCTOBER"). Title "Welcome back, *<first name>*" (from `NSFullUserName()` [ASSUMED]; no name → "Welcome back").
- Stat strip, right-aligned with the title: "7-day streak · 6,343 words · 112 wpm", computed cheaply from Store aggregates.
- Feature card: "Make Murmur sound like *you*" + "Pick a style for messages, work chats and email. Murmur switches on its own, based on the app you're typing in." + **Set up styles** (primary, opens Style) + **Not now** (link; dismisses for good, stored). Right side, 320 wide: three sample cards (radius 12, padding 10 × 12, `bg-panel`, hairline 12%) each with an `MAppTile`, a `tag` line ("Messages · very casual") and a `sample` line.
- "TODAY" caption + `MSegmented` small: Cleaned | Raw (switches what every row shows).
- History list rows: grid 52 / 24 / flexible / 112, gap 14, padding 13 × 16. Time (`meta`), `MAppTile`, transcript (`body`), right meta "Mail · 15 w". Hover: actions Copy, Paste again, and a "raw" chip (mono 11 on `fill-selected`) that peeks at the raw text. Silent audio: mic tile at 12% ring, `text-tertiary` "Audio was silent" + info icon whose tooltip explains, "0 w". Then "YESTERDAY" and older date groups.

**Style** (hub-style.png)
- Title "Style" + "How Murmur writes in each kind of app. It looks at the app you're typing in and uses the matching style."
- `MSegmented`: Personal messages | Work messages | Email | Other.
- Four `MSelectableCard`s in a row, gap 12, padding 14: `card-title` name (Formal. / Casual / very casual / Excited!), a `tag` descriptor ("Caps · full punctuation"), and a `bg-sunken` sample box (radius 10, padding 10 × 12, `sample` type). Use the real example text from the existing implementation.
- Divider, then "AUTO CLEANUP" + "How much Murmur tidies what you said before it types. Applies to every style." with "You said" + the raw `quote` on the right.
- Three cards None / Light / Medium (padding 14 × 16): `label` title, `hint` description, `sample` result.

**Dictionary** (hub-dictionary.png)
- Title + "Names and words Murmur should always spell right. They're also passed to the speech engine as hints." + **Add word** (ink, plus icon).
- `MSearchField` 320 wide ("Search N words") + small segmented filter: All | Added by you | Learned.
- `MList`: the add/edit row sits at the top in place (`fill-hover` background; Word field focused; "Sounds like (optional)" field in `quote` style; Cancel link; **Save** ink sm). Rows 46 high, grid 200 / flexible / 84 / 72 / 64: word (`label` 14), sounds-like (`quote`, or "—" in `text-tertiary`), `MTag` (added = outline, learned = filled), "N uses" `meta`, hover actions Edit and Remove.
- After a save: `MPaperToast` "Added to Dictionary · "<word>"" with Undo.

**Snippets** (hub-snippets.png)
- Title + "Say a trigger on its own and Murmur types the full text in its place." + **New snippet** (ink).
- Two-column grid, gap 12, of cards (radius 12, padding 16): trigger in `trigger` style with curly quotes, a right arrow (14 pt, `text-tertiary`), "N uses" `meta`; below, the expansion in a 1 pt dashed box at ink 25% (radius 8, padding 10 × 12, 13 / 1.5, preserves line breaks). Hover/selected: 1.5 pt ink ring with Edit and Delete icon buttons in place of the count.

**Settings** (hub-settings.png)
- Title + `MSegmented`: General | System | Experimental | Data & privacy.
- General is two columns, gap 24. Each group: `caption` then a list container (radius 12) of rows (padding 12 × 14): `label` + `hint` on the left, control on the right.
  - **Dictation:** Push-to-talk (key cap + Change), Hands-free (⌥ Space key caps + Change), Microphone (`MSelect`), Languages (navigate `MSelect` showing the chosen list).
  - **Appearance:** Theme (System / Light / Dark; hint "The Flow Bar stays ink either way."), Text size (Default / Large; "Applies to the Hub only.").
  - **Output:** Auto cleanup (None / Light / Medium), Speech engine (`MSelect`, mono, shows [ENGINE]), Sounds (toggle), Show Flow Bar (toggle), Launch at login (toggle).
  - Info card (`bg-sunken`, radius 12, padding 14, shield icon): "Nothing leaves this Mac" / "Audio and transcripts stay on-device. Retention lives under Data & privacy."
- The other tabs hold the remaining SPEC settings in the same row pattern.

### 5.4 Onboarding (onboarding.png; same steps, order and behavior as SPEC §6)

Window content is one 400 × 560 step [ASSUMED window size], `bg-window`, padding 28, gap 20. Header: mono "02 / 10 · Permissions" on the left, a 120 × 2 progress bar (ink on ink 12%) on the right. Illustration wells are `bg-sunken`, radius 12, 200–220 high. Footer: "Back" (13, `text-tertiary`) left, one primary clay button right. Steps cross-fade with a 12 pt upward drift. Resume-where-stopped, skip-granted-steps and auto-advance are unchanged.

| # | Step | Illustration | Title / body | Primary |
| --- | --- | --- | --- | --- |
| 1 | Welcome | App icon 128 | "Speak, and it's written." / "Murmur turns your voice into clean, punctuated text in any app. Free, open source, and private by default." + mono "v[VERSION] · macOS [MIN_MACOS] or later" | Get started (full width) |
| 2 | Microphone | A mock system mic prompt | "Let Murmur hear you" / "Only while you hold the shortcut. Audio is transcribed on this Mac and deleted right after, unless you choose to keep it." | Allow microphone |
| 3 | Accessibility | A mock Privacy & Security › Accessibility list with Murmur on | "Let Murmur type for you" / "Accessibility lets Murmur place text at your cursor in any app. It doesn't read your screen." + ripple dots "Waiting for permission — this updates on its own" | Open System Settings |
| 4 | Input Monitoring | A 56-high [HOTKEY] key cap and a "down … held 0.6s" hold meter | "Notice when you hold the key" / "Input Monitoring is how Murmur knows [HOTKEY] is being held down — and released. It watches that one key; nothing you type is logged or stored." | Open System Settings |
| 5 | Mic test | Level meter (18 bars, 8 wide, gap 4, 64 high, heights ramping 30–100%; lit bars ink, lit bars in the last third clay) + `quote` "Pack my box with five dozen jugs." | "Check your mic" / "Read the line above at your normal volume. Aim for the bars to reach the last third." + mic `MSelect` | Sounds good |
| 6 | Shortcut | Two `MSelectableCard`s: Push-to-talk ([HOTKEY], "Hold, speak, release", "Best for quick replies and short notes.") and Hands-free (⌥ Space, "Tap to start, tap to stop", "Best for long emails and thinking out loud.") | "Pick how you talk" / "You can use both. Change them any time in Settings." | Continue |
| 7 | Languages | Search "Search 99 languages" + 32-high chips; selected chips are `ink-fill` with a check | "Which languages do you speak?" / "Murmur switches between them automatically, even mid-sentence." | Continue with N |
| 8 | Practice | A practice field (`bg-panel` card) with the **real** Flow Bar component docked at its bottom | "Try it once" / "Hold [HOTKEY] and say: *"um remind me to call Mom on Sunday, uh, at noon."*" | Looks right (Skip on the left) |
| 9 | Data | Two radio cards: "Nothing leaves this Mac" / "No analytics, no crash reports. Murmur works fully offline." and "Share anonymous crash reports" / "Stack traces and app version only — never audio, text or app names. Helps contributors fix bugs." + toggle "Keep audio for 7 days" | "Your data, your call" / "Either way, audio and transcripts never leave this Mac." | Continue |
| 10 | Flow Bar | The idle pill over a sketched Dock with a hand-drawn arrow and `quote` "This little pill" (original drawing) | "This is the Flow Bar" / "It rests just above your Dock. Hold [HOTKEY] in any app and it opens up to listen. Hide it any time from the menu bar." | Start dictating (opens Home) |

If SPEC has no crash reporting, drop the second card in step 9; don't add networking.

---

## 6. Motion and sound

### 6.1 Motion tokens

| Token | Value | Source |
| --- | --- | --- |
| `bar.width` | spring, ≈ 240 ms settle (response 0.24, damping 0.82) | BOARD |
| `bar.idleFade` | to 40% opacity after 10 s, 400 ms ease | BOARD |
| `bar.tooltip` | 400 ms delay in, 100 ms out | BOARD |
| `bar.timerDelay` | 3 s | BOARD |
| `bar.nudge` | at 5 min, one 4% scale pulse, 300 ms | ASSUMED |
| `wave.attack` / `wave.release` | ≈ 50 ms / ≈ 180 ms one-pole on level (0.30 / 0.09 per frame at 60 fps) | BOARD (reference code) |
| `dots.period` | 1.1 s, phase step 0.62 rad per dot, lift up to 0.9 × dot size, opacity 0.4 → 1 | BOARD |
| `inserted.check` / `inserted.hold` | 180 ms stroke draw / 1.2 s | BOARD |
| `toast.paste` | 4 s, rise 8 pt + fade | BOARD |
| `toast.cancel` | 5 s ring, pauses on hover | BOARD |
| `alert.sticky` | 8 s | BOARD |
| `alert.shake` | 2 pt horizontal, 3 cycles, 240 ms | BOARD amplitude; ASSUMED duration |
| `onboarding.step` | cross-fade 220 ms with a 12 pt upward drift | BOARD drift; ASSUMED duration |
| `hub.pageSwitch` | 160 ms ease-out, 6 pt rise | ASSUMED |
| `ui.hover` | 100 ms ease | ASSUMED |
| `ui.press` | 80 ms, 1 pt down, `*-pressed` fill | BOARD |
| `toggle.knob` | spring response 0.22, damping 0.80 | ASSUMED |
| `segmented.select` | spring response 0.28, damping 0.85 | ASSUMED |
| `timeScale` | global multiplier, default 1.0; debug panel can set 0.2 | — |

### 6.2 The waveform (port `drawWave` from `Design/motion/murmur-motion.js`)

The logo's tail, alive: a filled shape between a top and bottom contour around the center line.

- **Envelope over x** (u = x / width): rise with `sin(π/2 · u / 0.14)` over the first 14%, flat to 42%, then fall as `(1 − (u − 0.42) / 0.58)^1.35` to a hairline at the right end.
- **Lobes:** `width / 15` lobes; phase `p = u · lobes · π − 2.4 · t`; lobe index `k = floor(p / π)`; lobe shape `sin(p − kπ)^1.2`. Each lobe's height drifts slowly between 0.3 and 1.0 (`lobeHeight(k, t)` in the reference).
- **Contours:** top = mid − (0.35 + amp · gain · env · height_top · shape); bottom = mid + (0.35 + 0.82 · amp · gain · env · height_bottom · shape), where amp = height / 2 − 0.75. The 0.35 pt half-thickness is the 0.7 pt silence hairline.
- **Gain:** the real mic level after `wave.attack` / `wave.release` smoothing, × 2.1, capped at 1. The reference's `speech()` function is a demo signal; never ship it.
- One `Canvas` inside a `TimelineView(.animation)` that is **paused** unless listening. Read the level at display rate from an atomic or lock-protected value; never publish from the audio thread per buffer.
- The still variant (hover pill, gallery) draws one frame at a fixed level.

`FlowDots`, `FlowRing` and the onboarding level meter follow the same file (`MurmurDots`, `MurmurRing`, `MurmurLevels`).

### 6.3 Accessibility switches

- **Reduce Motion:** springs become 120 ms fades; no scale or position changes; the waveform still follows the mic (it's data) but drops release smoothing; the dots become a 1.6 s opacity pulse; the shake becomes a single fade; page and step transitions are plain cross-fades.
- **Reduce Transparency:** this design has no materials; keep the code path.
- **Increase Contrast:** `border-hairline` and `border-divider` → `border-control`; `text-tertiary` → `text-secondary`; `flow-ring` → ivory 40%; selected-card ring 1.5 → 2 pt.

### 6.4 Sounds

Unchanged from v1: regenerate three original WAVs with `Tools/make_sounds.py` (numpy only, 44.1 kHz, 16-bit mono) from tokens in `Tokens+Sound`. **Start** is two soft sine plucks rising a fifth (784 Hz, then 1175 Hz), 55 ms each, 6 ms attack, 40 ms exponential decay, peak −18 dBFS. **Stop** is the same pair falling. **Error** is two 70 ms triangle pulses at 330 Hz, 50 ms apart, peak −16 dBFS. 5 ms fades. Keep the Settings switch. No sounds in the Hub.

---

## 7. Milestones

Work on a branch named `ui-redesign`. One commit per milestone, message `U<n>: <title>`. **Run the milestones in order without waiting for the owner.** After each one, append its report (§10) to `docs/ui-progress.md`, commit, and move on once its "Done when" is true. If a "Done when" can't be met after a real attempt, record what failed and why in the report and continue, unless later milestones depend on it. If a milestone would change dictation behavior, stop and ask. If the session ends midway, the next session resumes from `docs/ui-progress.md`.

### U0 — Audit and harness

1. Read `SPEC.md`, this file, `Design/`, `Package.swift` (note the deployment target; gate newer APIs) and everything under `Sources/UI`.
2. Write `docs/ui-audit.md`: each view, each system control it uses, the current `Tokens*.swift` API (keep names where they fit; give a migration list where they don't), how the Hub window and the Flow Bar panel are built, and what v1 work exists to reuse.
3. Snapshot tool (`murmur-snap`, reuse if present): renders any view to PNG with `ImageRenderer` at 2× in light and dark with fixture data into `Artifacts/ui/`. Render the current UI to `Artifacts/ui/before/`.
4. Design Gallery window (debug only) and debug panel: appearance override, Reduce Motion override, `timeScale`, text scale, force Flow Bar state.

*Done when:* `swift run murmur-snap` produces before-images for every Hub page and Flow Bar state, and `docs/ui-audit.md` exists.

### U1 — Tokens, theme, fonts

1. `Tokens+Color`, `+Type`, `+Geometry`, `+Motion`, `+Sound` with every value in §3 and §6. Each token gets a doc comment `source: board | logo | derived | assumed`; derived and assumed ones also get `// MEASURE`.
2. A unit test that every color token matches `Design/tokens.json`.
3. `ThemeProvider`, `\.theme`, Appearance and Text size settings.
4. Bundle and register Geist, Geist Mono and Newsreader (§3.3).
5. Token lint and contrast tests (§8).

*Done when:* lint, contrast and font-resolution tests pass; the app builds and looks unchanged.

### U2 — Components, icons, brand

Every §4 component, the icon set, `BrandMark` from `murmur-mark.svg`, the app iconset and `AppIcon`, and the menu bar template images in four states. Every state visible in the Gallery, light and dark.

*Done when:* Gallery snapshots exist for all components in both schemes; keyboard focus is visible on every interactive component; every component respects Reduce Motion.

### U3 — Flow Bar

1. All twelve states in §5.1, light and dark appearance.
2. Rendering per §5.1 and §6.2. Port the waveform, dots and ring.
3. Generated sounds (§6.4).
4. VoiceOver labels and state descriptions on the bar.
5. Every state reachable from the debug panel; tokens tunable live.

*Done when:* all states snapshot and sit side by side with the board crops in a contact sheet; the "never takes focus" test passes; idle CPU with the bar visible is 0%; a 10 s dictation profile stays within the SPEC frame budget.

### U4 — Hub shell and Home

Window chrome, sidebar, status card, panel, top bar and bell popover (lists system alerts such as a revoked permission), Home. Remove every stock `NavigationSplitView` and `List` from the Hub.

*Done when:* the Home snapshot at 1180 × 740 matches `Design/reference/hub-home.png` within ±2 pt on the §3.4 numbers; light and dark render; Option+Up/Down and Cmd+[ / Cmd+] still work.

### U5 — Style, Dictionary, Snippets

Per §5.3, with real data and examples from the existing implementation.

*Done when:* all three pages work with the new components, behave exactly as before, and have snapshots in both schemes next to their reference crops.

### U6 — Settings

Per §5.3, every stock control replaced, the new Appearance and Text size rows added.

*Done when:* every setting still persists and all four tabs have snapshots in both schemes.

### U7 — Onboarding

Per §5.4.

*Done when:* every step renders in snapshots in both schemes; resume-where-stopped and skip-granted-steps work with permissions reset (`tccutil reset All <bundle id>`); the permission-revocation test still passes. A full run in a fresh macOS user account goes on the owner's manual checklist.

### U8 — Menu bar, polish, accessibility

1. Status item states and the dropdown (§5.2).
2. Reduce Motion, Increase Contrast, text size 1.15 and VoiceOver passes on every screen; fix clipping.
3. Remove dead code and unused system-control styles. Write `docs/ui-calibration.md` (§9).
4. Final `Artifacts/ui/after/` and a contact sheet with three columns: before, after, reference board crop.

*Done when:* every §8 check passes and the contact sheet exists.

---

## 8. Verification and tooling

**Token lint** (`scripts/check-tokens.sh`, CI and pre-commit): in `Sources/UI/**` outside `Tokens*.swift`, fail on `Color(red:`, `Color(hex`, `NSColor(red`, `.font(.system(size`, `.font(.custom(` with a literal size, `.cornerRadius(<literal>)`, `.frame(width: <literal>`, `.padding(<literal>)`, `.animation(.spring(` with literals, and `lineWidth: <literal>`. Allow `0` and `.infinity`.

**Contrast tests** (`ContrastTests`): compute the WCAG ratio for every pair listed in §3.2 in both schemes and assert at least the stated value minus 0.05. Also fail if `stone` is used as a text color anywhere, if `accent-clay` appears outside primary buttons, the live mic, the recording menu bar icon and `BrandMark`, or if any view uses a red.

**Snapshot tool:** renders every page and component in light, dark, text scale 1.15 and Reduce Motion, into `Artifacts/ui/`. Fails on a blank image or a reported clipped layout.

**Reference comparison:** `murmur-snap --compare` crops the matching region of each `Design/reference/*.png` (the boards are drawn at 1 pt = 1 px, rendered at 2×) and writes side-by-side sheets to `Artifacts/ui/compare/`. Report the screens with visible differences; don't chase subpixel noise.

**Must stay green:** the SPEC suite, the 50-trial focus test, Reduce Motion behavior (A8), permission-revocation detection (A3), and the SPEC §7 latency budget.

**Manual checklist (for the owner):** the Flow Bar over a full-screen app, a dark app and a light app, with system appearance light and dark; Dock left, right and auto-hidden; two displays; window at 880 × 560 and 1180 × 740; `timeScale` 0.2 on each animation; onboarding in a fresh macOS user account. Do whatever of this you can automate; list the rest at the end of `docs/ui-progress.md` as checks for the owner.

---

## 9. Placeholders and open items (create `docs/ui-calibration.md` from this)

**Placeholders** on the boards, resolved at runtime:

| Placeholder | Becomes |
| --- | --- |
| `[HOTKEY]` | The user's configured push-to-talk key, symbol plus name (for example "fn" or "⌃ Ctrl") |
| `[VERSION]` | `CFBundleShortVersionString` |
| `[MIN_MACOS]` | The deployment target |
| `[ENGINE]` | The active engine's display name from SPEC |
| `[YOUR LINK]`, `[GITHUB_URL]`, `[YOUR ADDRESS]` | Snippet fixture text only; never shipped as defaults |
| "Swarit", "Priya", the stats, the history and dictionary rows | Fixture data for snapshots only |

**Open items** (keep the stated default until the owner decides):

| Item | Default | Owner decision |
| --- | --- | --- |
| Hands-free trigger | Whatever SPEC defines. The boards show both "double-tap [HOTKEY]" and "⌥ Space"; show the real binding everywhere | Confirm the trigger |
| Crash reports card (onboarding step 9) | Omit if SPEC has no crash reporting | Keep or drop |
| Five-minute nudge | One 4% scale pulse | Confirm |
| Toast morph from the pill | Width morph, bottom-anchored | Confirm |
| Onboarding window size | 400 × 560 content | Confirm |
| Hub dark theme | Derived from the Components board's dark tokens; no full dark Hub board exists | Review the dark snapshots |
| Display serif | Newsreader | Confirm |

---

## 10. How to report, and what not to do

**After each milestone, append to `docs/ui-progress.md`:** what changed (files), each "Done when" check with pass or fail, the paths of new snapshot and comparison images, any token you added that isn't in this file (with its source tag), and anything you couldn't do. Keep it short; no recap of the steps. **When all milestones are done**, post a short summary in chat: what's finished, what failed, where the final contact sheet is, and the owner's manual checks.

**Stop and ask** only if: fonts can't be fetched from any source in `START_HERE.md`; a milestone would change dictation behavior; a SPEC test regresses and the cause isn't obvious after a real attempt; a board and this file disagree in a way §0's precedence doesn't settle. For any other judgment call, take the default this file gives, note it in `docs/ui-progress.md`, and keep going.

**Don't:** use gradients, shadows in the Hub (beyond `shadow-float` on floating surfaces), system accent colors, red, any accent besides clay, clay outside §2.8, stone as text, emoji, stock `List` / `Form` / `Toggle` / `Picker` / `TextField` in the Hub, SF Symbols where an original icon exists, the reference app's name, logo, copy or sounds; invent final numbers for [ASSUMED] tokens; animate the `NSWindow` frame; leave an animation running while the bar is idle or the Hub is hidden.

---

## 11. Not in this task: the landing page

A marketing page comes later in this same system: the ivory, ink and clay tokens; Newsreader display with one italic word; the ink Flow Bar and live waveform as the product moment; the reversal headline ("You type faster than you speak", struck through, then "You speak faster than you type"); the mark's waveform drawing itself on load. Keep `Tokens+Color` and `Tokens+Type` free of app-only geometry so a web token file can be generated from them. The earlier landing-page prompt used Anthropic's clay `#D97757` and the reference app's dark chambers; update it to these tokens before using it.
