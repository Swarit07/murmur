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

## U4: Hub shell and Home

**Changed**
- **`Sources/HubUI/HubShell.swift` (new):**
  - `HubView` and `HubShell`: the ivory window, the 232 pt sidebar, and the paper panel inset 8 pt with radius 12 and a 1 pt edge. Content sits inside the edge.
  - The page switch is a 160 ms fade with a 6 pt rise.
  - **Sidebar:** the traffic lights' zone, the brand mark, Home, Dictionary, Snippets, Style, then Settings, Help & setup and the status card (Ready / Listening… / Working… / Loading, the key cap, the microphone).
  - **Home's 48 pt top bar:**
    - search opens a field above History;
    - the bell shows a dot when there are alerts and opens a popover of system alerts: missing Microphone, Accessibility or Input Monitoring, and the last error, each with its fix.
  - **Help & setup sheet:** shortcuts, permission rows, "Run setup again" (wired to onboarding), the version.
  - **Keyboard:** ⌥↑ / ⌥↓ and ⌘[ / ⌘] are kept; Esc closes the popover and the sheet.
  - **Pages not yet rebuilt (U5, U6)** render inside the panel. Settings shows its four tabs as an `MSegmented` over the old pages until U6.
- **`Sources/HubUI/HomePage.swift` (new):**
  - **Header:** the date caption, "Welcome back, *first name*" from `NSFullUserName()`, and the stat strip (day streak, words and wpm over 7 days, each hidden when it can't be computed).
  - **Feature card:** the user's own style applied to three sample lines; Set up styles opens Style; Not now hides the card for good (stored).
  - **History:** grouped by day in `MListContainer`s, with Cleaned | Raw.
    - **Rows:** time, app tile (Messages-like / work chat / mail / code / note by bundle id), transcript, "App · N w".
    - **Hover:** Copy, Play audio, Retry or Recover, and a "raw" chip that peeks at the spoken words.
    - **Silent rows:** "Audio was silent" with an info tooltip.
    - **Kept from before:** the context menu (copy, play, retry, undo or redo the AI edit, copy original words), ↑↓ / j k selection, and Return copies.
- **`Sources/HubUI/Hub.swift`:**
  - `HubModel` gains the text scale (Text size setting), search, bell, help, alerts, `onRunOnboarding` and `hotkeyLabel`.
  - The old shell, sidebar, status card, Home and history row are removed.
- **Shared plumbing (affects every component):**
  - `TextStyleModifier` gives each line the full CSS line box (half the leading above and below); `SerifTitle` does the same.
  - `MCard` and `MListContainer` put their 1 pt border outside the content, as a CSS border does.
  - Together these move Home from 3–12 pt off the board to within 1.5 pt.
- **`Sources/HubUI/DemoData.swift`:** the boards' fixture rows, dictionary and snippets (snapshots only).
- **Snapshots and checks:**
  - `murmur-snap` renders the Hub at 1180 × 740 with the status card ready.
  - The app's snapshot self-check (`debug.snapshot`) now checks dragging, the sidebar click and keyboard navigation in the v2 layout.
  - `Tools/measure_hub.py` measures Home against the board.

**Done when**
- **Home at 1180 × 740 matches `hub-home.png` within ±2 pt on the §3.4 numbers: pass.** Worst difference 1.5 pt (`Tools/measure_hub.py`):

  | Measured | Result |
  | --- | --- |
  | brand mark top, height, left | 0 |
  | Home row top, height | 0 |
  | panel left, top, right inset | 0 |
  | title top, left | 0 |
  | feature card top | −0.5 |
  | feature card left, right | 0 |
  | feature card height | −1.0 |
  | first History row | −1.5 |

  The side by side is `Artifacts/ui/compare/hub-home.png`, committed as `Artifacts/ui/sheets/hub-home-compare.png`.
- **Light and dark render: pass.** `Artifacts/ui/after/{light,dark}/hub-home.png`.
- **Option+Up/Down and Cmd+[ / Cmd+] still work: pass.** The in-app check posts the real key events: ⌘[ PASS, ⌘] PASS, ⌥↓ PASS, ⌥↑ PASS. Sidebar click PASS; window drag from the panel's top bar and the sidebar top PASS.
- **No stock `NavigationSplitView` or `List` in the Hub shell or Home: pass.** Dictionary, Snippets, Style and Settings still use `Table` and `Form` inside the new shell until U5 and U6.

**Tokens not in the brief** (all board values from `Hub-Home.dc.html`)
- **Geometry:** `trafficLightsZone` is now 20 (16 plus 2 pt CSS padding above and below); `featureSamplesGap` 8, `featureTextGap` 12, `featureParagraphWidth` 400.
- **Type:** `sampleCompact` (Newsreader 15/20) and `tagTight` (Geist Mono 10/13) for the feature card's sample lines.

**Judgment calls**
- **History rows offer Copy, Play audio, Retry and the raw chip.** The board's "Paste again" would insert text into another app from the Hub, which is new dictation behavior, so it's left out.
- **Times follow the user's locale** ("9:41 AM"); the board's "9:41" drops AM/PM.
- **The stat strip counts the last 7 days, from the 1,000 most recent dictations.**
- **Feature-card samples use the user's chosen style per category.** The text is neutral, not the board's "Priya" fixture.
- **Paper toasts aren't needed on Home yet;** they arrive with Dictionary saves in U5.

## U5: Style, Dictionary, Snippets

**Changed**
- **`Sources/HubUI/PageParts.swift` (new):**
  - `HubPageHeader`: the title, a one-line description in `lead` 14/18, and an action aligned to the bottom right.
  - `HubPageScroll`: the board's 44 / 56 page padding.
  - `PaperToastHost`: bottom center, 22 above the panel's edge, leaves after 4 s, Undo.
  - `UsageCounts`: how often a word or a snippet's text appears in the last 1,000 dictations, for "N uses".
- **`Sources/HubUI/VocabularyPages.swift` (new):**
  - **`DictionaryPage`:**
    - "Add word" (ink); search ("Search N words"); filter All | Added by you | Learned.
    - One bordered list with rows 46 high on the board's grid (200 / flexible / 84 / 72): word, sounds-like in the quote style or "—", an added or learned tag, uses; Edit and Remove on hover.
    - The add and edit row works in place (word field focused, sounds-like in quote style, Cancel, Save).
    - Adding shows the paper toast "Added to Dictionary · “word”" with Undo.
  - **`SnippetsPage`:**
    - "New snippet" (ink); two columns of cards (radius 12, padding 16) whose rows share a height.
    - Each card: trigger in italic curly quotes, an arrow, uses; Edit and Delete on hover with the 1.5 pt ink ring; the expansion in a dashed box that keeps line breaks; the edit card works in place.
  - **Both:**
    - List the most used first, ties alphabetically.
    - Keep v1's behavior: add, edit, delete (hover actions and context menu), search.
    - Keep v1's rule that a plain word stores `term` equal to its spelling.
- **`Sources/HubUI/StylePage.swift` (new):**
  - The category segmented control.
  - **Style cards** (`MSelectableCard`, radius 14, padding 14): name in `card-title`, the board's descriptor, the app's own example in a sunken box. Selection is an ink ring and a filled radio, never clay.
  - The apps in each category, as a hint.
  - **Auto cleanup:** caption, description, "You said" plus the raw quote, then None / Light / Medium cards.
  - **AI edits:** a switch in a settings group. With it off, the cleanup cards are disabled, as before.
- **Removed:** the old `StylePage`, `Card`, `DictionaryView`, `SnippetsView` and `EditableCell` (stock `Form`, `Table`, `Picker`, `TextField`).
- **Tokens:**
  - **Type (board):** `lead` 14/18, `expansion` 13/19.5.
  - **Geometry (board):** buttons with an icon padded 12 / 16; `titleToSubtitle` 8; subtitle widths 520 and 560; `snippetsSectionGap` 24; the dictionary's grid gap, field widths and edit-row padding; style card gap 10; divider margin 6; snippet header and action gaps.
  - **Assumed:** `MotionTokens.paperToast` 4 s, `OpacityTokens.disabledGroup` 0.5 (both MEASURE).
  - **`MTextField`:** gains `autofocus`.

**Done when**
- **All three pages work with the new components: pass.** No stock list, form, table, picker or field remains on these pages.
- **Behave exactly as before: pass (by construction).**
  - Add, edit and delete call the same store functions as v1, with the same `term` / `replacement` rule.
  - Style writes the same `styles`, `cleanupLevel` and `transformsEnabled` settings.
  - The two visible changes are list order (most used first) and the "N uses" counts. Both are display only.
- **Snapshots in both schemes next to their reference crops: pass.**
  - `Artifacts/ui/after/{light,dark}/hub-{style,dictionary,snippets}.png`.
  - `Artifacts/ui/sheets/hub-{style,dictionary,snippets}-compare.png` (board left, ours right).

**Visible differences from the boards, on purpose**
- **Style shows 3 cards per category, not 4.** The app offers "very casual" only for Personal and "Excited!" everywhere else (S4); the board shows all four.
- **Cleanup descriptions are the app's own.** The board's "Also resolves the corrections you make mid-sentence" isn't a promise the cleanup prompt makes; the samples are the existing implementation's.
- **"N uses" counts are computed from History** (the store keeps no counter), so a fresh install shows 0.
- **The board's fixture rows (Priya, Saoirse…) appear only in snapshots.**
- **In the app, the Dictionary search field takes focus when the page opens** (standard macOS first-responder behavior). Snapshots clear focus to show the resting state.

## U6: Settings

**Changed**
- **`Sources/HubUI/SettingsPages.swift` (new):** `SettingsPage` with the title and General | System | Experimental | Data & privacy. Each tab is two columns of settings groups (caption 8 above a 12-radius list, rows 12 × 14, label and hint left, control right, groups 20 apart).
  - **General:**
    - **Dictation:** push-to-talk, hands-free and Command Mode shortcuts (key caps plus Change, with v1's recorder logic); microphone; microphone test (compact level meter); languages (opens a sheet of chips); Reset to defaults; the Globe-key and Secure Keyboard Entry notices.
    - **Appearance (new):** Theme (System / Light / Dark) and Text size (Default / Large).
    - **Output:** auto cleanup, speech engine (mono select), cleanup model, sounds, show Flow Bar, launch at login (errors shown in the hint).
    - The "Nothing leaves this Mac" info card.
  - **System:**
    - Formatting (Smart Formatting), App (Show in Dock), Advanced (free memory when idle, debug menu).
    - Typing instead of pasting: app rows, Add app…
    - Permissions: state, Open System Settings, Restart Murmur when Input Monitoring needs it.
  - **Experimental:** Command Mode, and Press Enter with its confirmation.
  - **Data & privacy:**
    - History: keep audio, never store, delete everything with a confirmation.
    - Cloud keys: secure fields, Keychain, Save and Remove.
    - The info card.
  - **Confirmations** are an `MDialog` on the scrim, not system alerts; destructive actions use the ink button (no red).
  - **`FlowLayout`, `LanguageChips`, `LanguageNames`** are shared with onboarding in U7.
- **Components and tokens:**
  - `MSettingsRow` hints use `text-tertiary`; the group's caption gap is 8.
  - `MLevelMeter(compact:)`.
  - `HubGeometry.keycapHeight` is 28 (board, settings rows).
  - New tokens:
    - board: `settingsGroupGap` 20, `settingsCaptionGap` 8, `settingsControlGap` 6;
    - assumed, MEASURE: `meterCompact` 3 × 16, `meterCompactGap` 2.
- **Removed:** the old `GeneralPage`, `SystemPage`, `ExperimentalPage`, `PrivacyPage`, `TypingApps` and `CloudKeys` (stock `Form`, `Toggle`, `Picker`, `SecureField`, `.alert`, `confirmationDialog`), and the interim `SettingsShell` and `LegacyPage`.
  - The v1 shortcut, microphone and permission views stay in `Hub.swift` only because onboarding still uses them; U7 replaces them.

**Done when**
- **Every setting still persists: pass.** Each control writes the same `AppSettings` key (or controller call) as before:

  | Setting | Written to |
  | --- | --- |
  | Speech engine | `engine` |
  | Cleanup model | `cleanupProvider` |
  | Auto cleanup (here and on Style) | `cleanupLevel` |
  | Sounds | `soundsEnabled` |
  | Show Flow Bar | `showFlowBar` |
  | Show in Dock | `showInDock` |
  | Smart Formatting | `smartFormatting` |
  | Free memory when idle | `unloadWhenIdle` |
  | Debug menu | `debugMenu` |
  | Typing instead of pasting | `typingApps` |
  | Languages | `languages` |
  | Keep audio | `keepAudio` |
  | Never store anything | `neverStore` |
  | Command Mode | `commandMode` |
  | Press Enter | `pressEnter` |
  | Microphone | `controller.selectMicrophone` |
  | Shortcuts | `controller.setShortcuts` |
  | Launch at login | `SMAppService` |
  | Cloud keys | Keychain |
  | Theme (new) | `appearance` |
  | Text size (new) | `textSize` |

  `styles` and `transformsEnabled` live on Style (U5). No setting from v1 was dropped.
- **All four tabs have snapshots in both schemes: pass.**
  - `Artifacts/ui/after/{light,dark}/hub-{general,system,experimental,privacy}.png`.
  - General next to the board: `Artifacts/ui/sheets/hub-settings-compare.png`.

**Visible differences from the board, on purpose**
- **General has more rows than the board:**
  - Command Mode's shortcut, the microphone test, the cleanup model, and Reset to defaults.
  - The Globe-key notice, when it applies.
  - These are existing settings the board leaves out.
- **The speech engine select shows the engine's full display name,** not a short id.

## U7: Onboarding

**What changed**
- **`Onboarding.swift` is rewritten to §5.4.**
  - Each step is 400 × 560 on the ivory window. It has a mono header ("04 / 12 · Permissions" with the 120 × 2 progress bar), a sunken illustration well, a Newsreader title, Geist body text and one clay primary action. Steps cross-fade with the 12 pt upward drift, and the drift is off under Reduce Motion.
  - `StepScaffold`, `StepHeader` and `StepFooter` are shared by every step.
- **The illustrations are drawn in SwiftUI from tokens:**
  - the microphone prompt and the Accessibility list mock (with the brand icon);
  - the held key with its down/held meter;
  - models ready (or the waiting line while they load);
  - the mic-test meter with the reading line and microphone picker;
  - the two shortcut cards;
  - the language chips with search;
  - the practice field with a live copy of the Flow Bar;
  - the data choice cards;
  - the Flow Bar sketch above a Dock.
- **The app icon is bundled** as `Sources/UI/Resources/Brand/app-icon{,@2x}.png`, rendered from `Design/brand/app-icon.svg` by `Tools/make_icons.py`. It is shown on the welcome step and in the Accessibility mock.
- **The onboarding window** is fixed at `OnboardingGeometry.step` with transparent chrome (`Windows.swift`: `sizingOptions = []`, then `setFrame`).
- **Long copy can't push the footer out of the window.** The illustration well shrinks from 200 to at most 160 (`wellMinHeight`) when a step's text needs the room. The language chips scroll when they don't fit. Every step's primary button ends 28 pt from the bottom in both schemes (measured on the snapshots).
- **Removed v1 code:**
  - `ShortcutSettings`, `ShortcutRow`, `MicrophoneSettings`, `LevelMeter` and `PermissionsSummary` from `Hub.swift`. `PermissionsSummary.relaunch()` became `AppRelaunch.now()`.
  - `VocabularyWindows.swift`: `LanguagePicker` and `EmptyState`.
  - From `Design.swift`: `LegacyBrandMark`, `VisualEffect`, `StatTile`, `SearchField` and `Footnote`. What remains is renamed `WindowDragArea.swift`.
- **The token lint now covers** `Hub.swift`, `Onboarding.swift` and `WindowDragArea.swift`. The only exemptions left are the two debug tools (`TokenPanel.swift`, `DesignGallery.swift`).
- **New tokens:**
  - `OnboardingGeometry`: well, prompt card, settings card, hold key and meter, mock sizes, Dock sketch, arrow, `wellMinHeight` (derived).
  - `TypeTokens.keycapHold` (16/20 mono).
  - `MeterTokens.previewLevel`.
  - `rippleDot` is assumed and marked MEASURE.

**Done when**
- **Every step renders in snapshots in both schemes: pass.**
  - 12 steps × light/dark: `Artifacts/ui/after/{light,dark}/onboarding-*.png`, at 800 × 1120 px.
- **Resume-where-stopped and skip-granted-steps: pass, by unit test, not by `tccutil`.**
  - Not run: `tccutil reset All` would revoke Murmur's real permissions on this Mac, and the run rules forbid changing security settings.
  - Instead, `Tests/HubUITests/OnboardingTests.swift` (4 tests, passing) drives the real `OnboardingModel` with permission state injected through `isDoneOverride`. It checks that onboarding:
    - resumes at the saved step;
    - skips granted steps forward and back;
    - saves progress, except in the design preview;
    - keeps SPEC §6's 12 steps in order.
  - The live check with a reset is on the owner's checklist.
- **The permission-revocation test is unchanged and still pending with the owner** (`docs/m4-gate.md`, part B).
  - The detection code in `AppDelegate` was not touched; only its notice copy changed, to name "Settings › System".
  - Neither this test nor the fresh-account run can be automated here.
- **Tests:** 167 pass (`MURMUR_NO_MLX=1 swift test`). Token lint passes. The Release app builds and installs (`Scripts/install-app.sh`).

**Visible differences from the board, on purpose**
- **12 steps, not the board's 10.**
  - The board folds the model download into another step and has one practice step. SPEC §6 has a models step and two practice steps (hold, then hands-free).
  - The SPEC's behavior wins, so the counter reads "/ 12".
- **Real values in place of placeholders:**
  - `[HOTKEY]` shows the configured key ("fn"); hands-free shows the configured keys.
  - `[VERSION]` shows `CFBundleShortVersionString` ("dev" in snapshots).
  - The language count is the app's own list (17), not the board's 99.
- **Permission steps show the real state.** Their primary reads "Allow microphone" or "Open System Settings" until the permission is granted, then "Continue". The snapshots show whatever the `murmur-snap` process has, so the microphone step there reads "Continue".
- **The Input Monitoring step adds one line:** macOS may ask to quit and reopen Murmur. That is true on macOS 14 and up, and without it people abandon setup there.
- **Data step:**
  - The board's "Share anonymous crash reports" card is dropped: Murmur has no crash reporting, and the copy must be true.
  - The two cards are the existing choice: keep History on this Mac, or keep nothing.
  - "Keep audio" uses the real retention, 14 days.
- **Shortcut cards** show both modes as in use, with a Change button each, instead of a radio choice. Push-to-talk and hands-free both always work.

## U8: Menu bar, polish, accessibility

**What changed**
- **Status item (§3.6):**
  - Uses `MenuBarGlyph` in its four states: idle (template), recording (clay copy plus a 5 pt dot), processing (45% template plus five rippling dots), error (ink "!" badge, never red).
  - Loading shows the still processing glyph.
  - The ripple is redrawn every 1/30 s only while processing (`MotionTokens.menuBarFrame`) and is still under Reduce Motion.
  - The status item is now variable-length so the dots fit. Each state has its own VoiceOver label and tooltip.
- **Dropdown (§5.2)** is a native `NSMenu`, in the board's order:
  - Header: a custom view (`MenuHeaderView`) that mirrors the bar. It shows ready with the real hotkey; listening with the clay dot, mic name and a live mono timer; working; loading; or the last error split into what happened and the fix ("Transcription failed." / "The audio is saved in History.").
  - Open Murmur ⌘O, Paste last, Copy last.
  - Microphone ▸: "Automatic (*default device*)", each input, then Sound Settings….
  - Hide Flow Bar for 1 hour.
  - Shortcuts ▸, Settings… ⌘,, and Check permissions (it opens Settings › System). It shows a native "N missing" badge when Microphone, Accessibility or Input Monitoring is missing.
  - Quit Murmur ⌘Q.
  - Footer: a custom view with mono "v0.1.0 · on-device engine", or which part runs in the cloud.
  - The highlight is the system's.
- **Measured against the real menu.** The header and footer start 16 pt in (`menuInsetH`), matching the native item titles on macOS 27 in a capture of the real dropdown. A debug hook (`com.swaritsheel.Murmur.debug.menu <state>`) opens the dropdown in a state and saves it to `Snapshots/menu/`.
- **Accessibility passes:**
  - **Text size 1.15** (`murmur-snap --large`): the History time column wrapped ("9:41 A / M"). It now stays on one line and its column grows with the text.
  - **Text size scope:** the setting now applies only to the Hub, as its hint says. `ThemeProvider` takes a scale only from the Hub, so onboarding, the Flow Bar and menus stay at default size, including under the debug override.
  - **Increase Contrast:** new `murmur-snap --contrast` set (`UIDebug.increaseContrast`). Edges and tertiary text strengthen in both schemes; no clipping.
  - **Reduce Motion** (`--reduce-motion`): renders clean. Behavior is covered by the motion tests in `ThemeTests`.
  - **VoiceOver:**
    - A runtime scan isn't possible offscreen: SwiftUI only builds its accessibility tree for an attached assistive client.
    - So every control was audited in source: icon-only buttons, the Flow Bar round buttons, the search clear button, onboarding Back, cards, chips, segmented items, selects and key caps all carry names; selected items carry the selected trait.
    - `MToggle` now reports the toggle trait (VoiceOver says "switch") instead of button.
- **Clipping check:** `Tools/check_layout.py`. It fails if an onboarding step's primary button ends within 20 pt of the window bottom, or if anything but the backdrop touches a Flow Bar canvas edge. All four snapshot sets pass (58 images each).
- **Truth fixes:**
  - The sidebar status card's tag says "cloud" when a cloud speech engine or cleanup model is selected; before, it always said "on-device".
  - "macOS 14 or later" now comes from the bundle's minimum version (`AppInfo`).
- **Dead code removed:**
  - `MStepFrame` (onboarding uses `StepScaffold`); its file is now `MIllustrationWell.swift`.
  - `TextStyleToken.sized`.
  - Nine unused tokens: `silentTile`, `subtle`, `menuMinWidth`, `historyTileColumn`, `dictionaryActionsColumn`, `editFieldHeight`, `holdKeyHeight`, `textGap`, `ringDigitShare`.
  - No stock `Form`, `Toggle`, `Picker`, `.alert` or `confirmationDialog`, and no SF Symbols, remain in shipped UI.
  - The only token-lint exemptions left are the two debug tools.
- **`docs/ui-calibration.md`:** the §9 placeholders and where each is resolved, the open items with what ships now, and all 76 `// MEASURE` tokens with value, reason and location.
- **Contact sheet:** `Tools/redesign_sheet.py` writes three columns per screen: before (v1), after (v2), reference board crop.
  - Sections: `Artifacts/ui/sheets/contact-{hub,onboarding,flowbar,menubar}.png`.
  - Overview: `Artifacts/ui/sheets/contact-sheet.png`.
  - The per-milestone compare sheets and the gallery in `Artifacts/ui/sheets/` were refreshed to the final build.

**§8 checks**

| Check | Result |
| --- | --- |
| Token lint (`Scripts/check-tokens.sh`) | Pass. Only the two debug tools are exempt. |
| Contrast tests (every §3.2 pair, both schemes; no stone text, clay only where allowed, no red) | Pass (`ThemeTests`) |
| Snapshot tool: light, dark, 1.15, Reduce Motion, Increase Contrast | Pass: 77 images per set, none blank. Clipping check passes on all four sets. |
| Reference comparison (`murmur-snap after --compare`) | Written to `Artifacts/ui/compare/`. Differences are listed in each milestone's report above. |
| SPEC test suite | Pass: 167 tests (`MURMUR_NO_MLX=1 swift test`) |
| 50-trial focus test | Pass: 50/50 kept focus in TextEdit, 50/50 clicks reached the bar, 50/50 started hands-free |
| Reduce Motion behavior (A8) | Pass (motion tests; the processing ripple and onboarding drift are still under Reduce Motion) |
| Permission-revocation detection (A3) | Code unchanged; the live test is on the owner's checklist (it needs permissions revoked by hand) |
| SPEC §7 latency budget | Pass. Release to text p50 652 ms, p95 1,340 ms over today's 62 dictations (targets 800 ms and 1.5 s). The pipeline was not touched. |
| Dictation self-test (21 recorded clips through the real pipeline into TextEdit) | Pass: 21/21 |
| In-app checks (window drag, Style row click, ⌘[ ⌘] ⌥↑ ⌥↓) | Pass |
| Idle CPU | 0.0–0.1% with the new status item |

**Not fully met**
- **Flow Bar frame pacing during a live recording:** 12 of 572 frames (2%) went over 16.7 ms in U3's profile. The bar alone has none over budget (commit p99 5.5 ms). The late frames line up with the speech engine's GPU work, and the main thread is about 92% idle. Details are in the U3 report.
- **Menu header and footer inset:** 16 pt was measured on macOS 27 only. macOS 14's native menu inset may differ by a point or two; the value is marked MEASURE.

## Owner checklist (manual)

Things that can't be run from here. About 30 minutes in all.

1. **Fresh macOS account onboarding** (`docs/m4-gate.md` part A): run setup end to end. Quit midway and reopen: it resumes at the same step and skips permissions already granted.
2. **Permission revocation** (`docs/m4-gate.md` part B): turn Accessibility off while Murmur runs. The notice should appear, the menu's Check permissions should show "1 missing", and the status item should show the error glyph.
3. **Flow Bar placement:**
   - over a full-screen app, a dark app and a light app, with system appearance light and then dark;
   - Dock on the left, on the right and auto-hidden;
   - two displays.
4. **Hub window** at the minimum 880 × 560 and the default 1180 × 740: nothing clipped, and the sidebar and status card fit.
5. **Slow motion:** menu bar › Debug › Token panel…, set time scale to 0.2, then watch each Flow Bar transition, a page switch and an onboarding step.
6. **VoiceOver** (⌘F5): walk the sidebar, a Settings tab with toggles, one onboarding step and the menu bar dropdown.
7. **Decisions** (details in `docs/ui-calibration.md` and `docs/ui-todo.md`):
   - wire the "We couldn't hear you" card or not;
   - v2 Flow Bar timings vs SPEC §6;
   - "Shortcuts" as a submenu;
   - the board's ⌃⌥V/⌃⌥C vs the real ⌃⌘V/⌃⌘C;
   - review the dark Hub (there is no dark Hub board);
   - the onboarding size and the data-step crash-reports card.

## After U8: Flow Bar off screen (owner report)

- **Symptom:** holding fn showed no bar at all.
- **Cause:** a saved drag offset (`murmur.flowBarOffset`, 320 pt down) was added to the resting point with no limit. On the 1512 × 982 screen with the Dock hidden, the panel sat at y = 1176, entirely below the display. It was visible and animating, just off screen. The bug dates from the original Flow Bar drag code, not the redesign, but nothing caught it before.
- **Fix:** `FlowBarController.clamp` keeps the whole canvas (the widest card and the tooltip) inside the screen's visible frame. It is applied when the bar is placed and on every drag, so a drag past an edge or an offset saved on another display can't hide the bar. The bar now sits 8 pt above the bottom edge. Right-click › Reset position recenters it.
- **Tests:** `FlowBarPlacementTests` (3) cover the owner's exact offset, every edge, and an ordinary drag that's kept.
