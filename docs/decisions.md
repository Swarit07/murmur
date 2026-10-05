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

## 2026-10-04 · After the first cleanup round

- **MLX prefix KV cache.** Round 1 showed both 4B models timing out on 98–100% of runs and Qwen3.5-2B at 525 ms p50: every call re-read the ~600-token system prompt and examples. The provider now builds the KV cache for that shared prefix once (per prompt variant) and copies it per call (`KVCache.copy()`, which also works for Qwen3.5's hybrid recurrent layers, unlike trimming). A spot check moved Qwen3.5-2B to ~120 ms and Qwen3-4B-2507 to ~240 ms. `MURMUR_MLX_NO_PREFIX_CACHE=1` turns it off for comparison.
- **Guard rejects reordered words at the Light level.** Round 1 found models swapping a correction instead of resolving it ("four, make that six" → "six, make that four"; "north … I mean south" → "south … I mean north"). No fact was added or removed, so the old checks passed it. The guard now aligns input and output words and flags content words that appear out of the speaker's order. Medium may restructure sentences, so it is exempt.
- **More, and more varied, correction examples in the prompt** (eight worked examples, none taken from the test set, including one "actually" that is not a correction). Cheap now that the prefix is cached.
- **Apple Foundation Models keeps one prewarmed session ready**, created right after each use, so a dictation does not pay for reading the instructions.
- **Guard: "X, no, Y" and "X, wait, Y" count as corrections** (only between commas, so a sentence starting "No," does not), and **words spoken after the cue may move forward** in the order check. Round 2 showed the guard rejecting 7 of 8 correct resolutions from Qwen3.5-4B (for example "add Jordan to the thread, no wait, add Taylor" → "Add Taylor to the thread"). Swapped corrections are still rejected because the swapped-in word was spoken before the cue.
- **Same eight-example prompt for every provider.** Apple Foundation Models runs 500–800 ms per call with or without examples, and without them it misses corrections, so trimming the prompt for it does not help.

## 2026-10-04 · Final M0 runs

- **Added three more open candidates:** Parakeet phonon2 (speech), SmolLM3-3B and Gemma 3 1B (cleanup), at the owner's request for smaller or faster open models.
- **Gemma 3 1B is reported as not measured.** In this harness it never emits a stop token, so every call runs to the token limit (~3.3 s) even though the visible answer is right. Not worth fixing for the bake-off: the comparable Qwen3.5-2B already falls well short on corrections.
- **Guard accepts real-transcript correction shapes.** Speech engines write "fourteen. No, sixteen", "six no, six thirty" and "the docs folder, no the assets folder". The cue pattern now accepts a bare "no"/"wait" after a word, followed by a comma or period or by a short function word ("the", "my", "to" …). "That's fine, no problem" and a leading "No," still do not count. Without this, 4 of Qwen3.5-4B's 6 misses on real transcripts were correct answers the guard threw away.
- **"I" and its contractions (I'm, I'ma, I'd) are never names** in the guard. Found in the live session: "I'ma" was taken for a name and a good cleanup was discarded.
- **Report scores negation entities by count, not literal word,** so "we not rename" → "we don't rename" is not a change.

## 2026-10-05 · Milestone 1 (core loop)

- **M0 approved by the owner; defaults are Parakeet ultra + Qwen3.5-4B** (settings `engine`, `cleanupProvider`), switchable in Settings without a restart (T1).
- **Xcode project generated by XcodeGen** from `App/project.yml`; the `.xcodeproj` is not committed. `Scripts/install-app.sh` builds Release, installs to `~/Applications` and launches.
- **Signing:** manual, identity "Apple Development: swarit.sheel@gmail.com", team 65J23J52T8 (the owner's free Personal Team, already in Xcode), no provisioning profile, no sandbox, no hardened runtime. The designated requirement is bundle id + certificate, so TCC grants survive rebuilds. Bundle id `com.swaritsheel.Murmur`.
- **New `MurmurKit` module** holds the app's orchestration (`DictationController`) so the Xcode target stays a thin AppKit shell; it re-exports the modules the app uses.
- **`Settings` is `AppSettings`** to avoid clashing with SwiftUI's `Settings` scene.
- **Hotkey recognizer is a pure state machine** (`HotkeyRecognizer`) fed by a listen-only event tap; 13 recorded-sequence tests cover hold, tap, double-tap, Fn+Space, Fn+other key within 250 ms, extra modifiers, Esc, the D4 rapid-tap guards and Ctrl+Option. Fn is tracked from its own key events only, because arrow and function keys also set the Fn flag.
- **D4 (rapid-tap guard) implemented now** though the spec lists it for Milestone 5; it fell out of the recognizer at no cost.
- **Paste and Copy last transcript use Carbon `RegisterEventHotKey`** (consumed, no permission) rather than the listen-only tap, which cannot stop the keys reaching the frontmost app.
- **Recording starts at key down; a quick tap (< 300 ms) or Fn+other key is discarded with no History row.** A real dictation gets its History row and audio file before transcription, and its raw text before cleanup (T2).
- **Error states do not block the next dictation.** The menu-bar icon shows the error until the menu is opened (spec: dismissed by a click on the app icon), but a new key press dismisses it and starts. Blocking dictation until a click would lose the next dictation, which the M1 gate forbids.
- **Menu-bar icon is the M1 "listening" indicator** (idle, recording, hands-free, processing, error, loading). The Flow Bar overlay and its 50 ms target arrive in Milestone 2.
- **Smart leading space:** a dictation that lands right after a word gets a leading space (read through Accessibility, `kAXStringForRangeParameterizedAttribute`). Unknown cursor context adds nothing.
- **Microphone chosen per app** through `kAudioOutputUnitProperty_CurrentDevice`; the system default input is never changed. The engine rebuilds after `AVAudioEngineConfigurationChange` (device or Bluetooth route change).
- **Audio kept 14 days** for Retry and Recover (A4), deleted at launch after that; a Settings switch turns keeping audio off.
- **Sounds are generated tones** (`Scripts/make-sounds.swift`), placeholders until Milestone 2 tokens.
- **Groq keys come from the Keychain** in the app (`Keychain` service `com.swaritsheel.Murmur`, account `groq`), the environment in the CLI.
- **2026-10-05 · The owner moved the M1 gate.** Milestone 2 starts now, and the owner keeps using Murmur day to day instead of a dedicated test day. Crashes and lost dictations found that way are fixed as they come up, and Claude checks History (`Scripts/m1-day-report.sh`) along the way instead of asking for a formal report. Two crashes found in the first 10 minutes of use (an empty audio-engine prepare, and paste off the main thread) were fixed before this decision.

## 2026-10-05 · Milestone 2 (Flow Bar)

- **No measurements of the reference app yet, so every visual value is a placeholder** in `Sources/UI/Tokens.swift` (geometry, colors for light and dark, material, motion, type, sound). The design is original: a capsule with a level-driven waveform, a three-dot processing loop and notice cards.
- **Tokens are live.** `LiveTokens` starts from `Tokens.defaults`, can be edited from Debug › Token panel, persists overrides in UserDefaults, and "Copy as Swift" prints the current values for pasting back into `Tokens.swift`.
- **Sounds are synthesized at runtime from the sound tokens** (pitch, length, volume), so tuning is heard on the next dictation. The bundled WAVs and `Scripts/make-sounds.swift` are gone.
- **The panel can never become key or main** (`canBecomeKey`/`canBecomeMain` false, `.nonactivatingPanel`), sits one level above the Dock, and joins all Spaces including full-screen (`.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.stationary`).
- **Only the bar's rectangle takes mouse events.** The panel is a fixed canvas big enough for the largest state; global and local mouse-moved monitors switch `ignoresMouseEvents` on whether the pointer is over the bar. Mouse monitors need no permission.
- **Placement:** bottom center of the visible frame of the screen holding the focused window (read through Accessibility at each dictation start), plus `bottomMargin`; a visible frame reaching the screen bottom (full screen, auto-hidden or side Dock) adds `fullScreenLift`. The multi-display rule is still to be confirmed from a recording, as the spec says.
- **Drag moves the bar anywhere;** the offset persists, and "Reset Flow Bar position" in the right-click menu clears it.
- **Hide for 1 hour (A6)** is in the right-click and menu-bar menus. Its Undo is "Show Flow Bar" in the menu-bar menu rather than a toast, since the bar itself is hidden.
- **Undo on the cancelled toast inserts the cancelled dictation after all;** Retry on a transcription error re-runs it. Both keep the audio in memory, re-run the pipeline, and paste into the field that had focus originally.
- **Focus test for the gate** (Debug › Run focus test): 50 synthetic clicks on the bar while a text field elsewhere has focus. After each click it checks that the same app and element have focus and that Murmur never became active, then writes a log to the data folder.
- **Reduce Motion (A8, Milestone 4) is honoured already** in the bar: springs become fades and the processing loop holds still.
- **Fourth sound: a "done" chime when text lands,** at the owner's request. Original synthesis only: per spec rule 1, Wispr's sound files are never copied or sampled. The owner can record the reference app; Claude measures pitch, length and envelope and puts those numbers into the sound tokens, and the sound stays synthesized.
- **Sounds are two-note tones with overtones:** a short pitch glide (`soundGlide`), brightness and "bellness" (how far the overtones drift from exact harmonics toward a bell's) as tokens. Debug › Play sounds plays each one for tuning.
- **2026-10-05 · The owner started Milestone 3 before running the M2 focus test.** The test stays in Debug › Run focus test and will run before release.
