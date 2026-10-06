# Homebrew tap

`Casks/murmur.rb` is the recipe for a personal Homebrew tap. Homebrew's main cask repository only takes apps that are notarized and already well known, so Murmur ships through its own tap instead.

**Publishing it (once the repo is public and a release with `Murmur.zip` exists):**
1. Create a public GitHub repository named `homebrew-murmur` under `Swarit07`, and copy `Casks/murmur.rb` into its `Casks/` folder.
2. People install with:

   ```bash
   brew install --cask swarit07/murmur/murmur
   ```

**Each new release:**
1. Set `version` to the release's version (the tag without the `v`).
2. Set `sha256` to `shasum -a 256 Murmur.zip`.
3. Commit the change to `homebrew-murmur`.

The release zip must be the asset `Murmur.zip` on the GitHub release tagged `v<version>`. Murmur isn't notarized, so Homebrew installs it and macOS still asks once on first launch (the caveat says how).
