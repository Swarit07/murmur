#!/bin/sh
# Layout QA: renders every Hub page, onboarding step and Flow Bar state at five window sizes (the 880 × 560
# minimum up to 1920 × 1080), at default and Large text, in light and dark, then fails if any page is wider
# than its window, a footer leaves its step, or a Flow Bar card leaves its canvas (Tools/check_layout.py).
#   Scripts/qa-layout.sh            renders into Artifacts/ui/sizes/ and checks
set -e
cd "$(dirname "$0")/.."
MURMUR_NO_MLX=1 swift build --scratch-path .build-test --product murmur-snap -q
rm -rf Artifacts/ui/sizes
for size in 880x560 980x670 1180x740 1440x900 1920x1080; do
  .build-test/debug/murmur-snap after --size "$size" --out Artifacts/ui/sizes >/dev/null
  .build-test/debug/murmur-snap after --large --size "$size" --out Artifacts/ui/sizes >/dev/null
done
Tools/.venv/bin/python Tools/check_layout.py Artifacts/ui/sizes/*
