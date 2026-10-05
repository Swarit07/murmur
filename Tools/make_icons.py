#!/usr/bin/env python3
"""Renders Murmur's icons from the brand SVGs (UI_REDESIGN.md v2 §3.6).

  - App icon: Design/brand/app-icon.svg -> App/AppIcon.iconset (16 to 512 at 1x and 2x, which is 16 to
    1024 px) and App/Assets.xcassets/AppIcon.appiconset. iconutil checks the iconset builds an .icns.
  - Menu bar: Design/brand/menubar-template.svg -> Sources/UI/Resources/MenuBar/menubar-template.png at
    18 pt (1x, 2x, 3x). The four states (idle, recording, processing, error) are composed from it at
    runtime by MenuBarGlyph, so their dots and badge come from the Swift tokens.

    Tools/.venv/bin/python Tools/make_icons.py      # needs cairosvg (pip install cairosvg)
"""
import json
import subprocess
import tempfile
from pathlib import Path

import cairosvg

ROOT = Path(__file__).resolve().parent.parent
BRAND = ROOT / "Design/brand"


def render(svg, px, out):
    cairosvg.svg2png(url=str(svg), write_to=str(out), output_width=px, output_height=px)


def app_icon():
    iconset = ROOT / "App/AppIcon.iconset"
    assets = ROOT / "App/Assets.xcassets"
    appicon = assets / "AppIcon.appiconset"
    iconset.mkdir(parents=True, exist_ok=True)
    appicon.mkdir(parents=True, exist_ok=True)
    images = []
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
            render(BRAND / "app-icon.svg", size * scale, iconset / name)
            (appicon / name).write_bytes((iconset / name).read_bytes())
            images.append({"idiom": "mac", "size": f"{size}x{size}", "scale": f"{scale}x", "filename": name})
    (appicon / "Contents.json").write_text(json.dumps({"images": images, "info": {"version": 1, "author": "xcode"}}, indent=2) + "\n")
    (assets / "Contents.json").write_text(json.dumps({"info": {"version": 1, "author": "xcode"}}, indent=2) + "\n")
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(Path(tmp) / "Murmur.icns")], check=True)
    print("app icon: App/AppIcon.iconset, App/Assets.xcassets/AppIcon.appiconset (iconutil ok)")


def menu_bar():
    out = ROOT / "Sources/UI/Resources/MenuBar"
    out.mkdir(parents=True, exist_ok=True)
    for scale, suffix in ((1, ""), (2, "@2x"), (3, "@3x")):
        render(BRAND / "menubar-template.svg", 18 * scale, out / f"menubar-template{suffix}.png")
    print("menu bar: Sources/UI/Resources/MenuBar/menubar-template{,@2x,@3x}.png")


if __name__ == "__main__":
    app_icon()
    menu_bar()
