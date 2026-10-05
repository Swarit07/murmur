# UI redesign v2 ("Paper & Clay"): progress

One report per milestone (UI_REDESIGN.md §10), newest last. If a session ends midway, the next one resumes from here. The branch is `ui-redesign`: commits are local only, never pushed.

## Setup (U-)

- **Before starting:** the tree held the unfinished v1 U3 Flow Bar work. At the owner's choice it was committed as `8903940 U3 (v1, unfinished)`, then the v2 bundle was installed.
- **Bundle install (`d69c8e3`):**
  - `UI_REDESIGN.md` v2 and `Design/` were copied in.
  - The v1 brief moved to `docs/archive/UI_REDESIGN.v1.md`.
  - The v1 mark files moved to `docs/archive/design-v1/`.
  - The logo raster is byte-identical and now lives at `Design/brand/logo-murmur.png`.
- **SPEC:** `SPEC.md` (there is no `claude-code-prompt.md`).

## U0: Audit and harness

**Changed**
- `docs/ui-audit.md`: a v2 section covering the v1 pieces reused, the token and component migration list (v1 → v2), and what stands in the way.
- `Sources/MurmurSnap/main.swift`: two new flags.
  - `--large` renders at text scale 1.15 into `<set>-large/`.
  - `--reduce-motion` renders with Reduce Motion on into `<set>-reduced/`.
- `.gitignore`: ignores the variant sets and `Artifacts/ui/compare/`.

**Reused from v1** (details in the audit):
- the snapshot tool, Design Gallery, token panel with the debug overrides, token lint;
- the token-file split with `ThemeProvider`, `Motion`, `UIDebug` and `FontRegistry`;
- the `BrandMark` SVG path parser and `MicLevelSource`;
- the sound generator, and the Flow Bar panel and model plumbing.

**Done when**
- **`murmur-snap` produces before-images for every Hub page and Flow Bar state: pass.**
  - `Artifacts/ui/before/{light,dark}/` holds the pre-redesign UI from v1 U0: 8 Hub pages, 12 onboarding steps, 13 Flow Bar states and the gallery. The contact sheet is `Artifacts/ui/sheets/before.png`.
  - That set was rendered before any visual change, so it stays the "before" column. Re-rendering now would capture v1's half-built Flow Bar instead.
  - `murmur-snap after` still runs clean.
- **`docs/ui-audit.md` exists: pass.**

**Judgment calls (defaults taken)**
- **Onboarding keeps SPEC's 12 steps** rather than the board's 10 (§5.4 says "same steps as SPEC §6").
- **Shortcuts show the real bindings:** ⌃⌘V and ⌃⌘C, not the board's ⌃⌥V and ⌃⌥C.
- **The no-audio alert is built but not wired.** The controller has no silent-recording event, and adding one changes dictation behavior. **Owner decision needed.**

## U1: Tokens, theme, fonts

**Changed**
- **`Tokens+Color.swift`:** v2 `ThemeColors`, light and dark, all §3.2 tokens.
  - `ColorToken` now carries alpha. Ink and ivory at an opacity are written as the boards write them.
  - Contrast is measured after compositing translucent colors over their background.
  - `FlowBarColors.light` and `.dark` are picked by the system appearance, with an Increase Contrast variant.
- **`Tokens+Type.swift`:** the §3.3 styles.
  - Families: Geist, Geist Mono, and Newsreader in two optical cuts.
  - `FontRegistry` logs once and falls back to system faces if registration fails.
- **`Tokens+Geometry.swift`:** spacing scale, radii, strokes, `shadow-float`, Hub, onboarding and Flow Bar geometry (§3.4, §3.5, §4, §5).
- **`Tokens+Motion.swift`:**
  - the §6.1 motion tokens;
  - `WaveTokens` and `MeterTokens`, ported from `Design/motion/murmur-motion.js`.
- **`Theme.swift`:** `theme.flow` now follows the scheme and Increase Contrast.
- **Fonts (`Sources/UI/Resources/Fonts`):**
  - Added: Geist 400, 500, 600 and Geist Mono 400, 500 (vercel/geist-font v1.7.2).
  - Added: Newsreader, cut from Google Fonts' variable fonts: opsz 16 at 400, 400 Italic and 500; "Newsreader Display" at opsz 36, 400 and 400 Italic.
  - OFL licenses are included.
  - Removed: Source Sans 3 and v1's Newsreader Medium Italic.
  - `Tools/fetch_fonts.sh` reproduces the folder.
- **`Tests/UITests/ThemeTests.swift`:**
  - every §3.2 contrast pair, light, dark and Flow Bar;
  - `Design/tokens.json` matches every color (light and dark), every type style, spacing and radii;
  - font resolution, including which Newsreader cut each style gets;
  - §8 source checks: stone never text, clay only where allowed, no red;
  - Reduce Motion, and the board's per-frame wave smoothing equals the time constants.
- **`Sources/UI/TokensV1.swift` (temporary):**
  - v1's token values under `V1*` names, so the v1 components and the v1 Flow Bar build and look as before.
  - U2 and U3 remove their uses; the file goes when nothing references it.
  - The source checks skip files still on it.

**Done when**
- **Token lint: pass.**
- **Contrast tests: pass.** Every stated ratio is met at two decimals. Dark `border-control` on the window is 4.85 against the stated 4.9, which is within the 0.05 allowance.
- **Font resolution: pass.**
- **`tokens.json` match: pass.**
- **App builds: pass** (Release `xcodebuild`).
- **Looks unchanged: pass.**
  - The Hub, onboarding and menu bar don't read these tokens yet.
  - The v1 Flow Bar and components read the `V1*` copies.
  - The only visible change is the font in v1 components (Geist replaces Source Sans 3), and those only appear in the debug gallery.

**Tokens not in the brief**
- **Edge colors** (the boards draw these ink strengths inline): `edgePanel` 12%, `edgeList` 14%, `edgeStrong` 20%, `edgeKey` 25%, `edgeToast` 18%, `underline` 30%, `fieldHalo` 8%. Board in light; dark is derived and marked MEASURE.
- **Hover colors:** `accentClayHover` and `inkFillHover` (derived, halfway to pressed, MEASURE). The brief gives only pressed, and §4 wants hover to change the fill.
- **Flow Bar colors:** `flowKeyRing`, `flowKeyBottom`, `flowTimer`, `flowStillWave` (board, from §3.5 and §4 text).
- **Opacities:** `OpacityTokens.idleFaded`, `silentTile`, `processingGlyph`, `ringTrack` (board).
- **Type:**
  - `controlSmall`, `keycapInline`, `keycapLarge` (board sizes from §3.3's ranges).
  - `ringDigit` (mono 9, board §3.5). It's the one style below the 10 pt floor and is noted as such.
- **Font cuts:** `displayCutFrom` = 26 pt for the Newsreader display cut (derived).
- **`ShadowTokens.floatRadius`:** derived, because SwiftUI has no spread.

**Judgment calls**
- **Two Newsreader optical cuts instead of one.** The boards are rendered by a browser, which sets the optical size from the font size; one 24 pt cut would set the 40 pt titles visibly heavier than the reference.

## U2: Components, icons, brand

**Changed** (all in `Sources/UI/Components/` unless noted)
- **New or rebuilt components:**
  - `MButton`: primary, ink, outline, link; regular 40 and small 28; optional 15 pt icon.
  - `MIconButton` (32 or 28), `MToggle` (regular and small), `MSegmented` (replaces v1 `MTabs`; regular and small, arrow keys, sliding selection), `MRadio` (replaces v1 `MCheckbox`).
  - `MTextField` (plain, quote, secure, multiline; focus border plus halo), `MSearchField`, `MSelect` (native menu; mono variant), `MNavigateSelect`.
  - `MKeycap` (inline and standard, pressed) and `MShortcut`, `MTag` (outline and filled), `MStatStrip` (drops missing stats), `MAppTile` (normal and faint).
  - `MCard`, `MSelectableCard` (ink ring and radio, never clay; 2 pt under Increase Contrast), `MFeatureCard`, `MWell`.
  - `MList`, `MListContainer` and `MListRow` (hover fill, trailing actions fade in over 100 ms).
  - `MSidebarItem`, `MStatusCard`, `MSettingsGroup`, `MSettingsRow`, `MToggleRow`, `MInfoCard`.
  - `MPaperToast` (with `shadow-float`), `MTooltip` / `TooltipPill`, `MDialog`, `MEmptyState` with `FlowIdlePill`, `MLevelMeter` (onboarding mic test), `MChip`, `MStepFrame` with `MIllustrationWell`.
- **Shared plumbing (`ComponentSupport.swift`):** focus ring 2 pt with a 2 pt gap, press moves down 1 pt (no scale), `insetRing`, `floatShadow`, `SerifTitle`, `MCaption`, `Hairline`.
- **`SVGPath.swift`:** a full SVG path parser (M L H V C S Q T A Z, absolute and relative, arcs to Béziers).
- **`Icons.swift`:** 45 icons from the boards' path strings; the stroke scales with size as the boards draw it.
- **`BrandMark.swift`:** the v2 mark, parsed from `Design/brand/murmur-mark.svg`, in the theme's clay.
- **`Sources/UI/MenuBarGlyph.swift`:** idle (template), recording (clay copy and 5 pt dot), processing (45% template and five rippling dots, phase-driven), error (template with a cut-out "!" badge, never red).
- **Icon assets (`Tools/make_icons.py`, cairosvg):**
  - `App/AppIcon.iconset`, 16–1024 px; `iconutil` builds an `.icns` from it.
  - `App/Assets.xcassets/AppIcon.appiconset`; `App/project.yml` adds the catalog and `ASSETCATALOG_COMPILER_APPICON_NAME`.
  - `Sources/UI/Resources/MenuBar/menubar-template{,@2x,@3x}.png`.
- **Design Gallery (`HubUI/DesignGallery.swift`):** rewritten for v2, every component in every state, light and dark side by side:
  - brand, menu bar states, icons, type specimens, color swatches;
  - all controls, cards, lists, settings, toast, tooltip, dialog, empty state, level meter;
  - the Flow Bar cells, which stay v1 until U3.

**Done when**
- **Gallery snapshots exist for all components in both schemes: pass.** `Artifacts/ui/after/gallery.png` (two columns).
- **Keyboard focus visible on every interactive component: pass.**
  - Every control takes focus (`focusable` plus `FocusState`) and draws `FocusRing`.
  - The gallery shows the forced focused state for buttons, icon buttons, links, toggles, chips, segmented controls, selects, fields, selectable cards and sidebar items.
- **Every component respects Reduce Motion: pass.**
  - Every animation goes through `theme.motion`: springs become 120 ms fades, the press drop and other offsets go to 0. The token lint fails on any direct `.animation(.…)` or `withAnimation(.…)`.
  - The segmented control cross-fades in place under Reduce Motion.

**Tokens not in the brief**
- **Stroke and spacing:** `Stroke.dash` (assumed, MEASURE); `HubGeometry.fieldPaddingH`, `keycapPaddingHInline` (assumed); `chipPaddingH`, `chipCheck` (assumed); `OnboardingGeometry.meterBarRadius` (board, from the motion reference).
- **`MenuBarGeometry`:** glyph, dot, badge and cut-out are board values; the processing dots' gap after the glyph (3) and between dots (1.5) are assumed, MEASURE.
- **`IconTokens` stroke steps:** 1.6, 1.7, 1.8 grid units by size (board).

**Judgment calls**
- **App icon in the gallery:** it shows the running app's icon, so in `murmur-snap` it's the generic one. The real icon is in the app bundle and in `App/AppIcon.iconset`.
- **Hub tooltips** use the Flow Bar's ink pill style: the boards show no Hub tooltip, and §4 lists `MTooltip` without a look.

## U3: Flow Bar

**Changed**
- **`Sources/UI/FlowBarModel.swift`:**
  - Notices and timings per §5.1:
    - cancelled: 5 s with a ring, Undo and Open History;
    - paste error: 4 s;
    - transcription and mic errors: sticky 8 s with Retry;
    - no text box: until dismissed;
    - no audio: sticky 8 s, Switch microphone and Test mic.
  - `FlowSurface` (the one morphing surface), idle fade after 10 s, hover with a tooltip after 400 ms ("Hold [key] to dictate").
  - Hands-free timer from 3 s, inserted word count.
  - Gallery entries for all twelve board states plus the SPEC notices.
  - The right-click menu matches §5.1 #12 (Start hands-free, Paste last transcript, Hide for 1 hour, Settings…) plus Reset Flow Bar position.
- **`Sources/UI/FlowBarView.swift`:** rewritten.
  - **Surface:** one surface on a width spring (240 ms), bottom-anchored. Cards replace the pill in place, and their content fades and rises in.
  - **Size:** computed from tokens and measured text, so the shape springs to its final size before the content lays out.
  - **`FlowWave`:** `drawWave` ported into one `Canvas` inside a `TimelineView` that runs only while listening; per-frame one-pole smoothing (50 / 180 ms) with gain 2.1.
  - **`FlowDots`, `FlowRing`, `FlowCheck`:** ported from `murmur-motion.js`.
  - **Effects:** the transcription-error shake (2 pt, 3 cycles) and the 5-minute nudge.
  - **VoiceOver:** labels and a state description on every state.
  - **Reduce Motion:** fades only, still lobes, a dot pulse, no shake.
- **`Sources/UI/FlowBarPanel.swift`:**
  - fixed canvas sized from the largest card;
  - hit-testing on the surface (the idle pill answers over the hover pill's area) and the tooltip;
  - follows the **system** appearance (`AppleInterfaceThemeChangedNotification`), not the Hub's setting;
  - sits 8 pt above the Dock.
- **`App/Sources/FlowBarWiring.swift`:** inserted word count (a count only), the new actions and menu items.
- **`App/Sources/AppDelegate.swift`:** debug hooks, gated by the Debug menu setting:
  - `debug.forceFlowBar <state>`;
  - `debug.recordTenSeconds`, a hands-free recording that is discarded, used for profiling.
- **Removed:** `Sources/UI/TokensV1.swift`; nothing uses the v1 tokens any more.
- **Tools:**
  - `Tools/compare.py` and `murmur-snap --compare` crop the board's state tiles and write board-and-ours sheets.
  - `Tests/UITests/FlowBarStateTests.swift` rewritten for v2: board sizes, card sizes inside the canvas, notice buttons and timings, tooltip, idle fade, timer, level source, wave shape, saved overrides.

**Done when**
- **All states snapshot side by side with the board crops: pass.**
  - The sheet is `Artifacts/ui/sheets/flowbar-compare.png` (board left, ours right, 11 board states). Raw captures are in `Artifacts/ui/after/{light,dark}/flowbar-*.png`.
  - **Sizes:** the 52 × 12, 76 × 28, 160 × 36, 144 × 36 and 276 sizes, and the card layouts, match the board.
  - **Visible differences:** copy where the board's would be untrue (below), and the snapshot moment of the processing dots and countdown ring.
- **"Never takes focus" test: pass.** 50/50 kept focus in TextEdit, 50/50 clicks reached the bar, 50/50 started hands-free (`Scripts/focus-test.sh`).
- **Idle CPU with the bar visible: pass.** 0.00% over 30 s. The only wakeups are the existing 2 s permission watchdog; the bar runs no timers or animations while idle.
- **10 s dictation profile within the SPEC frame budget (16.7 ms at 60 fps): partial.**
  - **Method:** Instruments Animation Hitches, forced live wave over a real hands-free recording.
  - **Bar alone:** 60 updates/s, app commit p99 5.5 ms, max 11.7 ms, 0 frames over budget.
  - **During a recording:** 60 updates/s, commit p50 1.8 ms, p95 2.7 ms, p99 29.8 ms; 12 of 572 frames (2%) over 16.7 ms.
  - **Cause:** a main-thread sample during recording shows the thread about 92% idle. The slow frames are Core Animation commits waiting on the Metal command queue and a render-server lock while the speech engine uses the GPU and ANE; the bar's own view work is under 2 ms. Reducing it means changing how the engine shares the GPU, which is dictation behavior, so it is left as is.

**Tokens not in the brief**
- **`FlowGeometry`:**
  - board: `inlineKeyBottom` 1.5, `pasteKeyGap` 3, `buttonGap` 6, `buttonIconGap` 6, `cancelledLabelTrail` 4, `noAudioInset` 2 (from `Main.dc.html`);
  - assumed, MEASURE: `timerWidth` 30, `cardTextMaxWidth` 260, `canvasCardWidth` 420, `canvasCardHeight` 96.
- **`TypeTokens.keycapSmall`:** mono 11/500 (board), for the paste key caps and the timer.
- **`WaveTokens`:** `previewLevel` 0.6, the hash constants and `stillTime` (board, from the motion reference).
- **`MotionTokens.contentDelayShare`:** 1/3 (assumed, MEASURE).

**Judgment calls**
- **Copy changed where the board's would be untrue:**
  - The no-text-box sub-line says "Saved to History · ⌃⌘V pastes it". Insertion stops before the clipboard, so "Saved to History and clipboard" is not true here.
  - The transcription-error sub-line says "Audio saved in History", because the engine's reason isn't passed to the bar.
- **Timings follow v2 over SPEC §6's table:** paste error 4 s, no text box until dismissed, cancelled 5 s, transcription error sticky 8 s. Listed in `docs/ui-todo.md` for the owner.
- **Test mic and Switch microphone both open Settings,** where the microphone picker and the level meter live, rather than an onboarding sheet.
- **Command Mode looks the same as dictation on the bar.** v2 has no separate treatment, and clay is reserved for the live mic; VoiceOver says "Command Mode".
- **The forced (debug) listening state draws the motion reference's default level of 0.6,** not its demo `speech()` signal, which the brief says never to ship.
