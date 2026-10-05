# UI calibration

This file tracks every value in the UI that isn't final yet: the board placeholders, the open design decisions, and every token still marked `// MEASURE`. It was created from UI_REDESIGN.md v2 §9 in U8.

How a value gets settled:
1. Measure it: on a board (`Design/reference/*.png` is drawn at 1 pt = 1 px), with `Tools/compare.py` and `Tools/measure_hub.py`, or live in the token panel (menu bar › Debug › Token panel…, Flow Bar tokens only).
2. Put the final number in the token file and change its tag to `// source: board`, or `// source: measured`, with the method.
3. Delete its row here.

## Placeholders

Every placeholder is resolved at runtime; none ships as literal text.

| Placeholder | Becomes | Where it's resolved |
| --- | --- | --- |
| `[HOTKEY]` | The configured push-to-talk key, symbol plus name ("fn", "⌃ Ctrl") | `HubModel.hotkeyLabel`. Used by the status card, the menu header, the onboarding copy and the Flow Bar hover tooltip. |
| `[VERSION]` | `CFBundleShortVersionString` ("dev" outside the app bundle) | `AppInfo.version`. Used by the onboarding welcome, the Help & setup sheet and the menu footer. |
| `[MIN_MACOS]` | The bundle's `LSMinimumSystemVersion` ("macOS 14 or later") | `AppInfo.requirement` |
| `[ENGINE]` | The active engine's display name | The Settings › General select (`ModelNames.engines`). The status card tag and the menu footer say "on-device", "cloud", or which part is cloud (`AppInfo.cloud`). |
| `[YOUR LINK]`, `[GITHUB_URL]`, `[YOUR ADDRESS]` | Snippet fixture text | `DemoData` only. It seeds in-memory stores for `murmur-snap` and the Debug snapshot sweep, never the user's database. |
| "Swarit", "Priya", the stats, History and Dictionary rows | Fixture data | `DemoData`, as above. The real Home greets `NSFullUserName()`'s first name, and its stats come from History. |

## Open items (defaults in place until the owner decides)

| Item | What ships now | Owner decision |
| --- | --- | --- |
| Hands-free trigger | The real binding everywhere: ⌥ Space, fn Space or a custom shortcut, plus double-tap of push-to-talk (both work in SPEC). | Confirm |
| Crash reports card (onboarding data step) | Dropped. Murmur has no crash reporting, and the copy must be true. | Keep or drop |
| Five-minute nudge | One 4% scale pulse at 5:00 of hands-free (`MotionTokens.barNudge*`) | Confirm |
| Toast morph from the pill | Width morph, bottom-anchored (one morphing surface) | Confirm |
| Onboarding window size | 400 × 560 content, fixed. Long copy shrinks the illustration well (200 → at least 160) rather than the footer. | Confirm |
| Hub dark theme | Derived from the Components board's dark tokens (the `dark.*` rows below). Review `Artifacts/ui/after/dark/`. | Review the dark snapshots |
| Display serif | Newsreader: opsz 16 cut for text, opsz 36 "Display" cut for 26 pt and up | Confirm |
| "We couldn't hear you" card | Wired: shows after a recording of 1 s or more with no speech | **Decided 2026-10-05: wire it** |
| v2 timings vs SPEC §6's table | The v2 motion tokens | **Decided 2026-10-05: keep v2** |
| Menu "Shortcuts" | A submenu, not the board's "Shortcuts…" item. It holds the keyboard preset (fn vs ⌃⌥). | **Decided 2026-10-05: keep the submenu** |
| Paste and Copy last shortcuts | ⌃⌘V and ⌃⌘C (SPEC I7), not the board's ⌃⌥V and ⌃⌥C | **Decided 2026-10-05: keep ⌃⌘** |

## Tokens marked `// MEASURE`

"derived" means the value was computed from a board value: a contrast target, halfway to pressed, or the light strength applied on dark. "assumed" means no board shows it.

### Color (25)

| Token | Current value | Why it's not final | Where |
| --- | --- | --- | --- |
| `light.textTertiary` | `ColorToken("#6F6A62")` | derived (AA replacement for the boards' stone captions) | [Tokens+Color.swift:97](../Sources/UI/Tokens+Color.swift#L97) |
| `light.borderControl` | `ColorToken("#8A857C")` | derived (3:1 control edge) | [Tokens+Color.swift:101](../Sources/UI/Tokens+Color.swift#L101) |
| `light.accentClayHover` | `ColorToken("#A94737")` | derived (halfway to pressed) | [Tokens+Color.swift:103](../Sources/UI/Tokens+Color.swift#L103) |
| `light.accentClayPressed` | `ColorToken("#9E4234")` | derived | [Tokens+Color.swift:104](../Sources/UI/Tokens+Color.swift#L104) |
| `light.inkFillHover` | `ColorToken("#272625")` | derived (halfway to pressed) | [Tokens+Color.swift:107](../Sources/UI/Tokens+Color.swift#L107) |
| `light.inkFillPressed` | `ColorToken("#2F2D2C")` | derived | [Tokens+Color.swift:108](../Sources/UI/Tokens+Color.swift#L108) |
| `light.scrim` | `.ink(0.40)` | assumed (sheets) | [Tokens+Color.swift:119](../Sources/UI/Tokens+Color.swift#L119) |
| `dark.bgSunken` | `ColorToken("#191817")` | derived | [Tokens+Color.swift:125](../Sources/UI/Tokens+Color.swift#L125) |
| `dark.fillHover` | `.ivory(0.05)` | derived | [Tokens+Color.swift:126](../Sources/UI/Tokens+Color.swift#L126) |
| `dark.textTertiary` | `ColorToken("#9A958C")` | derived | [Tokens+Color.swift:131](../Sources/UI/Tokens+Color.swift#L131) |
| `dark.borderControl` | `ColorToken("#8F8A81")` | derived | [Tokens+Color.swift:135](../Sources/UI/Tokens+Color.swift#L135) |
| `dark.accentClayHover` | `ColorToken("#DC7B6B")` | derived (halfway to pressed) | [Tokens+Color.swift:137](../Sources/UI/Tokens+Color.swift#L137) |
| `dark.accentClayPressed` | `ColorToken("#DF8678")` | derived | [Tokens+Color.swift:138](../Sources/UI/Tokens+Color.swift#L138) |
| `dark.inkFillHover` | `ColorToken("#EEE6DA")` | derived (halfway to pressed) | [Tokens+Color.swift:141](../Sources/UI/Tokens+Color.swift#L141) |
| `dark.inkFillPressed` | `ColorToken("#E6DDD1")` | derived | [Tokens+Color.swift:142](../Sources/UI/Tokens+Color.swift#L142) |
| `dark.edgePanel` | `.ivory(0.12)` | derived (light strengths on ivory) | [Tokens+Color.swift:145](../Sources/UI/Tokens+Color.swift#L145) |
| `dark.edgeList` | `.ivory(0.14)` | derived | [Tokens+Color.swift:146](../Sources/UI/Tokens+Color.swift#L146) |
| `dark.edgeStrong` | `.ivory(0.20)` | derived | [Tokens+Color.swift:147](../Sources/UI/Tokens+Color.swift#L147) |
| `dark.edgeKey` | `.ivory(0.25)` | derived | [Tokens+Color.swift:148](../Sources/UI/Tokens+Color.swift#L148) |
| `dark.edgeToast` | `.ivory(0.18)` | derived | [Tokens+Color.swift:149](../Sources/UI/Tokens+Color.swift#L149) |
| `dark.underline` | `.ivory(0.30)` | derived | [Tokens+Color.swift:150](../Sources/UI/Tokens+Color.swift#L150) |
| `dark.fieldHalo` | `.ivory(0.10)` | derived | [Tokens+Color.swift:151](../Sources/UI/Tokens+Color.swift#L151) |
| `dark.shadowFloat` | `ColorToken("#000000").opacity(0.50)` | derived | [Tokens+Color.swift:152](../Sources/UI/Tokens+Color.swift#L152) |
| `dark.scrim` | `ColorToken("#000000").opacity(0.55)` | assumed | [Tokens+Color.swift:153](../Sources/UI/Tokens+Color.swift#L153) |
| `OpacityTokens.disabledGroup` | `0.5` | assumed | [Tokens+Color.swift:222](../Sources/UI/Tokens+Color.swift#L222) |

### Geometry (28)

| Token | Current value | Why it's not final | Where |
| --- | --- | --- | --- |
| `Stroke.dash` | `4` | assumed (dashed snippet box) | [Tokens+Geometry.swift:47](../Sources/UI/Tokens+Geometry.swift#L47) |
| `ShadowTokens.floatRadius` | `(floatBlur + floatSpread) / 2` | derived | [Tokens+Geometry.swift:57](../Sources/UI/Tokens+Geometry.swift#L57) |
| `HubGeometry.defaultWindow` | `CGSize(width: 1180, height: 740)` | assumed | [Tokens+Geometry.swift:62](../Sources/UI/Tokens+Geometry.swift#L62) |
| `HubGeometry.minimumWindow` | `CGSize(width: 880, height: 560)` | assumed | [Tokens+Geometry.swift:63](../Sources/UI/Tokens+Geometry.swift#L63) |
| `HubGeometry.contentMaxWidth` | `1000` | assumed (wide windows) | [Tokens+Geometry.swift:97](../Sources/UI/Tokens+Geometry.swift#L97) |
| `HubGeometry.fieldPaddingH` | `12` | assumed | [Tokens+Geometry.swift:120](../Sources/UI/Tokens+Geometry.swift#L120) |
| `HubGeometry.keycapPaddingHInline` | `6` | assumed | [Tokens+Geometry.swift:127](../Sources/UI/Tokens+Geometry.swift#L127) |
| `HubGeometry.chipPaddingH` | `12` | assumed | [Tokens+Geometry.swift:138](../Sources/UI/Tokens+Geometry.swift#L138) |
| `HubGeometry.chipCheck` | `12` | assumed | [Tokens+Geometry.swift:139](../Sources/UI/Tokens+Geometry.swift#L139) |
| `HubGeometry.emptyStateMaxWidth` | `380` | assumed | [Tokens+Geometry.swift:152](../Sources/UI/Tokens+Geometry.swift#L152) |
| `HubGeometry.dialogWidth` | `440` | assumed (Help & setup sheet) | [Tokens+Geometry.swift:153](../Sources/UI/Tokens+Geometry.swift#L153) |
| `HubGeometry.popoverWidth` | `300` | assumed (bell popover) | [Tokens+Geometry.swift:154](../Sources/UI/Tokens+Geometry.swift#L154) |
| `HubGeometry.meterCompact` | `CGSize(width: 3, height: 16)` | assumed | [Tokens+Geometry.swift:188](../Sources/UI/Tokens+Geometry.swift#L188) |
| `HubGeometry.meterCompactGap` | `2` | assumed | [Tokens+Geometry.swift:189](../Sources/UI/Tokens+Geometry.swift#L189) |
| `OnboardingGeometry.step` | `CGSize(width: 400, height: 560)` | assumed | [Tokens+Geometry.swift:197](../Sources/UI/Tokens+Geometry.swift#L197) |
| `OnboardingGeometry.rippleDot` | `3` | assumed (inline waiting dots) | [Tokens+Geometry.swift:216](../Sources/UI/Tokens+Geometry.swift#L216) |
| `FlowGeometry.timerWidth` | `30` | assumed (room for "0:07" in mono 11) | [Tokens+Geometry.swift:296](../Sources/UI/Tokens+Geometry.swift#L296) |
| `FlowGeometry.cardTextMaxWidth` | `260` | assumed | [Tokens+Geometry.swift:298](../Sources/UI/Tokens+Geometry.swift#L298) |
| `FlowGeometry.canvasMargin` | `16` | assumed | [Tokens+Geometry.swift:303](../Sources/UI/Tokens+Geometry.swift#L303) |
| `FlowGeometry.canvasCardWidth` | `420` | assumed | [Tokens+Geometry.swift:305](../Sources/UI/Tokens+Geometry.swift#L305) |
| `FlowGeometry.canvasCardHeight` | `96` | assumed | [Tokens+Geometry.swift:306](../Sources/UI/Tokens+Geometry.swift#L306) |
| `FlowGeometry.hoverTargetSlop` | `2` | assumed | [Tokens+Geometry.swift:308](../Sources/UI/Tokens+Geometry.swift#L308) |
| `MenuBarGeometry.processingGap` | `3` | assumed (glyph to first dot) | [Tokens+Geometry.swift:318](../Sources/UI/Tokens+Geometry.swift#L318) |
| `MenuBarGeometry.processingDotGap` | `1.5` | assumed | [Tokens+Geometry.swift:319](../Sources/UI/Tokens+Geometry.swift#L319) |
| `MenuBarGeometry.menuInsetH` | `16` | measured (native item titles start 16 pt in on macOS 27; check on 14) | [Tokens+Geometry.swift:325](../Sources/UI/Tokens+Geometry.swift#L325) |
| `MenuBarGeometry.menuHeaderPaddingV` | `6` | assumed | [Tokens+Geometry.swift:326](../Sources/UI/Tokens+Geometry.swift#L326) |
| `MenuBarGeometry.menuFooterPaddingV` | `2` | assumed | [Tokens+Geometry.swift:327](../Sources/UI/Tokens+Geometry.swift#L327) |
| `MenuBarGeometry.menuLiveDotGap` | `8` | assumed | [Tokens+Geometry.swift:329](../Sources/UI/Tokens+Geometry.swift#L329) |

### Motion (14)

| Token | Current value | Why it's not final | Where |
| --- | --- | --- | --- |
| `MotionTokens.barNudgeAt` | `300` | assumed | [Tokens+Motion.swift:23](../Sources/UI/Tokens+Motion.swift#L23) |
| `MotionTokens.barNudgeScale` | `1.04` | assumed | [Tokens+Motion.swift:24](../Sources/UI/Tokens+Motion.swift#L24) |
| `MotionTokens.barNudge` | `0.300` | assumed | [Tokens+Motion.swift:25](../Sources/UI/Tokens+Motion.swift#L25) |
| `MotionTokens.toastIn` | `0.200` | assumed | [Tokens+Motion.swift:43](../Sources/UI/Tokens+Motion.swift#L43) |
| `MotionTokens.toastOut` | `0.140` | assumed | [Tokens+Motion.swift:44](../Sources/UI/Tokens+Motion.swift#L44) |
| `MotionTokens.paperToast` | `4` | assumed | [Tokens+Motion.swift:47](../Sources/UI/Tokens+Motion.swift#L47) |
| `MotionTokens.alertShakeDuration` | `0.240` | assumed | [Tokens+Motion.swift:51](../Sources/UI/Tokens+Motion.swift#L51) |
| `MotionTokens.onboardingStep` | `0.220` | assumed | [Tokens+Motion.swift:52](../Sources/UI/Tokens+Motion.swift#L52) |
| `MotionTokens.pageSwitch` | `0.160` | assumed | [Tokens+Motion.swift:54](../Sources/UI/Tokens+Motion.swift#L54) |
| `MotionTokens.pageRise` | `6` | assumed | [Tokens+Motion.swift:55](../Sources/UI/Tokens+Motion.swift#L55) |
| `MotionTokens.hover` | `0.100` | assumed | [Tokens+Motion.swift:56](../Sources/UI/Tokens+Motion.swift#L56) |
| `MotionTokens.toggleKnob` | `SpringToken(response: 0.22, damping: 0.80)` | assumed | [Tokens+Motion.swift:59](../Sources/UI/Tokens+Motion.swift#L59) |
| `MotionTokens.segmentedSelect` | `SpringToken(response: 0.28, damping: 0.85)` | assumed | [Tokens+Motion.swift:60](../Sources/UI/Tokens+Motion.swift#L60) |
| `MotionTokens.contentDelayShare` | `1.0 / 3` | assumed | [Tokens+Motion.swift:63](../Sources/UI/Tokens+Motion.swift#L63) |

### Sound (5)

| Token | Current value | Why it's not final | Where |
| --- | --- | --- | --- |
| `SoundTokens.fade` | `0.005` | assumed | [Tokens+Sound.swift:25](../Sources/UI/Tokens+Sound.swift#L25) |
| `SoundTokens.start` | `ToneToken(wave: .sine, notes: [784, 1175], noteLength: 0.055, gap: 0, attack: 0.006, decay: 0.040, peakDb: -18)` | assumed | [Tokens+Sound.swift:28](../Sources/UI/Tokens+Sound.swift#L28) |
| `SoundTokens.stop` | `ToneToken(wave: .sine, notes: [1175, 784], noteLength: 0.055, gap: 0, attack: 0.006, decay: 0.040, peakDb: -18)` | assumed | [Tokens+Sound.swift:30](../Sources/UI/Tokens+Sound.swift#L30) |
| `SoundTokens.error` | `ToneToken(wave: .triangle, notes: [330, 330], noteLength: 0.070, gap: 0.050, attack: 0.006, decay: 0.050, peakDb: -16)` | assumed | [Tokens+Sound.swift:32](../Sources/UI/Tokens+Sound.swift#L32) |
| `SoundTokens.done` | `ToneToken(wave: .sine, notes: [1568, 2349], noteLength: 0.070, gap: 0, attack: 0.006, decay: 0.090, peakDb: -20)` | assumed | [Tokens+Sound.swift:35](../Sources/UI/Tokens+Sound.swift#L35) |

### Flow Bar (live tokens) (4)

| Token | Current value | Why it's not final | Where |
| --- | --- | --- | --- |
| `Tokens.fullScreenLift` | `6` | assumed | [Tokens.swift:47](../Sources/UI/Tokens.swift#L47) |
| `Tokens.dockSideOffset` | `0` | assumed | [Tokens.swift:49](../Sources/UI/Tokens.swift#L49) |
| `Tokens.waveformFloorDb` | `-55` | assumed | [Tokens.swift:54](../Sources/UI/Tokens.swift#L54) |
| `Tokens.waveformCeilingDb` | `-12` | assumed | [Tokens.swift:55](../Sources/UI/Tokens.swift#L55) |
