#!/usr/bin/env python3
"""Render the placeholder soundtrack/SFX to WAV (numpy only, no samples).

  python3 tools/gen_audio.py        -> assets/audio/**.wav

Loops carry a RIFF 'smpl' chunk so Godot's importer loops them automatically.
Replace these with recorded/composed audio in the art & audio phase.
"""
import struct
import wave
from pathlib import Path

import numpy as np

SR = 22050
ROOT = Path(__file__).resolve().parent.parent / "assets" / "audio"
rng = np.random.default_rng(7)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def save(path, data, loop=False):
    data = np.asarray(data, dtype=np.float64)
    peak = np.max(np.abs(data)) or 1.0
    pcm = (np.clip(data / peak * 0.89, -1, 1) * 32767).astype("<i2")
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    if loop:
        # Append a 'smpl' chunk with one forward loop over the whole file.
        smpl = struct.pack("<9I", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, len(pcm) - 1, 0, 0)
        raw = bytearray(path.read_bytes())
        raw += b"smpl" + struct.pack("<I", len(smpl)) + smpl
        struct.pack_into("<I", raw, 4, len(raw) - 8)
        path.write_bytes(bytes(raw))
    print(f"{path.relative_to(ROOT.parent.parent)}  {len(pcm) / SR:.1f}s")


def lowpass(x, alpha):
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y


def env(n, attack=0.01, release=0.2):
    t = np.arange(n) / SR
    a = np.clip(t / attack, 0, 1)
    r = np.clip((n / SR - t) / release, 0, 1)
    return a * r


def pluck(freq, dur, bright=0.5):
    """Karplus-Strong plucked string (lute)."""
    n = int(dur * SR)
    period = max(2, int(SR / freq))
    buf = rng.uniform(-1, 1, period)
    out = np.empty(n)
    for i in range(n):
        j = i % period
        out[i] = buf[j]
        buf[j] = 0.996 * (bright * buf[j] + (1 - bright) * buf[(j + 1) % period])
    return out * env(n, 0.002, 0.05)


def recorder(freq, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * t) * np.clip(t / 0.15, 0, 1)
    phase = np.cumsum(2 * np.pi * freq * vib / SR)
    tone = np.sin(phase) + 0.25 * np.sin(2 * phase) + 0.08 * np.sin(3 * phase)
    breath = rng.normal(0, 0.03, n)
    return (tone + breath) * env(n, 0.02, 0.06)


# --- Festive jig (D dorian, 6/8) ------------------------------------------------
EIGHTH = 0.19
MELODY = [
    (74, 2), (69, 1), (65, 1), (67, 1), (69, 1), (72, 2), (69, 1), (67, 2), (65, 1),
    (64, 1), (65, 1), (67, 1), (69, 2), (67, 1), (65, 1), (64, 1), (62, 1), (62, 3),
    (74, 2), (76, 1), (74, 1), (72, 1), (69, 1), (72, 2), (74, 1), (76, 2), (74, 1),
    (72, 1), (69, 1), (67, 1), (65, 1), (67, 1), (69, 1), (67, 1), (65, 1), (64, 1), (62, 3),
    (69, 1), (72, 1), (74, 1), (76, 2), (74, 1), (72, 1), (74, 1), (72, 1), (69, 3),
    (67, 1), (69, 1), (72, 1), (74, 2), (72, 1), (69, 1), (67, 1), (65, 1), (64, 3),
    (65, 1), (67, 1), (69, 1), (72, 2), (69, 1), (74, 2), (72, 1), (69, 2), (67, 1),
    (65, 1), (67, 1), (69, 1), (67, 1), (65, 1), (64, 1), (62, 3), (62, 3),
]
CHORDS = {62: (50, 53, 57), 60: (48, 52, 55), 67: (43, 47, 50), 69: (45, 48, 52), 64: (40, 43, 47), 65: (41, 45, 48)}
BAR_ROOTS = [62, 60, 67, 62, 62, 60, 67, 62, 69, 60, 67, 64, 65, 62, 60, 62]


def jig():
    bars = len(BAR_ROOTS)
    total = int(bars * 6 * EIGHTH * SR)
    mix = np.zeros(total + SR)
    pos = 0
    for note, length in MELODY:
        start = int(pos * EIGHTH * SR)
        tone = recorder(midi(note), length * EIGHTH * 0.95)
        mix[start:start + len(tone)] += tone * 0.32
        pos += length
    for b, root in enumerate(BAR_ROOTS):
        chord = CHORDS[root]
        for k, step in enumerate((0, 2, 3, 5)):
            start = int((b * 6 + step) * EIGHTH * SR)
            n = chord[k % 3] + (12 if k == 3 else 0)
            p = pluck(midi(n), EIGHTH * 2.2, 0.55)
            mix[start:start + len(p)] += p * (0.3 if k == 0 else 0.2)
        # Frame drum on beats 1 and 4, tambourine on the offbeats.
        for step, strength in ((0, 1.0), (3, 0.7)):
            start = int((b * 6 + step) * EIGHTH * SR)
            n = int(0.25 * SR)
            t = np.arange(n) / SR
            drum = np.sin(2 * np.pi * (95 - 50 * t / 0.25) * t) * np.exp(-t * 18) + rng.normal(0, 0.15, n) * np.exp(-t * 40)
            mix[start:start + n] += drum * 0.5 * strength
        for step in (1, 2, 4, 5):
            start = int((b * 6 + step) * EIGHTH * SR)
            n = int(0.07 * SR)
            t = np.arange(n) / SR
            jingle = rng.normal(0, 1, n) * np.exp(-t * 60) * np.sin(2 * np.pi * 7000 * t)
            mix[start:start + n] += jingle * 0.07
    # Hurdy-gurdy drone: D + A, buzzy and slightly beating.
    t = np.arange(len(mix)) / SR
    drone = sum(np.sign(np.sin(2 * np.pi * midi(n) * f * t)) for n in (38, 45) for f in (1.0, 1.003))
    mix += lowpass(drone * 0.035, 0.08)
    mix = mix[:total]
    # Crossfade the tail into the head so the loop is seamless.
    fade = int(0.05 * SR)
    mix[:fade] = mix[:fade] * np.linspace(0, 1, fade) + mix[-fade:] * np.linspace(1, 0, fade)
    return mix


def wind(seconds=24.0):
    n = int(seconds * SR)
    white = rng.normal(0, 1, n)
    brown = np.cumsum(white)
    brown -= lowpass(brown, 0.0005)
    t = np.arange(n) / SR
    gust = 0.5 + 0.5 * np.sin(2 * np.pi * t / seconds * 3) * np.sin(2 * np.pi * t / seconds * 7 + 1.3)
    howl = lowpass(white, 0.02) * (0.3 + gust)
    drone = (np.sin(2 * np.pi * 55 * t) + np.sin(2 * np.pi * 55.4 * t)) * 0.02
    out = brown * 0.002 * (0.4 + gust) + howl * 0.4 + drone
    fade = int(1.0 * SR)
    out[:fade] = out[:fade] * np.linspace(0, 1, fade) + out[-fade:] * np.linspace(1, 0, fade)
    return out[:-fade] if False else out


def fire(seconds=6.0):
    n = int(seconds * SR)
    rumble = lowpass(rng.normal(0, 1, n), 0.01) * 0.6
    crackle = np.zeros(n)
    for _ in range(int(seconds * 26)):
        i = rng.integers(0, n - 400)
        k = rng.integers(40, 400)
        crackle[i:i + k] += rng.normal(0, 1, k) * np.exp(-np.arange(k) / (k / 5)) * rng.uniform(0.2, 1.0)
    out = rumble + crackle * 0.5
    fade = int(0.2 * SR)
    out[:fade] = out[:fade] * np.linspace(0, 1, fade) + out[-fade:] * np.linspace(1, 0, fade)
    return out


def firework():
    whistle_n = int(0.9 * SR)
    t = np.arange(whistle_n) / SR
    whistle = np.sin(2 * np.pi * np.cumsum(900 + 1400 * t / 0.9) / SR) * np.linspace(0.05, 0.25, whistle_n)
    boom_n = int(2.2 * SR)
    tb = np.arange(boom_n) / SR
    boom = lowpass(rng.normal(0, 1, boom_n), 0.05) * np.exp(-tb * 3.5) * 2.5
    sparkle = rng.normal(0, 1, boom_n) * (rng.random(boom_n) > 0.995) * np.exp(-tb * 1.5) * 0.6
    return np.concatenate([whistle, boom + sparkle])


if __name__ == "__main__":
    save(ROOT / "music" / "festive_jig.wav", jig(), loop=True)
    save(ROOT / "ambience" / "night_wind.wav", wind(), loop=True)
    save(ROOT / "ambience" / "bonfire.wav", fire(), loop=True)
    save(ROOT / "sfx" / "firework.wav", firework())
