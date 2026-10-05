# UI audit (U0, before the redesign)

Written 2026-10-05 against `ui-redesign` at the start of U0. It covers how every surface is built today, which system controls it uses, the token API, and what stands in the way of `UI_REDESIGN.md`.

## Platform

- **Deployment target:** macOS 14 (`Package.swift`, `App/project.yml`), with Swift 6 language mode.
  - Everything the redesign needs exists on 14: `Canvas`, `TimelineView`, `matchedGeometryEffect`, `onKeyPress`, `@Entry`, `ImageRenderer`, and `CTFontManagerRegisterFontsForURLs`.
  - APIs newer than 14 are not to be used without `if #available`. That includes `WindowDragGesture`, `pointerStyle` and `onScrollGeometryChange` (macOS 15).
- **Modules:**
  - `UI`: the Flow Bar and its tokens. It depends on `Core` only.
  - `HubUI`: new in U0. The windows moved here from the app target (Hub, onboarding, dictionary and snippets, window manager, token panel, demo data), so `murmur-snap` can render them. It depends on `UI` and `MurmurKit`.
  - App target: the app delegate, Flow Bar wiring, sounds, focus test and self-test.

## Surfaces and the system controls they use

| Surface | File | Built from | System controls / chrome |
|---|---|---|---|
| Hub window | `HubUI/Windows.swift` (`WindowManager.makeWindow`, chrome `.unified`) | `NSWindow` with a full-size content view, transparent title bar, empty unified `NSToolbar` (52 pt bar, traffic lights centered), `NSHostingController` | Window chrome only |
| Hub shell | `HubUI/Hub.swift` `HubView`, `HubSidebar`, `SidebarRow`, `StatusCard` | Hand-built `HStack`: 214 pt sidebar plus page column. **No `NavigationSplitView`.** | `NSVisualEffectView` (`.sidebar` material) behind the sidebar; SF Symbols for icons; `Button(.borderless/.plain)`; `WindowDragArea` (an `NSView` that drags the window) |
| Home | `HomePage`, `HistoryRow` | Stat tiles, search field, `List(selection:)` with day header rows | `List` (inset), `TextField(.plain)`, SF Symbols, `.regularMaterial` hover pill, `contextMenu`, `AVAudioPlayer` |
| Dictionary | `HubUI/VocabularyWindows.swift` `DictionaryView`, `EditableCell` | Add row plus `Table` with in-place editing | `Table`, `TextField(.roundedBorder/.plain)`, `contextMenu`, `onDeleteCommand` |
| Snippets | `SnippetsView` | Same pattern | `Table`, multi-line `TextField(axis: .vertical)` |
| Style | `StylePage`, `Card` | `Form(.grouped)` with a segmented `Picker` and selectable cards | `Form`, `Picker(.segmented)`, `Toggle` |
| General | `GeneralPage`, `ShortcutSettings`, `ShortcutRow`, `MicrophoneSettings`, `LevelMeter`, `LanguagePicker`, `PermissionsSummary` | `Form(.grouped)` | `Form`, `Section`, `Picker` (menu), `Toggle(.checkbox)` in a `LazyVGrid`, `Button(.bordered)`, local `NSEvent` monitor for recording |
| System | `SystemPage`, `TypingApps` | `Form(.grouped)` | `Toggle` ×5, `NSOpenPanel` |
| Experimental | `ExperimentalPage` | `Form(.grouped)` | `Toggle` ×2, `.alert` |
| Data and Privacy | `PrivacyPage`, `CloudKeys` | `Form(.grouped)` | `Toggle`, `SecureField(.roundedBorder)`, `confirmationDialog` |
| Onboarding | `HubUI/Onboarding.swift` | Fixed 640 × 540 window (chrome `.transparent`), step icon tile, `ProgressView`, Back/Skip/Continue | `ProgressView`, `Form` (shortcut step), `Picker(.radioGroup)` (data step), `TextEditor` (practice), SF Symbols |
| Token panel (debug) | `HubUI/TokenPanel.swift` | Filter field, `List` of editable rows | `List`, `TextField` |
| Flow Bar | `UI/FlowBarPanel.swift`, `FlowBarView.swift`, `FlowBarModel.swift` | Borderless non-activating `NSPanel` (level above the Dock, all Spaces, full-screen auxiliary, `canBecomeKey == false`), fixed canvas sized for the largest state, `FirstMouseHostingView`, click-through outside the bar | `NSVisualEffectView` blur (`useBlur`), drop shadow, SF Symbols, `Button(.plain)`, `contextMenu` (native) |
| Menu bar | `App/AppDelegate.swift` | Native `NSMenu`; SF Symbol status images per phase | Stays native (allowed) |

## Token API today (`Sources/UI/Tokens.swift`)

- **`Tokens`** is one `Codable` struct of Flow Bar values, edited live through `LiveTokens.shared` (persisted overrides that merge over the defaults, so new tokens never invalidate a saved set). Its groups:
  - geometry: `idleWidth/Height`, `activeWidth/Height`, `handsFreeWidth`, `noticeWidth/Height`, `cornerRadius`, `bottomMargin`, `fullScreenLift`, `dockSideOffset`;
  - waveform: `waveformBars`, `BarWidth`, `BarGap`, `Min/MaxHeight`, `Floor/CeilingDb`, `Attack/Release`, `FrameRate`;
  - colors as hex strings in light/dark pairs: `surface`, `waveform`, `idle`, `stop`, `cancel`, `error`, `success`, `command`, `text`, `secondaryText`, `border`;
  - material: `useBlur`, `borderWidth`, `shadowRadius/Opacity/Y`;
  - motion: `appear/disappearDuration`, `springResponse/Damping`, `processingLoopPeriod`, `confirmationHold`, `cancelledToastDuration`, `noticeDuration`;
  - type: `labelSize`, `labelWeight`, `buttonSize`, `hubTypeface`;
  - sound: start, stop, done and error pitches, lengths and volumes, plus `glide`, `brightness`, `bellness`, `attack`.
- **Colors** resolve through `Color.token(light, dark)`, a dynamic `NSColor` keyed on `NSAppearance`. Rule 5 asks for the SwiftUI `colorScheme` environment instead. The redesign adds `ThemeColors` and `FlowBarColors` beside this and moves views over.
- **Names are kept** and extended rather than renamed. If U3 retires a Flow Bar token (for example `useBlur` or the shadow), it stays in the struct with its new default (blur off, shadow 0), so saved overrides keep decoding.

## What stands in the way of `UI_REDESIGN.md`

1. **Stock controls everywhere in the Hub** (rule 6): `Form`, `List`, `Table`, `Toggle`, `Picker`, `TextField` and `SecureField`. U4–U6 replace them with the §4 components. Text input still needs an AppKit-backed text field underneath; it gets the `MTextField` styling.
2. **SF Symbols** carry most of the "stock Mac" look. U2 adds the original icon set, and anything not yet drawn is listed in `docs/ui-todo.md`.
3. **Flow Bar:**
   - blur material and a drop shadow (rule 7 wants flat, with the shadow off by default);
   - the waveform is an `HStack` of animated capsules (rule 8 wants one `Canvas`);
   - levels are pushed to the main actor per audio buffer (U3 reads them at display rate instead);
   - notices are one card style, where §5.1 wants alerts and toasts.
4. **Settings live in four sidebar items.** §5.3 wants one Settings item with tabs, plus Help.
5. **Sounds** are synthesized at runtime from tokens and include a fourth "done" sound the owner asked for. §6.3 wants script-generated WAVs for start, stop and error; U3 generates all four (keeping "done") and flags it.
6. **Fonts:** none are bundled. U1 adds Source Sans 3 and Newsreader.

## Snapshot harness (built in U0)

- **Tool:** `swift run murmur-snap [before|after]` renders every Hub page, onboarding step and Flow Bar state, in light and dark at the screen's 2× scale, with demo data from `DemoData.seed`, into `Artifacts/ui/<set>/<appearance>/`. It exits non-zero on a blank image.
- **Rendering:** it draws real offscreen windows through AppKit's `cacheDisplay`, not `ImageRenderer`, because `ImageRenderer` cannot draw AppKit-backed controls (text fields, today's toggles and tables).
- **Committed output:** the raw sets are git-ignored and only contact sheets are committed.

---

# v2 audit: Paper & Clay (U0 of the v2 brief)

Written 2026-10-05 after the v2 bundle was installed. UI_REDESIGN.md v2 replaces the v1 values and visuals; v1's infrastructure is kept. The surface table above is still accurate for the Hub, onboarding and menu bar: none of them was restyled in v1. Only the Flow Bar changed in v1, in the unfinished U3 commit.

## Platform

- **Unchanged:** macOS 14 deployment target, Swift 6.
- **Gated APIs:** the v2 brief needs nothing newer than 14. Still avoid `Group(subviews:)`, `WindowDragGesture`, `pointerStyle` and `onScrollGeometryChange` (all macOS 15).

## v1 work reused

| v1 piece | Where | v2 use |
| --- | --- | --- |
| Snapshot tool | `Sources/MurmurSnap` | Kept. U0 adds `--large` (text scale 1.15) and `--reduce-motion`; U3 adds `--compare` (board crops). |
| Design Gallery, token panel | `HubUI/DesignGallery.swift`, `TokenPanel.swift` | Kept. Debug overrides: appearance, Reduce Motion, time scale, text scale, forced Flow Bar state (with hover). |
| Token lint | `Scripts/check-tokens.sh` | Kept at its existing path (v2 writes `scripts/`; the repo uses `Scripts/`). |
| Token file split, `ThemeProvider`, `\.theme`, `Motion`, `AppearanceController`, `UIDebug` | `Sources/UI` | Kept. The values and names change in U1. |
| `FontRegistry` | `Tokens+Type.swift` | Kept. Source Sans 3 is replaced by Geist and Geist Mono; Newsreader stays (400, 400 Italic, 500). |
| `BrandMark` SVG path parser | `Components/BrandMark.swift` | Kept. U2 also uses it for the icon set (board SVG paths). |
| `MicLevelSource` | `Sources/Core` | Kept: the audio thread writes under a lock and the UI reads once per frame. |
| Sounds | `Tools/make_sounds.py`, `Tokens+Sound.swift`, `Resources/Sounds` | Kept; v2 §6.4 has the same values. "done" stays, as v1 noted. |
| Flow Bar panel | `FlowBarPanel.swift` | Kept: fixed canvas, click-through except visible shapes, hover tracking, measured card size. |
| Flow Bar model | `FlowBarModel.swift` | Kept (gallery entries with hover, countdowns, tooltip delay). U3 adds the v2 states: hands-free timer, word count, idle fade, no audio. |
| Components | `Sources/UI/Components` | The structure and focus, hover and press plumbing (`resolvedState`, `FocusRing`, forced interaction for the gallery) are kept. The visuals are redone in U2. |

## Token migration (v1 → v2)

- **Colors (`ThemeColors`):**

  | v1 | v2 |
  | --- | --- |
  | `bgCard`, `bgField` | `bgPanel` |
  | `bgHover` | `fillHover` |
  | `bgChip` | `fillChip` |
  | `bgFeature` | `bgSunken` |
  | `borderPanel` | `borderHairline` |
  | `textTitle` | `textPrimary` |
  | `textBody` | `textSecondary` |
  | `textDisabled`, `textPlaceholder` | `textTertiary` |
  | `accentClayText` | `accentClay` (the dark value is `#D9705F`) |
  | `buttonText` | `onClay` |

  - **Dropped:** `borderFeature`, `accentClayTint` (selection is an ink ring), `dangerText` (errors are never red).
  - **New:** `fillSelected`, `textTertiary`, `stone`, `inkFill`, `inkFillPressed`, `onInk`.
  - **Kept as assumed:** `scrim`.
- **Flow Bar (`FlowBarColors`):** now picked by system appearance.

  | v1 | v2 |
  | --- | --- |
  | `fill`, `tooltip` | `flowFill` |
  | `border`, `alertBorder` | `flowRing` |
  | `dot` | `flowIdleMark` |
  | `bar`, `stop` | `flowLive` |
  | `xCircle` | `flowCancel` |
  | `xGlyph`, `text`, `iconError`, `iconInfo` | `flowText` |
  | `button` | `flowButton` |

  - **New:** `flowTextSecondary`, `flowStopGlyph`, `flowButtonText`, `flowButtonRing`.
- **Type:** Source Sans 3 becomes Geist; Geist Mono is new.

  | v1 | v2 |
  | --- | --- |
  | `heading` | `cardTitle` / `stepTitle` |
  | `row` | `body` |
  | `section` | `caption` (mono) |
  | `chip` | `stat` (mono) |
  | `badge` | `tag` (mono) |
  | `flowText`, `flowAlert` | `label` |
  | `meta` | `meta` (now mono) |

  - **New:** `welcomeTitle`, `stepTitle`, `cardTitle`, `trigger`, `quote`, `sample`, `label`, `control`, `hint`, `flowSub`.
- **Components:**

  | v1 | v2 |
  | --- | --- |
  | `MButton` kinds primary / secondary / ghost / destructive | primary / ink / outline / link / icon (destructive dropped: no red) |
  | `MTabs` | `MSegmented` |
  | `MCheckbox` | `MRadio` |
  | `MStatChip` | `MStatStrip` |
  | `MBadge` | `MTag` |
  | `MToast` | `MPaperToast` |

  - **New:** `MAppTile`, `MStatusCard`, `MStepFrame`.

## What stands in the way of v2

1. Everything in the v1 list above, except fonts and tokens, which U1 replaces.
2. **Onboarding has 12 steps, the board shows 10.** The implementation follows SPEC §6:
   - The 12 steps: welcome, microphone, accessibility, input monitoring, models, mic test, shortcut, languages, practice (hold), practice (hands-free), data, Flow Bar.
   - v2 §5.4 says "same steps, order and behavior as SPEC §6", so all 12 stay. The models step and the second practice step get board-style frames, and the counter reads "NN / 12".
3. **No "no audio" event.** The dictation controller never reports a silent recording to the Flow Bar.
   - The v2 no-audio alert is built and reachable from the debug menu.
   - Wiring it to real silent recordings would change dictation behavior, so it waits for the owner (logged in `docs/ui-progress.md`).
4. **Paste last shortcut.** v2's right-click menu and menu bar show ⌃⌥V and ⌃⌥C; the app's shortcuts are ⌃⌘V and ⌃⌘C (I7). Shortcuts are behavior, so the real bindings are shown.
5. **Help & setup and the bell popover** are new surfaces with no SPEC behavior. They only reuse existing actions: permissions, onboarding re-run, shortcuts.
