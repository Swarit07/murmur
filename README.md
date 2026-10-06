# Murmur

A private, on-device dictation app for macOS. Hold a key, speak, let go, and the words appear, cleaned up and punctuated, wherever your cursor is.

<p align="center">
  <a href="docs/media/murmur-demo.mp4"><img src="docs/media/murmur-demo-preview.gif" width="820" alt="Murmur turning “um so can we push the sync to thursday — no wait, friday — and uh loop in priya” into “Can we push the sync to Friday and loop in Priya?”"></a>
  <br>
  <sub><a href="docs/media/murmur-demo.mp4"><b>▶ Watch the 20-second demo</b></a> · sound on</sub>
</p>

- **Local by default.** Speech recognition (NVIDIA Parakeet via FluidAudio, on the Neural Engine) and cleanup (Qwen3.5 4B via MLX, on the GPU) both run on the Mac. Groq and OpenRouter are optional, behind your own keys.
- **Fast.** Across 38 real dictations, release to text was p50 0.62 s and p95 1.1 s.
- **Safe with your words:**
  - A guard checker inserts the rule-cleaned transcript whenever the model changes a number, name, URL or negation.
  - The clipboard is restored after every paste.
  - Password fields are never typed into.
  - Logs hold timings, never text.

The full product spec is in [SPEC.md](SPEC.md). Progress against it is tracked in [docs/STATUS.md](docs/STATUS.md).

## Install

You need an Apple silicon Mac with macOS 14 or later. On first launch Murmur downloads its speech and cleanup models (about 3 GB), so the first start takes a few minutes.

1. Download `Murmur.zip` from the [latest release](../../releases/latest), unzip it, and drag `Murmur.app` into Applications.
2. Open it. Murmur isn't notarized by Apple (that needs a paid developer account), so macOS blocks the first launch once:
   - **macOS 15 or later:** after the warning, open System Settings › Privacy & Security, scroll down to "Murmur was blocked", and click **Open Anyway**.
   - **macOS 14:** right-click Murmur in Applications, choose **Open**, then **Open** again.
   - Or, in Terminal: `xattr -dr com.apple.quarantine /Applications/Murmur.app`
3. Follow the short setup. Murmur asks for three permissions:
   - **Microphone**, to hear you;
   - **Accessibility**, to type into the app you're using;
   - **Input Monitoring**, to notice the dictation key.

Prefer to check the code and build it yourself? See [Build from source](#build-from-source).

## What works today

- **Dictation:**
  - Push-to-talk (Fn, or Control+Option), hands-free (Fn+Space, double-tap, or a click on the Flow Bar), and Esc to cancel with Undo.
  - Custom shortcuts: any key, chord, modifier, Caps Lock or mouse button.
  - Microphone choice with a live level meter.
- **Cleanup:**
  - None, Light and Medium levels, plus an AI edits master switch.
  - Self-corrections ("at 2, actually 3"), spoken punctuation ("new paragraph"), and Smart Formatting (numbered lists, paragraphs).
  - A time limit that never holds up the paste.
- **Personalization:**
  - A Dictionary with "Heard as" spellings and safe near-miss matching.
  - Suggestions to add a word when you correct one.
  - Snippets that cleanup can't alter.
  - Styles per app category (Personal, Work, Email, Other; web apps by address).
  - Language choice.
- **Command Mode** (Settings › Experimental): hold Fn+Control and say "make this friendlier" or "translate to Spanish". Murmur rewrites the selection in place (one ⌘Z undoes it), or drafts at the cursor.
- **Insertion:**
  - One paste per dictation, so one ⌘Z removes it.
  - Layout-independent ⌘V.
  - Focus guard.
  - ⌃⌘V pastes the last transcript; ⌃⌘C copies it.
  - Optional "press enter" at the end.
  - Typing instead of pasting for apps you list.
- **App:**
  - Menu-bar app.
  - The Flow Bar overlay, which never takes focus.
  - The Murmur window: Home and History, Dictionary, Snippets, Style, and Settings.
  - Onboarding.
  - A permission watchdog.
  - Launch at login.
  - Never-store mode.
  - Auto-stop at 20 minutes.
  - Model unloading after 10 idle minutes (on by default; can be turned off in Settings › System).

## Build from source

**Requirements:**
- An Apple silicon Mac on macOS 14 or later (developed on macOS 27).
- Xcode 27 (Swift 6.4), set with `xcode-select -s`, plus the Metal Toolchain component.
- `xcodegen` (`brew install xcodegen`).

The models download on first launch: Parakeet is about 0.5 GB and Qwen3.5 4B 4-bit about 2.5 GB.

**Build and install:**

```bash
MURMUR_TEAM=ABCDE12345 Scripts/install-app.sh
```

This builds the Release app, installs it to `~/Applications/Murmur.app` and starts it. Add `--system` to also copy it to `/Applications`.

**Signing:**
- `MURMUR_TEAM` is your Apple Development team ID (Xcode › Settings › Accounts; a free Apple account works). A stable signature lets macOS keep Murmur's permissions across rebuilds.
- With no Apple account, use `MURMUR_TEAM=adhoc Scripts/install-app.sh`. This signs the app ad hoc, so macOS asks for Accessibility and Input Monitoring again after each rebuild.
- Without `MURMUR_TEAM`, the build uses the maintainer's team from `App/project.yml`.

```bash
Scripts/test.sh
```

This runs the unit tests (Swift Testing; MLX is excluded so it runs without Metal).

```bash
swift build -c release --scratch-path .build-mlx
```

This builds the command-line tools with MLX: `murmur-cli` and `murmur-bench`.

### Benchmarks and gates

`murmur-bench` holds the measurements behind every milestone gate. It uses the recorded corpus in `corpus/` (the audio stays local and is git-ignored):

| Command | Measures |
|---|---|
| `murmur-bench run` / `report` | Engine WER and latency, cleanup correction rate and fact changes (M0) |
| `murmur-bench cleanup-pass --provider mlx:qwen3.5-4b --smart-formatting` | C2 backtracking (27/30 gate), C5, C7 |
| `murmur-bench guard-test` | Guard blocks every injected change (C5) |
| `murmur-bench stall-test` | Stalled model still lands text within 1.5 s (C6) |
| `murmur-bench vocab-test --pipeline mlx:qwen3.5-4b` | Dictionary recognition (T4) |
| `murmur-bench vocab-false-test` | Dictionary words appearing where nobody said them (must be 0) |
| `murmur-bench style-test` | Styles per category on cleaned corpus sentences (S4 gate) |
| `murmur-bench command-test` | Command Mode quality: 16 instructions with checks |
| `murmur-bench reload-test` | MLX memory across model reloads |
| `murmur-bench long-test` | Cleanup time on 34–60-word dictations |
| `murmur-bench punctuation-test` | Spoken punctuation (C4) |
| `murmur-bench e2e` | Release-to-paste latency (replays into TextEdit; needs Accessibility for the terminal) |

In the app, turn on **Settings › System › Debug menu** to get:
- **Run self-test in TextEdit:** spoken phrases go through the real pipeline and are checked when read back.
- **Save window snapshots:** every page at three sizes, in light and dark.
- **Run focus test:** 50 trials.
- **Force Flow Bar state** and the **Token panel**.

## Layout

| Path | What |
|---|---|
| `Sources/Core` | State machine, text metrics, `SpellingMatcher`, `CorrectionDetector`, recording limits, signposts |
| `Sources/Hotkey` | Shortcut recognizer, event tap, Caps Lock monitor, global hot keys |
| `Sources/Audio` | Recorder (AVAudioEngine, device changes), WAV, resampler |
| `Sources/SpeechEngines` | Parakeet, Whisper, Apple Speech, Groq Whisper behind one protocol |
| `Sources/Cleanup` | Rules, prompts (cleanup and Command Mode), guard checker, styles, runner with time limit, providers |
| `Sources/CleanupMLX` | Local LLMs through mlx-swift-lm, with prefix KV cache |
| `Sources/Context`, `Sources/Insertion` | Focus snapshot, clipboard transaction, paste keystroke, smart spacing |
| `Sources/Store` | History, dictionary and snippets (SQLite through GRDB), settings, Keychain |
| `Sources/UI` | Flow Bar panel, view and tokens |
| `Sources/Pipeline`, `Sources/MurmurKit` | Catalogs, corpus, and the `DictationController` that wires everything together |
| `App/` | The macOS app target (XcodeGen): Hub, onboarding, menu, self-test |
| `Sources/MurmurCLI`, `Sources/MurmurBench` | Command-line spike and benchmark tool |
| `Tests/` | Unit tests: Core, Hotkey, Store, Cleanup, Insertion, UI |
| `docs/` | Status, decisions, milestone reports and gate instructions |

## Docs

- [docs/STATUS.md](docs/STATUS.md): where every milestone and requirement stands, what was skipped or deferred, and the work log.
- [docs/decisions.md](docs/decisions.md): every design decision, with the measurement behind it.
- Milestone reports:
  - [M0 results](docs/m0-results.md)
  - [M1](docs/m1-report.md)
  - [M2](docs/m2-report.md)
  - [M3](docs/m3-report.md)
  - [M4 QA pass](docs/m4-qa.md)
  - [M4 gate steps](docs/m4-gate.md)
  - [M5](docs/m5-report.md)
  - [M6](docs/m6-report.md)

## Branches

`main` holds the newest work. `milestone-0` … `milestone-N` mark where each milestone's work lives. Tags mark each gate: `m0-passed`, `m1-done`, `m2-passed`, `m3-passed`, `m5-passed`.

## Original work

Murmur's name, icon, sounds and copy are original. It does not use any other product's assets.
