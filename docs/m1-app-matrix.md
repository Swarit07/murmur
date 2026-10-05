# Milestone 1 gate: a day of real use

**Gate:** a full day of real use across at least 10 apps with zero lost dictations. A dictation is lost if you spoke and the words are nowhere: not in the field, not on the clipboard, and not in History.

At the end of the day run `Scripts/m1-day-report.sh`. It counts dictations per app and per outcome and lists every one that did not paste.

## Five checks per app

Do these once in each app you use:

1. **Lands complete:** dictate a sentence or two; all of it appears, with a space before it if you dictated right after a word.
2. **One Cmd+Z removes it:** press Cmd+Z once and the whole dictation disappears (C9).
3. **Clipboard restored:** copy something first, dictate, then paste with Cmd+V; you get what you copied, not the dictation.
4. **Focus unchanged:** the cursor is still in the same field after the dictation.
5. **Paste last works:** press Ctrl+Cmd+V; the last dictation is pasted again.

## Apps

Tick what you tried. Write anything odd in the notes column.

| App | Lands | Cmd+Z | Clipboard | Focus | ⌃⌘V | Notes |
|---|---|---|---|---|---|---|
| Notes | | | | | | |
| TextEdit | | | | | | |
| Safari or Chrome: a plain text box | | | | | | |
| Gmail compose | | | | | | |
| Google Docs | | | | | | |
| Slack or Discord | | | | | | |
| Messages | | | | | | |
| VS Code or Cursor | | | | | | |
| Terminal or iTerm2 | | | | | | |
| Claude app or ChatGPT in the browser | | | | | | |
| Notion or Obsidian | | | | | | |
| Pages or Word | | | | | | |

## Hostile cases (it should refuse, not paste)

| Case | What should happen | Result |
|---|---|---|
| A password field (any login page) | Nothing pasted; the menu-bar icon shows a notice | |
| Click into another app while still talking | Nothing pasted into the new app; the text is on the clipboard and in History | |
| Press Esc while talking | Nothing pasted; the History entry says Cancelled | |
| Fn+arrow key, or Fn+F-key | No dictation starts | |
| A very quick Fn tap | Nothing happens | |
