# UI to-do (redesign v2)

Things the redesign has not finished yet, kept current milestone by milestone.

## Icons

- **Murmur's own set** (`Sources/UI/Components/Icons.swift`): the boards' SVG paths on a 24 pt grid, stroke scaled with the icon (1.6 grid units at 18 pt and up, 1.7 at 15–17, 1.8 below).
  - Core 24: mic, wave, stop, cancel, check, retry, clipboard, alert, textfield, hotkey, hands-free, history, home, dictionary, snippet, style, settings, cleanup, local, shield, globe, branch, star, download.
  - From the Hub and Flow Bar boards: search, bell, copy, trash, edit, plus, chevrons (right, left, down, up/down), info, help, mail, chat, lines, code, note, mic-off, arrow-right.
- **SF Symbols:** none left in shipped UI (U8). The menu bar status item uses `MenuBarGlyph` in all four states, and every Hub, onboarding and Flow Bar icon comes from `Icons.swift`. The only SF Symbols left are in the debug tools (Token panel, Design Gallery).

## Owner decisions pending

- **No-audio card:** built and reachable from the debug menu and the gallery. The dictation controller has no silent-recording event; adding one changes dictation behavior.
- **Flow Bar timings follow v2 where SPEC §6's state table differs:**
  - paste error expires after 4 s (SPEC: until clicked);
  - no text box stays until dismissed (SPEC: a countdown);
  - cancelled lasts 5 s (SPEC: about 3 s);
  - transcription error is sticky for 8 s with Retry (SPEC: Retry or dismiss).
- **Menu bar dropdown, two departures from the board:**
  - "Shortcuts" stays a submenu, not "Shortcuts…", because it holds the keyboard preset (fn vs ⌃⌥), which exists nowhere else.
  - Paste and Copy last show the real ⌃⌘V and ⌃⌘C, not the board's ⌃⌥ (shortcuts were left as they are).
  - Both are listed in `docs/ui-calibration.md`.
