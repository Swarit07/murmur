#!/bin/zsh
# Reproduces Sources/UI/Resources/Fonts (UI_REDESIGN.md v2 §3.3). All three families are SIL OFL 1.1.
#  - Geist 400/500/600 and Geist Mono 400/500: static TTFs from vercel/geist-font release v1.7.2.
#  - Newsreader: static instances cut from Google Fonts' variable fonts. A browser (the boards) picks
#    the optical size from the font size, so two cuts are made: "Newsreader" at opsz 16 for text sizes
#    (15-22 pt: samples, quotes, triggers, card titles; 400, 400 italic, 500) and "Newsreader Display"
#    at opsz 36 for titles (28-40 pt; 400 and 400 italic).
# Needs gh, curl, and Python with fontTools (Tools/.venv: python3 -m venv Tools/.venv; pip install fonttools).
set -e
root="${0:A:h}/.."
out="$root/Sources/UI/Resources/Fonts"
py="$root/Tools/.venv/bin/python"
[[ -x $py ]] || py=python3
work=$(mktemp -d)
cd "$work"
gh release download v1.7.2 -R vercel/geist-font -p 'geist-font-v1.7.2.zip'
unzip -q geist-font-v1.7.2.zip -d geist
base=geist/geist-font
cp $base/Geist/ttf/Geist-{Regular,Medium,SemiBold}.ttf "$out/"
cp $base/GeistMono/ttf/GeistMono-{Regular,Medium}.ttf "$out/"
cp $base/OFL.txt "$out/Geist-OFL.txt"
curl -fsSL -o NewsreaderVF.ttf 'https://raw.githubusercontent.com/google/fonts/main/ofl/newsreader/Newsreader%5Bopsz,wght%5D.ttf'
curl -fsSL -o NewsreaderItalicVF.ttf 'https://raw.githubusercontent.com/google/fonts/main/ofl/newsreader/Newsreader-Italic%5Bopsz,wght%5D.ttf'
curl -fsSL -o "$out/Newsreader-OFL.txt" https://raw.githubusercontent.com/google/fonts/main/ofl/newsreader/OFL.txt
OUT="$out" "$py" - <<'PY'
import os
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
out = os.environ['OUT']
# (source, weight, italic, optical size, family, style)
specs = [
    ('NewsreaderVF.ttf', 400, False, 16, 'Newsreader', 'Regular'),
    ('NewsreaderItalicVF.ttf', 400, True, 16, 'Newsreader', 'Italic'),
    ('NewsreaderVF.ttf', 500, False, 16, 'Newsreader', 'Medium'),
    ('NewsreaderVF.ttf', 400, False, 36, 'Newsreader Display', 'Regular'),
    ('NewsreaderItalicVF.ttf', 400, True, 36, 'Newsreader Display', 'Italic'),
]
for src, w, italic, opsz, family, style in specs:
    inst = instancer.instantiateVariableFont(TTFont(src), {'wght': w, 'opsz': opsz})
    n = inst['name']
    for rec in list(n.names):
        if rec.nameID in (1, 2, 3, 4, 6, 16, 17, 25):
            n.removeNames(nameID=rec.nameID)
    ps = family.replace(' ', '') + '-' + style
    legacy_family = family if w == 400 else family + ' Medium'
    n.setName(legacy_family, 1, 3, 1, 0x409)
    n.setName('Italic' if italic else 'Regular', 2, 3, 1, 0x409)
    n.setName(f'2.0;Murmur;{ps}', 3, 3, 1, 0x409)
    n.setName(f'{family} {style}', 4, 3, 1, 0x409)
    n.setName(ps, 6, 3, 1, 0x409)
    n.setName(family, 16, 3, 1, 0x409)
    n.setName(style, 17, 3, 1, 0x409)
    inst['OS/2'].usWeightClass = w
    sel = inst['OS/2'].fsSelection & ~(1 | 32 | 64)
    sel |= 1 if italic else 0
    if w == 400 and not italic:
        sel |= 64
    inst['OS/2'].fsSelection = sel
    inst['head'].macStyle = 2 if italic else 0
    inst.save(os.path.join(out, ps + '.ttf'))
    print('wrote', ps)
PY
echo "fonts written to $out"
