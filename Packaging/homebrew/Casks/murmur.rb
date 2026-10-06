cask "murmur" do
  version "0.1.0"
  sha256 "f63f3dc36d993f6488332bb558c030e84c5fe906e4301c6623886aeb66a99cc7"

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
