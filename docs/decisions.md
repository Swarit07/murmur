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
- **2026-10-05 · Correction: milestones go strictly in order.** The owner clarified that only the M1 day-of-use report was skipped. Every other gate runs before the next milestone starts, so Milestone 3 waits for the M2 focus test.

## 2026-10-05 · Milestone 3 (cleanup, dictionary, snippets)

- **Dictionary entries are "write" plus optional "heard as" spellings.** The rules stage maps every heard-as spelling (and the word itself, which fixes capitals) to the written form; the written forms bias the engine and go to the cleanup model.
- **Parakeet biasing uses FluidAudio's separate CTC 110M encoder** (Approach 2 in its docs, stable), loaded on first use. Threshold sweeps changed nothing for the hard misses, so FluidAudio's defaults stay.
- **The guard trusts the dictionary:** a dictionary term in the output is never an injected name, and it may replace a look-alike fragment ("V" → "Vite", "Pri" → "Priya": prefix or edit distance ≤ a third of the term). An unrelated name is still blocked.
- **Corrections relax only what was said before the cue.** Numbers, URLs, names and negations spoken before the last cue (cue words included) may be dropped; everything after the cue must survive. Found by the guard-injection test, where a filler "I mean" let the model drop a later "not".
- **Smart Formatting is on by default.** List markers count as layout (numbers 1…N may replace spoken ordinals), and the prompt says a correction is never a list (it had read "two engineers, I mean three" as a list).
- **Prompt now carries "never translate" (C8)** and, when the dictionary is not empty, the dictionary with "use them where the transcript has a word that sounds like one of them".
- **Hosted cleanup is one OpenAI-compatible provider:** Groq (default `openai/gpt-oss-20b`, `reasoning_effort: low`, `include_reasoning: false`, +256 tokens for reasoning) and OpenRouter. Keys live in the Keychain.
- **Speculative decoding is an option, not the default** (`mlx:qwen3-4b-2507+draft`, 4 draft tokens; 6 and 8 were slower). It needs trimmable caches, so not Qwen3.5.
- **Cleanup is prewarmed with the exact instructions in use** at launch and whenever the dictionary, level, formatting or Transforms change.
- **An MLX call never returns while its generator still runs:** on cancel it cancels the generator task and awaits it, because an overlap crashed Metal. `unload()` waits for in-flight calls.

## 2026-10-05 · Milestone 4 (app windows)

- **Shortcuts are a `Shortcut` value** (modifiers alone, key plus modifiers, mouse button, Caps Lock) for push-to-talk and hands-free, stored per Mac as JSON in UserDefaults. The recognizer reduces every event kind to push-to-talk down and up, other key, hands-free trigger and Esc, so one state machine serves them all (20 tests).
- **Caps Lock comes from the keyboard HID** (IOHIDManager, usage 0x39): the event tap only sees Caps Lock when its lock flips. While Caps Lock is a Murmur shortcut, its lock state is put back after each press (`IOHIDSetModifierLockState`), so typing is not left in capitals.
- **The Hub replaces the separate windows:** Home (History), Dictionary, Snippets, Style, and Settings (General, System, Experimental, Data and Privacy). ⌘[ and ⌘] go back and forward; ⌥↑ and ⌥↓ move between pages; History supports ↑↓/j/k and Return to copy.
- **Retry and Recover in History** re-run a saved dictation from its audio and update the row without pasting. Shown when the audio is under 14 days old; failed rows must also be at least 5 s (A4).
- **Onboarding adds a "Getting the models ready" step** (not in the spec's list). A fresh account downloads ~3 GB before the first dictation can work, and without the step that wait would look like a broken app.
- **Never-store mode routes History writes to an in-memory store,** so nothing reaches disk but Paste last still works for the session; audio is not written.
- **Permission watchdog every 2 s** (A3): a revoked permission shows a notice naming it; Input Monitoring coming back restarts the event tap; pasting already fails closed without Accessibility.
- **Microphone failures show a Retry notice** (D9) that rebuilds the audio engine and checks the mic.
- **Launch at login through `SMAppService.mainApp`** (A7); it shows when macOS needs approval in Login Items.
- **Style page stores a style per category now;** applying styles to cleanup is S4, Milestone 5.
- **Experimental toggles (Command Mode, Press Enter) are shown but disabled** until Milestone 5.
- **`Scripts/install-app.sh --system` also copies to /Applications** for the fresh-account gate test.
- **2026-10-05 · The owner deferred the M4 gate tests to the end** (onboarding in a fresh account; permission revocation) and asked for a full QA and UI-polish pass first, then work on the language model ("talk, communicate, accuracy"). QA tooling goes into the Debug menu: a snapshot sweep (all pages and onboarding steps, two sizes, light and dark, all Flow Bar states) and an in-app self-test that replays recorded clips through the real pipeline into TextEdit and reads the result back.
- **2026-10-05 · Hub redesign under a transparent unified title bar.** The sidebar (sidebar material) runs to the top of the window with the traffic lights centered in a 52-pt bar; each page draws its own header row. Layout stays hand-built (no SwiftUI toolbar or split view). Page headers sit above the page with `zIndex`, because a grouped Form's background otherwise paints over them under the title bar. Empty strips that SwiftUI covers get a `WindowDragArea` so the window still drags.
- **Snapshot sweep renders a preview Hub on demo data** (in-memory store), never the owner's History, and checks in-process that clicks and drags under the title bar land where they should.
- **Self-test uses the system voice (`say`), not the owner's clips,** so its phrases can exercise a dictionary word, a snippet and a list. It restores settings, clipboard, dictionary and snippets, and deletes its own History rows.
- **A Shortcuts preset in the menu clears custom shortcuts**, so choosing one always takes effect.
- **2026-10-05 · Engine vocabulary boosting is off; dictionary spellings are matched in the rules stage instead.** The self-test found that one dictionary word made FluidAudio's CTC rescoring write that word over ordinary speech ("the lazy dog" → "the Murmurly"). The new `vocab-false-test` measured it on all 98 spoken clips plus 8 system-voice phrases: with the corpus dictionary, the default thresholds caused 13 false insertions (12 of 85 clean clips damaged, e.g. "meeting" → "Mei-Ling", "price" → "Priya"); with a one-word dictionary they caused 76. Stricter thresholds did not fix the one-word case. `SpellingMatcher` (Core) now does the job deterministically:
  - exact matches apart from case and spacing ("use effect" → useEffect);
  - close misses of six letters or more (≥ 0.8 similarity, same first letter);
  - sound-alikes ("Belouve" → Bellevue).
  
  A near miss never overwrites a real English word (system word list with suffix stripping). Result: **0 false insertions** in every configuration, 4–5 terms fixed. Boosting stays available behind `TranscribeOptions.boost`, and every rescoring change must pass the same matcher. Turning it off also removes the 13 s CTC model load on the first dictation after adding a word.
- **2026-10-05 · T4 re-measured without boosting:** 7 of 10 missed names recognized from the dictionary alone, 8 of 10 with a "Heard as" entry (Chivan → Siobhan), and 0 broken. The M3 figure of 8/10 relied on the unsafe rescoring.
- **2026-10-05 · C6 amended (owner delegated the call overnight):** cleanup may run 800 ms plus 10 ms per word over 30, capped at 1,250 ms. Long dictations (34–60 words) now finish cleanup (0/11 over the limit, previously ~3/11). The stall test with long inputs still lands text within 1.34 s, under the 1.5 s gate.
- **2026-10-05 · Smart Formatting keeps the list's lead-in** ("My three goals are:"); the model used to drop it, and the guard (rightly) rejected the result as too short. Lists of one or two items are now a guard flag (`shortList`). Cleanup gate with Smart Formatting: 28/30 corrections, 0 fact changes, C7 4/4.
- **2026-10-05 · Style names follow the spec exactly** ("Formal.", "Casual", "very casual", "Excited!"), with a one-line description under each, because the names show their own style.
- **2026-10-05 · Repository:** private GitHub repo `Swarit07/murmur`. `main` tracks the newest work; `milestone-N` branches mark each milestone. Each commit is pushed to its branch and fast-forwarded to `main`.
- **2026-10-05 · Styles (S4) are deterministic rules applied after cleanup, not prompt changes.** They only touch sentence-initial capitals, a greeting's comma and sentence-final marks, so they can't alter facts, are unit-testable, and keep the model's cached prompt the same for every app. Lists, paragraphs and mostly non-English text keep the cleaned form (styles are English only, per the spec). very casual also lowercases "I", following "no caps".
- **Categories:** bundle ids for native apps. In browsers and Electron apps, the host of the Accessibility web area's URL decides (Gmail, Outlook, Slack, Teams, WhatsApp Web, Discord…). Anything unknown is Other.
- **Command Mode uses the cleanup model with its own prompt and worked examples** (cached as a second prefix, prewarmed while the mode is on). It has a 30 s limit instead of cleanup's 800 ms, because the user is waiting for a rewrite and can press Esc. The selection is read through Accessibility, or Cmd+C with the clipboard restored. With a selection, the paste replaces it as is (no smart spacing), so one Cmd+Z restores it.
- **Command Mode's default shortcut on other keyboards is Control+Option+Command**, since push-to-talk there is Control+Option. A command starts when the Command shortcut goes down, or when Control joins a Fn hold within 250 ms (later, Fn+Control stays a dictation).
- **C11's one-time confirmation happens when the switch is turned on** (an alert in Settings), not at the first spoken "press enter". The confirmation then never interrupts a dictation.
- **D7 "no audio" means no buffers, not silence:** 3 s without an audio buffer stops the recording (a device change that silently stopped the engine). A quiet room keeps recording.
- **I10 is enforced at the insertion layer** with a first-come, first-served gate. Every paste goes through it: dictations, Paste last, Undo on a cancel, Retry.
- **2026-10-05 · S2 suggestions come from the field Murmur pasted into, compared with its own text right after the paste.** A suggestion needs every replaced word to be one Murmur wrote, a change of one or two words, and a new spelling that is either the same letters written differently or not an everyday English word. That catches "Chivan" → "Siobhan" but not "meet" → "talk". It shows as a Flow Bar card (Add / Dismiss), never silently: a wrong dictionary entry would affect every later dictation.
- **I9 typing** posts whole characters per Unicode key event (≤ 16 UTF-16 units, never splitting an emoji), with Return for line breaks and 4 ms between chunks. It is per app because typing is slower and undo granularity varies.
- **Idle unload frees both models** and reloads them at key-down, so the reload overlaps the user speaking. The engine is awaited before transcription. Dictation cleanup does not wait (rules fallback), but Command Mode does. MLX's cache must be cleared on unload or the memory is not returned (2.27 GB → 2.23 GB without it, → 0.31 GB with it).
- **2026-10-05 · Idle unload is built but off by default (deviation from section 7).** `murmur-bench reload-test` and three app cycles show that every load → unload of Qwen3.5 4B through mlx-swift-lm leaves about 400 MB of MLX arrays alive (407 → 815 → 1,222 → 1,630 MB in the app). That is the size of the quantized embedding table. It is not timing (unchanged 2 s later) and not Murmur's prompt cache (same with the cache off). Dropping the model's compiled traces before release (`invalidateCompiledTraces`, now done) helps only partly. With unloading on by default, memory would grow with every break. With it off, memory stays flat at about 2.4 GB (the soak: 250 dictations, no growth beyond allocator noise). The switch remains in Settings › System › Advanced, and the reload path is tested (self-test passes from the unloaded state). Narrowed further: load → unload with no generation frees everything (0 MB over 3 cycles, `MURMUR_MLX_NO_WARMUP=1 murmur-bench reload-test --load-only`). One generation per load leaks the ~407 MB. The compiled decode segments declare the embedding as an input and are invalidated before release, so the retention is elsewhere in the generation path. Follow-up: find it, report or patch it upstream, then turn the default back on.
- **2026-10-05 · Command Mode's keys work in either order (owner feedback).** Holding Fn and then pressing Control at any point now switches the recording to a command. Before, only Control within 250 ms of Fn did, so pressing Fn first usually stayed a dictation. The command's quick-tap and other-key windows start when Control goes down.
- **2026-10-05 · Owner decisions on the UI redesign's open items.**
  - Wire the no-audio card: a recording of 1 s or more with no speech, whether the speech gate found none or it transcribed to nothing, shows "We couldn't hear you" with Switch microphone and Test mic. Nothing is inserted, as before.
  - Keep the v2 Flow Bar timings over SPEC §6's table.
  - Keep "Shortcuts" as a submenu.
  - Keep ⌃⌘V and ⌃⌘C for Paste and Copy last.
- **2026-10-05 · The self-test checks focus before every dictation.** A run while the owner was typing put about 18 test dictations into the owner's focused Claude prompt box, because a test dictation targets whatever has focus when it starts. The insertion's own focus guard only covers focus changes after the start. The self-test now confirms that TextEdit is frontmost and its scratch document has focus before every dictation, Command Mode instruction, Paste last and recording. If not, it stops the run and reports it.
- **2026-10-05 · Milestone 7 (Windows) is dropped (owner).** Murmur stays macOS-only.
- **2026-10-05 · Health check before committing (owner asked to make sure the app fully works).**
  - The Release build is installed and running, with no crash since 14:29.
  - 170 unit tests, the token lint and the layout check pass.
  - Self-test 23/23 and app matrix 6/6, both on the current dictation code.
  - The owner's own dictations on this build were inserted in 291 to 779 ms.
  - Idle CPU is about 0%.
  - Commit `a74823d` also picked up 16 of the landing page's source files: another session is building it in `website/` in this same folder, and `git add -A` caught them. They were left in place rather than rewriting history under an active session; app commits now stage only app paths.
- **2026-10-05 · Idle unload is on by default again: the reload leak is fixed in Murmur** ([mlx-unload-leak.md](mlx-unload-leak.md)). There were two leaks, both upstream.
  - The ~408 MB per reload was Qwen3.5's fused GDN input projections (17 MB × 24 layers), not the embedding table. mlx-swift-lm's compiled decode traces read them without declaring them, so they became trace constants. MLX never frees released traces: its compile cache is per thread, and it does not break multi-output sibling cycles. Confining MLX to one thread still left 85–289 MB per reload.
  - Each model build also stranded ~5,900 graph nodes (~4.3 MB): the lazily quantized random weights that `loadWeights` assigns over.

  The fix:
  - MLX compile is off (`MLX.compile(enable: false)`). Cleanup outputs are identical (110/110 on the corpus); latency is the same within noise (p50 251 vs 253 ms over 600 runs each; long dictations no slower).
  - `unload()` keeps the model and replaces its weights with unevaluated zeros of the same shapes, which hold no memory. `load()` refills them with `loadWeights`, so the model is built only once.
  - A flag checked inside `ModelContainer.perform` keeps a call queued behind an unload from running on the empty model.
  - Turning the fusion off (`MLX_QWEN_FOUR_GDN=0`) also stops the first leak, but changes one corpus output, so it was not used.

  Result: `reload-test` footprint after unload 129–136 MB over 10 reloads (was +440 MB each), 0 MB of MLX arrays. With Parakeet unloading too, no growth over 8 cycles. Reload takes 1.3 s instead of 2.0 s. `MURMUR_MLX_COMPILE=1` turns compile back on for comparison; once upstream fixes the traces, it can go back on.
- **2026-10-05 · Prompt-lookup decoding for cleanup: built, measured, off by default** ([cleanup-speed.md](cleanup-speed.md)). The owner's 2–3-sentence dictations took 0.6–1.2 s of cleanup, because Qwen3.5 4B rewrites the whole text one token per pass. The goal was much faster cleanup with identical output.
  - **What it does.** Guesses come from the dictation itself (the output's last 1–3 tokens looked up in the prompt) and are checked in one pass. Qwen3.5's GatedDeltaNet states roll back by keeping references taken before the pass and replaying the kept tokens with the next pass. Attention caches trim. A cost model picks each guess length, because on the M4 Pro a pass of 3–10 tokens costs 1.3–3.3 one-token passes.
  - **Speed.** 1.3–1.6× at the median by length: 61+ words 1,334 → 818 ms, 36–60 words 876 → 549 ms. 11 long dictations (34–60 words) go from about 660 to 280–310 ms with no time limit.
  - **Not lossless, so off by default.** 9 of 251 outputs changed, 1 of 110 corpus outputs and 1 of 16 Command Mode outputs. MLX multiplies quantized layers by 2–12 rows with `qmv_wide` and by 13+ with `qmm`, not with the one-row `qmv`. The sums come out in a different order: 79% of a layer's outputs come out different, and the logits differ by up to 0.33. So near-ties flip, for example "eighteen hundred fifty" vs "eighteen hundred and fifty". The same holds for a draft model or Qwen's MTP head, and should for any 4-bit model on this Mac.
  - **Default output.** With the switch off the app's output is identical to before: 110/110 in three corpus passes, 16/16 in Command Mode, 11/11 long dictations. `MURMUR_PROMPT_LOOKUP=1` turns lookup on.
  - mlx-swift-lm's `SpeculativeTokenIterator` cannot take a custom guesser for Qwen3.5: it wants a draft model and caches that trim. The 4-bit checkpoint has no MTP weights.
  - The next-best option, cleaning finished sentences while the speaker talks, is written up as a proposal. Simulated, 61+ words would wait about 290–350 ms after release instead of 1.3 s, but the text changes. Corrections that span the engine's sentence ends need holding, and Smart Formatting needs the whole text. On long dictations, whole-text cleanup is often the one that leaves corrections and fillers in.
