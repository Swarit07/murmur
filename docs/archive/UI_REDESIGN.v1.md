# UI_REDESIGN.md — Murmur visual redesign (master prompt)

Put this file in the repo root next to `SPEC.md` (the original spec, `claude-code-prompt.md`). Also place the owner's brand files in `Design/`: `murmur-mark.svg` (traced vector of the logo, supplied with this prompt) and `logo-murmur.png` (the owner's original). Read everything. Where files disagree, **SPEC.md hard rules win**, then this file, then your own taste.

Murmur is functionally finished. This task changes how it **looks, moves and sounds**. **No dictation behavior changes.**

**The recipe: a reference dictation app's skeleton, Anthropic's skin, the owner's mark.** Keep the layout, proportions and component shapes of the reference app (the black Flow Bar, the sidebar plus inset content panel, the feature card, the history list). Replace its colors and type with a warm paper, ink and clay theme taken from Anthropic's published theme, with the owner's logo clay as the single accent. The result must feel like its own product, not a copy, and must stop looking like a stock Mac app.

---

## 1. Sources and tags (read this; it explains every tag)

1. **Reference-app screenshots** (five images from the owner): **layout, proportions, component shapes and the Flow Bar form**. Tag **[WIS]**. Sizes were measured in pixels and converted to points.
   - *Hub screenshot scale:* macOS traffic lights are 16 px across and 12 pt in macOS, so **1 pt = 1.333 px**. All Hub sizes use that.
   - *Flow Bar scale (no OS anchor):* I assumed the tooltip text is 12 pt in the reference, giving about **5.7 px per pt**; alerts and toasts assumed 13 pt text, about **3.1 px per pt**. Flow Bar and alert **absolute sizes are [ASSUMED-SCALE]**; their **proportions are measured**.
2. **Anthropic theme page** (the "advanced theming" Streamlit demo). Computed styles were read from the live page. Tag **[ANT]**: app background `#F4F3ED`, raised surface `#F9F9F6`, sidebar `#E8E7DD`, secondary fill `#ECEBE3`, border `#D3D2CA`, text `#3D3A2A`, primary `#BB5A38`, button radius 9.6 px, headings weight 500. The page sets its font to "Styrene B" with "Source Sans" as the fallback. **Styrene B is Anthropic's licensed typeface; do not bundle or imitate it by name.** Use the open fallback instead (§3.3).
3. **The owner's logo** (a raster image): the mark is an "M" whose right stroke flows into a waveform. Sampled colors: **clay `#B54B3C`** on **cream `#F6EEE5`**. Tag **[LOGO]**. A traced vector of it is in `Design/murmur-mark.svg` (one path, `viewBox="0 0 1002 378"`). Its edges were auto-traced: tidy the path by hand if you see nubs at the leg ends.
4. **My adaptation** where nothing above covers a surface (Dictionary, Snippets, Style, Settings, onboarding, dark mode, motion numbers, sounds, the serif display type). Tag **[ASSUMED]** or **[DERIVED]** (computed from sourced values). Every such token gets a `// MEASURE` comment so the owner can replace it.

Never present an assumed value as measured. The earlier plan used the reference website's lavender/ember palette; that is dropped.

**Known gaps (no reference yet):** Dictionary, Snippets, Style, Settings, onboarding, menu bar dropdown, Flow Bar right-click menu, countdown ring, dark mode, all animation timing, all sounds. Design them by extending the system and flag them.

---

## 2. Hard rules (carried over from SPEC.md, plus new ones)

1. **Original assets only.** No Wispr name, logo, icon art, sound files or copy; no Anthropic marks, logos or the Styrene typeface. Screenshots and the theme page are for measuring only; never ship them. Open-source fonts (SIL OFL) are fine.
2. **No hidden magic numbers.** Every size, color, radius, border width, duration, spring and sound parameter is a named token in `Sources/UI/Tokens*.swift`. Views reference tokens only. A lint script (§8) fails on raw literals in view files.
3. **The Flow Bar never takes focus.** Non-activating `NSPanel`, all Spaces, full-screen auxiliary, above the Dock. The SPEC "never takes focus in 50 trials" test must still pass.
4. **Reduce Motion, Reduce Transparency and Increase Contrast** are honored (§6.2).
5. **Light and dark both ship.** Colors resolve from the SwiftUI `colorScheme` environment (not `NSAppearance` lookups inside views). The **Flow Bar looks identical in both** because it floats over other apps.
6. **No system chrome for content.** In the Hub do not use stock `List`, `Form`, `GroupBox`, `Toggle`, `Picker(.segmented)`, `TextField`, `Button` styles or `NavigationSplitView` sidebar vibrancy. Build the §4 components. The menu bar dropdown stays a native `NSMenu`.
7. **Flat.** No gradients. No shadows in the Hub. The Flow Bar has a 1 pt border; an optional soft shadow token defaults to **off**.
8. **Performance budget unchanged** (SPEC §7). Nothing animates while the Hub is hidden or the Flow Bar is idle. The waveform is one `Canvas`, not N animated views.
9. **Fail closed on assets.** If a bundled font fails to load, fall back to system fonts, log once, keep working.
10. Plain sentence-case copy. No emoji, **except** the three stat-chip glyphs on Home (flame, rocket, waving hand), which use Apple's emoji font.
11. **One accent.** Clay is the only accent color. No blues, greens or purples anywhere in the UI.

---

## 3. Design system

### 3.1 Principles

- **Warm paper, ink, one clay.** Paper surfaces, warm-dark ink text, the logo's clay for everything that is "the action" or "the brand".
- **Serif for voice, sans for work.** Titles and the feature card use a serif with one italic emphasis word; everything operational is sans.
- **Black Flow Bar.** Pure black pill, white bars, a clay stop button. The signature element.
- **Soft hairlines instead of shadows.** 1 pt warm borders.
- **Motion is short and kind.** 100–300 ms, one gentle spring on the Flow Bar, otherwise eased fades and 2–6 pt rises.

### 3.2 Color tokens

All hex values are sRGB. Source tags: **ANT** measured from Anthropic's theme page, **LOGO** sampled from the logo, **WIS** from the reference screenshots, **DER** derived by me (computed to hit contrast targets), **ASM** assumed. Where two tags show, the first applies to light and the second to dark.

**Hub and brand tokens**

| Token | Light | Dark | Source | Use |
| --- | --- | --- | --- | --- |
| `bg-window` | `#F4F3ED` | `#181713` | ANT / DER | Window and sidebar background |
| `bg-panel` | `#F9F9F6` | `#1F1E19` | ANT / DER | Content panel and dialogs |
| `bg-card` | `#FFFFFF` | `#26241E` | ANT / DER | Plain cards, settings groups, list container |
| `bg-field` | `#FFFFFF` | `#26241E` | ANT / DER | Inputs and search |
| `bg-hover` | `#E8E7DD` | `#302E26` | ANT / DER | Selected sidebar row, hover fill, icon-button hover |
| `bg-chip` | `#ECEBE3` | `#2A2822` | ANT / DER | Stat chip, tab track, code and keycap-like chips |
| `bg-feature` | `#F6EEE5` | `#2B211B` | LOGO / DER | Warm feature card (the logo's own cream) |
| `border-panel` | `#E3E2D8` | `#34322A` | DER | 1 pt hairlines: panel, list, card |
| `border-feature` | `#E6D6C8` | `#42342B` | DER | 1 pt border on the feature card |
| `border-divider` | `#E8E7DD` | `#2D2B24` | ANT / DER | Row dividers, sidebar rule |
| `border-control` | `#858371` | `#75725F` | DER | Input, secondary button, toggle-off, keycap borders (3:1 or better) |
| `text-title` | `#2A2819` | `#FAF9F5` | DER | Page title |
| `text-primary` | `#3D3A2A` | `#EDEBE0` | ANT / DER | Default UI text, sidebar labels, icons |
| `text-body` | `#4D4A39` | `#D9D6C8` | DER | Paragraphs and history row text |
| `text-secondary` | `#6A6755` | `#A8A596` | DER | Timestamps, captions, descriptions, placeholders |
| `text-disabled` | `#A8A596` | `#6F6C5C` | DER | Disabled and silent-audio text only |
| `text-placeholder` | `#6A6755` | `#A8A596` | DER | Input placeholder |
| `accent-clay` | `#B54B3C` | `#B54B3C` | LOGO | Brand clay: primary button fill, plan badge, toggle-on, selection, notification dot |
| `accent-clay-hover` | `#A24133` | `#C45646` | DER | Primary button hover |
| `accent-clay-pressed` | `#8F3A2E` | `#A24133` | DER | Primary button pressed |
| `accent-clay-text` | `#A8402F` | `#E58B77` | DER | Clay used as text or icon on paper, feature card and tint |
| `accent-clay-tint` | `#F1DDD5` | `#3A241E` | DER | Selected card tint, soft badge fill |
| `button-text` | `#FFFFFF` | `#FFFFFF` | ANT / DER | Text on the clay primary button |
| `focus-ring` | `#8F3A2E` | `#E58B77` | DER | 2 pt keyboard focus outline, 2 pt gap |
| `danger-text` | `#9B3A2E` | `#E58B77` | DER | Error text (always with an icon) |
| `scrim` | `#2A281966` | `#00000099` | DER | Dialog backdrop |

**Flow Bar tokens (identical in light and dark)**

| Token | Light | Dark | Source | Use |
| --- | --- | --- | --- | --- |
| `flow-fill` | `#000000` | `#000000` | WIS | Flow Bar pill, alert and toast fill |
| `flow-border` | `#403D35` | `#403D35` | WIS (warmed) | 1 pt pill border |
| `flow-tooltip` | `#2E2C25` | `#2E2C25` | WIS (warmed) | Tooltip fill |
| `flow-text` | `#FFFFFF` | `#FFFFFF` | WIS | Text on black surfaces |
| `flow-dot` | `#D9D6CC` | `#D9D6CC` | WIS (warmed) | Idle squares |
| `flow-bar` | `#FFFFFF` | `#FFFFFF` | WIS | Active waveform bars |
| `flow-x-circle` | `#77746A` | `#77746A` | WIS (warmed) | Cancel circle |
| `flow-x-glyph` | `#ECEAE0` | `#ECEAE0` | WIS (warmed) | X glyph |
| `flow-stop` | `#C9503F` | `#C9503F` | LOGO (lifted) | Stop circle; the logo clay lifted 8% for legibility on black |
| `flow-alert-border` | `#3A382F` | `#3A382F` | WIS (warmed) | 1 pt alert and toast border |
| `flow-button` | `#3E3C35` | `#3E3C35` | WIS (warmed) | Buttons inside alerts and toasts |
| `flow-icon-error` | `#E27A66` | `#E27A66` | DER | Error ring icon on black |
| `flow-icon-info` | `#D3D2CA` | `#D3D2CA` | ANT | Info ring icon on black |

*Warmed neutrals:* the reference Flow Bar's grays carry a violet cast. I shifted them to warm equivalents so the bar belongs to this palette. To restore the reference exactly: pill border `#3F3C43`, tooltip `#2A282F`, cancel circle `#737076`, X glyph `#E5E7EA`, idle squares `#D9D9D9`, stop circle `#E06964`, alert border `#383838`, alert buttons `#3D3F43`, error ring `#DB5E59`, info ring `#756AD8`.

*About the clay:* Anthropic's page uses `#BB5A38` as its primary. The owner's logo clay `#B54B3C` is within a hair of it, so the logo color is the single brand accent and the UI matches the logo exactly.

**Verified contrast (WCAG, computed; encode as tests in §8):**
Light: `text-title` on `bg-panel` 14.1; `text-primary` on `bg-panel` 10.8, on `bg-window` 10.3, on `bg-hover` 9.2; `text-body` on `bg-card` 8.9; `text-secondary` on `bg-panel` 5.4, `bg-window` 5.1, `bg-chip` 4.8, `bg-hover` 4.6, `bg-feature` 5.0; `text-disabled` on `bg-panel` 2.4 (disabled and silent rows only, always with an icon or tooltip); white on `accent-clay` 5.2 (hover 6.3); `accent-clay` as text or icon on `bg-panel` 4.9 and on `bg-window` 4.7; `accent-clay-text` on `bg-panel` 5.8, `bg-feature` 5.3, `accent-clay-tint` 4.7; `border-control` on white 3.8, on `bg-panel` 3.6, on `bg-chip` 3.2; `focus-ring` on `bg-panel` 7.1; `danger-text` 6.6.
Flow Bar: white on black 21.0; `flow-dot` 14.4; `flow-x-glyph` on `flow-x-circle` 3.9; `flow-x-circle` on black 4.5; `flow-stop` on black 4.7 with a white glyph on it 4.5; `flow-icon-error` on black 7.2; `flow-icon-info` 13.8; white on `flow-tooltip` 14.0; white on `flow-button` 11.0.
Dark: `text-title` on `bg-panel` 15.9; `text-primary` 14.0 (on `bg-hover` 11.4); `text-body` on `bg-card` 10.6; `text-secondary` on `bg-panel` 6.8, `bg-card` 6.3, `bg-hover` 5.5; `accent-clay-text` on `bg-panel` 6.6 and `bg-card` 6.1; `border-control` on `bg-panel` 3.4 and `bg-card` 3.2; white on `accent-clay` 5.2.

**Swift structure (sketch)**

```swift
public struct ThemeColors: Sendable {
    public let bgWindow, bgPanel, bgCard, bgField, bgHover, bgChip, bgFeature: Color
    public let borderPanel, borderFeature, borderDivider, borderControl: Color
    public let textTitle, textPrimary, textBody, textSecondary, textDisabled, textPlaceholder: Color
    public let accentClay, accentClayHover, accentClayPressed, accentClayText, accentClayTint: Color
    public let buttonText, focusRing, dangerText, scrim: Color
    public static let light = ThemeColors(/* values from the table */)
    public static let dark  = ThemeColors(/* values from the table */)
}
public struct FlowBarColors: Sendable { /* one set, no light/dark */ }
public struct Theme { public let colors: ThemeColors; public let flow: FlowBarColors /* + type, geometry, motion */ }
extension EnvironmentValues { @Entry public var theme = Theme.light }
```

A `ThemeProvider` root view reads `\.colorScheme` and the Appearance setting (System / Light / Dark) and injects `\.theme`. AppKit surfaces (Flow Bar panel, status item) map the same tokens to `NSColor`.

### 3.3 Typography

Two open families (SIL OFL), static instances, bundled in `Sources/UI/Resources/Fonts/` with license files:

- **Source Sans 3** (UI): 400, 500, 600, 700. **[ANT]** The Anthropic theme page names it as the fallback for its own proprietary face, so it is the right open stand-in. Provide one switch, `Tokens.type.sans`, to point at `.system`.
- **Newsreader** (display serif): 400, 500, with **Italic**. **[ASSUMED]** The Anthropic theme page itself sets headings in sans; the serif is my addition because the owner wants an italic-serif voice (and the landing page will use it). Swap-in candidates if it disappoints: Source Serif 4, Instrument Serif.

If only variable fonts are available, make static instances with `fontTools.varLib.instancer` and commit them. Register at launch with `CTFontManagerRegisterFontsForURLs(..., .process, ...)`. Unit-test that every token font resolves to a non-fallback `NSFont`. If the network blocks fetching, stop and ask the owner to drop the files in place.

Source Sans 3 has a smaller x-height than the reference's face, so sizes are **one point larger** than the measured reference where it is sans. The serif title replaces the reference's bold sans title.

| Token | Font | Size / line | Notes |
| --- | --- | --- | --- |
| `page.title` | Newsreader 500, name in italic | 34 / 40 | "Welcome back, *<name>*". Replaces the reference's 26 pt bold sans [ASSUMED] |
| `feature.title` | Newsreader 500, one italic word | 30 / 36 | "Make Murmur sound like *you*" [ASSUMED size; the reference title was 38 pt Garamond-style] |
| `heading` | Newsreader 500 | 22 / 28 | card titles such as style names [ASSUMED] |
| `body` | Source Sans 3 400, 500 for emphasized phrases | 16 / 24 | feature paragraph [WIS size +1] |
| `nav` | Source Sans 3 500 | 16 / 20 | sidebar labels [WIS +1] |
| `row` | Source Sans 3 400 | 17 / 24 | history row text [WIS +1] |
| `meta` | Source Sans 3 400 | 15 / 20 | timestamps [WIS +1] |
| `section` | Source Sans 3 600, uppercase, tracking +0.06 em | 12 / 16 | "TODAY" |
| `button` | Source Sans 3 500 | 16 / 20 | [WIS +1] |
| `chip` | Source Sans 3 500 | 16 / 20 | stat chip [WIS +1] |
| `badge` | Source Sans 3 600 | 14 / 18 | plan badge [ASSUMED] |
| `keycap` | Source Sans 3 600 | 13 / 16 | [ASSUMED] |
| `flow.text` | Source Sans 3 500 | 13 / 16 | tooltip [ASSUMED-SCALE, +1] |
| `flow.alert` | Source Sans 3 500 | 14 / 18 | alert title, body, buttons, toast text, one size [ASSUMED-SCALE, +1] |

Minimum text size 11. Expose `Tokens.type.scale` (default 1.0) and a Settings control "Text size: Default / Large" (1.0 / 1.15); nothing may clip at 1.15.

### 3.4 Geometry [WIS, measured unless tagged]

Hub (pt, 1.333 px per pt):

| Token | Value |
| --- | --- |
| Reference window | 1280 × 700 (default 1100 × 700, min 880 × 560 [ASSUMED]) |
| Sidebar width | 230 |
| Sidebar item | 208 wide, 38 high, 44 pitch, 10 pt left inset, radius 8 [estimated] |
| Sidebar icon | ~16 pt glyph, 13 pt gap to label |
| Title bar zone | 46 pt; traffic lights, sidebar-toggle icon (x ≈ 124) and the bell on one centre line 20 pt from the top |
| Content panel | flush against the sidebar, 46 top / 9 right / 9 bottom inset, 1 pt `border-panel`, radius 12 [estimated] |
| Content column | max width 850, centered; side padding clamps to ≥ 32 |
| Page title | cap top 66 below the panel top; 29 gap to the feature card (re-check after the serif swap) |
| Feature card | 850 × ~230, padding 28, radius 14 [estimated], 1 pt `border-feature`; title-to-body gap 28, body-to-button gap 31 |
| Primary button | ~100 × 40, radius 10 [ANT 9.6], 16 pt text, 15 pt horizontal padding |
| Section caption | 58 below the card, 22 above the list |
| History list | 850 wide, 1 pt `border-panel`, radius 14 [estimated], dividers `border-divider`; single-line row ~57 high, two-line ~75; time column starts 18 in, text column starts 124 in, text wraps near 500 wide |
| Stat chip | ~313 × 32, full radius, `bg-chip`, 1 pt vertical separators |
| Plan badge | height ~26, radius 7 [estimated], `accent-clay` fill, white text |
| Notification dot (bell) | `accent-clay`, ~14 pt, white numeral |

Spacing scale (pt): 4, 8, 12, 16, 20, 24, 28, 32, 40, 48, 64. Dark uses the same geometry.

### 3.5 Flow Bar geometry (proportions [WIS], absolute [ASSUMED-SCALE])

Let **H** be the pill height.

| Element | Ratio | Absolute (H = 28) |
| --- | --- | --- |
| Pill height | 1.00 H | 28 |
| Idle-hover pill width | 2.33 H | 68 |
| Active (hands-free) pill width | 3.54 H | 102 |
| Round buttons (cancel, stop) | 0.60 H diameter | 18 |
| Padding around buttons | 0.19 H | 5 |
| Pill border | ~0.03 H | 1 |
| Tooltip height | 1.07 H | 30 |
| Gap tooltip → pill | 0.14 H | 4 |
| Tooltip text | 0.43 H | 13 (Source Sans) |
| Idle squares | — | 14 squares, side 1.75, pitch 2.7, `flow-dot`, centred, total width ~37 |
| Active bars | — | 10 bars, width 1.75, pitch 3.9, `flow-bar`; heights 2.5–4.5 × width at normal speech (4.4–7.7 pt); minimum height equals the width (a square), so silence looks like the idle squares; maximum ~11 |
| Alert (with actions) | — | 378 × 139, radius ~28 [estimated], padding 28, 1 pt `flow-alert-border`; icon ring 17 pt beside the title; close X top right; two buttons 32 high, radius 10, gap 9.5, widths 135 and 100 |
| Toast ("Transcript cancelled") | — | 273 × 47, radius ~14 [estimated], padding 9 / 25; info ring 17 pt, text, then an "Undo" button 50 × 30, radius 10 |

The waveform and the idle squares occupy the same centre area: idle is the waveform at zero level, dimmed to `flow-dot`.

### 3.6 Iconography and the brand mark

**UI icons.** SF Symbols are a major part of the "generic Mac" feel. Replace them with an original line icon set drawn as SwiftUI `Shape`s on a 24 pt grid, **1.5 pt stroke, round caps and joins**, `text-primary`, ~16 pt in the sidebar. Needed: home (2×2 rounded squares), dictionary (book), snippets (rounded square with a cut mark), style (serif "T"), settings (gear), help (circle with a question mark), bell, user circle, sidebar toggle (rounded rectangle with a left pane), info circle, mic, stop, close, copy, paste, check, warning ring, clock, plus, search, trash, chevron, keyboard, globe, lock. Use an `Icon` enum so any icon can be swapped. Anything not yet drawn maps to an SF Symbol at `.regular` weight and is listed in `docs/ui-todo.md`.

**The mark** (`Design/murmur-mark.svg`, aspect 2.65 : 1, one path). Use `accent-clay` on light surfaces and `accent-clay-text` on dark. Never recolor outside the palette; never stretch; keep clear space of at least the height of the "M"'s leg stroke on every side.
- *Sidebar:* mark 22 pt tall (about 58 wide) left-aligned at the top, with the plan badge "Personal" to its right. No wordmark text beside it.
- *Welcome / About / Help sheet:* mark 56 pt tall.
- *App icon:* a rounded-square tile filled `bg-feature` (`#F6EEE5`) with the mark centred at about 62% of the tile width, in clay. Produce the full macOS iconset (16 to 1024) with `iconutil`, and an `Assets.xcassets/AppIcon`.
- *Menu bar:* menu bar items cannot show a 2.65 : 1 mark legibly. Build a compact **template** glyph: the "M" plus a short three-bar waveform, about 22 × 14 pt, monochrome with transparency, in 1× / 2× / 3×. Variants for idle, recording (bars active, plus a non-template clay dot), processing (bars settle with a trailing dot) and error (a small notch). Hand-design these; do not downscale the mark.

### 3.7 Copy

Plain, warm, short. "Hold Fn and speak." "Copied." "Audio is silent." Errors say what happened and what to do. Tooltip pattern: "Click or hold <key> to start dictating", where `<key>` is the user's configured shortcut shown as symbol plus name (for example "^ Ctrl"). Sidebar has no "Notes", "Invite your team" or "Get a free month" items.

---

## 4. Components (build all in `Sources/UI/Components/`; show all in the Design Gallery)

Every interactive component has default, hover, pressed, focused (keyboard), disabled states. Hover = fill change only. Pressed = scale 0.98 for 80 ms. Focused = 2 pt `focus-ring` outline with a 2 pt gap, always visible. Disabled = `text-disabled`, no hover.

| Component | Spec |
| --- | --- |
| `MButton` | **primary:** `accent-clay` fill (hover `accent-clay-hover`, pressed `accent-clay-pressed`), white text, radius 10, 40 high, `button` type. **secondary:** `bg-card` fill, 1 pt `border-control`, `text-primary`. **ghost:** text only, hover `bg-hover`. **icon:** 32 square, radius 8, hover `bg-hover`. **destructive** (only inside a confirm dialog): secondary shape with `danger-text`. Sizes sm 32, md 40, lg 48. |
| `MToggle` | 40 × 24 pill. Off: `bg-hover` track, 1 pt `border-control`, white knob. On: `accent-clay` track, white knob. Knob spring. Whole row is the hit target. [ASSUMED] |
| `MTextField`, `MSearchField` | 40 high, radius 10, `bg-field`, 1 pt `border-control`; focus adds the ring; placeholder `text-placeholder`. Search has a leading icon and a clear button. |
| `MTabs` | Pill row on `bg-chip`; selected pill `bg-panel` with a 1 pt `border-panel`, `text-primary` 500; unselected `text-secondary`. Selection slides (`matchedGeometryEffect`). Arrow keys move selection. [ASSUMED] |
| `MFeatureCard` | `bg-feature` fill, 1 pt `border-feature`, radius 14, padding 28, Newsreader title with one italic word, paragraph with medium-weight emphasis, optional primary button. At most once per page. |
| `MCard` | Plain card: `bg-card`, 1 pt `border-panel`, radius 14, padding 20. Selectable variant: 2 pt `accent-clay` border plus `accent-clay-tint` fill when selected. [ASSUMED] |
| `MStatChip` | Pill container `bg-chip`, full radius, 32 high, up to three groups divided by 1 pt `border-divider` separators, each with a glyph and `chip` text. |
| `MBadge` | Radius 7, `badge` type. `.plan` (`accent-clay` fill, white text, label "Personal"), `.neutral` (`bg-hover`, `text-body`), `.soft` (`accent-clay-tint`, `accent-clay-text`). |
| `MKeycap` | Radius 6, 1 pt `border-control`, `bg-card`, `keycap` type, min 26 × 26. Used for every shortcut display and the shortcut recorder. |
| `MSidebarItem` | 38 high, radius 8, 16 pt icon, 13 gap, `nav` type. Selected: `bg-hover`, same text color. Hover: `bg-hover` at 50%. |
| `MListRow` | Min height 57, `border-divider` between rows, time column then text column (§3.4), hover reveals trailing icon buttons (copy, paste, delete) with a 100 ms fade. A "silent" row shows `text-disabled` text and an info icon whose tooltip explains the audio was silent. |
| `MDialog`, `MToast` (Hub) | `bg-panel`, 1 pt `border-panel`, radius 14; dialogs sit on `scrim`; buttons right-aligned (secondary then primary). |
| `MTooltip` | Pill, `flow-tooltip` fill, white 13 pt text, 400 ms delay. |
| `FlowBarView` and parts | See §5.1. `FlowWaveform` is a single `Canvas`. |
| `MEmptyState` | `body` line, optional primary button, a tiny waveform-square motif in `flow-dot` on a black pill. |
| `FocusRing` modifier | The one place that draws focus. |

---

## 5. Screens

### 5.1 Flow Bar (the signature surface; every state reachable from the debug menu)

Panel frame is **fixed at the largest state**, transparent. Animate the SwiftUI content inside it, never the `NSWindow` frame (it jitters). Hit-testing passes through everywhere except the visible pill, tooltip and notification.

| State | Visual |
| --- | --- |
| Idle | A tiny black pill (smaller than hover; start at 36 × 6) with the 1 pt `flow-border`. No animation. [ASSUMED size] |
| Idle hover | Grows to the measured 68 × 28 pill showing 14 `flow-dot` squares; the tooltip pill appears above it after 400 ms: "Click or hold ^ Ctrl to start dictating" (the user's configured key). |
| Listening, hold | Pill at the hover or active size (measure from recordings), waveform bars driven by mic level, no buttons. [ASSUMED] |
| Listening, hands-free | 102 × 28 pill: cancel circle (X) on the left, waveform centred, `flow-stop` circle with a white rounded-square glyph on the right. Squares become white bars as audio arrives. |
| Processing | Bars settle to squares and pulse in sequence (a left-to-right shimmer, `flow-dot` to white). [ASSUMED] |
| Inserted | Brief white check drawn, hold, then shrink to idle. [ASSUMED] |
| Paste error | Toast: `flow-icon-error` ring "!" icon, "Copied. Press ⌘V to paste." [ASSUMED copy; style from the reference] |
| Transcription error | **Alert** (§3.5): error ring icon, title "We couldn't transcribe that", one-sentence body, buttons **Retry** and **Dismiss**, X top right. |
| No audio | **Alert**: title "We couldn't hear you", body "We didn't pick up any speech from your <mic name> microphone.", buttons **Select microphone** and **Troubleshoot**. (Modeled on the reference; write your own final wording.) |
| No text box | Toast with the paste shortcut as keycaps and a Dismiss text button; countdown ring 16 pt, 2 pt stroke, pauses on hover. [ASSUMED] |
| Cancelled | **Toast:** `flow-icon-info` ring "!" icon, "Transcript cancelled", **Undo** button. SPEC §6 also requires "Open History": add it as a small link after Undo [ASSUMED; the reference shows only Undo]. |

Alerts and toasts appear above the pill, horizontally centred on it, with the 4 pt gap used by the tooltip. The right-click menu stays a native `NSMenu`.

### 5.2 Menu bar

Native `NSMenu`, same items and order as SPEC §6, using the template glyphs from §3.6.

### 5.3 Hub window

**Chrome.** Transparent title bar, full-size content view, `bg-window` behind everything. Sidebar and content panel as in §3.4. Title-bar controls: sidebar-toggle icon (collapses the sidebar, 160 ms) beside the traffic lights; on the right, a **bell** (opens a popover listing system alerts such as a revoked permission; an `accent-clay` numbered dot when there are any) and, optionally, a user-circle icon opening a small menu (Check permissions, Quit).

**Sidebar.** Top: the mark (22 pt tall) plus the `.plan` badge "Personal". Items: Home, Dictionary, Snippets, Style. A hairline divider near the bottom, then **Settings** and **Help** (Help opens a sheet: shortcuts, check permissions, version, the mark).

**Home.** `page.title` "Welcome back, *<name>*", right-aligned `MStatChip` (flame + days streak, rocket + words, wave + words per minute), computed cheaply from Store aggregates; hide any chip that can't be computed. One `MFeatureCard` (title "Make Murmur sound like *you*", paragraph about styles with the phrase "messages, work chats, emails, and other apps" in medium weight, primary button "Start now" that opens Style), dismissible once (stored). Then the section caption "TODAY" (then "YESTERDAY", then dates) and the history list. Empty state per `MEmptyState`. A silent audio row is shown disabled with the info icon.

**Dictionary, Snippets, Style, Settings [ASSUMED; extend the system].**
- *Dictionary:* `page.title`, `MSearchField`, primary "Add word"; entries in one bordered list like History (word, optional "sounds like", `.soft` badge for auto-added, hover edit/delete). Add/edit in an `MDialog`.
- *Snippets:* same pattern; trigger shown as a keycap-style chip, expansion with a two-line clamp.
- *Style:* `MTabs` (Personal, Work, Email, Other). Style cards (Formal., Casual, very casual, Excited!) in a 2-column grid of selectable `MCard`s: name in Newsreader (`heading`, 22 / 28) plus a two-line sample. Below, **Auto Cleanup** (None, Light, Medium) as three selectable `MCard`s with a before → after example.
- *Settings:* `MTabs` (General, System, Experimental, Data and privacy). Each group is an `MCard` with rows: label and `meta` description on the left, control on the right, `border-divider` between rows. New General rows: **Appearance** (System / Light / Dark), **Text size** (Default / Large). Everything else per SPEC.

Page switch: 160 ms cross-fade with a 6 pt rise. Keyboard navigation per SPEC.

### 5.4 Onboarding (same steps and order as SPEC §6) [ASSUMED look]

Full-window `bg-panel`, no sidebar, centred 560 pt column, progress dots at the bottom. Titles in Newsreader with one italic word; body in `body`; options in `MCard`s.

| Step | Look |
| --- | --- |
| Welcome | The mark at 56 pt tall, serif headline with one italic word, one primary button, on a `bg-feature` full-bleed backdrop. |
| Microphone, Accessibility, Input Monitoring | Short explanation, a status badge (`.neutral` "Waiting", `.plan` "Granted"), primary button opening the right System Settings pane; auto-advance 600 ms after granted. |
| Test your microphone | The Flow Bar pill at large scale (H = 56) with live bars, plus "Change microphone". |
| Choose the shortcut | Two selectable `MCard` options (push-to-talk, hands-free) with keycaps and the recorder. |
| Languages | Searchable list in an `MCard`. |
| Practice demos | A mock text field card above the **real Flow Bar component** docked at the bottom; each demo has a ghost "Skip". |
| Data preference | Two selectable `MCard`s. |
| "This is the Flow Bar" | The live bar at the bottom of the window, a small hand-drawn arrow (original) pointing to it, **Continue** opens Home. |

---

## 6. Motion and sound [ASSUMED; tune with the slow-motion tool]

### 6.1 Motion tokens

| Token | Value |
| --- | --- |
| `bar.appear` | spring response 0.30, damping 0.78, scale 0.86 → 1 with fade |
| `bar.disappear` | ease-in 140 ms |
| `bar.expand` | spring response 0.34, damping 0.82 (idle ↔ hover ↔ hands-free); buttons fade and scale in 120 ms after the pill reaches ~80% width |
| `wave.attack` / `wave.release` | 45 ms / 140 ms, one-pole smoothing on the level |
| `processing.period` | 1.1 s shimmer, left to right |
| `inserted.check` / `inserted.hold` | 220 ms draw / 600 ms hold |
| `toast.in` / `toast.out` | 200 ms rise 12 pt + fade / 140 ms fade |
| `countdown.ring` | linear over the notification duration, pauses on hover |
| `tooltip.delay` | 400 ms in, 100 ms out |
| `hub.pageSwitch` | 160 ms ease-out, 6 pt rise |
| `ui.hover` | 100 ms ease |
| `ui.press` | 80 ms, scale 0.98 |
| `toggle.knob` | spring response 0.22, damping 0.80 |
| `tabs.select` | spring response 0.28, damping 0.85 |
| `sidebar.collapse` | 160 ms ease-in-out |
| `timeScale` | global multiplier; default 1.0; the debug panel can set 0.2 for slow motion |

### 6.2 Accessibility switches

- **Reduce Motion:** springs become 120 ms fades; no scale or position changes; the waveform still follows the mic (it is data) without release smoothing; the processing shimmer becomes a slow opacity pulse (1.6 s); page switches are plain cross-fades.
- **Reduce Transparency:** this design uses no materials; keep a code path so future materials respect it.
- **Increase Contrast:** `border-panel` → `border-control`, `text-secondary` → `text-body`, `border-divider` → `border-control`, `accent-clay-tint` → `bg-hover` with a 2 pt clay border.

### 6.3 Sounds

Regenerate the three original WAVs with a script (`Tools/make_sounds.py`, numpy only, 44.1 kHz, 16-bit mono) from tokens in `Tokens+Sound`: **start** = two soft sine plucks rising a fifth (784 Hz then 1175 Hz), 55 ms each, 6 ms attack, 40 ms exponential decay, peak −18 dBFS; **stop** = the same pair falling; **error** = two 70 ms triangle pulses at 330 Hz, 50 ms apart, peak −16 dBFS; 5 ms fades to avoid clicks. Keep the Settings switch. The owner may supply recordings of the reference app's sounds for **measurement only** (pitch, length, envelope from a spectrogram); adjust tokens, never copy samples. No sounds in the Hub.

---

## 7. Milestones

Work on a branch named `ui-redesign`. One commit per milestone, message `U<n>: <title>`. After each milestone, stop and report in the format in §10. Do not start the next milestone until the "Done when" line is true. If a milestone would change dictation behavior, stop and ask.

### U0 — Audit and snapshot harness (no visual change)

1. Read `SPEC.md`, this file, `Package.swift` (note the deployment target and gate any API newer than it), and every file under `Sources/UI`.
2. Write `docs/ui-audit.md`: each view, each system control it uses, the existing `Tokens.swift` API (names are kept; extend rather than rename, and provide a migration list if you must rename), how the Hub window and the Flow Bar panel are built, and anything that would block the design (for example `NavigationSplitView`).
3. Build the **snapshot tool**: an executable target `murmur-snap` that renders any view to PNG with `ImageRenderer` at 2× in light and dark, with fixture data, into `Artifacts/ui/`. Render the **current** UI first as `Artifacts/ui/before/`.
4. Build a debug-only **Design Gallery** window listing every component in every state, and extend the existing debug panel with: appearance override (System / Light / Dark), Reduce Motion override, `timeScale`, text-size scale, and "force Flow Bar state".

*Done when:* `swift run murmur-snap` produces before-images for every Hub page and every Flow Bar state, and `docs/ui-audit.md` exists.

### U1 — Tokens, theme, fonts

1. Split tokens into `Tokens+Color`, `+Type`, `+Geometry`, `+Motion`, `+Sound`, with every value from §3 and §6. Add `// MEASURE` to every [ASSUMED] / [ASSUMED-SCALE] / [DERIVED] token and a `source:` tag in a doc comment (`ant`, `logo`, `wis`, `assumed`, `derived`).
2. `ThemeProvider`, `\.theme`, the Appearance setting (System / Light / Dark) and the Text size setting.
3. Fetch and bundle Source Sans 3 (static 400, 500, 600, 700) and Newsreader (400 and 500, each with Italic), with licenses; register at launch; font fallback per rule 9.
4. Add the lint script and unit tests in §8.

*Done when:* the token lint and contrast tests pass; the font-resolution test passes; the app still builds and looks unchanged.

### U2 — Components and gallery

Build every component in §4 plus the icon set in §3.6 (the sidebar and Flow Bar icons first; the rest fall back to SF Symbols and are logged in `docs/ui-todo.md`). Convert `Design/murmur-mark.svg` into a `BrandMark` SwiftUI `Shape` (one path, aspect 2.65 : 1) that takes its color from the theme, and tidy any nubs at the M's leg ends. Every state is visible in the Design Gallery in light and dark.

*Done when:* gallery snapshots exist for all components in both schemes; keyboard focus ring is visible on every interactive component; every component respects Reduce Motion.

### U3 — Flow Bar

1. Restyle the bar and all states per §5.1: black pill, 1 pt border, idle squares, bars, warm-gray cancel circle, clay `flow-stop` circle, tooltip, alert, toast.
2. Rendering: fixed-size transparent panel at the largest state, SwiftUI content animated inside it, hit-testing only on visible shapes. `FlowWaveform` is one `Canvas` driven by a `TimelineView(.animation)` that is **paused** unless listening or processing. Read the audio level at display rate from an atomic or lock-protected value; never publish from the audio thread per buffer.
3. Replace the placeholder tones with the generated sounds from §6.3.
4. Add VoiceOver labels and state descriptions to the bar even though it is non-activating.
5. Update the debug panel so every state is reachable and the tokens live-tune.

*Done when:* all states render per §5.1 in snapshots; the SPEC "never takes focus" test (50 trials) passes; idle CPU with the bar visible and idle is 0% (no timers or animations running); a profile of a 10 s dictation shows no frames over the SPEC budget.

### U4 — Hub shell and Home

Window chrome, sidebar (with the brand mark and plan badge), title-bar controls, bell popover, Home (serif greeting, stat chips, feature card, history list, empty state). Remove every stock `NavigationSplitView` / `List` use in the Hub.

*Done when:* the Home snapshot matches §3.4 numbers within ±2 pt at the reference window size (1280 × 700); light and dark both render; sidebar collapse works; Option+Up/Down and Cmd+[ / Cmd+] still work.

### U5 — Dictionary, Snippets, Style

Per §5.3. Style cards and Auto Cleanup cards show the real example text from the existing implementation.

*Done when:* all three pages are fully functional with the new components, with no behavior change, and have snapshots in both schemes.

### U6 — Settings

Per §5.3, including the new Appearance and Text size rows. Replace every stock control with the §4 components.

*Done when:* every Settings control is a custom component, every setting still persists, and snapshots exist for all four tabs in both schemes.

### U7 — Onboarding

Per §5.4. Resume-where-stopped, skip-granted-steps and permission-revocation behavior must be unchanged.

*Done when:* a clean run through onboarding works in a fresh macOS user account; the permission revocation test still passes.

### U8 — Menu bar, polish, accessibility pass

1. The app icon (cream tile with the clay mark, full `iconset` and `AppIcon` asset) and the menu-bar template glyphs and their four states (§3.6, §5.2).
2. Reduce Motion, Increase Contrast, text size 1.15, and VoiceOver passes over every screen. Fix clipping.
3. Remove dead code and unused system-control styles. Write `docs/ui-calibration.md` (§9).
4. Produce the final `Artifacts/ui/after/` set and a side-by-side contact sheet with `before/`.

*Done when:* all checks in §8 pass; the contact sheet exists; `docs/ui-calibration.md` lists every `// MEASURE` token with where it is used.

---

## 8. Verification and tooling

**Token lint** (`scripts/check-tokens.sh`, run in CI and as a pre-commit hook): in `Sources/UI/**` outside `Tokens*.swift`, fail on `Color(red:`, `Color(hex`, `NSColor(red`, `.font(.system(size`, `.font(.custom(` with a literal size, `.cornerRadius(<literal>)`, `.frame(width: <literal>`, `.padding(<literal>)`, `.animation(.spring(` with literals, and `lineWidth: <literal>`. Whitelist `0` and `.infinity`.

**Contrast tests** (`ContrastTests`): compute the WCAG ratio for each declared pair and assert it is at least the value stated in §3.2 minus 0.05. Pairs: every text token on every surface it is used on, in both schemes, plus the Flow Bar pairs. Add a test that **fails** if `text-disabled` is used anywhere except disabled controls and silent history rows.

**Snapshot tool:** `murmur-snap` renders every page and component in light, dark, text scale 1.15 and Reduce Motion on/off, to `Artifacts/ui/`. Fail the run if any image is blank or any view reports a clipped layout.

**Behavior checks that must stay green:** the SPEC suite, the "never takes focus" 50-trial test, the Reduce Motion behavior (A8), permission-revocation detection (A3), and the latency budget in SPEC §7.

**Manual checklist (report results, do not skip):** (1) the Flow Bar over a full-screen app, over a dark app and over a light app, border visible in all three; (2) Dock on the left, right, and auto-hidden; (3) two displays; (4) window at 880 × 560 and at 1280 × 700; (5) `timeScale` 0.2 to inspect each animation.

---

## 9. Calibration and open items (create `docs/ui-calibration.md` from this)

Each [ASSUMED] token stays tunable. The owner will replace values after sending more reference. Until then keep the placeholders and keep `// MEASURE` tags. Open items and what would resolve them:

| Open item | Needed from the owner |
| --- | --- |
| Flow Bar absolute size and idle (non-hover) size | A screenshot of the bar next to a known-size UI element (a menu bar or Dock icon), at native resolution |
| Hold-to-talk state (no buttons?) and the processing / inserted visuals | A short screen recording, or stills of each state |
| Waveform behavior (levels, smoothing) | A recording of speech with the bar visible |
| Dictionary, Snippets, Style, Settings, onboarding screens | Screenshots of each page |
| Dark mode | Screenshots if the real app has one; otherwise keep the derived dark theme |
| Menu bar dropdown and Flow Bar right-click menu | Screenshots |
| Notification countdown ring | A short recording |
| Display serif | Whether Newsreader feels right; alternatives are Source Serif 4 and Instrument Serif. The Anthropic theme page itself uses sans headings, so the serif is a choice to confirm |
| Clay shade | The logo clay `#B54B3C` is used everywhere. Anthropic's page uses a slightly more orange `#BB5A38`; swap one token (`accent-clay`) if the owner prefers it |
| Logo vector | The traced mark may have small nubs at the leg ends; a clean redraw from the owner's source file would replace it |
| Sounds | Recordings, used for measurement only |
| Corner radii marked "estimated" | Native-resolution crops of a button, the panel corner and a card corner |

---

## 10. How to report, and what not to do

**After each milestone report:** what changed (files), the "Done when" checks with pass/fail, the paths of new snapshot images, any token you had to add that is not in this file (with its source tag), and anything you could not do. Keep it short; no recap of the steps.

**Stop and ask** if: fonts cannot be fetched; a milestone would change dictation behavior; a SPEC test regresses and the cause is not obvious; a measured value in this file contradicts the screenshots the owner attached later.

**Do not:** use gradients, shadows on the Hub, system accent colors, any accent other than clay, stock `List`/`Form`/`Toggle`/`Picker`, SF Symbols where an original icon exists, Wispr's name, logo, copy or sounds, Anthropic's marks or the Styrene typeface; invent final numbers for [ASSUMED] tokens; animate the `NSWindow` frame; leave an animation running while the bar is idle or the Hub is hidden.

---

## 11. Not in this task: the landing page (keep it in mind)

The owner will want a marketing landing page later, in an enterprise-leaning version of this same brand. Direction so far, for context only; **do not build it now**, and design tokens so it can reuse them:

- Serif display type with an italic emphasis, the same voice as the app's titles.
- A headline that plays on a reversal: "You type faster than you speak" shown struck through, followed by the opposite, "You speak faster than you type".
- A tasteful load-in animation (the mark's waveform drawing itself is a natural candidate).
- Same palette: paper, ink, clay.

Keep `Tokens+Color` and `Tokens+Type` free of app-only assumptions (no Hub geometry in them) so a web design system can be generated from them later.
