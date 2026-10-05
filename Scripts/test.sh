#!/bin/sh
# Unit tests, without MLX so they build fast and need no Metal compiler. Uses its own build folder so
# it never replaces the binaries in .build/. With only the Command Line Tools active, it also points the
# compiler at the Swift Testing macros, which those tools install outside the default plugin path.
set -e
cd "$(dirname "$0")/.."
PLUGINS="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
case "$(xcode-select -p)" in
  */CommandLineTools)
    Scripts/check-tokens.sh || exit 1
    MURMUR_NO_MLX=1 exec swift test --scratch-path .build-test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@" ;;
  *)
    Scripts/check-tokens.sh || exit 1
    MURMUR_NO_MLX=1 exec swift test --scratch-path .build-test "$@" ;;
esac
