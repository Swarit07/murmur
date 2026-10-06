#!/bin/sh
# Builds Murmur.app (Release, signed with the Apple Development certificate), installs it and starts it.
# Permissions survive reinstalls because the signature stays the same.
#   Scripts/install-app.sh            installs to ~/Applications (this user)
#   Scripts/install-app.sh --system   also copies to /Applications, for other user accounts on this Mac
#
# Building with your own signing identity (the project is set up for the maintainer's team):
#   MURMUR_TEAM=ABCDE12345 Scripts/install-app.sh   your Apple Development team ID (Xcode › Settings ›
#                                                   Accounts); a stable signature keeps permissions
#   MURMUR_TEAM=adhoc Scripts/install-app.sh        no Apple account needed (ad-hoc signature); macOS asks
#                                                   for Accessibility and Input Monitoring again after each rebuild
set -e
cd "$(dirname "$0")/.."
(cd App && xcodegen --quiet)
case "${MURMUR_TEAM:-}" in
  "") set -- "$@" ;;
  adhoc) set -- "$@" CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ;;
  *) set -- "$@" "DEVELOPMENT_TEAM=$MURMUR_TEAM" ;;
esac
SYSTEM=no
SETTINGS=""
for arg in "$@"; do
  case "$arg" in
    --system) SYSTEM=yes ;;
    *=*) SETTINGS="$SETTINGS $arg" ;;
  esac
done
# shellcheck disable=SC2086 # the build settings are separate words on purpose
xcodebuild -project App/Murmur.xcodeproj -scheme Murmur -configuration Release -derivedDataPath App/build \
  -destination 'platform=macOS' -skipMacroValidation -skipPackagePluginValidation build -quiet $SETTINGS
pkill -x Murmur 2>/dev/null && sleep 0.5 || true
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Murmur.app"
cp -R App/build/Build/Products/Release/Murmur.app "$HOME/Applications/"
if [ "$SYSTEM" = yes ]; then
  rm -rf /Applications/Murmur.app
  cp -R App/build/Build/Products/Release/Murmur.app /Applications/
  echo "Also copied to /Applications/Murmur.app for other accounts"
fi
open "$HOME/Applications/Murmur.app"
echo "Installed and started ~/Applications/Murmur.app"
