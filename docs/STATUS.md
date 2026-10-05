# Murmur status

Last updated 2026-10-05. This file tracks where every milestone and requirement in [SPEC.md](../SPEC.md) stands. It also lists what was skipped or deferred and why, the overnight work log, and what still needs the owner. Decisions and their measurements are in [decisions.md](decisions.md).

## Afternoon summary (2026-10-05): UI redesign v2

**Done:**
- **The UI redesign v2 ("Paper & Clay") is built on the local branch `ui-redesign`, U0 through U8**, one commit per milestone. Nothing was pushed or merged; the bundle's rules forbid that.
  - Reports: [ui-progress.md](ui-progress.md).
  - Values still to measure: [ui-calibration.md](ui-calibration.md).
  - Before, after and board side by side: `Artifacts/ui/sheets/contact-sheet.png`.
- **Fixed:** the Flow Bar could be drawn off screen when a saved drag offset pushed it past the screen edge. It now always stays on screen.
- **Owner decisions:**
  - The no-audio card is wired: a recording of 1 s or more with no speech shows "We couldn't hear you".
  - The v2 timings stay.
  - "Shortcuts" stays a submenu.
  - ⌃⌘V and ⌃⌘C stay.
- **Self-test:** it now confirms its TextEdit document has focus before every dictation, after a run while the owner was typing sent test text into the owner's focused app.
- **New debug test, the app matrix:** Debug › Run app matrix dictates into blank targets in TextEdit, Safari, Chrome, Firefox, Terminal and Ghostty. All six pass (Safari and Chrome on the second run). VS Code and Cursor stay manual because their editors hide text from Accessibility. In each it checks that the text is complete, one Undo removes it, the clipboard is restored and focus is unchanged.
- **Checks:** unit tests 170 pass, focus test 50/50, self-test 21/21 (before the new cases), latency p50 652 ms and p95 1,340 ms.

**In progress:**
- A separate session is fixing the MLX reload leak, so idle unload can default to on. Its report will be in `docs/mlx-unload-leak.md`.

**Needs the owner:**
1. Five minutes off the keyboard and mouse, to run the self-test and the app matrix.
2. In the apps the app matrix can't cover, dictate one sentence each without sending, and check the four matrix items:
   - the logged-in apps: Slack, Discord, Messages, Notion, Gmail and Google Docs in Chrome, ChatGPT, Claude;
   - plus VS Code, Cursor and Word.
3. Flow Bar placement over full-screen, dark and light apps, with the Dock left, right and auto-hidden.
4. Last: onboarding in a fresh macOS account and the permission revocation test ([m4-gate.md](m4-gate.md)).

## Morning summary (2026-10-05)

**Done overnight:**
- **QA and redesign of every screen.** 13 issues fixed.
- **Milestone 5 (Context) built and gated:**
  - styles per app;
  - Command Mode, a spoken instruction that rewrites the selection or drafts text, with one-step Undo;
  - "press enter";
  - auto-stop at 20 minutes;
  - one insertion at a time, which fixed a clipboard race.
- **Most of Milestone 6 (Polish):**
  - suggestions to add a word you corrected to the dictionary;
  - typing instead of pasting;
  - hide with Undo;
  - performance pass: p50 0.62 s, p95 1.1 s on your real dictations.
- **A dictionary bug the self-test caught**, where one dictionary word overwrote ordinary speech, is fixed. It was measured on all your recordings and now inserts nothing wrong.
- **Private GitHub repo** with `main`, milestone branches and gate tags.
- **Checks:**
  - unit tests: 144 pass;
  - self-test: 21/21 in TextEdit;
  - soak: 210/210 over 10 runs, no crash.

**Decided for you (details in [decisions.md](decisions.md)):**
- Engine dictionary boosting is off; a safer matcher replaces it.
- The cleanup time limit grows a little for long dictations.
- Style names follow the spec ("Formal.", "very casual").
- Idle model unloading is built but off by default: each reload leaks ~400 MB inside the MLX library. A follow-up task is flagged.

**Needs you:**
1. The M4 gate: a fresh-account onboarding and the permission revocation test ([m4-gate.md](m4-gate.md), ~15 min). The latest build is in /Applications.
2. Screen recordings of the reference app, to measure the Flow Bar tokens (M6 gate).
3. To try Command Mode: Settings › Experimental › Command Mode, select some text, hold Fn+Control, and say "make this friendlier".

## Milestones

| # | Milestone | Work | Gate | Notes |
|---|---|---|---|---|
| 0 | Spike and bake-off | Done | **Passed** (owner approved) | Parakeet ultra 8.0% WER, 42 ms; Qwen3.5 4B 27/30 corrections, ~285 ms p50; CLI end-to-end p50 446 ms. [m0-results](m0-results.md) |
| 1 | Core loop | Done | **Skipped by owner** | Owner chose to skip the "full day in 10 apps" report. Insertion checks are covered by the self-test instead. [m1-report](m1-report.md) |
| 2 | Flow Bar | Done | **Passed** | 50/50 kept focus, 50/50 clicks reached the bar, all 10 states reachable. [m2-report](m2-report.md) |
| 3 | Cleanup | Done | **Passed** | 27/30 corrections (28/30 re-run with Smart Formatting), guard 291/291, stall 855 ms. T4 re-measured, see below. [m3-report](m3-report.md) |
| 4 | App windows | Done, plus QA and redesign pass | **Deferred to the end by owner** | Fresh-account onboarding and permission revocation need the owner's hands; steps in [m4-gate](m4-gate.md). QA pass: [m4-qa](m4-qa.md) |
| 5 | Context | Done | **Passed** (automated) | Style test 64/64; Command Mode round trip with one-step Undo; self-test 19/19. [m5-report](m5-report.md) |
| 6 | Polish | **In progress** | Needs the owner | S2, I9, A6, idle unload and the performance pass done; measured tokens and the app matrix need the owner. [m6-report](m6-report.md) |
| 7 | Windows (optional) | **Dropped by owner** (2026-10-05) | — | Not building a Windows version |

## Requirements

✅ done and verified · 🟡 partial or verified only in part · ⬜ not started · ➖ deferred (see below)

### Capture
| ID | Pri | Status | Evidence / notes |
|---|---|---|---|
| D1 Push-to-talk | P0 | ✅ | M1; Fn chords and taps under 300 ms are discarded |
| D2 Hands-free | P0 | ✅ | Double-tap, Fn+Space, Flow Bar click (M2 focus test 50/50) |
| D3 Cancel | P0 | ✅ | Esc or X; the History row is kept; Undo on the notice. The self-test checks cancel during processing, then Undo |
| D4 Rapid-tap guard | P1 | ✅ | Built in M1 (spec places it in M5); unit tests in HotkeyTests |
| D5 Ignore input while busy | P1 | ✅ | State-machine tests; self-test: a second start during processing is ignored |
| D6 Silence and short clips | P0 | ✅ | Energy gate plus Silero VAD; silence set inserts nothing |
| D7 Auto-stop at 20 min | P1 | ✅ | Warn at 19, stop at 20, stop on 3 s without audio; self-test with a 6 s limit |
| D8 Custom shortcuts | P1 | ✅ | M4; the menu's presets reset custom shortcuts |
| D9 Microphone choice | P1 | ✅ | M4; device changes rebuild the engine, retry notice |

### Transcription
| ID | Pri | Status | Evidence / notes |
|---|---|---|---|
| T1 Engine protocol | P0 | ✅ | Parakeet (3 versions), Whisper, Apple Speech, Groq Whisper; switch without restart |
| T2 Raw text first | P0 | ✅ | History row before transcription, raw text before cleanup |
| T3 Languages | P1 | ✅ | Automatic or chosen list |
| T4 Dictionary bias | P1 | 🟡 | **7/10** missed names recognized from the dictionary alone, **8/10** with a "Heard as" entry, 0 broken, **0 false insertions** in 98 clips. Engine CTC boosting turned off: it wrote dictionary words over normal speech (decisions.md, 2026-10-05) |

### Cleanup
| ID | Pri | Status | Evidence / notes |
|---|---|---|---|
| C1 Levels + Transforms | P0 | ✅ | Style › Auto Cleanup; the AI edits switch is in the Hub |
| C2 Backtracking | P0 | ✅ | 27–28/30 |
| C3 Smart Formatting | P1 | ✅ | Lists of 3+ keep their lead-in; lists of 1–2 items are a guard flag |
| C4 Spoken punctuation | P0 | 🟡 | Synthetic voices (latest run): ? 10/10, new paragraph 10/10, new line 9/10, comma 8/10 (earlier 6/10). Real-voice clips optional (owner) |
| C5 Guardrails | P0 | ✅ | guard-test 291/291 |
| C6 Time limit | P0 | ✅ | Amended: 800 ms + 10 ms per word over 30, cap 1,250 ms; stall test max 1.34 s |
| C7 Transcript is data | P0 | ✅ | 4/4 |
| C8 No translation | P2 | ✅ | Prompt rule |
| C9 Native undo | P0 | 🟡 | One paste per dictation by design; one Undo restores a Command Mode rewrite in TextEdit (self-test). Other apps were part of the skipped M1 report |
| C10 Undo AI edit | P1 | ✅ | History context menu |
| C11 "Press enter" | P2 | ✅ | Experimental, confirmed once; self-test |

### Insertion
| ID | Pri | Status | Evidence / notes |
|---|---|---|---|
| I1 Clipboard transaction | P0 | ✅ | Every item and type restored; the self-test checks the clipboard |
| I2 Restore only if untouched | P0 | ✅ | changeCount check |
| I3 Focus guard | P0 | ✅ | |
| I4 No text box | P1 | ✅ | Notice with ⌃⌘V hint (built early) |
| I5 Failed paste | P0 | ✅ | |
| I6 Secure fields | P0 | ✅ | |
| I7 Paste and copy last | P0 | ✅ | ⌃⌘V / ⌃⌘C; the self-test checks Paste last |
| I8 Layout-independent paste | P1 | ✅ | Key code looked up per paste for the current layout |
| I9 Fallback typing | P2 | ✅ | Per-app list in System; clipboard untouched; self-test |
| I10 One insertion at a time | P1 | ✅ | Insertion gate; regression test fails without it |
| I11 Remote desktop delay | P2 | ✅ | 5 s restore delay for remote desktop apps (built in M1) |

### Personalization, Command Mode, App shell
| ID | Pri | Status | Evidence / notes |
|---|---|---|---|
| S1 Dictionary | P1 | ✅ | Add, edit, delete; "Heard as"; spelling matcher |
| S2 Suggestions | P2 | ✅ | Corrected word → "Add to dictionary?" on the Flow Bar; self-test |
| S3 Snippets | P1 | ✅ | Multi-line expansions; protected from cleanup |
| S4 Styles | P1 | ✅ | Category from app or web address; deterministic styles; style-test 64/64 |
| M1–M3 Command Mode | P1/P2 | ✅ | Rewrite selection or draft; one Undo; badge in History; self-test |
| A1 Menu-bar app | P0 | ✅ | |
| A2 Flow Bar never takes focus | P0 | ✅ | 50/50 |
| A3 Onboarding + permissions | P1 | ✅ | Revocation test deferred with the M4 gate |
| A4 History | P1 | ✅ | Search, j/k, Return copies, Play, Retry/Recover, day groups |
| A5 Settings pages | P1 | ✅ | General, System (Flow Bar, Smart Formatting), Style, Experimental, Data and Privacy |
| A6 Hide Flow Bar 1 h | P2 | ✅ | Hide shows a card with Undo |
| A7 Launch at login | P1 | ✅ | SMAppService |
| A8 Reduce Motion | P1 | ✅ | Flow Bar and Hub |
| A9 Never store | P2 | ✅ | |

## Skipped or deferred, and why

| Item | Decision | By | Why |
|---|---|---|---|
| M1 gate: a day across 10 apps | Skipped | Owner | Owner preferred to keep building; the TextEdit self-test covers the core insertion checks |
| M4 gate: fresh-account onboarding, permission revocation | Deferred to the very end | Owner | Needs a second macOS account and the owner at the Mac |
| Engine dictionary boosting (FluidAudio CTC) | Off by default | Claude, overnight | 13–76 false insertions; the rules-stage matcher gets the same fixes with 0 |
| C6 fixed 800 ms limit | Amended | Claude, overnight (owner delegated) | Long dictations lost their cleanup; the 1.5 s gate still holds |
| C4 real-voice clips | Optional | Owner | Synthetic-voice results recorded; comma is the weak spot |
| Gemma 3 1B | Excluded | Claude | Never stops generating |
| Speculative decoding | Not default | Claude | Only ~12% faster on long inputs |
| Idle unload by default (section 7) | Off by default | Claude, overnight | Each model reload leaks ~400 MB in mlx-swift-lm; on by default would grow memory all day. Switch kept in System › Advanced |

## Performance (section 7)

Release to text p50 **623 ms**, p95 **1,111 ms** (targets 800 ms and 1.5 s), from 38 real dictations. Idle CPU 0%. Idle unload is built and works (2.6 GB → ~0.25 GB), but it is **off by default**: each reload leaks ~400 MB inside mlx-swift-lm. The 120 MB shell target is not met; see [m6-report](m6-report.md).

## Needs the owner

1. **M4 gate**, at the end: [m4-gate.md](m4-gate.md) (about 15 minutes).
2. **M6 tokens**: screen recordings of the reference app, to measure the Flow Bar's sizes and timings.
3. Optional: record the C4 punctuation clips in your own voice.

## Overnight log, 2026-10-05

- **QA pass and redesign of the Hub and onboarding.** 13 issues fixed, including headers hidden on the settings pages, a clipped caption, a missing AI edits switch, and Esc losing Undo ([m4-qa](m4-qa.md)).
- **New tools:** a snapshot sweep on demo data, in-process click and drag checks, and the in-app TextEdit self-test.
- **Self-test found a dictionary bug.** One dictionary word overwrote ordinary speech. It is fixed with `SpellingMatcher` and measured by the new `vocab-false-test`: 0 false insertions.
- **C6** amended for long dictations. **Smart Formatting** keeps list lead-ins. Cleanup logs its outcome (reason and timing only).
- **Repository:** private GitHub repo with `main` and the milestone branches; README; this status file.
- **Self-test:** 10/10. **Unit tests:** 106 pass.
- **Milestone 5, built and gated:**
  - S4 styles (style-test 64/64).
  - Command Mode: rewrite or draft, with one-step Undo verified.
  - C11 Press enter.
  - D7 auto-stop.
  - I10 insertion gate, which fixed a clipboard race.
  - D5 check.
  - Flow Bar Command accent.
  - Self-test 19/19, 129 unit tests.
- **Milestone 6, without the owner's recordings:**
  - S2 dictionary suggestions from corrections.
  - I9 typing fallback.
  - A6 hide with Undo.
  - Idle unload of both models, with MLX cache clearing.
  - Performance pass from real History timings.
  - Self-test 21/21, 136 unit tests.
  - Soak: 10 self-test runs back to back, 210/210 checks, no crash.
  - Command Mode no longer mistakes a code editor's whole-line copy for a selection.
- **Command Mode quality bench** (`murmur-bench command-test`, 16 instructions): Qwen3.5 4B **32/32**, p50 299 ms. It caught and fixed an injection that was partly obeyed.
- **End to end on your recordings:** 27/30 corrections, 0 fact changes, C7 4/4. No accuracy regression.
- **Idle unload:** built, then turned **off by default** after `reload-test` found ~400 MB leaked per model reload inside mlx-swift-lm. A follow-up task was flagged.
- **Flow Bar state tests** against the token values (spec section 8).
- **Milestone tags** pushed (`m0-passed` … `m5-passed`). The latest build is in /Applications for the fresh-account test.
