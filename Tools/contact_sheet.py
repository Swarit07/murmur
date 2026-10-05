#!/usr/bin/env python3
"""Tiles snapshot PNGs into contact sheets.

  contact_sheet.py <set-dir> <out.png>                 one sheet of a set (light row over dark row per image)
  contact_sheet.py --compare <before> <after> <out.png> before and after side by side, per image and look
"""
import sys, os
from PIL import Image, ImageDraw

def load(path, width):
    im = Image.open(path).convert('RGB')
    h = int(im.height * width / im.width)
    return im.resize((width, h), Image.LANCZOS)

def label(img, text):
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 8 + 7 * len(text), 18], fill=(255, 255, 255))
    d.text((4, 3), text, fill=(0, 0, 0))
    return img

def sheet(tiles, cols, out, gap=12, bg=(128, 128, 128)):
    if not tiles: return
    w = max(t.width for t in tiles); h = max(t.height for t in tiles)
    rows = (len(tiles) + cols - 1) // cols
    canvas = Image.new('RGB', (cols * (w + gap) + gap, rows * (h + gap) + gap), bg)
    for i, t in enumerate(tiles):
        canvas.paste(t, (gap + (i % cols) * (w + gap), gap + (i // cols) * (h + gap)))
    canvas.save(out, optimize=True)
    print(out, canvas.size)

if sys.argv[1] == '--compare':
    before, after, out = sys.argv[2:5]
    tiles = []
    names = sorted(set(os.listdir(os.path.join(after, 'light'))) | set(os.listdir(os.path.join(before, 'light'))))
    for name in names:
        if not name.endswith('.png') or name.startswith('gallery'): continue
        for look in ('light', 'dark'):
            for which, root in (('before', before), ('after', after)):
                p = os.path.join(root, look, name)
                if os.path.exists(p): tiles.append(label(load(p, 560), f'{which} {look} {name[:-4]}'))
                else: tiles.append(label(Image.new('RGB', (560, 306), (60, 60, 60)), f'{which} {look} {name[:-4]} (none)'))
    sheet(tiles, 4, out)
else:
    root, out = sys.argv[1:3]
    tiles = []
    for name in sorted(os.listdir(os.path.join(root, 'light'))):
        if not name.endswith('.png') or name.startswith('gallery'): continue
        for look in ('light', 'dark'):
            p = os.path.join(root, look, name)
            if os.path.exists(p): tiles.append(label(load(p, 560), f'{look} {name[:-4]}'))
    sheet(tiles, 4, out)
