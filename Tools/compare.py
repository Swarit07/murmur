#!/usr/bin/env python3
"""Reference comparison (UI_REDESIGN.md v2 §8): crops the matching region of each board in
Design/reference/*.png (drawn at 1 pt = 1 px, rendered at 2x) and writes side-by-side sheets of
"board | ours" to Artifacts/ui/compare/. Run by `murmur-snap after --compare`, or directly:

    Tools/.venv/bin/python Tools/compare.py Artifacts/ui/after
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
REF = ROOT / "Design/reference"
OUT = ROOT / "Artifacts/ui/compare"
S = 2  # pixels per point in both the boards and our captures

# Flow Bar board: a 3 x 4 grid of 343 x 146 pt stages; the surface sits 22 pt above a stage's bottom.
FLOW_TILE = (343, 146)
FLOW_COLS = [114, 483, 852]                # stage left edges, pt
FLOW_ROWS = [292, 550, 791, 1032]          # stage top edges, pt
FLOW_SURFACE_BOTTOM = 22                   # pt above the stage's bottom edge
OUR_SURFACE_BOTTOM = 16                    # FlowGeometry.canvasMargin
FLOW_STATES = [
    ("01-idle", 0, 0), ("02-idle-hover", 0, 1), ("03-listening-hold", 0, 2),
    ("04-listening-handsfree", 1, 0), ("05-processing", 1, 1), ("06-inserted", 1, 2),
    ("07-cancelled", 2, 0), ("08-paste-error", 2, 1), ("09-transcription-error", 2, 2),
    ("10-no-text-box", 3, 0), ("11-no-audio", 3, 1),
]


def board_tile(board, row, col):
    x, y = FLOW_COLS[col] * S, FLOW_ROWS[row] * S
    return board.crop((x, y, x + FLOW_TILE[0] * S, y + FLOW_TILE[1] * S))


def our_tile(path, backdrop):
    ours = Image.open(path).convert("RGB")
    tile = Image.new("RGB", (FLOW_TILE[0] * S, FLOW_TILE[1] * S), backdrop)
    x = (tile.width - ours.width) // 2
    y = tile.height - ours.height - (FLOW_SURFACE_BOTTOM - OUR_SURFACE_BOTTOM) * S
    tile.paste(ours, (x, y))
    return tile


def label(img, text):
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 0, 8 * len(text) + 10, 22), fill=(255, 255, 255))
    draw.text((5, 5), text, fill=(0, 0, 0))


def flow_bar(snaps):
    board = Image.open(REF / "flowbar-menubar.png").convert("RGB")
    pairs = []
    for name, row, col in FLOW_STATES:
        ours = snaps / "light" / f"flowbar-{name}.png"
        if not ours.exists():
            print(f"compare: missing {ours}")
            continue
        b = board_tile(board, row, col)
        o = our_tile(ours, b.getpixel((4, 4)))
        label(b, f"board {name}")
        label(o, f"ours {name}")
        pairs.append((b, o))
    if not pairs:
        return
    w, h = pairs[0][0].size
    gap = 12
    sheet = Image.new("RGB", (w * 2 + gap * 3, (h + gap) * len(pairs) + gap), (128, 128, 128))
    for i, (b, o) in enumerate(pairs):
        sheet.paste(b, (gap, gap + i * (h + gap)))
        sheet.paste(o, (gap * 2 + w, gap + i * (h + gap)))
    OUT.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT / "flowbar.png")
    print(f"compare: {OUT / 'flowbar.png'} ({len(pairs)} states)")


if __name__ == "__main__":
    snaps = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "Artifacts/ui/after"
    flow_bar(snaps)
