# Milestone 0: where things stand

**Status (2026-10-04, evening): Milestone 0 is complete and waiting for the owner's approval.** Results and the recommendation are in [m0-results.md](m0-results.md): Parakeet ultra + Qwen3.5-4B, with a measured release-to-paste time of 446 ms p50 live and 425 ms p50 over 100 replays. Do not start Milestone 1 until the owner approves. Steps 1–6 below are done; the history is kept for reference.

Paused on 2026-10-04. Branch `milestone-0`. Milestone 1 has not started and waits for approval of the M0 results.

## Done

- Repo, Swift package and module layout (section 3 of `SPEC.md`), `docs/decisions.md` with every deviation and why.
- `murmur-cli`: `doctor`, `record`, `transcribe`, `clean`, `dictate`.
- `murmur-bench`: `record-corpus`, `run`, `engine-pass`, `cleanup-pass`, `stall-test`, `e2e`, `report`, `status`.
- Engines: Parakeet v3, v2, ultra (FluidAudio), Whisper Large v3 Turbo (WhisperKit), Apple SpeechAnalyzer, Groq (needs a key).
- Cleanup: rules, guard checker, 800 ms limit, Apple Foundation Models, Qwen3.5 0.8B/2B/4B and Qwen3-4B-2507 through MLX with a cached prompt prefix, Groq (needs a key).
- 62 unit tests passing (`Scripts/test.sh`).
- Corpus: all 100 clips recorded (`corpus/audio/`, audio not committed). Note: `silence-10` is an empty file, because the AirPods mic started after the tap ended. It now reads as an empty clip.
- Measured so far (tables in `docs/m0-results-tables.md`, raw files in `results/raw/`, gitignored):
  - **Speech:** Parakeet ultra 8.0% WER at 43 ms p50 / 49 ms p95, no text on any silence clip. Whisper Turbo 7.6% WER but 465 ms p50, and it wrote "Thank you." on noise. Apple 12.1% WER at 90 ms. Names are the weak spot for every engine (Parakeet ultra 20.9% WER on the names set).
  - **Cleanup on the written sentences:** Qwen3.5-4B resolves 28/30 corrections at 319 ms p50 / 475 ms p95 with no timeouts and no fact changes after the guard (~2.9 GB). Apple Foundation Models 27/30 but over 800 ms on 27% of runs (7 MB). Smaller Qwen models miss too many corrections.
  - **Stalled model (C6):** passes; worst case 855 ms over 20 trials (limit 1.5 s).
- Permissions: Terminal.app has Accessibility and Input Monitoring. Claude's terminal panel has the microphone.

## Left to do, in order

1. **Owner, in Terminal.app.** Replay 100 clips into TextEdit to measure release-to-paste; hands off the keyboard and mouse while it runs:
   ```bash
   cd ~/Developer/murmur && .build-mlx/release/murmur-bench e2e --engine parakeet-ultra --cleanup mlx:qwen3.5-4b --runs 100
   ```
2. **Owner, in Terminal.app.** About 20 live dictations across a few apps (hold Right Option, speak, release; Ctrl+C to quit):
   ```bash
   cd ~/Developer/murmur && .build-mlx/release/murmur-cli dictate --engine parakeet-ultra --cleanup mlx:qwen3.5-4b
   ```
3. **Optional, owner.** A Groq key, to add the cloud rows: `export GROQ_API_KEY=…` in the terminal that runs the bench. Never paste it into chat.
4. **Claude.** Rerun the engine passes so `silence-10` is included (and Groq if a key is set):
   `.build-mlx/release/murmur-bench run --skip-cleanup`
5. **Claude.** Run cleanup on real transcripts:
   `.build-mlx/release/murmur-bench run --skip-engines --skip-reference --cleanup-sources parakeet-ultra,whisper-turbo --cleanups rules,apple-foundation,mlx:qwen3.5-4b,mlx:qwen3-4b-2507,mlx:qwen3.5-2b`
6. **Claude.** Write `docs/m0-results.md` (tables from `murmur-bench report`, the recommended engine and cleanup model, and what would change the recommendation), then commit.
7. **Owner.** Approve or redirect. Then Milestone 1 can start (it begins with stable code signing; see section 3 of the spec).

## Leaning (not final until steps 1–5 are measured)

Parakeet ultra for speech and Qwen3.5-4B for cleanup, with the guard and the rule-cleaned fallback. Things that could change it: the measured end-to-end p50 above 800 ms, names accuracy (dictionary biasing is Milestone 3), Qwen's ~2.9 GB memory against Apple's 7 MB if Apple's latency improves, or the Groq rows.

## Notes to carry forward

- The AirPods are the default mic. Bluetooth mic start-up is slow (hence the empty `silence-10`); measure first-audio latency in step 2.
- Release builds live in `.build-mlx/` (with MLX); the debug build in `.build/` has no MLX. Rebuild with `swift build -c release --scratch-path .build-mlx`.
- `xcode-select` now points at Xcode 27, with the Metal Toolchain installed.
