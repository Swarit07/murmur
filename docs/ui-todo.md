# UI to-do (redesign v2)

Things the redesign has not finished yet, kept current milestone by milestone.

## Icons

- **Murmur's own set** (`Sources/UI/Components/Icons.swift`): the boards' SVG paths on a 24 pt grid, stroke scaled with the icon (1.6 grid units at 18 pt and up, 1.7 at 15–17, 1.8 below).
  - Core 24: mic, wave, stop, cancel, check, retry, clipboard, alert, textfield, hotkey, hands-free, history, home, dictionary, snippet, style, settings, cleanup, local, shield, globe, branch, star, download.
  - From the Hub and Flow Bar boards: search, bell, copy, trash, edit, plus, chevrons (right, left, down, up/down), info, help, mail, chat, lines, code, note, mic-off, arrow-right.
- **SF Symbols:** none left in shipped UI (U8). The menu bar status item uses `MenuBarGlyph` in all four states, and every Hub, onboarding and Flow Bar icon comes from `Icons.swift`. The only SF Symbols left are in the debug tools (Token panel, Design Gallery).

## Owner decisions (2026-10-05)

- **No-audio card: wired.** A recording of 1 s or longer with no speech shows "We couldn't hear you · No speech from *mic*" with Switch microphone and Test mic. That covers both the speech gate finding nothing and a transcription that comes back empty. Shorter taps stay quiet, and nothing is inserted either way.
- **Flow Bar timings: the board's v2 values stay.** A paste error fades after 4 s, "No text box" stays until dismissed, Cancelled lasts 5 s, and a transcription error stays 8 s with Retry. SPEC §6's table is superseded for these four.
- **Menu "Shortcuts": stays a submenu.** It holds the fn vs ⌃⌥ keyboard choice.
- **Paste and Copy last: stay ⌃⌘V and ⌃⌘C.**
