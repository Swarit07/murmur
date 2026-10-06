# Legal docs progress

Running log for `LEGAL_DOCS.md`, newest milestone last.

## L0: Audit (2026-10-05)

**Files:** `LEGAL_DOCS.md` (the brief, added to the repo root), `docs/legal-audit.md`, `docs/legal-progress.md`.

**Done when:**
- Audit exists, and every section has findings or an explicit "none found, searched for": **pass.**

**Stopped here (LEGAL_DOCS §1 rule 2, L0 stop condition).** The audit found network connections that `SPEC.md` doesn't describe (audit §1):
- **1a.** Speech model download from Hugging Face on first launch.
- **1b.** Cleanup model: Murmur asks Hugging Face for the model's file list on **every launch**, and downloads updated files if the repo changed.
- **1c.** Other models picked in Settings.
- **1d.** Apple speech assets, downloaded through macOS (opt-in).

1b also sends the user's Hugging Face token if one exists on the Mac (`~/.cache/huggingface/token` or `HF_TOKEN`). No audio, text or settings go to Hugging Face. Groq and OpenRouter are described in SPEC and are off by default. `PRIVACY.md` waits for the owner's decision on how to describe these connections, or whether to change them.

**Couldn't determine:**
- **License of `mlx-community/Qwen3.5-4B-4bit`, the default cleanup model.** The repo has no card or license. Apache-2.0 is inferred from `Qwen/Qwen3.5-4B`, whose config matches. Owner check.
- **FluidAudio's LuxTTS lexicon.** Murmur doesn't use it, but it ships in the app bundle. FluidAudio's docs say it was harvested from espeak-ng (GPL-3.0) output, while FluidAudio is Apache-2.0 and says it has no GPL dependencies. Owner decision (audit §6 note A).
- **Apple on-device speech engine permission.** Whether picking it on macOS 26 triggers a Speech Recognition prompt. Owner check (audit §5).

**Mismatches found (audit §8):**
- **M1.** Menu footer and sidebar tag say "on-device" while cleanup runs on Groq or OpenRouter. This is a code bug; fix in L5.
- **M2.** Mic onboarding copy is false by default. Apply the new copy in L5.
- **M3–M8.** Proposed copy below, awaiting owner approval.
- **M14.** Stale notices; fixed by L3.

**Proposed copy (for L5; final wording depends on the network decision):**

| # | Where | New copy |
|---|---|---|
| M2 | Onboarding › Microphone | "Murmur listens only while you dictate. Its built-in speech model runs on this Mac. You'll choose whether to keep recordings in a later step." |
| M3 | Onboarding › Data | "Either way, your audio and transcripts stay on this Mac unless you pick a cloud option in Settings." |
| M4 | Settings › Data & privacy card title | "Your words stay on this Mac" (detail adds: "Murmur downloads its models from Hugging Face and checks the cleanup model for updates when it starts. No audio or text is sent.") |
| M5 | Onboarding › Models | "Murmur's speech and cleanup models run on this Mac. The first time, they download from Hugging Face (about 3 GB). After that they load in a few seconds, and Murmur checks for cleanup model updates when it starts." |
| M6 | Onboarding › Input Monitoring | "Input Monitoring is how Murmur knows [hotkey] is being held down — and released. macOS shows Murmur every key press; it reacts only to its shortcuts and Esc. Nothing you type is logged or stored." |
| M7 | Onboarding › Accessibility | "Accessibility lets Murmur place text at your cursor in any app. It reads only the app and text box you're dictating into, never captures your screen, and never types into password fields." |
| M8 | `NSMicrophoneUsageDescription` | "Murmur listens only while you dictate. Its built-in speech model runs on this Mac." |
