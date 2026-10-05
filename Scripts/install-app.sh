#!/bin/sh
# Builds Murmur.app (Release, signed with the Apple Development certificate), installs it in
# ~/Applications and starts it. Permissions survive reinstalls because the signature stays the same.
set -e
cd "$(dirname "$0")/.."
(cd App && xcodegen --quiet)
xcodebuild -project App/Murmur.xcodeproj -scheme Murmur -configuration Release -derivedDataPath App/build \
  -destination 'platform=macOS' -skipMacroValidation -skipPackagePluginValidation build -quiet
mkdir -p "$HOME/Applications"
pkill -x Murmur 2>/dev/null && sleep 0.5 || true
rm -rf "$HOME/Applications/Murmur.app"
cp -R App/build/Build/Products/Release/Murmur.app "$HOME/Applications/"
open "$HOME/Applications/Murmur.app"
echo "Installed and started ~/Applications/Murmur.app"
