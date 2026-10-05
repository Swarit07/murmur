#!/usr/bin/env python3
"""Measures the Home board's layout numbers (UI_REDESIGN.md v2 §3.4) in the board crop and in our
snapshot, so U4's "within ±2 pt" check is a number, not an impression. Run after `murmur-snap --compare`.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent


def load(p):
    return np.array(Image.open(p).convert("RGB")).astype(int)


def near(img, color, tol):
    return np.abs(img - np.array(color)).sum(axis=2) <= tol


def first(mask_line):
    idx = np.where(mask_line)[0]
    return int(idx[0]) if len(idx) else None


def measure(img):
    m = {}
    clay = near(img, (0xB5, 0x4C, 0x3C), 60)
    ys, xs = np.where(clay[:, : 232 * 2])
    m["brand mark top"] = ys.min() / 2
    m["brand mark height"] = (ys.max() - ys.min() + 1) / 2
    m["brand mark left"] = xs.min() / 2
    sel = near(img, (0xE6, 0xDE, 0xD5), 6)
    col = sel[: 400 * 2, 100 * 2]
    top = first(col)
    end = top
    while end < len(col) and col[end]:
        end += 1
    m["Home row top"] = top / 2
    m["Home row height"] = (end - top) / 2
    panel = near(img, (0xFB, 0xF7, 0xF1), 3)
    m["panel left"] = first(panel[400 * 2, 200 * 2:]) / 2 + 200
    m["panel top"] = first(panel[:, 700 * 2]) / 2
    m["panel right gap"] = 1180 - (np.where(panel[400 * 2])[0].max() + 1) / 2
    ink = img.sum(axis=2) < 450
    region = ink[60 * 2: 140 * 2, 240 * 2: 800 * 2]
    ys, xs = np.where(region)
    m["title top"] = ys.min() / 2 + 60
    m["title left"] = xs.min() / 2 + 240
    sunk = near(img, (0xED, 0xE3, 0xD6), 3)
    ys, xs = np.where(sunk[100 * 2: 500 * 2, 240 * 2: 1170 * 2])
    m["feature top"] = ys.min() / 2 + 100
    m["feature left"] = xs.min() / 2 + 240
    m["feature right"] = xs.max() / 2 + 240
    m["feature height"] = (ys.max() - ys.min() + 1) / 2
    # The first History row's time ("9:41"): the first ink in the time column below the feature card.
    below = int((m["feature top"] + m["feature height"] + 20) * 2)
    tail = ink[below:, 260 * 2: 300 * 2]
    m["first row text top"] = first(tail.any(axis=1)) / 2 + below / 2
    return m


if __name__ == "__main__":
    snaps = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "Artifacts/ui/after"
    board = measure(load(ROOT / "Artifacts/ui/compare/hub-home-board.png"))
    ours = measure(load(snaps / "light/hub-home.png"))
    worst = 0
    for k in board:
        d = ours[k] - board[k]
        worst = max(worst, abs(d))
        print(f"{k:20s} board {board[k]:7.1f}  ours {ours[k]:7.1f}  diff {d:+5.1f}{'  <-- over 2 pt' if abs(d) > 2 else ''}")
    print(f"worst difference: {worst:.1f} pt")
