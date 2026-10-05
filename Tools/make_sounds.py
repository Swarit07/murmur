#!/usr/bin/env python3
"""Writes Murmur's sounds (UI_REDESIGN.md §6.3) from the tokens in Sources/UI/Tokens+Sound.swift.

Every sound is synthesized here: sine or triangle notes with a short linear attack, an exponential
decay and 5 ms fades, normalized to the token's peak level. No recorded audio. 44.1 kHz, 16-bit mono.

    Tools/.venv/bin/python Tools/make_sounds.py        # needs numpy (python3 -m venv Tools/.venv; pip install numpy)

A unit test (SoundFileTests) checks the WAVs still match the tokens, so change a token, rerun this.
"""
import re
import sys
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
TOKENS = ROOT / "Sources/UI/Tokens+Sound.swift"
OUT = ROOT / "Sources/UI/Resources/Sounds"


def read_tokens(text):
    rate = int(re.search(r"sampleRate\s*=\s*([\d_]+)", text).group(1).replace("_", ""))
    fade = float(re.search(r"static let fade: Double = ([\d.]+)", text).group(1))
    tones = {}
    pattern = re.compile(
        r"static let (\w+) = ToneToken\(wave: \.(\w+), notes: \[([^\]]*)\], noteLength: ([\d.]+), gap: ([\d.]+), "
        r"attack: ([\d.]+), decay: ([\d.]+), peakDb: (-?[\d.]+)\)")
    for m in pattern.finditer(text):
        name, wave_kind, notes, length, gap, attack, decay, peak = m.groups()
        tones[name] = dict(wave=wave_kind, notes=[float(n) for n in notes.split(",")], length=float(length),
                           gap=float(gap), attack=float(attack), decay=float(decay), peak=float(peak))
    return rate, fade, tones


def note(freq, tone, rate, fade):
    n = int(round(tone["length"] * rate))
    t = np.arange(n) / rate
    phase = freq * t
    if tone["wave"] == "triangle":
        wave_ = 2 * np.abs(2 * (phase - np.floor(phase + 0.5))) - 1
    else:
        wave_ = np.sin(2 * np.pi * phase)
    attack = np.clip(t / max(tone["attack"], 1e-6), 0, 1)
    decay = np.exp(-np.clip(t - tone["attack"], 0, None) / tone["decay"])
    env = attack * decay
    k = max(1, int(round(fade * rate)))
    env[:k] *= np.linspace(0, 1, k)
    env[-k:] *= np.linspace(1, 0, k)
    return wave_ * env


def render(tone, rate, fade):
    gap = np.zeros(int(round(tone["gap"] * rate)))
    parts = []
    for i, f in enumerate(tone["notes"]):
        if i:
            parts.append(gap)
        parts.append(note(f, tone, rate, fade))
    samples = np.concatenate(parts)
    peak = 10 ** (tone["peak"] / 20)
    return samples / np.max(np.abs(samples)) * peak


def write(path, samples, rate):
    data = np.round(samples * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(data.tobytes())


def main():
    rate, fade, tones = read_tokens(TOKENS.read_text())
    if not tones:
        sys.exit("make_sounds: no ToneToken found in " + str(TOKENS))
    OUT.mkdir(parents=True, exist_ok=True)
    for name, tone in tones.items():
        samples = render(tone, rate, fade)
        write(OUT / f"{name}.wav", samples, rate)
        print(f"{name}.wav  {len(samples) / rate * 1000:.0f} ms  peak {20 * np.log10(np.max(np.abs(samples))):.1f} dBFS")


if __name__ == "__main__":
    main()
