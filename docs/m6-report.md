# Milestone 6 report: Polish (in progress)

Branch `milestone-6`, 2026-10-05 (overnight). The gate itself needs the owner. Side-by-side recordings must match the reference app within 1 pt and one frame at 60 fps, and that requires the owner's screen recordings. Everything else in the milestone that can be built and measured without the owner is below.

## Done

| Item | What | Verified |
|---|---|---|
| S2 dictionary suggestions | After a paste, Murmur keeps the field's text and checks it again 15 s and 45 s later, and before the next paste. If a word Murmur wrote was replaced with a name or term, or the same letters spelled differently, the Flow Bar offers "Add “Siobhan” to your dictionary?". Add saves it as heard-as; Dismiss hides that pair for the session. Only the field Murmur pasted into is read. | Unit tests (`CorrectionDetector`); self-test: Chivan → Siobhan suggested, Add saves it |
| I9 typing instead of pasting | Settings › System lists apps that get the text typed as Unicode key events, with Return for line breaks. The clipboard is never touched. | Unit test; self-test in TextEdit with the clipboard's change count unchanged |
| A6 hide with Undo | Hiding the Flow Bar for an hour shows a card with Undo. | Snapshot of the card |
| I11 remote desktop | Clipboard restore waits 5 s in remote-desktop viewers (built in M1). | Unit test |
| Idle unload (section 7) | Both models unload after 10 minutes without dictation and reload as the next dictation starts. MLX's buffer cache is cleared so the memory is really returned. | Footprint 2.6 GB loaded, ~0.25 GB unloaded; a self-test started unloaded passes 21/21; no growth over two runs |
| Spaces and full screen | The Flow Bar panel joins all Spaces, shows over full-screen apps and lifts when there is no Dock (built in M2). It follows the screen of the focused window. | M2 focus test; not tested on a second display |

## Performance (section 7)

| Target | Measured | Source |
|---|---|---|
| Release to text p50 ≤ 800 ms | **623 ms** | 38 real dictations in History (median 6 s of audio) |
| Release to text p95 ≤ 1.5 s | **1,111 ms** | same |
| Transcription | p50 101 ms, p95 162 ms | same |
| LLM cleanup | p50 381 ms, p95 847 ms | same |
| Insertion | p50 2 ms, p95 11 ms | same |
| Idle CPU < 1% | **0.0%** | `ps`, `top` |
| App shell ≤ 120 MB | **Not met: ~225–300 MB with models unloaded** | `footprint`. About 170 MB of it is MLX arrays that stay alive after the model is released. The amount is fixed, not growing (see below). |

## Still open

- **Gate:** side-by-side recordings within 1 pt and one frame. Needs the owner's recordings of the reference app to measure the tokens; `Tokens.swift` still holds placeholders, by design (spec rule 5).
- **App matrix** (spec section 8): manual, owner.
- **Residual MLX memory after unload** (~170–400 MB of live arrays, depending on what ran). It does not grow with use. Likely held inside mlx-swift-lm; worth a look before tuning the 120 MB target further.
- **Second display:** untested; there is only one display here.
