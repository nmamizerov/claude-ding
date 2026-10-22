#!/usr/bin/env python3
"""Generates the 10 bundled sounds from scratch (pure synthesis, no samples).

Everything in sounds/ is produced by this script, so the repo carries no
third-party audio. Re-run after tweaking:  python3 tools/generate_sounds.py
"""
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sounds")


def t(dur):
    return np.linspace(0, dur, int(SR * dur), endpoint=False)


def env(n, attack=0.005, decay=6.0):
    x = np.arange(n) / SR
    a = np.clip(x / attack, 0, 1)
    return a * np.exp(-decay * x)


def tone(freq, dur, decay=6.0, harmonics=((1, 1.0),), attack=0.005):
    x = t(dur)
    sig = sum(amp * np.sin(2 * np.pi * freq * h * x) for h, amp in harmonics)
    return sig * env(len(x), attack, decay)


def seq(*parts, gap=0.0):
    """Overlap-add notes: parts are (start_seconds, signal)."""
    end = max(s + len(p) / SR for s, p in parts) + gap
    out = np.zeros(int(SR * end) + 1)
    for s, p in parts:
        i = int(SR * s)
        out[i:i + len(p)] += p
    return out


def sweep(f0, f1, dur, decay=8.0, shape="sine"):
    x = t(dur)
    f = np.geomspace(f0, f1, len(x))
    ph = 2 * np.pi * np.cumsum(f) / SR
    w = np.sin(ph) if shape == "sine" else np.sign(np.sin(ph)) * 0.5
    return w * env(len(x), 0.002, decay)


def square(freq, dur, decay=4.0):
    x = t(dur)
    return 0.45 * np.sign(np.sin(2 * np.pi * freq * x)) * env(len(x), 0.001, decay)


BELL = ((1, 1.0), (2.76, 0.45), (5.4, 0.25), (8.93, 0.1))
MARIMBA = ((1, 1.0), (4, 0.3), (10, 0.05))
SOFT = ((1, 1.0), (2, 0.25), (3, 0.08))


def coin_clink(rng, f0, amp=1.0, dur=0.35):
    """One metal coin hitting other coins: inharmonic partials + a tiny noise click."""
    x = t(dur)
    n = len(x)
    ratios = (1.0, 1.47, 2.09, 2.56, 3.37)
    amps = (1.0, 0.7, 0.5, 0.35, 0.2)
    sig = np.zeros(n)
    for k, (rt, a) in enumerate(zip(ratios, amps)):
        f = f0 * rt * rng.uniform(0.995, 1.005)
        dec = rng.uniform(18, 28) * (1 + 0.6 * k)
        beat = 1 + 0.25 * np.sin(2 * np.pi * rng.uniform(4, 12) * x)  # shimmer
        sig += a * np.sin(2 * np.pi * f * x + rng.uniform(0, 6.28)) * np.exp(-dec * x) * beat
    click_n = int(SR * 0.004)
    click = np.diff(rng.standard_normal(click_n + 1)) * np.exp(-np.arange(click_n) / (SR * 0.0008))
    sig[:click_n] += 0.3 * click
    return amp * sig * env(n, 0.0005, 0)


def coins():
    """A small handful of coins dropping onto a pile, each with a quick bounce."""
    rng = np.random.default_rng(7)
    parts, t0 = [], 0.0
    gaps = (0.0, 0.09, 0.07, 0.12, 0.016, 0.1, 0.08, 0.14)
    amps = (1.0, 0.8, 0.9, 0.6, 0.55, 0.7, 0.45, 0.35)
    for gap, a in zip(gaps, amps):
        t0 += gap
        f0 = rng.uniform(2000, 3400)
        parts.append((t0, coin_clink(rng, f0, a)))
        parts.append((t0 + rng.uniform(0.03, 0.05), coin_clink(rng, f0 * rng.uniform(0.98, 1.02), a * 0.3, 0.2)))
    return seq(*parts)


def make():
    s = {}
    # 1. chime: two soft bell notes, up a fifth
    s["chime"] = seq((0, tone(784, 1.2, 4, BELL)), (0.12, tone(1175, 1.2, 4, BELL)))
    # 2. ping: one clean high note
    s["ping"] = tone(1568, 0.8, 7, SOFT)
    # 3. pop: short downward blip
    s["pop"] = sweep(900, 250, 0.09, 30)
    # 4. bubble: rising wobble
    x = t(0.25)
    f = 400 + 900 * (x / 0.25) ** 2 + 60 * np.sin(2 * np.pi * 30 * x)
    s["bubble"] = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(x), 0.005, 10)
    # 5. coins: real metal coins dropping onto a pile
    s["coins"] = coins()
    # 6. blip: three quick ascending ticks
    s["blip"] = seq(*[(i * 0.07, tone(f, 0.12, 25, SOFT)) for i, f in enumerate((880, 1109, 1319))])
    # 7. marimba: friendly three-note phrase
    s["marimba"] = seq(*[(i * 0.13, tone(f, 0.6, 9, MARIMBA)) for i, f in enumerate((523, 659, 784))])
    # 8. bell: single deep bell, long tail
    s["bell"] = tone(523, 2.0, 2.2, BELL)
    # 9. levelup: fast major arpeggio ending on octave
    notes = (523, 659, 784, 1047)
    s["levelup"] = seq(*[(i * 0.07, square(f, 0.3 if i == 3 else 0.09, 6 if i == 3 else 3)) for i, f in enumerate(notes)])
    # 10. droplet: water drop (quick rising sine)
    s["droplet"] = seq((0, sweep(600, 1800, 0.12, 20)), (0.1, sweep(900, 2000, 0.08, 30) * 0.4))
    return s


def save(name, sig):
    sig = sig / (np.max(np.abs(sig)) + 1e-9) * 0.4  # quiet by default; play.sh scales further by volume
    fade = min(len(sig), int(SR * 0.01))
    sig[-fade:] *= np.linspace(1, 0, fade)
    pcm = (sig * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for i, (name, sig) in enumerate(make().items(), 1):
        save(f"{i:02d}-{name}", sig)
        print(f"{i:02d}-{name}.wav  {len(sig) / SR:.2f}s")
