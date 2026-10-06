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
| M6 | Onboarding › Input Monitoring | "Input Monitoring is how Murmur knows [hotkey] is being held down — and released. macOS shows Murmur every key press; it uses them only to spot its shortcuts. Nothing you type is logged or stored." |
| M7 | Onboarding › Accessibility | "Accessibility lets Murmur place text at your cursor in any app. It reads only the app and text box you're dictating into, never captures your screen, and never types into password fields." |
| M8 | `NSMicrophoneUsageDescription` | "Murmur listens only while you dictate. Its built-in speech model runs on this Mac." |

**Owner decisions (2026-10-05):**
- Hugging Face: document it as it is, with no code changes.
- FluidAudio's LuxTTS lexicon: keep it and note it in the notices.
- "Flow Bar": keep the name. Add the not-affiliated line, and replace only the literal "Wispr" mentions.

## L1: LICENSE (2026-10-05)

**Files:**
- `Package.swift`: license comment; the UI target bundles `Resources/Legal`; fixed the stale font comment.
- `README.md`: MIT badge.
- `Sources/UI/Resources/Legal/LICENSE`: a copy of the root `LICENSE`.
- `Sources/UI/LegalDocuments.swift`: reads the bundled files.
- `Tests/UITests/LegalDocumentsTests.swift`.

**Done when:**
- `LICENSE` is the standard MIT text with `Copyright (c) 2026 Swarit Sheel`: **pass.** Compared with SPDX's MIT text, whitespace-normalized. It was already correct from commit 46d5436, so it wasn't changed.
- `LICENSE` is in the built `.app`: **pass.** A Release build (ad-hoc signed, `App/build`) has `Murmur.app/Contents/Resources/murmur_UI.bundle/Contents/Resources/Legal/LICENSE`, byte-identical to the repo's.
- `Scripts/test.sh --filter LegalDocuments`: 3 tests pass. One of them fails if the bundled copy drifts from the root `LICENSE`.

**For the owner:** confirm the copyright line, "Copyright (c) 2026 Swarit Sheel".

## L2: PRIVACY.md (2026-10-05)

**Files:**
- `PRIVACY.md` (new).
- `docs/legal-audit.md`: §1 adds two tests, the per-launch check and the offline run.

**Done when:**
- Every section maps to an audit finding (`<!-- audit: §n -->`): **pass.** A script checked that all 10 sections cite real audit sections.
- No section claims more than the audit shows: **pass.** The headline isn't "runs entirely on your Mac" (connections exist). It's "with those built-in models, your audio and transcripts stay on this Mac". The Hugging Face check, the token pickup, the Apple asset download and the Groq/OpenRouter payloads are each named, with what's sent and how to stop it.

**Tests run (audit §1):**
- The cleanup model contacts Hugging Face on every load even when fully cached: two runs against a local stand-in server, two requests.
- With outbound IP blocked, `murmur-cli` loads Parakeet ultra and Qwen3.5 4B from disk and transcribes and cleans a synthetic clip.

**For the owner:**
- Run one dictation in the app with Murmur's network blocked (Little Snitch, LuLu, or a firewall rule), after the models are downloaded. It should work like the CLI test did. I didn't run the app itself, because it needs your permissions and would disturb your running copy.
- `PRIVACY.md` links to `SECURITY.md`, which L4 adds.

## L3: Third-party notices (2026-10-05)

**Files:**
- `Scripts/gen-notices.py` (generator, standard-library Python) and `Scripts/test_gen_notices.py` (15 tests).
- `Licenses/packages.json` (per package: name, use, SPDX id, shipped or not, license files).
- `Licenses/manual.json` (fonts, models, shared license texts).
- `Licenses/packages/<identity>/…`: verbatim license and NOTICE files from each checkout, plus FluidAudio's ThirdPartyLicenses and text-processing-rs's LICENSE, NOTICE and THIRD-PARTY-LICENSES (v0.3.1). Also the picojson and DLPack notices, extracted from their headers.
- `Licenses/{OFL-Geist,OFL-Newsreader,Apache-2.0,CC-BY-4.0,MIT-OpenAI-Whisper}.txt`.
- `THIRD_PARTY_NOTICES.md` (regenerated).
- `Sources/UI/Resources/Legal/{THIRD_PARTY_NOTICES.md,notices.json,PRIVACY.md}`.
- `Sources/UI/LegalDocuments.swift` (privacy, notices) and two more tests in `Tests/UITests/LegalDocumentsTests.swift`.
- `.github/workflows/notices.yml` (new CI).
- `Scripts/test.sh` (runs the check before the unit tests).
- `docs/legal-audit.md` §6: adds the NemoTextProcessing.xcframework that FluidAudio links (note D).

**Done when:**
- The generator runs clean: **pass.**
- The CI check passes: **pass**, locally. `gen-notices.py --check` exits 0 and the generator tests pass. The workflow runs both on GitHub; it hasn't run there yet because the branch isn't pushed.
- The notices are in the built `.app`: **pass.** An incremental Release build has `murmur_UI.bundle/Contents/Resources/Legal/` with `LICENSE`, `PRIVACY.md`, `THIRD_PARTY_NOTICES.md` and `notices.json`, the first three byte-identical to the repo.
- CC BY model credit for the in-app Acknowledgements (L3.5): `notices.json` carries the attribution for Parakeet ultra, v3, v2 and phonon2 (NVIDIA, moondream, Fermion Research, FluidInference). L5 shows it.

**What changed from the old notices:**
- Removed the Silero VAD model; the app never downloads it.
- Moved swift-argument-parser, swift-asn1 and swift-syntax to "used only to build".
- Added XGrammar, picojson, DLPack, {fmt}, nlohmann/json, metal-cpp, swift-jinja, yyjson, EventSource and NemoTextProcessing.
- Every component now carries its full license text, not just a name.

**Couldn't determine:** per-crate notices for the Rust crates inside NemoTextProcessing.xcframework. Upstream only summarizes them (audit §6 note D).

**When dependencies change:** after `Package.resolved` changes, run `Scripts/gen-notices.py --refresh-from App/build/SourcePackages/checkouts`. For a new package, add its entry to `Licenses/packages.json` first. CI fails until this is done.

## L4: SECURITY.md and README (2026-10-05)

**Files:**
- `SECURITY.md` (new).
- `README.md`: Privacy, Permissions, Not affiliated and License sections. Install step 3 now links to Permissions instead of repeating them.
- "Wispr" replaced with "the reference app" in `SPEC.md` (8 places), `UI_REDESIGN.md` (3), `docs/decisions.md` (1) and `docs/archive/UI_REDESIGN.v1.md` (2). Each sentence keeps its meaning.

**Done when:**
- Both files exist: **pass.**
- `grep -ri wispr` in user-facing copy returns only the not-affiliated line: **pass.** Checked README, PRIVACY, SECURITY, THIRD_PARTY_NOTICES, `Sources/`, `App/Sources/`, `App/project.yml` and `Design/`; the only hit is README:183. The name still appears in three process documents that have to name it: `LEGAL_DOCS.md` (the brief), and the audit and this log (they record where it was).

**Kept on purpose (owner decision):**
- "Flow Bar" in about 20 app strings, the README and docs.
- The internal identifiers `FlowBarModel`, `FlowBarPanel`, `FlowBarView`, `FlowBarWiring` and `FlowBarStateTests`, which renaming wouldn't make clearer.

**For the owner:**
- `[SECURITY_CONTACT]` in `SECURITY.md` needs an email address.
- The repo is **private**, so GitHub's private vulnerability reporting isn't available, and the issue links in `PRIVACY.md` and `SECURITY.md` only work for collaborators. Once it's public, you can turn on Settings › Security › Private vulnerability reporting and point `SECURITY.md` at it.

## L5: In-app disclosures (2026-10-05)

**Files:**
- `Sources/HubUI/LegalViews.swift` (new): the document dialog, a small Markdown renderer for `PRIVACY.md`, the Acknowledgements list, and onboarding's privacy panel.
- `Hub.swift`: `document`, `open(_:fromHelp:)`.
- `HubShell.swift`: the dialog overlay, Esc, and Help & setup › About with Privacy and Acknowledgements rows.
- `SettingsPages.swift`: the Privacy row and the info-card copy.
- `Onboarding.swift`: copy, the "Read the privacy notes" link, the overlay.
- `DesignGallery.swift`: info-card copy.
- `Windows.swift`: the cloud-detection fix.
- `Sources/UI/LegalDocuments.swift`: `reflow` for license text.
- `Sources/UI/Components/MDialog.swift`: optional width.
- `Tokens+Geometry.swift`: `documentDialogWidth`.
- `App/project.yml`: `NSMicrophoneUsageDescription`.
- `Sources/MurmurSnap/main.swift`: captures the new views.
- Tests: `Tests/HubUITests/LegalViewsTests.swift` (new), `Tests/UITests/LegalDocumentsTests.swift`.
- `Artifacts/ui/sheets/legal-hub.png`, `legal-onboarding.png`.
- `docs/legal-audit.md`: adds M16.

**Done when:**
- Token lint passes: **pass.** `Scripts/check-tokens.sh`: "token lint: pass".
- Snapshots exist: **pass.** `murmur-snap` rendered 87 images with no blanks. The two contact sheets cover Help & setup, the Privacy dialog, Acknowledgements (closed, and with one row open), Settings › Data & privacy, Settings › General and four onboarding steps, in light and dark.
- Every in-app privacy claim matches `PRIVACY.md`: **pass** for the claims fixed below. M5 and M7 are true but less complete than `PRIVACY.md`; proposed copy is below.
- Unit tests: `Scripts/test.sh` passes, 204 tests in all. It includes the notices check, and 14 new tests cover the parser, the reflow, both paths of the cloud check, and the dialog state.
- The Release build has the new microphone string in its `Info.plist` and the legal files in its bundle.

**Changes applied, because the old claim was false (audit §8):**

| # | Where | Was | Now |
|---|---|---|---|
| M1 | Menu footer, sidebar status tag | "on-device engine" while cleanup ran on Groq or OpenRouter | Code fix: `AppInfo.cloud` matches `groq:<model>` and `openrouter:<model>`. The copy is unchanged. |
| M2 | Onboarding › Microphone | "Only while you hold the shortcut. Audio is transcribed on this Mac and deleted right after, unless you choose to keep it." | "Murmur listens only while you dictate. Its built-in speech model runs on this Mac. You'll choose whether to keep recordings in a later step." |
| M3 | Onboarding › Data | "Either way, audio and transcripts never leave this Mac." | "Either way, your audio and transcripts stay on this Mac unless you pick a cloud option in Settings." |
| M4 | Settings › Data & privacy card | "Nothing leaves this Mac" | Title "On this Mac by default". The detail adds the Hugging Face downloads and launch check. |
| M6 | Onboarding › Input Monitoring | "It watches that one key; …" | "macOS shows Murmur every key press; it uses them only to spot its shortcuts. Nothing you type is logged or stored." |
| M8 | `NSMicrophoneUsageDescription` | "…while you hold the dictation shortcut and turns it into text on this Mac." | "Murmur listens only while you dictate. Its built-in speech model runs on this Mac." |
| M16 | Settings › General card | "Nothing leaves this Mac" / "Audio and transcripts stay on-device." | "On this Mac by default" / "With the built-in models, your audio and transcripts stay on this Mac. Retention and cloud keys live under Data & privacy." |

**Proposed, not applied (the old copy is true, just incomplete). Owner to approve:**
- **M5**, Onboarding › Models: "Murmur's speech and cleanup models run on this Mac. The first time, they download from Hugging Face (about 3 GB). After that they load in a few seconds, and Murmur checks for cleanup model updates when it starts."
- **M7**, Onboarding › Accessibility: "Accessibility lets Murmur place text at your cursor in any app. It reads only the app and text box you're dictating into, never captures your screen, and never types into password fields."

**Not run here (need the app running with your permissions):** the 50-trial focus test and the latency budget. No dictation code changed, but please run both from the Debug menu and `murmur-bench e2e` before merging.

## L6: Distribution notes (2026-10-05)

**Files:** `docs/distribution.md` (new).

**Done when:**
- The file exists: **pass.**

**What it covers:**
- **GitHub releases and Homebrew:** a Developer ID certificate, the hardened runtime with the audio-input entitlement, notarization, the license already in the bundle, a public download URL, and a cask `zap` list taken from `PRIVACY.md`.
- **Mac App Store:**
  - Candidate App Privacy answers. Not "Data Not Collected", because audit §1 found connections; the developer collects nothing, and the opt-in Groq/OpenRouter traffic is an owner decision.
  - A privacy manifest is needed.
  - The App Sandbox conflicts with the synthetic paste, Accessibility reads and the model cache paths. Flagged, not solved.
- **Landing page:** today's `murmur-website` loads Google Fonts and calls the GitHub API from the visitor's browser. It needs its own short notice, or self-hosted fonts and GitHub numbers fetched at build time. That repo wasn't changed.

## Owner follow-ups (2026-10-05)

The owner gave swarit.sheel@gmail.com as the contact address and asked for whatever else is needed.

**Files:**
- `SECURITY.md`, `PRIVACY.md` (contact).
- `Sources/HubUI/Onboarding.swift` (M5, M7).
- `Sources/HubUI/LegalViews.swift`: email links stay clickable.
- `Scripts/rust-crate-notices.py` (new) and `Licenses/packages/fluidaudio/text-processing-rs/RUST-CRATES.md`.
- `Licenses/packages.json`, the regenerated notices and bundled copies.
- `Scripts/test_gen_notices.py` (5 new tests).
- `Tests/HubUITests/LegalViewsTests.swift`.
- `Artifacts/ui/sheets/legal-onboarding.png`.
- `docs/legal-audit.md`.

**Done:**
- **Security contact:** `[SECURITY_CONTACT]` is now swarit.sheel@gmail.com. `PRIVACY.md` also gives it as the place for questions, since the repo's issues are private.
- **Copyright line:** "Copyright (c) 2026 Swarit Sheel" stands.
- **M5 and M7 applied.** Onboarding's models step now mentions Hugging Face and the launch check. The Accessibility step now says Murmur reads only the app and text box you're dictating into. Every in-app privacy claim now matches `PRIVACY.md` with no proposals left open. Snapshots in `legal-onboarding.png`.
- **Rust crates in NemoTextProcessing:** notices for all 30 compiled-in crates, generated from the lockfile and the crates' own license files (audit §6 note D). Where a crate offers MIT, Murmur takes it under MIT and reproduces only the MIT text. That keeps the notices at 48 KB, not 440 KB.
- **Apple on-device speech:** no Speech Recognition permission needed. Tested; see audit §5.

**Still the owner's:**
- Make the repo public if you want the release, issue and advisory links to work for everyone.
- Run one dictation with Murmur's network blocked.
- Run the 50-trial focus test and `murmur-bench e2e` on a build of this branch. No dictation, Flow Bar or insertion code changed.
