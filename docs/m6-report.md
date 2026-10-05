# Milestone 6 report: Polish (in progress)

Branch `milestone-6`, 2026-10-05 (overnight). The gate itself needs the owner. Side-by-side recordings must match the reference app within 1 pt and one frame at 60 fps, and that requires the owner's screen recordings. Everything else in the milestone that can be built and measured without the owner is below.

## Done

| Item | What | Verified |
|---|---|---|
| S2 dictionary suggestions | After a paste, Murmur keeps the field's text and checks it again 15 s and 45 s later, and before the next paste. If a word Murmur wrote was replaced with a name or term, or the same letters spelled differently, the Flow Bar offers "Add “Siobhan” to your dictionary?". Add saves it as heard-as; Dismiss hides that pair for the session. Only the field Murmur pasted into is read. | Unit tests (`CorrectionDetector`); self-test: Chivan → Siobhan suggested, Add saves it |
| I9 typing instead of pasting | Settings › System lists apps that get the text typed as Unicode key events, with Return for line breaks. The clipboard is never touched. | Unit test; self-test in TextEdit with the clipboard's change count unchanged |
| A6 hide with Undo | Hiding the Flow Bar for an hour shows a card with Undo. | Snapshot of the card |
| I11 remote desktop | Clipboard restore waits 5 s in remote-desktop viewers (built in M1). | Unit test |
| Idle unload (section 7) | Both models unload after 10 minutes without dictation and reload as the next dictation starts. MLX's buffer cache is cleared so the memory is really returned. **Off by default for now**: each reload leaks about 400 MB inside mlx-swift-lm (see below). | Footprint 2.6 GB loaded, ~0.25 GB after the first unload; a self-test started unloaded passes 21/21 |
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
| App shell ≤ 120 MB | **Not met** | ~225–300 MB after the first unload, and each reload leaks ~400 MB, so idle unload is off by default; with models loaded the footprint is flat at ~2.4 GB |

## Soak test

The self-test ran 10 times back to back: about 250 dictations, Command Mode runs, auto-stops, suggestions and typing. **210/210 checks passed**, in one process with no crash. Resident memory went from 2,292 to 2,373 MB, about 0.3 MB per dictation of allocator growth. MLX's live arrays stay bounded: 2.26 GB of weights plus the prompt-prefix cache, which holds at most four prompts and is cleared when full. Its buffer cache stays at 40–76 MB.

## Still open

- **Gate:** side-by-side recordings within 1 pt and one frame. Needs the owner's recordings of the reference app to measure the tokens; `Tokens.swift` still holds placeholders, by design (spec rule 5).
- **App matrix** (spec section 8): manual, owner.
- **MLX memory retained across reloads.** Loading Qwen3.5 4B makes 2,257 MB of arrays active. Each unload leaves about 400 MB alive (the size of the quantized embedding table), and repeated reload cycles add up: 407 → 815 → 1,222 → 1,630 MB in the app. This is not timing and not Murmur's prompt cache. Dropping compiled traces before release helps only partly. Idle unload is therefore off by default until this is fixed upstream (`murmur-bench reload-test` reproduces it in about 30 s).
- **Second display:** untested; there is only one display here.
