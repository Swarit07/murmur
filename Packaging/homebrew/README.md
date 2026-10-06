# Homebrew tap

`Casks/murmur.rb` is the recipe for a personal Homebrew tap. Homebrew's main cask repository only takes apps that are notarized and already well known, so Murmur ships through its own tap instead.

The tap is published at [`Swarit07/homebrew-murmur`](https://github.com/Swarit07/homebrew-murmur), with a copy of `Casks/murmur.rb` in its `Casks/` folder. People install with:

```bash
brew install --cask swarit07/murmur/murmur
```

**Each new release:**
1. Set `version` to the release's version (the tag without the `v`).
2. Set `sha256` to `shasum -a 256 Murmur.zip`.
3. Commit the change here and copy the same file to `homebrew-murmur`'s `Casks/` folder.

The release zip must be the asset `Murmur.zip` on the GitHub release tagged `v<version>`. Murmur isn't notarized, so Homebrew installs it and macOS still asks once on first launch (the caveat says how).
