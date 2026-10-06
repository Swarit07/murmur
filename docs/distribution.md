# Distribution notes

*Written by the maintainer, not a lawyer.* What each way of shipping Murmur would need, based on [legal-audit.md](legal-audit.md) (2026-10-05). Nothing here has been done yet. Check Apple's and Homebrew's current rules before acting, because they change.

## Where things stand

- Builds are signed with an **Apple Development** certificate (`App/project.yml:41-43`), with the hardened runtime and the App Sandbox off (`project.yml:45-46`). They aren't notarized, so README tells people how to get past Gatekeeper.
- `LICENSE`, `PRIVACY.md` and `THIRD_PARTY_NOTICES.md` already ship inside the app (`Murmur.app/Contents/Resources/murmur_UI.bundle/Contents/Resources/Legal/`). The app shows them under Help & setup and Settings › Data & privacy.
- The GitHub repo is **private**. README's download link (`../../releases/latest`) and the issue links in `PRIVACY.md` and `SECURITY.md` only work for people with access.

## GitHub releases and Homebrew

**Needed:**
- **Developer ID Application certificate** (paid Apple Developer Program) to sign builds for people outside your team. An Apple Development certificate is only for your own devices.
- **Hardened runtime** (`ENABLE_HARDENED_RUNTIME: YES`); notarization requires it. With the hardened runtime on, the microphone needs the `com.apple.security.device.audio-input` entitlement. Accessibility and Input Monitoring use TCC prompts, not entitlements.
  - Test that MLX (Metal) and Core ML still load the models under the hardened runtime before shipping.
- **Notarization:** `xcrun notarytool submit Murmur.zip --wait`, then `xcrun stapler staple Murmur.app`. Once notarized, the Gatekeeper steps can come out of README.
- **The license in the bundle:** done (see above). Zip releases also carry the repo's `LICENSE` if you attach it.
- **A public download URL:** make the repo public, or host release zips somewhere public.
- **Homebrew cask:**
  - Needs a versioned download URL and its `sha256`.
  - Its `zap` stanza can list the paths in `PRIVACY.md` › Deleting everything: `~/Library/Application Support/Murmur`, `~/Library/Preferences/com.swaritsheel.Murmur.plist`, `~/Library/Caches/com.swaritsheel.Murmur`, `~/Library/HTTPStorages/com.swaritsheel.Murmur`. Leave `~/.cache/huggingface` and `~/Library/Application Support/FluidAudio` out, because other tools share them.
  - The main Homebrew cask repository expects apps that pass Gatekeeper (signed and notarized). A personal tap has no such rule.

**Not needed:** a hosted privacy policy URL. `PRIVACY.md` in the repo and the app is enough.

## Mac App Store (if ever)

**Needed:**
- **A hosted privacy policy URL.** `PRIVACY.md` published on GitHub Pages or the landing page would do. Update it for anything the App Store build changes, such as the sandbox paths below.
- **App Privacy questionnaire.** Because the audit found network connections (§1), the answer isn't simply "Data Not Collected". These are candidate answers to confirm against Apple's definitions at the time:
  - **The developer collects nothing.** There's no server, account, analytics or crash reporting (audit §1).
  - **Groq and OpenRouter** (off by default; the user's own key): when the user turns them on, **Audio Data** (Groq Whisper) and **Other User Content** (transcripts, selected text in Command Mode, dictionary words) go to those providers.
    - Purpose: App Functionality.
    - Not used for tracking.
    - Linked to the user only through the user's own provider account.
    - Whether this counts as "collected" depends on Apple's rules for data sent to a third party at the user's request with the user's own credentials. **Owner decision.** An App Store build could also leave the cloud options out.
  - **Hugging Face model downloads:** requests carry the IP address and no user content.
    - Normally this is outside the questionnaire, since it's a content download, not data the developer or a partner keeps about the user. Confirm.
    - The Hugging Face token pickup (audit §1b) wouldn't work inside the sandbox anyway, since `~/.cache` is outside the container.
- **A privacy manifest** (`PrivacyInfo.xcprivacy`) for the app. Murmur calls required-reason APIs: UserDefaults, and file timestamps in `DictationController.purgeOldAudio`. GRDB and swift-crypto ship their own manifests; FluidAudio, MLX and the Hugging Face packages don't.
- **Export compliance:** HTTPS only, so likely `ITSAppUsesNonExemptEncryption = NO`. Confirm.

**Flag, not solved: the App Sandbox.** The Mac App Store requires it, and Murmur depends on things the sandbox restricts:
- **Pasting and typing:** a synthetic ⌘V and typed key events into other apps (`Sources/Insertion/PasteKeystroke.swift`), and ⌘C for Command Mode (`SelectionReader.swift`).
- **Reading other apps:** the focused field, its text and the selection through Accessibility (`FocusContext.swift`).
- **Model storage:** caches in `~/.cache/huggingface` and `~/Library/Application Support/FluidAudio`, which would move into the container. Existing users would download about 3 GB again.
- **Not likely affected:** the Input Monitoring event tap (listen-only).

Whether a sandboxed build can do all of this, and pass review, needs testing before any App Store plan.

## Landing page

The landing page lives in its own repo (`murmur-website`, Vite and React) and has a privacy surface the app doesn't. As of 2026-10-05:
- **Fonts:** it loads Newsreader, Geist and Geist Mono from **Google Fonts** (`index.html:13-15`), so each visit sends the visitor's IP address and browser details to Google.
- **GitHub:** it calls the **GitHub API** from the visitor's browser for star count, license and latest release (`src/lib/hooks.ts:73-92`), so GitHub sees the visitor's IP too.
- **Hosting:** the host's request logs apply as well.
- **No analytics or cookies:** none found in its source.

To keep the site free of third-party requests:
- **Self-host the fonts.** They're OFL, and the app already bundles them.
- **Fetch the GitHub numbers at build time,** not in the browser.

Then a short note on the site ("no cookies, no analytics; the host keeps standard request logs") is enough. If the site keeps Google Fonts or adds analytics, it needs its own privacy notice, separate from the app's `PRIVACY.md`, saying what those services receive.
