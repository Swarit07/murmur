#!/bin/sh
# Builds Murmur.app (Release, signed with the Apple Development certificate), installs it and starts it.
# Permissions survive reinstalls because the signature stays the same.
#   Scripts/install-app.sh            installs to ~/Applications (this user)
#   Scripts/install-app.sh --system   also copies to /Applications, for other user accounts on this Mac
set -e
cd "$(dirname "$0")/.."
(cd App && xcodegen --quiet)
xcodebuild -project App/Murmur.xcodeproj -scheme Murmur -configuration Release -derivedDataPath App/build \
  -destination 'platform=macOS' -skipMacroValidation -skipPackagePluginValidation build -quiet
pkill -x Murmur 2>/dev/null && sleep 0.5 || true
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Murmur.app"
cp -R App/build/Build/Products/Release/Murmur.app "$HOME/Applications/"
if [ "$1" = "--system" ]; then
  rm -rf /Applications/Murmur.app
  cp -R App/build/Build/Products/Release/Murmur.app /Applications/
  echo "Also copied to /Applications/Murmur.app for other accounts"
fi
open "$HOME/Applications/Murmur.app"
echo "Installed and started ~/Applications/Murmur.app"
