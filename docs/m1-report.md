# Milestone 1 report: core loop

2026-10-05 · branch `milestone-1` · Murmur.app in `~/Applications`, signed with the owner's Apple Development certificate.

## Gate

The spec's gate is "a full day of real use across 10 apps with zero lost dictations." **The owner chose to skip the dedicated day test** and keep using Murmur day to day instead (see [decisions.md](decisions.md)). Usage up to this report:

| Measure | Result |
|---|---|
| Dictations | 11 (10 inserted, 1 interrupted by a crash, now fixed) |
| **Lost** (spoke, and the words are nowhere) | **0**: the interrupted one kept its raw and cleaned text in History |
| Apps | 3 (Claude, ChatGPT, Firefox) of the 10 the gate asks for |
| Release to paste, all dictations | p50 855 ms, p95 1113 ms (median clip 14 s, longest 27 s) |
| Release to paste, clips up to 15 s (the spec's scope) | 500–865 ms |

The checklist for the remaining app matrix is [m1-app-matrix.md](m1-app-matrix.md), and `Scripts/m1-day-report.sh` summarizes History at any time.

## Built

| Item | What it does |
|---|---|
| A1 | Menu-bar app, no Dock icon unless Show in Dock is on; menu in the spec's order; icon for loading, idle, listening, hands-free, processing, error |
| D1 | Hold Fn (or Ctrl+Option) to talk. Recording starts at key down. Fn with another key or extra modifier within 250 ms, or a tap under 300 ms, is discarded with no trace |
| D2 | Hands-free by double-tap or Fn+Space (Ctrl+Option+Space), stopped by the shortcut; start sound. The Flow Bar click came in M2 |
| D3 | Esc cancels while recording or processing, inserts nothing, keeps a Cancelled History row |
| D4 | Rapid-tap guards, ahead of schedule (spec says M5) |
| D6 | Clips under 300 ms or without speech are dropped silently (energy gate) |
| T1 | Engine and cleanup model switch in Settings without a restart |
| T2 | History row and audio are saved before transcription; raw text before cleanup |
| I1–I3, I5, I6 | Clipboard transaction (every item and type restored only if untouched), focus guard, failed paste leaves the text on the clipboard, secure fields refused |
| I7 | ⌃⌘V pastes and ⌃⌘C copies the last transcript (Carbon hot keys, consumed) |
| Carried over from M0 | Smart leading space between dictations; mic choice per app; engine rebuild on route changes |

## Tests

84 unit tests pass (`Scripts/test.sh`): state machine, hotkey recognizer (13 recorded sequences), History store (including raw text surviving a reopen), clipboard transaction (including running on the main thread), smart spacing, rules, guard, cleanup runner.

## Found in real use and fixed

1. **Crash on the first Fn press:** the audio engine was rebuilt and prepared with no input node, and AVAudioEngine raised an Objective-C exception. Fixed by never preparing an empty engine; every AVAudioEngine call now goes through an exception catcher, so a device problem becomes an error notice instead of a crash.
2. **Crash on paste:** macOS 26+ requires the keyboard-layout lookup to run on the main thread, and the paste ran on the cooperative pool. Fixed by running the whole insertion transaction on the main actor, with a regression test.

## Known issues

- **Long dictations (≥ ~20 s) hit the 800 ms cleanup limit** and fall back to rule-cleaned text. Carried into Milestone 3.
- First audio is ~170–180 ms after key down on both the built-in mic and AirPods (target 150 ms).
- C9 (one Cmd+Z removes a dictation) is verified only where it has been used so far; it is part of the app matrix.
