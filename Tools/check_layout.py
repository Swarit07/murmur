#!/usr/bin/env python3
"""Clipping check on the snapshot sets (UI_REDESIGN.md v2 §8): fails if a layout runs out of its frame.

- Onboarding: every step's clay primary button ends at least 20 pt above the window's bottom edge
  (the scaffold's padding is 28), so no copy pushed the footer out.
- Flow Bar: nothing but the backdrop touches the canvas edge, so no surface or card is cut off.

    Tools/.venv/bin/python Tools/check_layout.py            # every Artifacts/ui/after* set
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
S = 2
STEP_HEIGHT = 560
FOOTER_MIN = 20


def clay_rows(path):
    im = np.asarray(Image.open(path).convert("RGB")).astype(int)
    clay = (im[:, :, 0] - im[:, :, 2]) > 60
    return np.where(clay.sum(1) > 20)[0]


def check(folder):
    problems, checked = [], 0
    for path in sorted(folder.glob("*/onboarding-*.png")):
        rows = clay_rows(path)
        checked += 1
        if len(rows) == 0:
            continue  # the models step's primary is disabled (no clay) while models load
        bottom = rows.max() / S
        if bottom > STEP_HEIGHT - FOOTER_MIN:
            problems.append(f"{path.relative_to(ROOT)}: primary button ends {STEP_HEIGHT - bottom:.1f} pt from the bottom")
    for path in sorted(folder.glob("*/flowbar-*.png")):
        im = np.asarray(Image.open(path).convert("RGB")).astype(int)
        checked += 1
        backdrop = im[S * 2, S * 2]
        edges = np.concatenate([im[:2].reshape(-1, 3), im[-2:].reshape(-1, 3), im[:, :2].reshape(-1, 3), im[:, -2:].reshape(-1, 3)])
        if (np.abs(edges - backdrop).sum(1) > 24).any():
            problems.append(f"{path.relative_to(ROOT)}: content touches the canvas edge")
    return checked, problems


def main():
    sets = [Path(a) for a in sys.argv[1:]] or sorted((ROOT / "Artifacts/ui").glob("after*"))
    failed = False
    for folder in sets:
        checked, problems = check(folder)
        print(f"layout: {folder.name}: {checked} images, {len(problems)} clipped")
        for p in problems:
            print("  " + p)
        failed |= bool(problems)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
