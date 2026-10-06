# Legal and privacy audit (L0)

*Written by the maintainer, not a lawyer.*

Audit of the `legal-docs` branch (base `ui-redesign` at 46d5436), 2026-10-05, for `LEGAL_DOCS.md`. It describes what the code does today. Paths are relative to the repo root unless they start with `~` or name a dependency checkout. Dependency checkouts are at the versions in `Package.resolved` (`App/build/SourcePackages/checkouts/<name>/…`, shortened below to `<name>/…`).

Scope: the menu-bar app (`App/`, and the `MurmurKit`, `HubUI`, `UI` and lower modules it links). `murmur-cli`, `murmur-bench` and `murmur-snap` are developer tools that aren't in `Murmur.app`; they're mentioned only where they write into the app's data folder.

Evidence beyond reading code: the installed build at `~/Applications/Murmur.app` (built 2026-10-05 19:45 from this commit), its linked symbols (`nm`, `otool -L`), the maintainer's own data folders (names and sizes only, no contents), Murmur's HTTP cache (`~/Library/Caches/com.swaritsheel.Murmur/Cache.db`, which URLs were requested), and the Hugging Face model cards (fetched 2026-10-05).

---

## 1. Network

### Searched for

In `Sources/`, `App/Sources/`, `Scripts/`, `Tools/` and every checkout in `Package.resolved`: `URLSession`, `URLRequest`, `NWConnection`, `NWPathMonitor`, `CFNetwork`, `import Network`, `WKWebView`, `NSWorkspace…open` with `http`, `Process(` (and what it runs), `curl`, `git`, `SUFeedURL`, `SPUUpdater`, `Sparkle`, `Sentry`, `Crashlytics`, `PLCrashReporter`, `TelemetryDeck`, `PostHog`, `Firebase`, `analytics`, `telemetry`, `https?://`, `huggingface`, `HubApi`, `HubClient`, `downloadAndLoad`, `downloadSnapshot`, `AssetInventory`.

### Not found

- No analytics, telemetry or crash-reporting SDK in the app or any dependency the app links.
- No update checks (no Sparkle or similar).
- No web views.
- `Process` runs only local commands: `/bin/sh -c "sleep 0.5; open <Murmur.app>"` to relaunch (`Sources/HubUI/Hub.swift:135-138`) and `/usr/bin/say` to make test audio for the Debug menu's self-test and app matrix (`App/Sources/SelfTest.swift:373-375`, `App/Sources/AppMatrix.swift:322-324`).
- `NSWorkspace.open` opens only `x-apple.systempreferences:` panes and the local data folder (`Sources/HubUI/SettingsPages.swift:132,513`, `Sources/HubUI/Onboarding.swift:250`, `Sources/HubUI/HubShell.swift:209,285`, `App/Sources/AppDelegate.swift:487,575`).
- `Network.framework` is linked (seen in `otool -L`) for WhisperKit's `NWPathMonitor` (`argmax-oss-swift/Sources/ArgmaxCore/External/Hub/HubApi.swift:839-848`). It only watches whether the Mac is online and opens no connection. `AuthenticationServices` is linked for swift-huggingface's OAuth code, which Murmur never calls.

### Found: five outbound connections

| # | Destination | Default | Described in SPEC.md? |
|---|---|---|---|
| 1a | `huggingface.co` (and the download hosts it redirects to): speech model | **On.** First launch, and again only if files go missing | **No** |
| 1b | `huggingface.co`: cleanup model | **On.** Every launch, plus the first download | **No** |
| 1c | `huggingface.co`: other models picked in Settings | Off until picked | **No** |
| 1d | Apple, through macOS: Apple speech assets | Off (opt-in engine, macOS 26+) | **No** |
| 1e | `api.groq.com` and `openrouter.ai` | Off (needs the user's own key and choice) | Yes (§1 rule 2, §2) |

#### 1a. Speech model download (FluidAudio, Parakeet)

- **Trigger:** `ParakeetEngine.load()` calls `AsrModels.downloadAndLoad` (`Sources/SpeechEngines/ParakeetEngine.swift:37`). The default engine is `parakeet-ultra` (`Sources/Store/Settings.swift:28`), loaded at launch by `DictationController.reloadModels()` (`Sources/MurmurKit/DictationController.swift:270-309`).
- **When it connects:** only when the model files aren't already in `~/Library/Application Support/FluidAudio/Models/` or don't match FluidAudio's pinned revision. `AsrModels.download` returns early when they're present (`FluidAudio/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/TDT/AsrModels.swift:604-607`), and `ModelHub.loadModelsOnce` downloads only missing files (`FluidAudio/Sources/FluidAudio/Shared/Download/ModelHub.swift:343-346`). Idle unloads and reloads read from disk.
- **Destination:** `https://huggingface.co/FluidInference/parakeet-ultra-coreml` (`FluidAudio/Sources/FluidAudio/ModelNames.swift:21`). The host can be changed with the `REGISTRY_URL` or `MODEL_REGISTRY_URL` environment variables (`FluidAudio/Sources/FluidAudio/ModelRegistry.swift:32-37`).
- **What's sent:** HTTPS GET requests for the repo's file list and files, with standard request headers (the system's `User-Agent`) and the Mac's IP address. **No audio, text or settings.** If the environment has `HF_TOKEN`, `HUGGING_FACE_HUB_TOKEN` or `HUGGINGFACEHUB_API_TOKEN`, that token is sent as `Authorization: Bearer` (`FluidAudio/Sources/FluidAudio/Shared/Download/HFClient.swift:29-43`). An app opened from Finder doesn't normally inherit shell variables, so this mostly applies when Murmur is started from a terminal.
- **Size:** about 0.5 GB (README).
- **Can the user turn it off?** No setting. After the first download Murmur works with the network blocked. Not used by the app: the Silero VAD model (`SileroSpeechGate`, `ParakeetEngine.swift:111`; the app uses the energy gate, `DictationController.swift:77`) and the CTC dictionary-boost model (`ParakeetEngine.swift:83`, only when `TranscribeOptions.boost` is true; it defaults to false, `Sources/SpeechEngines/SpeechEngine.swift:14`, and the app never sets it).

#### 1b. Cleanup model (MLX, Qwen3.5 4B), checked on every launch

- **Trigger:** `MLXCleanupProvider.load()` calls `#huggingFaceLoadModelContainer` (`Sources/CleanupMLX/MLXCleanupProvider.swift:96-98`) the first time it loads in a run of the app. The default provider is `mlx:qwen3.5-4b` (`Sources/Store/Settings.swift:34`) → `mlx-community/Qwen3.5-4B-4bit` (`MLXCleanupProvider.swift:30`). Reloads after an idle unload reuse the loaded container and don't touch the network (`MLXCleanupProvider.swift:80-95`).
- **When it connects:** **every app launch**, not only the first. The macro wraps swift-huggingface's `HubClient()` (`mlx-swift-lm/Libraries/MLXHuggingFaceMacros/HuggingFaceIntegrationMacros.swift:23-58`). Its offline fast path only applies when the revision is a commit hash (`swift-huggingface/Sources/HuggingFace/Hub/HubClient+Files.swift:1966-1976`). Murmur asks for `main`, so each load lists the repo's files over the network (`HubClient+Files.swift:1661`). If that request fails, it falls back to the cached copy (`HubClient+Files.swift:1662-1680`). If the files on Hugging Face have changed since the last download, the new ones are downloaded. Evidence: Murmur's HTTP cache holds one entry, `https://huggingface.co/api/models/mlx-community/Qwen3.5-4B-4bit/tree/main?recursive=true`, dated 2026-10-05 05:08, long after the first download.
- **Tested 2026-10-05:** with the model fully cached, `HF_ENDPOINT` pointed at a local stand-in server, and `murmur-cli clean --cleanup mlx:qwen3.5-4b` run twice, each run sent `GET /api/models/mlx-community/Qwen3.5-4B-4bit/tree/main?recursive=true`, got a 404, and still loaded the cached model. That's one request per load. Hugging Face's real reply has an ETag but no `Cache-Control`, so URLSession revalidates rather than reusing it.
- **Destination:** `https://huggingface.co/api/models/mlx-community/Qwen3.5-4B-4bit/…` and the file download hosts. Host can be changed with `HF_ENDPOINT` (`swift-huggingface/Sources/HuggingFace/Hub/HubClient.swift:184-190`).
- **What's sent:** the repo name, request headers and IP address. **No audio, text or settings.** **Hugging Face token:** `HubClient()` uses `TokenProvider.environment` (`HubClient.swift:118`), which reads `HF_TOKEN`, `HUGGING_FACE_HUB_TOKEN`, the file at `HF_TOKEN_PATH`, `$HF_HOME/token`, **`~/.cache/huggingface/token`** or `~/.huggingface/token` (`swift-huggingface/Sources/HuggingFace/Shared/TokenProvider.swift:109-121`). Murmur isn't sandboxed, so if the user has ever run `huggingface-cli login`, their token goes to Hugging Face with these requests, which links the requests to their Hugging Face account. (No token file exists on the maintainer's Mac.)
- **Size:** about 2.5 GB on first download (README).
- **Can the user turn it off?** No setting. Choosing "Rules only" or "Apple on-device" cleanup stops it. With the network blocked, the check fails and the cached model loads.

#### 1c. Other models picked in Settings

Settings › General offers these engines and cleanup models (`Sources/HubUI/Windows.swift:98-112`, catalogs at `Sources/SpeechEngines/SpeechEngine.swift:51-67` and `Sources/Pipeline/Catalog.swift:8-46`). Picking one loads it and downloads it if needed:

- Parakeet v3, v2 and phonon2: as 1a (`FluidInference/parakeet-tdt-0.6b-v3-coreml`, `…-v2-coreml`, `FluidInference/phonon-2-coreml`).
- Whisper Large v3 Turbo (WhisperKit): `WhisperKitConfig(…, download: true)` (`Sources/SpeechEngines/WhisperKitEngine.swift:18`) fetches `argmaxinc/whisperkit-coreml` and the tokenizer from `openai/whisper-large-v3` into `~/Documents/huggingface/models/` (`argmax-oss-swift/Sources/ArgmaxCore/External/Hub/HubApi.swift:108-109`). It checks the network on each load, falling back to the local copy when offline (`HubApi.swift:590-594`). It reads a Hugging Face token from the same places as 1b (`HubApi.swift:133-152`).
- Qwen3.5 2B, Qwen3 4B 2507, SmolLM3 3B (MLX): as 1b.
- Not offered in the app's menus, only by id in the catalog: `qwen3.5-0.8b`, `gemma3-1b` and the `+draft` variants (`MLXCleanupProvider.swift:27-39`).

#### 1d. Apple on-device speech (opt-in, macOS 26 and later)

`AppleSpeechEngine.load()` asks macOS to install the speech assets for the locale (`Sources/SpeechEngines/AppleSpeechEngine.swift:26-27`). macOS downloads them from Apple and shares them with other apps; Murmur doesn't make the request itself. Transcription then runs on the Mac (`isLocal = true`, line 10). The Apple Intelligence cleanup option (`AppleFoundationCleanupProvider`, `Sources/Cleanup/Providers.swift:100-184`) uses the on-device system model and downloads nothing.

#### 1e. Groq and OpenRouter (optional cloud, behind the user's own key)

- **Off by default.** They run only if the user picks "Groq Whisper (cloud, needs key)" as the engine or "Groq"/"OpenRouter (cloud, needs key)" as the cleanup model, and saves a key (`Sources/HubUI/SettingsPages.swift:581-584`). Keys come from the Keychain, then the `GROQ_API_KEY`/`OPENROUTER_API_KEY` environment variables (`DictationController.swift:275-276`).
- **Groq speech** (`Sources/SpeechEngines/GroqWhisperEngine.swift:33-61`): POST to `https://api.groq.com/openai/v1/audio/transcriptions` with each dictation's **audio** as a WAV, the chosen language, and **the dictionary words** as a prompt (lines 40-46). On load it sends half a second of silence to warm the connection (line 30).
- **Groq or OpenRouter cleanup** (`Sources/Cleanup/Providers.swift:45-67`): POST to `https://api.groq.com/openai/v1/chat/completions` (line 79) or `https://openrouter.ai/api/v1/chat/completions` (line 92) with **the transcript**, Murmur's cleanup instructions, the dictionary words and the style. **Command Mode** sends the spoken instruction and **the selected text** (`DictationController.swift:541-543`). On load each sends "Reply with OK." (line 42). OpenRouter forwards requests to whichever company hosts the chosen model.
- Requests use an ephemeral session (`Providers.swift:31`, `GroqWhisperEngine.swift:20`), so nothing is cached on disk. What Groq or OpenRouter keep is up to their own policies.
- **Turn off:** pick a local engine and model in Settings › General, and remove the key in Settings › Data & privacy.

**Offline test (2026-10-05).** Under `sandbox-exec` with outbound IP blocked (`(deny network-outbound (remote ip))`; a control `curl https://huggingface.co` under the same profile failed to connect), `murmur-cli transcribe --engine parakeet-ultra` on a synthetic `say` clip loaded the model in 9.4 s and transcribed it. `murmur-cli clean --cleanup mlx:qwen3.5-4b` loaded the model in 2.4 s and cleaned the text ("So let's meet at three on Thursday."). Both used the same dependency versions and load paths as the app (`.build-mlx` release build of 2026-10-05 03:19). The app itself wasn't run offline, because that needs its permissions and would disturb the maintainer's running copy. That's an owner check (see the progress log).

**Stop condition met:** 1a–1d aren't described in `SPEC.md`. SPEC §2 says engines "run locally by default" and covers only the key-gated cloud engine and hosted model (1e). It never mentions downloading models from Hugging Face, the check on every launch, or the token pickup. Per LEGAL_DOCS §1 rule 2 and L0, `PRIVACY.md` waits for the owner.

---

## 2. Data at rest

| Item | Path | Contents | Retention | How it's deleted |
|---|---|---|---|---|
| History database | `~/Library/Application Support/Murmur/murmur.sqlite` (`Sources/Store/HistoryStore.swift:6-13`) | Table `dictation`: time, duration, **app bundle id and app name**, mode, engine, cleanup id, **raw and cleaned transcript**, status, error code, audio path, stage timings (lines 105-121, 143-145). Error codes can hold an engine or HTTP error message (`DictationController.swift:496`). Tables `dictionary_entry` (word, "heard as" spellings, manual or suggested) and `snippet` (cue, expansion). Table `app_style` exists but nothing writes to it. | **Kept until deleted.** No automatic expiry. | Settings › Data & privacy › "Delete all History and audio" deletes every dictation row and the Audio folder (`Sources/HubUI/SettingsPages.swift:569-576`, `HistoryStore.swift:211-214`). The dictionary and snippets stay; delete those one by one on their pages, or delete the file. No per-row delete in the UI. Note: macOS's SQLite runs `secure_delete` in FAST mode (checked: `PRAGMA secure_delete` → 2). Deleted text on pages that stay in use is zeroed, but whole pages freed by a delete can keep old text until SQLite reuses them. There's no `VACUUM`. |
| Audio | `~/Library/Application Support/Murmur/Audio/<id>.wav` (`DictationController.swift:472-476, 787-792`) | 16 kHz mono WAV of each dictation, and of cancelled ones | **On by default** ("Keep audio for 14 days", `Settings.swift:167-171`). Files older than 14 days are deleted **when Murmur starts** (`DictationController.swift:171, 1013-1023`), so they can outlive 14 days if Murmur runs for weeks without restarting. | The toggle in Settings › Data & privacy stops new files; Delete all removes the folder. |
| Never-store mode | none | When on, History goes to an in-memory database and no audio is written (`DictationController.swift:71-74, 472`). | Until Murmur quits. | Off by default (`Settings.swift:129-133`). |
| Settings | `~/Library/Preferences/com.swaritsheel.Murmur.plist` | The keys in `Settings.swift:15-17` (engine, cleanup model and level, shortcuts, microphone UID, languages, styles, typing-app bundle ids, toggles, onboarding progress), plus `murmur.flowBarOffset` (`Sources/UI/FlowBarPanel.swift:50-53`), `murmur.hub.styleCardDismissed` (`Sources/HubUI/HomePage.swift:20`), `murmur.tokenOverrides.v2` (Debug token panel, `Sources/UI/Tokens.swift:130-146`) and window frames `NSWindowFrame murmur.*` (`Sources/HubUI/Windows.swift:33`). **No transcript text.** | Until deleted | `defaults delete com.swaritsheel.Murmur` |
| Cloud keys | Login Keychain, generic passwords, service `com.swaritsheel.Murmur`, accounts `groq` and `openrouter` (`Settings.swift:174-204`), accessible after first unlock (line 202) | The user's API keys | Until removed | "Remove" in Settings › Data & privacy (`SettingsPages.swift:608`), or Keychain Access |
| Speech models | `~/Library/Application Support/FluidAudio/Models/` (`FluidAudio/Sources/FluidAudio/Shared/MLModelConfigurationUtils.swift:37-41`) | Downloaded model files | Kept | Delete the folder (another FluidAudio-based app may share it) |
| Cleanup models | `~/.cache/huggingface/hub/models--mlx-community--…` (or `$HF_HUB_CACHE`, `$HF_HOME/hub`; `swift-huggingface/Sources/HuggingFace/Hub/HubCache.swift:19-36`) | Downloaded model files | Kept | Delete the `models--mlx-community--…` folders. **Shared with other Hugging Face tools** on the Mac. |
| WhisperKit models (if picked) | `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml`, `…/openai/whisper-large-v3` | Model and tokenizer files | Kept | Delete the folders |
| System caches | `~/Library/Caches/com.swaritsheel.Murmur/` | Core ML's compiled-model cache (`com.apple.e5rt.e5bundlecache`), and URLSession's HTTP cache (`Cache.db`, `fsCachedData`) holding Hugging Face API replies. Cloud requests are ephemeral and never cached (§1e). | Managed by macOS | Delete the folder |
| HTTP storage | `~/Library/HTTPStorages/com.swaritsheel.Murmur/` | URLSession cookie and alt-svc store for the Hugging Face requests | Managed by macOS | Delete the folder |
| Debug menu output | `~/Library/Application Support/Murmur/` | `focus-test-*.txt`: pass/fail, **app name, bundle id and accessibility role** of the field under test (`App/Sources/FlowBarWiring.swift:194-205`, `Sources/Context/FocusContext.swift:66-68`). `selftest/`: synthetic `say` clips, a TextEdit document and a report of fixed test phrases (`App/Sources/SelfTest.swift:15, 348, 372, 388`). Self-test dictations also pass through History, and the test deletes its rows afterwards (`SelfTest.swift:332-333`). `snapshots/` and `Snapshots/menu/`: PNGs of Murmur's windows on **demo data** (`App/Sources/AppDelegate.swift:352-393, 606-616`). | Only when the user runs those items. **The Debug menu is shown by default** (`Settings.swift:161-165`). | Delete the files |
| CLI timing log | `~/Library/Application Support/Murmur/m0/dictate-timings.jsonl` (`Sources/Pipeline/DictationPipeline.swift:143-190`) | Written by `murmur-cli dictate` only (`Sources/MurmurCLI/main.swift:322`): timings, engine, status and the **target app name**. No text. | Grows | Delete the folder |
| Permissions | macOS's TCC database | Microphone, Accessibility, Input Monitoring grants | Until revoked | System Settings › Privacy & Security, or `tccutil reset All com.swaritsheel.Murmur` |
| Login item | macOS background-items store | Registered by `SMAppService.mainApp` when "Launch at login" is on (`SettingsPages.swift:181-203`) | Until turned off | The Settings toggle, or System Settings › General › Login Items |

---

## 3. Clipboard and text access

**Writes:**

1. **Every paste** (`Sources/Insertion/InsertionTransaction.swift:79-98`): saves every item and type on the general pasteboard, writes the transcript with the nspasteboard.org transient, concealed and auto-generated markers so clipboard managers skip it (`Sources/Insertion/Pasteboard.swift:40-46, 68-80`), sends ⌘V, waits 0.5 s (5 s for remote-desktop apps, lines 25-40), then **restores the saved clipboard only if nothing else changed it** (line 93). If the user copied something in that window, their copy is kept and the transcript isn't restored over it.
2. **When a paste can't happen** (focus moved, password field, keystroke not sent): the transcript is left on the clipboard **without markers**, so it can be pasted by hand and clipboard managers may record it. The old clipboard isn't restored (`InsertionTransaction.swift:66-68, 72-74, 84-86`).
3. **"Typing instead" apps** (Settings list): the text is typed with key events and the clipboard isn't touched (lines 70-77).
4. **Copy last transcript (⌃⌘C)** and History's Copy: write plain text with no markers and no restore (`DictationController.swift:1001-1008`, `Sources/HubUI/HomePage.swift:247-251`).

**Reads:**

5. **Command Mode** reads the selection through Accessibility. If the app doesn't expose it, Murmur sends ⌘C, reads the clipboard and restores the previous clipboard exactly (`Sources/Insertion/SelectionReader.swift:12-63`). The selection isn't stored. It goes to the cleanup model, which is a cloud service if the user picked one (§1e). History stores the instruction and the rewritten text (`DictationController.swift:530-581`).

**Accessibility reads (not the clipboard):**

6. At key-down: the frontmost app's name and bundle id, the focused element, its role and whether it's a secure field (`Sources/Context/FocusContext.swift:77-110`). App name and bundle id go into History (§2).
7. For styles: the URL of the web page holding the focused field (`FocusContext.swift:126-145`, used at `DictationController.swift:748`). It's used to pick a style category and **not stored**.
8. For dictionary suggestions (S2): 300 ms after a paste, and again 15 and 45 s later, Murmur reads the **text of the field it pasted into**, up to 20,000 characters (`DictationController.swift:697-730`, `FocusContext.swift:112-122`). It's kept in memory only to spot a corrected word. Nothing is written unless the user clicks Add, which saves that one word to the dictionary (line 736).
9. Murmur never captures the screen (`CGWindowListCreateImage` is used only for its own menu windows in a Debug action, `AppDelegate.swift:382-394`).

---

## 4. Logs

Murmur uses `os.Logger` with subsystem `com.swaritsheel.Murmur`, categories `dictation`, `mlx` and `fonts`. It has no file logs other than the Debug and CLI files in §2. Every app log line:

- `DictationController.swift:233, 352, 362, 373, 381, 409, 412, 418, 545, 576, 657, 671, 688, 729, 907, 973`: counts, states, timings, outcomes ("ok", "timeout", "rules", "model"), guard-flag kinds and error descriptions. Line 545 logs "selection" or "draft", never the selection itself.
- `Sources/CleanupMLX/MLXCleanupProvider.swift:91, 106, 111, 207, 213, 360, 376`: memory sizes, token counts, and error descriptions marked `.public`.
- `Sources/UI/Tokens+Type.swift:161, 171, 176`: font file names.

**No log line contains transcript text, selected text, window titles or app names.** Two error lines (`DictationController.swift:373`, `MLXCleanupProvider.swift:91, 376`) log `String(describing: error)` as `.public`. They can include a device name or a file path, and a path under the home folder shows the macOS user name. Nothing to fix for the "never transcript text" rule. Dependencies log through their own `os.Logger`s (FluidAudio logs model paths and system info, `FluidAudio/Sources/FluidAudio/Shared/SystemInfo.swift:85`). None of them see transcript text except the engines' outputs, which they don't log at the default level.

Logs stay in macOS's unified log on the Mac. Murmur sends them nowhere.

---

## 5. Permissions

| Permission | How it's requested | Info.plist string | What Murmur does with it |
|---|---|---|---|
| Microphone | `AVCaptureDevice.requestAccess(for: .audio)` (`Sources/Audio/AudioRecorder.swift:21`, `Sources/HubUI/Onboarding.swift:168`, `SettingsPages.swift:497`) | `NSMicrophoneUsageDescription`: "Murmur records your voice while you hold the dictation shortcut and turns it into text on this Mac." (`App/project.yml:32`; same in the installed build's Info.plist) | Records while a dictation is running (hold, hands-free, Command Mode) and during the mic level test. |
| Accessibility | `AXIsProcessTrustedWithOptions` prompt (`Sources/Context/FocusContext.swift:13`) | none (macOS doesn't use one) | Sends the paste keystroke and typed text, reads the focused element and selection (§3), and posts ⌘C for Command Mode and Return for "press enter". |
| Input Monitoring | `CGRequestListenEventAccess` (`FocusContext.swift:20`) | none | A **listen-only** event tap on `keyDown`, `keyUp`, `flagsChanged` and other-mouse-button events (`Sources/Hotkey/KeyEventTap.swift:30-40`). macOS delivers **every key press** to it. Murmur passes on only the key code and modifier flags, never the character (`KeyEventTap.swift:66-99`). The recognizer acts on the configured shortcuts and Esc (`Sources/Hotkey/HotkeyRecognizer.swift:207`) and keeps no key history (state fields at lines 139-147). If Caps Lock is a shortcut, an IOHID monitor watches the Caps Lock key only (`Sources/Hotkey/CapsLockMonitor.swift:20-30`). ⌃⌘V and ⌃⌘C use Carbon global hot keys (`GlobalHotKey`, `KeyEventTap.swift:106-140`). |
| Not requested | | | Screen Recording, Speech Recognition, Automation/Apple Events, Contacts, Location, Camera. The Apple speech engine (§1d) uses `SpeechAnalyzer`, and the app never requests Speech Recognition authorization. `NSSpeechRecognitionUsageDescription` isn't in Info.plist. That's fine as long as macOS doesn't prompt for `SpeechTranscriber`. **Owner check:** pick Apple on-device once on macOS 26 and confirm nothing asks for permission. |

Launch at login (`SMAppService`) needs the user's approval in Login Items but isn't a privacy permission.

---

## 6. Third-party components

### Bundled in Murmur.app

What's linked was checked with `nm -U` on the installed binary. The resource bundles are in `Murmur.app/Contents/Resources`.

| Component | Version | Used for | License (SPDX) | License text | In the app? |
|---|---|---|---|---|---|
| Geist, Geist Mono (Vercel) | 1.7.2 (`Tools/fetch_fonts.sh:3`) | UI type | OFL-1.1 | `Sources/UI/Resources/Fonts/Geist-OFL.txt` | Yes, fonts and OFL text (`murmur_UI.bundle/Fonts`) |
| Newsreader (Production Type), static cuts "Newsreader" and "Newsreader Display" | Google Fonts variable font, cut by `Tools/fetch_fonts.sh` | Display type | OFL-1.1 (no Reserved Font Name in the copyright line) | `Sources/UI/Resources/Fonts/Newsreader-OFL.txt` | Yes |
| FluidAudio | 0.17.5 | Parakeet engine | Apache-2.0 | `FluidAudio/LICENSE` | Yes, linked. Also ships `FluidAudio_FluidAudio.bundle` with LuxTTS text-to-speech lexicon files Murmur doesn't use (see note A) |
| argmax-oss-swift (WhisperKit, ArgmaxCore) | 1.1.0 | Whisper engine | MIT, with Apache-2.0 parts from swift-transformers | `argmax-oss-swift/LICENSE`, `NOTICES` | Yes, linked |
| mlx-swift (incl. MLX, mlx-c) | 0.32.3 | Runs the cleanup model | MIT | `mlx-swift/LICENSE`, `Source/Cmlx/mlx/LICENSE`, `Source/Cmlx/mlx-c/LICENSE` | Yes, linked, plus `mlx-swift_Cmlx.bundle/default.metallib` |
| ↳ fmt (vendored) | in mlx-swift 0.32.3 | | MIT | `mlx-swift/Source/Cmlx/fmt/LICENSE` | Yes (`fmt::` symbols) |
| ↳ nlohmann/json (vendored) | in mlx-swift 0.32.3 | | MIT | `mlx-swift/Source/Cmlx/json/LICENSE.MIT` | Yes |
| ↳ metal-cpp (vendored) | in mlx-swift 0.32.3 | | Apache-2.0 | `mlx-swift/Source/Cmlx/metal-cpp/LICENSE.txt` | Yes (`MTL::` symbols) |
| mlx-swift-lm | 3.32.3 | LLM loading and generation | MIT | `mlx-swift-lm/LICENSE` | Yes, linked |
| ↳ XGrammar (vendored) | in mlx-swift-lm 3.32.3 | | Apache-2.0, with NOTICE | `mlx-swift-lm/Libraries/MLXCXGrammar/xgrammar/LICENSE`, `NOTICE` | Yes (1,556 `xgrammar` symbols) |
| ↳ ↳ dlpack, picojson (vendored by XGrammar) | | | Apache-2.0; BSD-2-Clause | `xgrammar/3rdparty/…` | Compiled in through XGrammar headers |
| swift-huggingface | 0.12.0 | Model downloads (1b) | Apache-2.0 | `swift-huggingface/LICENSE` | Yes, linked |
| swift-transformers (Hub, Tokenizers) | 1.3.4 | Tokenizers | Apache-2.0 | `swift-transformers/LICENSE` | Yes, linked, plus `swift-transformers_Hub.bundle` (fallback GPT-2/T5 tokenizer configs) |
| swift-jinja | 2.5.1 | Chat templates | Apache-2.0 | `swift-jinja/LICENSE` | Yes, linked |
| yyjson | 0.12.0 | JSON parsing for swift-transformers | MIT | `yyjson/LICENSE` | Yes (`_yyjson_read_opts`) |
| EventSource | 1.5.1 | Server-sent events for swift-huggingface's inference client (unused by Murmur) | MIT | `EventSource/LICENSE.md` | Yes, linked |
| GRDB.swift | 7.11.1 | SQLite History | MIT | `GRDB.swift/LICENSE` | Yes, linked (uses the system SQLite, `/usr/lib/libsqlite3.dylib`), plus `GRDB_GRDB.bundle/PrivacyInfo.xcprivacy` |
| swift-collections | 1.7.1 | Dependency of the above | Apache-2.0 | `swift-collections/LICENSE.txt` | Yes (`OrderedCollections`) |
| swift-numerics | 1.1.1 | Dependency of the above | Apache-2.0 | `swift-numerics/LICENSE.txt` | Yes (`RealModule`) |
| swift-crypto | 4.5.2 | Dependency of swift-huggingface | Apache-2.0 (NOTICE.txt) | `swift-crypto/LICENSE.txt`, `NOTICE.txt` | Yes, linked as a thin layer over CryptoKit. No BoringSSL symbols in the binary. `swift-crypto_Crypto.bundle/PrivacyInfo.xcprivacy` |
| libswiftCompatibilitySpan.dylib | toolchain | Swift runtime back-deployment | Apache-2.0 with Runtime Library Exception | Swift toolchain | Yes (`Contents/Frameworks`); the exception means no notice is required |

### In Package.resolved but not in the app

| Component | Version | License | Why not shipped |
|---|---|---|---|
| swift-argument-parser | 1.8.2 | Apache-2.0 | Only `murmur-cli` and `murmur-bench` link it (0 symbols in the app) |
| swift-asn1 | 1.7.3 | Apache-2.0 | 0 symbols in the app |
| swift-syntax | 603.0.2 | Apache-2.0 | Build-time macro plugin only |

### Model weights (downloaded at run time, not shipped in the app or the repo)

Licenses come from each Hugging Face model card (`cardData.license`) and its `base_model`, fetched 2026-10-05.

| Model | Used as | License | Upstream | Attribution needed? |
|---|---|---|---|---|
| `FluidInference/parakeet-ultra-coreml` @95eaa59a39 | **Default speech model** | CC-BY-4.0 | `moondream/parakeet-ultra` (CC-BY-4.0) ← `nvidia/parakeet-tdt-0.6b-v3` (CC-BY-4.0) | Yes, CC-BY-4.0 requires credit. Murmur doesn't redistribute the weights (users download them from Hugging Face), but crediting NVIDIA, moondream and FluidInference in the app is the safe default (L3.5). |
| `FluidInference/parakeet-tdt-0.6b-v3-coreml` | Optional | CC-BY-4.0 | `nvidia/parakeet-tdt-0.6b-v3` | Yes |
| `FluidInference/parakeet-tdt-0.6b-v2-coreml` | Optional | CC-BY-4.0 | `nvidia/parakeet-tdt-0.6b-v2` | Yes |
| `FluidInference/phonon-2-coreml` | Optional | CC-BY-4.0 | `FermionResearch/Phonon-2` (CC-BY-4.0) ← parakeet-tdt-0.6b-v3 | Yes |
| `mlx-community/Qwen3.5-4B-4bit` @0e7ffd5c62 | **Default cleanup model** | **Apache-2.0, inferred from upstream.** The conversion repo has no model card, no license metadata and no LICENSE file. Its config matches `Qwen/Qwen3.5-4B` (same architecture, 2560 hidden, 32 layers, 248,320 vocab), and its commit is "Convert Qwen3.5 to MLX Qwen3.5-4B-4bit". `Qwen/Qwen3.5-4B` is Apache-2.0. | `Qwen/Qwen3.5-4B` | Apache-2.0 asks redistributors to include the license. Murmur doesn't redistribute. **Owner check:** accept the inference, or pin a conversion that carries its license. |
| `mlx-community/Qwen3.5-2B-4bit` | Optional | Apache-2.0 | `Qwen/Qwen3.5-2B` | No |
| `mlx-community/Qwen3-4B-Instruct-2507-4bit` | Optional | Apache-2.0 | `Qwen/Qwen3-4B-Instruct-2507` | No |
| `mlx-community/SmolLM3-3B-4bit` | Optional | Apache-2.0 | `HuggingFaceTB/SmolLM3-3B` | No |
| `argmaxinc/whisperkit-coreml` (large-v3 turbo) | Optional | MIT | `openai/whisper-large-v3-turbo` (MIT) | MIT notice, if shown |
| `openai/whisper-large-v3` (tokenizer files only) | With WhisperKit | Apache-2.0 | | No |
| `mlx-community/gemma-3-1b-it-qat-4bit`, `Qwen3.5-0.8B-4bit`, `Qwen3-0.6B-4bit` | Bench and CLI only, not offered in the app | Gemma Terms of Use; Apache-2.0; Apache-2.0 | | n/a for the app |
| Apple speech assets, Apple Intelligence model | Optional | Apple's macOS license | | No, part of macOS |

### Original work

App icon, brand mark, menu bar glyph (`Design/brand/*.svg`, rendered by `Tools/make_icons.py`) and the four sounds (synthesized with numpy by `Tools/make_sounds.py`). The UI icons (`Sources/UI/Components/Icons.swift:41-84`) are the design boards' own 24-pt paths (`UI_REDESIGN.md` §3.6), not an icon library. I spot-checked `mic` and `copy` against Lucide and they differ. All covered by Murmur's MIT license. `numpy` and `cairosvg` are build tools whose output is shipped; their licenses don't reach the output.

### Notes

- **A. FluidAudio's LuxTTS lexicon.** `FluidAudio_FluidAudio.bundle` ships `luxtts_en_us_lexicon.tsv.zz` and `luxtts_en_us_g2p_aux.json`. Murmur doesn't use LuxTTS, but SwiftPM copies the resources in. FluidAudio's docs say the lexicon was "harvested offline from espeak-ng via piper_phonemize" and the clause rules port "espeak's `translate.c`/`dictionary.c` semantics" (`FluidAudio/Documentation/TTS/LuxTts.md:166-180`). espeak-ng is GPL-3.0. FluidAudio is Apache-2.0 and its README says it has no GPL dependencies (`FluidAudio/README.md:637`). Whether lexicon data harvested from GPL software carries the GPL is a question for the owner, not this audit. Options: accept FluidAudio's statement, strip the two files from the app bundle in a build phase, or ask FluidAudio. **Not a redistribution prohibition and not UNKNOWN, so not a stop. Flagged.**
- **B.** The existing `THIRD_PARTY_NOTICES.md` (commit 46d5436) lists the Silero VAD model as downloaded at first launch. The app never loads it (§1a). It also omits XGrammar, dlpack, picojson, fmt, nlohmann/json, metal-cpp, swift-jinja, yyjson and EventSource as shipped components, and lists swift-argument-parser and swift-asn1, which the app doesn't ship. The license texts aren't in the app bundle. L3 fixes all of this.
- **C.** `Package.swift:45` says the UI target "Bundles Source Sans 3 and Newsreader". It bundles Geist, Geist Mono and Newsreader. The comment is stale.

No component found whose license forbids redistribution, and none `UNKNOWN`.

---

## 7. Branding

**"Wispr"** (15 occurrences, all in docs, none in code, assets or in-app copy):

- `SPEC.md:1` (title: "…macOS dictation app (Wispr Flow-style)"), `:9` ("reproduces the behavior and look of Wispr Flow's dictation"), `:15` ("recording the real Wispr Flow app"), `:21` (rule: don't use Wispr's assets), `:100`, `:137`, `:178` ("Flow Bar (Wispr documents these facts)"), `:211`.
- `UI_REDESIGN.md:42` (rule: no Wispr name or assets), `:524`, `:530`.
- `docs/decisions.md:80` (Wispr's sound files never copied).
- `docs/archive/UI_REDESIGN.v1.md:28, 458`.
- README: none. No "clone of …" wording in the README.

**"Flow" as a product name:** only inside "Wispr Flow" above. **"Flow Bar"** is Murmur's own name for its overlay (SPEC §6), but Wispr Flow calls its overlay the "Flow bar", so the name echoes the other product's UI copy, which SPEC rule 1 forbids. It appears in 20 user-facing strings (`Sources/HubUI/Onboarding.swift:25, 239, 817`, `Sources/HubUI/SettingsPages.swift:141, 162, 450`, `Sources/UI/FlowBarModel.swift:137, 360, 366, 373`, `Sources/UI/FlowBarView.swift:278` (accessibility label), `App/Sources/AppDelegate.swift:418, 420, 523, 572, 838`, `App/Sources/FlowBarWiring.swift:56`, and the Debug-only `Sources/HubUI/TokenPanel.swift:68`, `Windows.swift:76`, `DesignGallery.swift:313`), in README (4) and in the docs. The type and file names (`FlowBarModel`, `FlowBarPanel`, …) are internal identifiers. Owner decision; see §8.

**Other marks used descriptively:** Apple, macOS, Apple Intelligence, NVIDIA Parakeet, Qwen, Whisper, Groq, OpenRouter, Hugging Face, Vercel (Geist) all appear as nominative references to the products Murmur uses. Anthropic marks and the Styrene typeface are banned in `docs/archive/UI_REDESIGN.v1.md:28`; none are used.

---

## 8. Mismatches: privacy claims the audit shows are false or unproven

| # | Where | Claim | Finding | Status |
|---|---|---|---|---|
| M1 | Menu footer, `App/Sources/AppDelegate.swift:437-447`; sidebar status tag, `Sources/HubUI/HubShell.swift:141-142` | "on-device engine" / "on-device" | **False when cleanup is Groq or OpenRouter.** `AppInfo.cloud` checks `["groq","openrouter"].contains(cleanupDescription)` (`Sources/HubUI/Windows.swift:94`), but the provider id is `groq:<model>` or `openrouter:<model>` (`Providers.swift:79, 92`), so the check never matches. Transcripts go to the cloud while the menu says "on-device engine". | Code bug. Fix the check (no copy change); L5 |
| M2 | Onboarding, Microphone step, `Sources/HubUI/Onboarding.swift:166` | "Only while you hold the shortcut. Audio is transcribed on this Mac and deleted right after, unless you choose to keep it." | **False by default.** "Keep audio for 14 days" defaults to on (`Settings.swift:167-171`), and step 9 shows it already on. Hands-free records without holding anything. | Copy is false; apply proposed copy in L5 |
| M3 | Onboarding, step 9, `Onboarding.swift:491` | "Either way, audio and transcripts never leave this Mac." | True with the defaults. **False if a Groq or OpenRouter option is chosen**, and "never" is unconditional. | Propose copy; owner approves (L5) |
| M4 | Settings › Data & privacy info card, `SettingsPages.swift:579` | Title "Nothing leaves this Mac" | The detail line correctly covers Groq and OpenRouter, but **the title is false**: Murmur contacts Hugging Face on every launch (§1b), downloads models (§1a, 1c), and may send a Hugging Face token. "Your words stay on this Mac" would be true. | Propose copy (LEGAL_DOCS rule 2 forbids the old title while a connection exists); owner approves |
| M5 | Onboarding, model step, `Onboarding.swift:197` | "…The first time, they download (about 3 GB); after that they load in a few seconds." | **Incomplete.** After the first time, every launch still asks Hugging Face for the cleanup model's file list and can download updated files (§1b). | Propose copy |
| M6 | Onboarding, Input Monitoring step, `Onboarding.swift:184` | "It watches that one key; nothing you type is logged or stored." | The second half is true. **The first half is false**: macOS delivers every key press to the tap, and Murmur also acts on Esc and the other shortcuts (§5). | Propose copy (LEGAL_DOCS L2.3 requires PRIVACY.md to match) |
| M7 | Onboarding, Accessibility step, `Onboarding.swift:174` | "It doesn't read your screen…" | True (no screen capture). But it **does read the text of the field it pastes into** (dictionary suggestions, §3.8) and the selection (Command Mode), which this copy doesn't mention. Unproven by omission, not false. | Propose copy |
| M8 | `NSMicrophoneUsageDescription`, `App/project.yml:32` | "Murmur records your voice while you hold the dictation shortcut and turns it into text on this Mac." | False for hands-free (no holding) and for Groq Whisper (not on this Mac). | Propose string (L5.1) |
| M9 | Onboarding step 9 card, `Onboarding.swift:505`; Settings toggle, `SettingsPages.swift:568` | "Keep nothing: … nothing written to disk" / "Never store anything: No History, no audio, nothing written to disk." | True for dictation content (§2). Settings, model caches and system caches still get written; none hold your words. | OK; PRIVACY.md says "none of your dictations" |
| M10 | `SettingsPages.swift:566` | "Keep audio for 14 days" | Files are deleted at the next launch after 14 days (§2), so they can be older. | Minor; PRIVACY.md states it exactly |
| M11 | README:17 | "Logs hold timings, never text." | True (§4). | OK |
| M12 | README:11; Settings detail line, `SettingsPages.swift:579` | "Local by default… Groq and OpenRouter are optional, behind your own keys." / "…its logs hold timings, never your words." | True. | OK |
| M13 | README:23 | "On first launch Murmur downloads its speech and cleanup models" | True but incomplete (same as M5). | README Privacy section (L4) |
| M14 | `THIRD_PARTY_NOTICES.md` | Lists Silero VAD as downloaded at first launch | False for the app (§6 note B). | Fixed by L3 |
| M15 | Onboarding step 9 card, `Onboarding.swift:498` | "No analytics, no crash reports." | True (§1). | OK |
