# Decisions

Newest last. Each entry: date, decision, reason.

## 2026-10-04 · Milestone 0 setup

- **Repo at `~/Developer/murmur`.** Asked for by the owner, instead of `~/murmur` in the setup notes.
- **Toolchain.** Swift 6.4 from the Command Line Tools for everything that does not need Metal; Xcode 27.0 for MLX. The package uses Swift 6 language mode (strict concurrency) in every target.
- **Library versions checked against source on 2026-10-04,** not from memory:
  - FluidAudio **0.17.5** (2026-10-01). API: `AsrModels.downloadAndLoad(version:)`, `AsrManager.loadModels(_:)`, `transcribe(_:decoderState:)` with `TdtDecoderState.make(decoderLayers:)`. Model versions now include `.ultra` (post-trained v3, recommended by the maintainers over v3), `.redux` and `.phonon2` besides `.v3` and `.v2`.
  - WhisperKit **1.1.0** (2026-08-06). The repo moved to `argmaxinc/argmax-oss-swift`; the `WhisperKit` product is unchanged. Large v3 Turbo is the `large-v3-v20240930_turbo` variant. Dictionary bias goes through `DecodingOptions.promptTokens`.
  - mlx-swift **0.32.3**, mlx-swift-lm **3.32.3**, swift-huggingface 0.12.0, swift-transformers 1.3.4. `ChatSession(…, additionalContext: ["enable_thinking": false])` turns off Qwen thinking.
  - GRDB **7.11.1**. Not used until Milestone 1 (M0 keeps no database).
- **Cleanup model candidates are Qwen3.5 0.8B, 2B and 4B (4-bit), plus Qwen3-4B-Instruct-2507.** The spec named Qwen3 0.6B/1.7B/4B "or what is current". Qwen3.5 is the current small family (mlx-community 4-bit builds exist for all three sizes); Qwen3.6 only ships at 27B and 35B-A3B, too large for an 800 ms budget. Qwen3-4B-Instruct-2507 stays in as a non-thinking reference point.
- **Two extra local candidates: Apple SpeechAnalyzer (speech) and Apple Foundation Models (cleanup).** Both ship with macOS 26+, need no download, and their memory is managed by the OS, which helps the 120 MB shell target. Cheap to add behind the same protocols; the bake-off decides.
- **One cloud provider for both stages: Groq.** `whisper-large-v3-turbo` for speech and `llama-3.1-8b-instant` (override with `MURMUR_GROQ_CLEANUP_MODEL`) for hosted cleanup, so one key (`GROQ_API_KEY`) covers both. The CLI reads the environment; the app will use the Keychain (spec rule 2).
- **Speech module is named `SpeechEngines`, not `Speech`.** A package module called `Speech` shadows Apple's `Speech` framework, so the Apple engine could not import it.
- **Added a `Pipeline` module** (engines + cleanup + insertion wiring, corpus model, timing log). The CLI, the bench and later the app share it.
- **MLX lives in its own `CleanupMLX` target, and `MURMUR_NO_MLX=1` drops it.** MLX's Metal shaders need full Xcode; everything else builds and tests with the Command Line Tools. `Scripts/test.sh` runs the unit tests this way.
- **Swift Testing needs an explicit plugin path with the Command Line Tools.** Their `TestingMacros` plugin sits in `usr/lib/swift/host/plugins/testing`, which the compiler does not search by default. `Scripts/test.sh` passes it.
- **`murmur-cli record` uses Enter to start and Enter to stop.** A terminal cannot see key-up events, so "hold a key" is not possible there. `murmur-cli dictate` does use a real held key through a listen-only event tap.
- **`dictate` defaults to Right Option, not Fn.** On this Mac `AppleFnUsageType` is unset, so Fn may open the emoji picker or dictation. `--key fn` is available; `doctor` explains the setting.
- **Focus is read through Accessibility (`kAXFocusedApplicationAttribute`)** rather than `NSWorkspace.frontmostApplication`, which only refreshes when the main run loop turns.
- **Guard checker allows removing a number, name, URL or negation only when the input contains a self-correction cue** ("actually", "no wait", "sorry", "scratch that", "make that", "I mean", …). Additions are never allowed. Backtracking (C2) needs removals; everything else must keep facts.
- **Silence gate: energy gate by default, Silero VAD measured alongside.** The bench reports how many silence/noise clips would insert text under no gate, the energy gate and Silero, then M0 picks one.
- **Corpus audio is not committed.** `corpus/audio/*.wav` is gitignored (it is the owner's voice); `corpus/manifest.json` and the `.txt` references are committed.
- **Each bench pass runs in its own process** so model load time and memory are measured cleanly per engine and per cleanup model.
- **Active developer directory switched to Xcode 27** (`xcode-select -s`), with the Metal Toolchain component installed. `swift build` now compiles MLX's Metal shaders directly, so `xcodebuild` is not needed. Release builds with MLX go to `.build-mlx/` so they never replace the debug binaries used for recording.
