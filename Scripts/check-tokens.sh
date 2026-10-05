#!/bin/zsh
# Token lint (UI_REDESIGN.md §8): views reference tokens, never raw sizes, colors, radii, durations or
# springs. Scans Sources/UI and Sources/HubUI outside Tokens*.swift. 0 and .infinity are allowed.
# Files that predate the redesign and are being rewritten are listed in Scripts/token-lint-legacy.txt;
# each milestone removes its files from that list.
cd "${0:A:h}/.." || exit 2
legacy=(${(f)"$(grep -v '^#' Scripts/token-lint-legacy.txt 2>/dev/null | sed '/^$/d')"})
patterns=(
  'Color\(red:'
  'Color\(hex'
  'NSColor\(red'
  'NSColor\(srgbRed'
  '\.font\(\.system\(size: *[0-9]'
  '\.font\(\.custom\([^)]*size: *[0-9]'
  '\.cornerRadius\( *[1-9]'
  'cornerRadius: *[1-9]'
  '\.frame\((width|height|minWidth|minHeight|maxWidth|maxHeight|idealWidth): *[1-9]'
  '\.padding\( *[1-9]'
  '\.padding\(\.[a-zA-Z]+, *[1-9]'
  '\.spring\(response: *[0-9]'
  'lineWidth: *[1-9]'
  'spacing: *[1-9]'
  'duration: *[0-9]'
  '\.opacity\( *0?\.[0-9]'
  'withAnimation\(\.(easeIn|easeOut|easeInOut|linear|spring|default|smooth|snappy|bouncy)'
  '\.animation\(\.(easeIn|easeOut|easeInOut|linear|spring|default|smooth|snappy|bouncy)'
)
fail=0
for file in Sources/UI/**/*.swift(N) Sources/HubUI/**/*.swift(N); do
  [[ ${file:t} == Tokens* ]] && continue
  (( ${legacy[(Ie)$file]} )) && continue
  for p in $patterns; do
    hits=$(grep -nE "$p" "$file" | grep -vE '^[0-9]+: *//')
    if [[ -n $hits ]]; then
      echo "$file: raw literal ($p):"
      echo "$hits" | sed 's/^/    /'
      fail=1
    fi
  done
done
if (( fail )); then
  echo "token lint: FAIL (use a token from Sources/UI/Tokens*.swift)"
  exit 1
fi
echo "token lint: pass (${#legacy} legacy files pending rewrite)"
