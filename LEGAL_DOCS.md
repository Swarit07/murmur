# LEGAL_DOCS.md — Murmur license, privacy and disclosure pass (master prompt)

Put this file in the repo root next to `SPEC.md` and `UI_REDESIGN.md`. Read all three before writing anything.

Murmur is a free, open-source, MIT-licensed macOS dictation app. It has no accounts, no payments and no server of its own. This task adds the documents and in-app disclosures an app like this should ship with. **No dictation behavior changes. No new networking.**

**Every claim must be true of the code as it is.** You are not writing aspirational policy. You are describing what the app actually does, found by auditing the repo. If the code and a claim in this file disagree, the code wins and you report the mismatch.

**Where files disagree:** `SPEC.md` hard rules win, then this file, then `UI_REDESIGN.md` (for any in-app UI), then your judgment.

---

## 0. What this task does and doesn't produce

| Produce | Don't produce |
| --- | --- |
| `LICENSE` (check / fix) | A Terms of Service. The MIT license's warranty disclaimer and liability limit cover this; there is no service or account to govern |
| `PRIVACY.md` | Cookie banners, consent flows, or a GDPR "data controller" section for data the app never collects |
| `THIRD_PARTY_NOTICES.md` and a generator script | Invented legal citations, statute names, or "compliant with X" claims |
| `SECURITY.md` | Any telemetry, analytics, or network code |
| README sections: Privacy, License, Not affiliated | Wispr's name or logo anywhere except one plain "not affiliated" line |
| In-app: permission strings, Acknowledgements, privacy links | Restyled native permission prompts |

Add one line near the top of `PRIVACY.md` and `docs/legal-audit.md`: *"Written by the maintainer, not a lawyer."*

---

## 1. Hard rules

1. **Audit first, write second.** No document is written until `docs/legal-audit.md` exists (L0).
2. **Fail closed on network.** If the audit finds any outbound connection, the privacy docs must name it: what is sent, to whom, when, whether it's optional, and how to turn it off. Never write "nothing leaves this Mac" while a connection exists. If a connection exists that `SPEC.md` doesn't mention, **stop and ask** the owner before writing `PRIVACY.md`.
3. **One source of truth for privacy copy.** The in-app claims (onboarding step 9, the Settings info card "Nothing leaves this Mac", the menu footer "on-device engine") must match `PRIVACY.md`. If any of them would become false, report it and propose new copy; don't change it silently.
4. **Every bundled third-party thing is attributed**: Swift packages, fonts, the speech model's code *and its weights* (licensed separately; check both), sound-generation libraries if their output is shipped, and any icons not drawn in-house.
5. **License texts ship inside the app bundle**, not only in the repo. The OFL requires it for the fonts; MIT requires it for MIT code.
6. **Plain language.** Sentence case, short sentences, same voice as `UI_REDESIGN.md` §2.10. No legalese beyond the license texts themselves.
7. **Token rules still apply** to any UI you add (`UI_REDESIGN.md` §2, §8 lint).

---

## 2. Milestones

Branch `legal-docs`. One commit per milestone, message `L<n>: <title>`. Run them in order without waiting for the owner. After each, append a short report (§4) to `docs/legal-progress.md`.

### L0 — Audit

Write `docs/legal-audit.md` with these sections. Cite file paths and line numbers for every finding.

1. **Network.** Search the whole repo and all resolved dependencies for outbound connections: `URLSession`, `URLRequest`, `NWConnection`, `NWPathMonitor`, `CFNetwork`, `Network.framework`, `WKWebView`, `NSWorkspace.open` with `http`, `Process` calling `curl`/`git`, Sparkle (`SUFeedURL`, `SPUUpdater`), crash and analytics SDKs (Sentry, Crashlytics, PLCrashReporter, TelemetryDeck, PostHog, Firebase), and any model, language-pack or update download URL. For each: the destination, what's sent, the trigger, whether it's on by default, and whether the user can turn it off. If none are found, say so and list the patterns searched.
2. **Data at rest.** Every file, database, `UserDefaults` key, Keychain item and cache the app writes: the path, what's in it (transcripts, raw audio, dictionary, snippets, styles, history, settings, logs), the retention rule, and how it's deleted (in-app control, uninstall, or manually).
3. **Clipboard and text access.** When Murmur reads or writes the pasteboard, whether it restores the previous clipboard, and whether any text read through Accessibility is stored.
4. **Logs.** What `os_log` / `Logger` / file logs contain. Flag any log line that can contain transcript text, audio paths, app names or window titles, and whether it uses `.private`.
5. **Permissions.** Each TCC permission requested (Microphone, Accessibility, Input Monitoring, any other), the exact `Info.plist` usage strings, and what the app does with each permission.
6. **Third-party components.** A table: name, version, what it's used for, license (SPDX id), where the license text lives, and whether it's bundled in the app. Include the speech engine code, **its model weights** (find the weights' license on the model card or upstream repo; if it can't be determined, mark it `UNKNOWN — owner must check`), Geist, Geist Mono, Newsreader, and every Swift package in `Package.resolved`.
7. **Branding.** Every occurrence of "Wispr", "Flow" (as a product name) or other trademarks in code, copy, assets and docs.
8. **Mismatches.** Every in-app or README claim about privacy that the audit shows is false or unproven.

*Done when:* the audit exists and every section has either findings or an explicit "none found, searched for: …".

**Stop and ask** if section 1 finds a connection not described in `SPEC.md`, or section 6 finds a component whose license forbids redistribution or is `UNKNOWN`.

### L1 — LICENSE

- Ensure `LICENSE` is the standard MIT text, unmodified, with `Copyright (c) 2026 Swarit Sheel` (keep any existing year range if older). Add a note in the progress report asking the owner to confirm the copyright line.
- Add `"license": "MIT"` metadata wherever the project has a place for it (README badge, `Package.swift` comment).
- Copy `LICENSE` into the app bundle's resources.

*Done when:* `LICENSE` is correct and present in the built `.app`.

### L2 — PRIVACY.md

Build it from the audit only. Structure:

1. **Summary** (3–5 sentences): what Murmur does with your voice, in plain words. The headline is true only if L0 §1 found no connections: "Murmur runs entirely on your Mac. Your audio and transcripts never leave it."
2. **What Murmur stores, and where.** A table from L0 §2: item, location, how long, how to delete.
3. **Permissions and why.** One short paragraph per permission. Input Monitoring must say plainly which keys are watched and that typing isn't logged, matching the onboarding copy.
4. **Network.** Either "Murmur makes no network connections" with a one-line note on how a reader can verify it (e.g. Little Snitch, or deny network in a firewall and confirm it still works), or one subsection per connection from L0 §1.
5. **Clipboard.** From L0 §3.
6. **Logs.** What's logged, where, and that transcript text is never logged (fix the code first if L0 §4 found it is: change it to `.private` or remove it, and record the change; this isn't a dictation-behavior change).
7. **Optional features** (only those that exist): keep-audio retention, crash reports, update checks. Default state and where to switch each.
8. **Deleting everything.** Exact steps: the in-app control if one exists, then the paths to remove, then `tccutil reset All <bundle id>` for permissions.
9. **Children, selling data, ads.** One sentence: Murmur collects nothing, so there's nothing to sell or share.
10. **Changes and contact.** Changes are tracked in this file's git history; questions go to GitHub issues (or the address in `SECURITY.md` for anything sensitive).
11. **Last updated** date.

*Done when:* every statement in `PRIVACY.md` maps to an L0 finding (add an HTML comment `<!-- audit: §n -->` after each section), and no section claims more than the audit shows.

### L3 — Third-party notices

1. `scripts/gen-notices.sh` (or a Swift/Python script, whichever the repo already uses) reads `Package.resolved` and a hand-maintained `Licenses/manual.json` (fonts, model weights, anything not a Swift package) and writes `THIRD_PARTY_NOTICES.md` with each component's name, version, URL, SPDX id and full license text.
2. Put each full license text under `Licenses/` (e.g. `Licenses/OFL-Geist.txt`, `Licenses/OFL-Newsreader.txt`).
3. Bundle `THIRD_PARTY_NOTICES.md` (or the `Licenses/` folder) in the app.
4. Add a CI check that fails if `Package.resolved` lists a package missing from the notices.
5. If any license requires attribution in a visible place (e.g. CC-BY model weights), make sure the in-app Acknowledgements (L5) shows it.

*Done when:* the generator runs clean, the CI check passes, and the notices are in the built `.app`.

### L4 — SECURITY.md and README

- **`SECURITY.md`:** how to report a vulnerability privately (GitHub private vulnerability reporting if enabled; otherwise `[SECURITY_CONTACT]` placeholder for the owner), what's in scope (anything touching Input Monitoring, Accessibility, the pasteboard, stored transcripts), expected response time "best effort, usually within a week", and that there's no bug bounty.
- **README:** add
  - **Privacy:** two sentences + link to `PRIVACY.md`.
  - **Permissions:** the three permissions, one line each.
  - **License:** "MIT. See `LICENSE`. Third-party components are listed in `THIRD_PARTY_NOTICES.md`."
  - **Not affiliated:** "Murmur is an independent open-source project. It isn't affiliated with or endorsed by Wispr or any other dictation product." Use this line instead of any "clone of …" wording elsewhere in the README.
- Replace every L0 §7 branding hit in user-facing copy and docs (leave git history alone). Internal code identifiers may stay if renaming would change behavior; list them.

*Done when:* both files exist and `grep -ri wispr` in user-facing copy returns only the not-affiliated line.

### L5 — In-app disclosures

UI follows `UI_REDESIGN.md` tokens and components; no new visual language.

1. **Permission strings.** Make sure `NSMicrophoneUsageDescription` (and any other required usage keys) exist and match the onboarding copy, e.g. "Murmur listens only while you hold your dictation shortcut. Audio is transcribed on this Mac." Keep them under ~2 lines.
2. **Acknowledgements.** In the Help & setup sheet, add an "Acknowledgements" row (navigate `MSelect` style) opening a scrollable view of the bundled notices: component name in `label`, license in `meta`, full text in `body` on `bg-sunken`, collapsed by default. Include "Murmur is released under the MIT License" and the copyright line.
3. **Privacy links.** In Settings › Data & privacy, add a row "Privacy" with a `hint` summary and a link button opening the bundled `PRIVACY.md` (rendered in-app; don't require a network fetch). Link it from onboarding step 9 too, as a `link`-style button "Read the privacy notes".
4. **Copy consistency.** Fix or report every L0 §8 mismatch. Proposed copy changes go in the progress report for the owner to approve; only apply them if the old copy is false.
5. Snapshots of the new views in light and dark via `murmur-snap`.

*Done when:* the token lint passes, snapshots exist, and every in-app privacy claim matches `PRIVACY.md`.

### L6 — Distribution notes

Write `docs/distribution.md` (don't do any of this, just document it):

- **GitHub releases / Homebrew:** what's needed (signing, notarization, `LICENSE` in the bundle). No privacy policy URL required.
- **Mac App Store** (if ever): needs a hosted privacy policy URL and the App Privacy questionnaire. Fill in what the answers would be from the audit ("Data Not Collected" only if L0 §1 is empty). Note that sandboxing may conflict with Accessibility/Input Monitoring use; flag it, don't solve it.
- **Landing page** (future): if it uses analytics, cookies, or embeds third-party fonts/scripts, it needs its own short privacy notice separate from the app's. Self-hosting fonts and cookieless or no analytics avoids most of this.

*Done when:* the file exists.

---

## 3. Verification

- `docs/legal-audit.md` has no empty sections.
- Every `PRIVACY.md` section has an `audit:` comment pointing to a real audit section.
- Built `.app` contains `LICENSE` and the third-party notices (check with `find Murmur.app -iname '*licen*' -o -iname '*notice*'`).
- Notices CI check passes; token lint passes; the SPEC suite, the 50-trial focus test and the latency budget stay green.
- If L0 found no network code: run the app with networking blocked (e.g. `sandbox-exec` deny-network profile, or a firewall rule) through one full dictation and confirm it works. Record the result. If this can't be automated, add it to the owner's checklist.

## 4. Reporting and when to stop

After each milestone, append to `docs/legal-progress.md`: files changed, each "Done when" with pass/fail, anything you couldn't determine, and any copy change awaiting owner approval. Keep it short.

**Stop and ask** only if: the audit finds an undocumented network connection; a component's license is unknown or forbids redistribution; making a privacy claim true would require changing dictation behavior. Otherwise take the default here, note it, and continue.

**When done**, post a short chat summary: what was added, the network finding in one line, open owner decisions (copyright line, `[SECURITY_CONTACT]`, any unknown licenses, proposed copy changes), and the owner's manual checks.
