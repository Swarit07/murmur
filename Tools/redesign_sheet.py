#!/usr/bin/env python3
"""The redesign's contact sheet (UI_REDESIGN.md v2 U8): three columns per screen, before (the v1 UI,
Artifacts/ui/before from U0), after (Artifacts/ui/after), and the matching crop of the reference board.
Light theme. Screens with no board, or no v1 counterpart, show an empty cell with a note.

    Tools/.venv/bin/python Tools/redesign_sheet.py

Writes Artifacts/ui/sheets/contact-sheet.png (everything, downscaled) and one full-size sheet per section
(contact-hub.png, contact-onboarding.png, contact-flowbar.png, contact-menubar.png).
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

import compare

ROOT = Path(__file__).resolve().parent.parent
REF = ROOT / "Design/reference"
BEFORE = ROOT / "Artifacts/ui/before/light"
AFTER = ROOT / "Artifacts/ui/after/light"
OUT = ROOT / "Artifacts/ui/sheets"
S = 2
GAP = 24
GREY = (128, 128, 128)
FONT = ImageFont.load_default(size=26)
SMALL = ImageFont.load_default(size=20)


def board_crop(file, x, y, w, h):
    return Image.open(REF / file).convert("RGB").crop((x * S, y * S, (x + w) * S, (y + h) * S))


def load(path):
    return Image.open(path).convert("RGB") if path and Path(path).exists() else None


# Onboarding board: ten 400 x 560 cards, five per row, 32 pt apart, from (64, 148).
def onboarding_card(index):
    col, row = index % 5, index // 5
    return board_crop("onboarding.png", 64 + col * 432, 148 + row * 592, 400, 560)


def rows():
    hub_board = {"home": "hub-home.png", "style": "hub-style.png", "dictionary": "hub-dictionary.png",
                 "snippets": "hub-snippets.png", "general": "hub-settings.png"}
    x, y, w, h = compare.HUB_WINDOW
    hub = []
    for page in ["home", "dictionary", "snippets", "style", "general", "system", "experimental", "privacy"]:
        ref = board_crop(hub_board[page], x, y, w, h) if page in hub_board else None
        hub.append((f"Hub · {page}", load(BEFORE / f"hub-{page}.png"), load(AFTER / f"hub-{page}.png"), ref))

    # Our 12 onboarding steps against the board's 10 cards (models and hands-free practice have none).
    board_index = {1: 0, 2: 1, 3: 2, 4: 3, 6: 4, 7: 5, 8: 6, 9: 7, 11: 8, 12: 9}
    onboarding = []
    for path in sorted(AFTER.glob("onboarding-*.png")):
        step = int(path.name.split("-")[1])
        ref = onboarding_card(board_index[step]) if step in board_index else None
        onboarding.append((path.stem, load(BEFORE / path.name), load(path), ref))

    # Flow Bar: the board's stages, ours placed on the same stage (see compare.py).
    board = Image.open(REF / "flowbar-menubar.png").convert("RGB")
    v1_names = {"01-idle": "idle", "03-listening-hold": "listening-hold", "04-listening-handsfree": "listening-handsfree",
                "05-processing": "processing", "06-inserted": "inserted", "07-cancelled": "cancelled",
                "08-paste-error": "paste-error", "09-transcription-error": "transcription-error", "10-no-text-box": "no-text-box"}
    flow = []
    for name, row, col in compare.FLOW_STATES:
        ref = compare.board_tile(board, row, col)
        backdrop = ref.getpixel((4, 4))
        ours = compare.our_tile(AFTER / f"flowbar-{name}.png", backdrop)
        before_path = BEFORE / f"flowbar-{v1_names[name]}.png" if name in v1_names else None
        before = compare.our_tile(before_path, backdrop) if before_path and before_path.exists() else None
        flow.append((f"Flow Bar · {name[3:]}", before, ours, ref))

    # Menu bar: the glyph states and dropdown header/footer (rendered offscreen, light and dark), plus the
    # real dropdown captured from the running app, against the board's menu bar section.
    menu_parts = [load(AFTER / "menubar.png"), load(ROOT / "Artifacts/ui/after/dark/menubar.png")]
    for name in ["idle", "recording"]:
        menu_parts.append(load(ROOT / f"Artifacts/ui/after/menu/{name}.png"))
    menu_parts = [p for p in menu_parts if p]
    ours = stack(menu_parts, horizontal=True) if menu_parts else None
    menu = [("Menu bar · glyphs and dropdown", None, ours, board_crop("flowbar-menubar.png", 100, 1660, 1110, 520))]
    return {"hub": hub, "onboarding": onboarding, "flowbar": flow, "menubar": menu}


def stack(images, horizontal=False):
    if horizontal:
        h = max(i.height for i in images)
        out = Image.new("RGB", (sum(i.width for i in images) + GAP * (len(images) - 1), h), GREY)
        x = 0
        for i in images:
            out.paste(i, (x, 0))
            x += i.width + GAP
        return out
    w = max(i.width for i in images)
    out = Image.new("RGB", (w, sum(i.height for i in images) + GAP * (len(images) - 1)), GREY)
    y = 0
    for i in images:
        out.paste(i, (0, y))
        y += i.height + GAP
    return out


def fit(img, w, h):
    if img is None:
        return None
    scale = min(w / img.width, h / img.height)
    return img.resize((max(1, round(img.width * scale)), max(1, round(img.height * scale))), Image.LANCZOS)


def section(title, entries):
    """One sheet: a header row, then per screen a label and three cells (before, after, board)."""
    cell_w = max(max((c.width for c in e[1:] if c is not None), default=0) for e in entries)
    cell_h = max(max((c.height for c in e[1:] if c is not None), default=0) for e in entries)
    # Hub pages are large; show them at 1x (half the 2x capture) so the sheet stays readable.
    if cell_w > 2000:
        cell_w, cell_h = cell_w // 2, cell_h // 2
    label_h = 40
    width = GAP * 4 + cell_w * 3
    height = 100 + len(entries) * (label_h + cell_h + GAP)
    sheet = Image.new("RGB", (width, height), GREY)
    draw = ImageDraw.Draw(sheet)
    draw.text((GAP, 20), title, fill=(255, 255, 255), font=FONT)
    for i, head in enumerate(["before (v1)", "after (v2)", "reference board"]):
        draw.text((GAP + i * (cell_w + GAP), 62), head, fill=(235, 235, 235), font=SMALL)
    y = 100
    for name, *cells in entries:
        draw.text((GAP, y + 8), name, fill=(255, 255, 255), font=SMALL)
        y += label_h
        for i, cell in enumerate(cells):
            x = GAP + i * (cell_w + GAP)
            img = fit(cell, cell_w, cell_h)
            if img is None:
                draw.rectangle((x, y, x + cell_w - 1, y + cell_h - 1), outline=(150, 150, 150))
                note = "no v1 screen" if i == 0 else "no board for this screen" if i == 2 else "missing"
                draw.text((x + 16, y + 16), note, fill=(220, 220, 220), font=SMALL)
            else:
                sheet.paste(img, (x, y))
        y += cell_h + GAP
    return sheet


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    titles = {"hub": "Hub", "onboarding": "Onboarding", "flowbar": "Flow Bar", "menubar": "Menu bar"}
    sheets = []
    for key, entries in rows().items():
        sheet = section(titles[key], entries)
        sheet.save(OUT / f"contact-{key}.png", optimize=True)
        print(f"contact sheet: {OUT / f'contact-{key}.png'} ({len(entries)} screens)")
        sheets.append(sheet)
    width = 2400
    scaled = [s.resize((width, round(s.height * width / s.width)), Image.LANCZOS) for s in sheets]
    stack(scaled).save(OUT / "contact-sheet.png", optimize=True)
    print(f"contact sheet: {OUT / 'contact-sheet.png'}")


if __name__ == "__main__":
    main()
