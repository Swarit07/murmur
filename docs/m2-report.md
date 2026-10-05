# Milestone 2 report: Flow Bar

2026-10-05 · branch `milestone-2`.

## Gate

| Gate item | Result |
|---|---|
| **Bar never takes focus in 50 trials** | **Pass.** `Scripts/focus-test.sh`: TextEdit's text area kept focus in 50/50 trials; 50/50 synthetic clicks reached the bar and 50/50 started a hands-free dictation; Murmur never became the active app |
| **Every state reachable from the debug menu** | **Pass.** Debug › Force Flow Bar state lists all ten states from the spec's table: Idle, Hidden, Listening (hold), Listening (hands-free), Processing, Inserted, Paste error, Transcription error, No text box, Cancelled |

Test output (`~/Library/Application Support/Murmur/focus-test-1791179020.txt`):

```
Focus test: 50/50 kept focus in TextEdit; 50/50 clicks reached the bar; 50/50 started hands-free.
target: TextEdit (com.apple.TextEdit) role=AXTextArea
```

Getting there took three runs, each finding a real problem:
1. 0/50 clicks started hands-free. Synthetic clicks carried no click count, so SwiftUI's tap never fired. Fixed in the test; the hosting view now also accepts the first mouse, so real clicks on the never-key panel always register.
2. 46/50. The test's own "starts in 2 seconds" message was still on the bar for the first four clicks, and a click on a notice card rightly starts nothing. Fixed in the test.
3. 50/50.

## Built

- **`Sources/UI/Tokens.swift`:** every size, color (light and dark), material, motion value, type setting and sound parameter as a named placeholder, editable live in Debug › Token panel ("Copy as Swift" exports the values).
- **Flow Bar states:**
  - an idle pill
  - listening with a waveform that follows the mic level
  - hands-free with ✕ and stop
  - a looping three-dot processing indicator
  - an inserted ✓
  - notice cards: paste error; transcription error with Retry; no text box; cancelled with Undo and Open History. Countdown rings pause on hover.
- **Panel:** non-activating, never key or main, one level above the Dock, on all Spaces including full-screen. It takes clicks only inside the bar, follows the screen of the focused window, can be dragged (offset saved, reset from the right-click menu), and can be hidden for an hour (A6).
- **Behaviour:** clicking the bar starts hands-free (D2); the right-click menu has paste last, copy last, hide for 1 hour, reset position, History and Settings; there is a "Show Flow Bar at all times" setting (A5, System).
- **Sounds:** four original sounds (start, stop, done chime, error), synthesized at runtime from the sound tokens; Debug › Play sounds.
- **Reduce Motion (A8):** springs become fades and the processing loop holds still.
- **Logging:** Logger `com.swaritsheel.Murmur` records timings and reasons only, never transcript text.

## Not yet done

- All visual and sound values are placeholders until the owner measures the reference app. The owner may record the reference sounds for pitch and length measurement; the sounds stay synthesized.
- The multi-display placement rule is unconfirmed (the spec says it will be confirmed from a recording). Today the bar uses the screen of the focused window.
- Snapshot tests of each state against token values (spec section 8) are not written yet. Forcing states from the Debug menu covers them by hand for now.
