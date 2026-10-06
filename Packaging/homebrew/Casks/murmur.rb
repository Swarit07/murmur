cask "murmur" do
  version "0.1.0"
  sha256 "cb4f34b29584854a67df521f4d2fbceeae3ba4d553e12d251d4216b520e307bf"

  url "https://github.com/Swarit07/murmur/releases/download/v#{version}/Murmur.zip"
  name "Murmur"
  desc "Private, on-device dictation"
  homepage "https://github.com/Swarit07/murmur"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Murmur.app"

  # The paths in PRIVACY.md › Deleting everything. The model caches (~/.cache/huggingface and
  # ~/Library/Application Support/FluidAudio) are left alone because other tools share them.
  zap trash: [
    "~/Library/Application Support/Murmur",
    "~/Library/Caches/com.swaritsheel.Murmur",
    "~/Library/HTTPStorages/com.swaritsheel.Murmur",
    "~/Library/Preferences/com.swaritsheel.Murmur.plist",
  ]

  caveats <<~EOS
    Murmur isn't notarized by Apple, so macOS blocks its first launch once.
    Open System Settings > Privacy & Security and click "Open Anyway".
    On first launch Murmur also downloads its speech and cleanup models (about 3 GB).
  EOS
end
