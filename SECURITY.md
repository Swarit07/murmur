# Security

Murmur listens to your keyboard, types into other apps and keeps what you say, so security problems matter. Thanks for reporting them privately.

## How to report

Please don't open a public issue. Email **[SECURITY_CONTACT]** with:
- what you found;
- the steps to reproduce it;
- the Murmur version (Help & setup shows it) and your macOS version.

## What's in scope

Anything that touches:
- **Input Monitoring:** the shortcut event tap and the Caps Lock monitor.
- **Accessibility:** pasting and typing into other apps, the password-field check, and reading the focused field or selection.
- **The pasteboard:** saving and restoring your clipboard, and the markers that keep transcripts out of clipboard managers.
- **Stored data:** the History database, the audio recordings, the dictionary and snippets, and the API keys in the Keychain.
- **Network:** the model downloads from Hugging Face and the optional Groq and OpenRouter requests (see [PRIVACY.md](PRIVACY.md)).

Out of scope:
- Bugs in macOS, Hugging Face, Groq or OpenRouter. Please report those to them.
- Attacks that need someone who already controls your Mac account.

## What to expect

- Murmur is maintained by one person in their spare time. Responses are best effort, usually within a week.
- Fixes ship in the next release. Supported version: the latest release only.
- There's no bug bounty.
