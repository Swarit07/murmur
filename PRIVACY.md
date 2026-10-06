# Privacy

*Written by the maintainer, not a lawyer.* This describes what Murmur 0.1 does, checked against its code ([docs/legal-audit.md](docs/legal-audit.md)).

## Summary

Murmur turns your voice into text with speech and cleanup models that run on your Mac. With those built-in models, your audio and transcripts stay on this Mac. Murmur has no account, no analytics and no crash reporting, and it never sends your words anywhere unless you pick a cloud option and add your own key. It does connect to Hugging Face to download its models, and each time it starts it checks Hugging Face for cleanup model updates. Those requests carry no audio or text.

<!-- audit: §1, §2 -->

## What Murmur stores, and where

| What | Where | How long | How to delete |
|---|---|---|---|
| History: each dictation's raw and cleaned text, time, length, the app you dictated into (name and bundle id), and timings | `~/Library/Application Support/Murmur/murmur.sqlite` | Until you delete it | Settings › Data & privacy › Delete all History and audio |
| Audio recordings of each dictation (on by default) | `~/Library/Application Support/Murmur/Audio/` | 14 days. Older files are deleted when Murmur starts. | Turn off "Keep audio for 14 days", or Delete all |
| Your dictionary and snippets | Same database | Until you delete them | Remove them on the Dictionary and Snippets pages. Delete all keeps them. |
| Settings (shortcuts, microphone, languages, styles, model choices, toggles) | `~/Library/Preferences/com.swaritsheel.Murmur.plist` | Until you delete it | `defaults delete com.swaritsheel.Murmur` |
| Groq and OpenRouter API keys, if you add them | Your login Keychain, under `com.swaritsheel.Murmur` | Until you remove them | Remove, in Settings › Data & privacy |
| Speech models | `~/Library/Application Support/FluidAudio/Models/` | Kept | Delete the folder |
| Cleanup models | `~/.cache/huggingface/hub/models--mlx-community--…` | Kept | Delete those folders. Other Hugging Face tools on your Mac use the same cache. |
| Whisper models, if you pick Whisper | `~/Documents/huggingface/models/` | Kept | Delete the folder |
| System caches (compiled models, Hugging Face replies) | `~/Library/Caches/com.swaritsheel.Murmur/`, `~/Library/HTTPStorages/com.swaritsheel.Murmur/` | Managed by macOS | Delete the folders |
| Debug menu output (focus test results with the app name, self-test files, window snapshots on demo data) | `~/Library/Application Support/Murmur/` | Only written when you run those items | Delete the files |

Your text is never stored in settings, caches or logs.

**Never store anything** (Settings › Data & privacy, off by default) keeps History in memory only and writes no audio. Paste last transcript still works until Murmur quits. Nothing from your dictations reaches the disk. Settings and model files are still saved.

**Delete all History and audio** removes every dictation and the Audio folder. SQLite can leave fragments of deleted text in unused parts of the database file until it reuses that space. To be sure nothing remains, quit Murmur and delete `murmur.sqlite` (this also deletes your dictionary and snippets).

<!-- audit: §2 -->

## Permissions and why

**Microphone.** Murmur records only while you dictate: while you hold the push-to-talk shortcut, from a hands-free start until you stop it, while you give a Command Mode instruction, and during the microphone test.

**Accessibility.** Lets Murmur paste or type into the app you're using, check for password fields (it never types into them), and read the app and text box you're dictating into. Concretely:
- Murmur notes which app and field had focus, so it pastes only into that field.
- In a browser, it reads the page's address to pick a writing style. The address isn't saved.
- In Command Mode, it reads your selected text.
- For dictionary suggestions, it reads the text box it just pasted into, a few times in the following minute, to spot a word you corrected. That text stays in memory. Only a word you choose to add is saved.

Murmur never captures your screen.

**Input Monitoring.** This is how Murmur notices your dictation shortcut, including Fn alone, which normal shortcuts can't use. macOS shows Murmur every key press and every press of an extra mouse button. Murmur uses them only to spot its shortcuts and Esc. It sees key codes, not the characters you type, and nothing you type is logged or stored. If Caps Lock is one of your shortcuts, Murmur also watches the Caps Lock key directly.

Murmur doesn't ask for Screen Recording, Contacts, Location, Camera or Automation.

<!-- audit: §3, §5 -->

## Network

Murmur has no server. It makes these connections, and only these.

### Hugging Face: model downloads and update checks

- **What:** Murmur downloads its models from huggingface.co and the download servers it points to:
  - the speech model, `FluidInference/parakeet-ultra-coreml` (about 0.5 GB);
  - the cleanup model, `mlx-community/Qwen3.5-4B-4bit` (about 2.5 GB);
  - any other model you pick in Settings.
- **When:** the speech model downloads on first launch, and again only if its files go missing or a Murmur update needs a newer version. The cleanup model downloads on first launch, and **every time Murmur starts** it asks Hugging Face for the model's file list. If the files changed, it downloads the new ones.
- **What's sent:** requests for the model files, with standard web request details such as your IP address. **No audio, text, dictionary or settings.** If you've signed in to Hugging Face on this Mac (a token in `~/.cache/huggingface/token` or the `HF_TOKEN` environment variable), Murmur's model downloader sends that token with these requests. Hugging Face can then tell the requests came from your account.
- **Optional?** The downloads are needed for the built-in models. There's no setting to turn off the launch check. If you block Murmur's network access after the first download, Murmur keeps working: the check fails and it loads the copy on disk. Choosing "Rules only" or "Apple on-device" cleanup in Settings › General also stops the cleanup model check.

### Apple, if you pick an Apple on-device option

Choosing "Apple on-device" speech (macOS 26 or later) makes macOS download Apple's speech model, which other apps share. Transcription then happens on your Mac. "Apple on-device" cleanup uses the model built into macOS and downloads nothing.

### Groq and OpenRouter, only if you choose them

These are off unless you pick "Groq Whisper", "Groq" or "OpenRouter" in Settings › General and add your own API key.
- **Groq Whisper** (speech): each dictation's **audio**, your chosen language and your **dictionary words** go to `api.groq.com`.
- **Groq or OpenRouter** (cleanup): each **transcript**, Murmur's cleanup instructions, your dictionary words and the style go to `api.groq.com` or `openrouter.ai`. In Command Mode, your instruction and the **selected text** go there too. OpenRouter passes requests to the company that hosts the model you chose.
- When one of these loads, Murmur sends a short test request ("Reply with OK.", or half a second of silence).
- These companies' own privacy policies apply to what you send them. Murmur doesn't cache these requests on disk.
- **Turn off:** pick a built-in engine and cleanup model, and remove your keys in Settings › Data & privacy.

### Nothing else

Murmur makes no other network connections: no analytics, no crash reports, no update checks. To check this yourself, watch Murmur with a network monitor such as Little Snitch or LuLu. Or, after the first download, block Murmur's network access and dictate as usual. It keeps working.

<!-- audit: §1 -->

## Clipboard

- **Pasting a dictation:** Murmur saves what's on your clipboard and puts the text there, marked so clipboard managers skip it. It presses ⌘V, waits half a second (5 seconds for remote-desktop apps), then puts your old clipboard back. If you copied something in the meantime, Murmur keeps your copy.
- **When a paste can't happen** (focus moved, a password field, or the paste keystroke failed): the text stays on the clipboard, without the skip markers, so you can paste it yourself. Your old clipboard isn't restored.
- **Apps on your "type instead" list:** Murmur types the text and doesn't touch the clipboard.
- **Copy last transcript (⌃⌘C) and Copy in History:** these put plain text on the clipboard, like any copy.
- **Command Mode:** if an app doesn't share its selection, Murmur presses ⌘C, reads the selection, and restores your clipboard exactly.

<!-- audit: §3 -->

## Logs

Murmur writes to macOS's system log on your Mac under `com.swaritsheel.Murmur`. The log holds timings, counts, states and error messages, never your transcripts, selected text, app names or window titles. Error messages can include a file path, which shows your macOS user name. Murmur sends logs nowhere. The command-line tool `murmur-cli`, which isn't part of the app, keeps its own timing file with app names and no text.

<!-- audit: §4 -->

## Optional features

| Feature | Default | Where |
|---|---|---|
| Keep audio for 14 days | On | Settings › Data & privacy (also asked during setup) |
| Never store anything | Off | Settings › Data & privacy (also asked during setup) |
| Cloud speech or cleanup (Groq, OpenRouter) | Off | Settings › General, plus keys in Settings › Data & privacy |
| Dictionary suggestions after you correct a word | Always on | A prompt on the Flow Bar. Nothing is saved unless you click Add. |
| Debug menu (focus test, self-test, snapshots) | Shown | Settings › System. Its items write files only when you run them. |

Murmur has no crash reporting and no update checks to switch off.

<!-- audit: §1, §2, §3 -->

## Deleting everything

1. In Murmur: Settings › Data & privacy › **Delete all History and audio**, then **Remove** any API keys. Turn off **Launch at login** in Settings › General.
2. Quit Murmur, then delete:
   - `~/Library/Application Support/Murmur/`
   - `~/Library/Application Support/FluidAudio/`
   - `~/.cache/huggingface/hub/models--mlx-community--*` (check that no other tool needs them)
   - `~/Documents/huggingface/` (only if you used Whisper)
   - `~/Library/Caches/com.swaritsheel.Murmur/`
   - `~/Library/HTTPStorages/com.swaritsheel.Murmur/`
3. Delete the settings: `defaults delete com.swaritsheel.Murmur`
4. Reset the permissions: `tccutil reset All com.swaritsheel.Murmur`
5. Move `Murmur.app` to the Trash. If it still shows in System Settings › General › Login Items, remove it there.

<!-- audit: §2, §5 -->

## Children, selling data, ads

Murmur collects nothing, so there's nothing to sell, share or advertise with, for anyone of any age.

<!-- audit: §1 -->

## Changes and contact

Changes to this file are tracked in its git history. Questions go to [GitHub issues](https://github.com/Swarit07/murmur/issues). For anything sensitive, such as a security problem, follow [SECURITY.md](SECURITY.md).

<!-- audit: §1 -->

*Last updated: 5 October 2026.*
