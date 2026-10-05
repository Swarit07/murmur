#!/bin/zsh
# Reproduces Sources/UI/Resources/Fonts (UI_REDESIGN.md §3.3). Both families are SIL OFL 1.1.
#  - Source Sans 3: static TTFs 400/500/600/700 from Adobe's release 3.052R.
#  - Newsreader: static instances cut at a 24 pt optical size from Google Fonts' variable fonts
#    (the upstream statics come only at 6, 16 and 72 pt), weights 400 and 500, roman and italic.
# Needs gh, curl, and Python with fontTools (python3 -m pip install fonttools).
set -e
out="${0:A:h}/../Sources/UI/Resources/Fonts"
work=$(mktemp -d)
cd "$work"
gh release download 3.052R -R adobe-fonts/source-sans -p 'TTF-source-sans-3.052R.zip'
unzip -q TTF-source-sans-3.052R.zip -d ss3
cp ss3/TTF/SourceSans3-{Regular,Medium,Semibold,Bold}.ttf "$out/"
curl -sSL -o "$out/SourceSans3-OFL.md" https://raw.githubusercontent.com/adobe-fonts/source-sans/release/LICENSE.md
curl -sSL -o NewsreaderVF.ttf 'https://raw.githubusercontent.com/google/fonts/main/ofl/newsreader/Newsreader%5Bopsz,wght%5D.ttf'
curl -sSL -o NewsreaderItalicVF.ttf 'https://raw.githubusercontent.com/google/fonts/main/ofl/newsreader/Newsreader-Italic%5Bopsz,wght%5D.ttf'
curl -sSL -o "$out/Newsreader-OFL.txt" https://raw.githubusercontent.com/google/fonts/main/ofl/newsreader/OFL.txt
OUT="$out" python3 - <<'PY'
import os
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
out = os.environ['OUT']
specs = [('NewsreaderVF.ttf', 400, False, 'Regular'), ('NewsreaderItalicVF.ttf', 400, True, 'Italic'),
         ('NewsreaderVF.ttf', 500, False, 'Medium'), ('NewsreaderItalicVF.ttf', 500, True, 'MediumItalic')]
for src, w, italic, style in specs:
    inst = instancer.instantiateVariableFont(TTFont(src), {'wght': w, 'opsz': 24})
    n = inst['name']
    for rec in list(n.names):
        if rec.nameID in (1, 2, 3, 4, 6, 16, 17, 25): n.removeNames(nameID=rec.nameID)
    typo = {'Regular': 'Regular', 'Italic': 'Italic', 'Medium': 'Medium', 'MediumItalic': 'Medium Italic'}[style]
    ps = f'Newsreader-{style}'
    n.setName('Newsreader' if w == 400 else 'Newsreader Medium', 1, 3, 1, 0x409)
    n.setName('Italic' if italic else 'Regular', 2, 3, 1, 0x409)
    n.setName(f'2.0;Murmur;{ps}', 3, 3, 1, 0x409)
    n.setName('Newsreader ' + typo, 4, 3, 1, 0x409)
    n.setName(ps, 6, 3, 1, 0x409)
    n.setName('Newsreader', 16, 3, 1, 0x409)
    n.setName(typo, 17, 3, 1, 0x409)
    inst['OS/2'].usWeightClass = w
    sel = inst['OS/2'].fsSelection & ~(1 | 32 | 64)
    sel |= 1 if italic else 0
    if w == 400 and not italic: sel |= 64
    inst['OS/2'].fsSelection = sel
    inst['head'].macStyle = 2 if italic else 0
    inst.save(os.path.join(out, ps + '.ttf'))
PY
echo "fonts written to $out"
