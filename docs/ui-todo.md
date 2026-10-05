# UI to-do (redesign v2)

Things the redesign has not finished yet, kept current milestone by milestone.

## Icons

- **Murmur's own set** (`Sources/UI/Components/Icons.swift`): the boards' SVG paths on a 24 pt grid, stroke scaled with the icon (1.6 grid units at 18 pt and up, 1.7 at 15–17, 1.8 below).
  - Core 24: mic, wave, stop, cancel, check, retry, clipboard, alert, textfield, hotkey, hands-free, history, home, dictionary, snippet, style, settings, cleanup, local, shield, globe, branch, star, download.
  - From the Hub and Flow Bar boards: search, bell, copy, trash, edit, plus, chevrons (right, left, down, up/down), info, help, mail, chat, lines, code, note, mic-off, arrow-right.
- **SF Symbols still in use, until the screens that use them are rebuilt:**
  - Flow Bar (U3): none (v1 already used Murmur's icons).
  - Hub shell, Home, Dictionary, Snippets, Style, Settings (U4–U6): sidebar and page icons, row actions, permission status.
  - Onboarding (U7): step icons.
  - Menu bar status item (U8): it still uses SF Symbols until `MenuBarGlyph` is wired in.
