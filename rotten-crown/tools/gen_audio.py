#!/usr/bin/env python3
"""Render the placeholder soundtrack/SFX to WAV (numpy only, no samples).

  python3 tools/gen_audio.py        -> assets/audio/**.wav

Loops carry a RIFF 'smpl' chunk so Godot's importer loops them automatically.
Replace these with recorded/composed audio in the art & audio phase.
"""
import struct
import sys
import wave
from pathlib import Path

import numpy as np

SR = 22050
ROOT = Path(__file__).resolve().parent.parent / "assets" / "audio"
rng = np.random.default_rng(7)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def save(path, data, loop=False, level=0.89):
    data = np.asarray(data, dtype=np.float64)
    peak = np.max(np.abs(data)) or 1.0
    pcm = (np.clip(data / peak * level, -1, 1) * 32767).astype("<i2")
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


def rain(seconds=24.0):
    n = int(seconds * SR)
    white = rng.normal(0, 1, n)
    hiss = white - lowpass(white, 0.15)  # high-passed noise
    hiss = lowpass(hiss, 0.7) * 0.22
    t = np.arange(n) / SR
    swell = 0.85 + 0.15 * np.sin(2 * np.pi * t / seconds * 4 + 0.7)
    ticks = np.zeros(n)
    for _ in range(int(seconds * 90)):
        i = rng.integers(0, n - 300)
        k = rng.integers(30, 300)
        f = rng.uniform(1500, 5000)
        tt = np.arange(k) / SR
        ticks[i:i + k] += np.sin(2 * np.pi * f * tt) * np.exp(-tt * rng.uniform(300, 900)) * rng.uniform(0.1, 0.6)
    roof = lowpass(rng.normal(0, 1, n), 0.04) * 0.9
    drum = np.zeros(n)
    for _ in range(int(seconds * 25)):
        i = rng.integers(0, n - 2000)
        k = rng.integers(600, 2000)
        tt = np.arange(k) / SR
        drum[i:i + k] += np.sin(2 * np.pi * rng.uniform(70, 140) * tt) * np.exp(-tt * 40) * rng.uniform(0.2, 0.8)
    out = (hiss + roof * 0.08 + ticks * 0.25 + drum * 0.15) * swell
    fade = int(1.0 * SR)
    out[:fade] = out[:fade] * np.linspace(0, 1, fade) + out[-fade:] * np.linspace(1, 0, fade)
    return out


def thunder(seconds=6.0, crack=False):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    noise = rng.normal(0, 1, n)
    rumble = lowpass(lowpass(noise, 0.02), 0.05)
    roll = 0.6 + 0.4 * np.sin(2 * np.pi * (0.9 * t + 0.3 * np.sin(2 * np.pi * 0.37 * t)))
    body = rumble * roll * np.minimum(t / 0.4, 1) * np.exp(-t / 2.2)
    body = body / (np.max(np.abs(body)) or 1.0)
    out = body * 0.9
    if crack:
        k = int(0.5 * SR)
        tc = np.arange(k) / SR
        snap = (noise[:k] - lowpass(noise[:k], 0.1)) * np.exp(-tc * 14)
        out[:k] += snap * 0.9 / (np.max(np.abs(snap)) or 1.0)
        out[:int(0.01 * SR)] *= np.linspace(0, 1, int(0.01 * SR))
    return out


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


# --- Witness static and garbled voices (own RNG: existing outputs unchanged) ----
WRNG = np.random.default_rng(11)
PEAK_MINUS6 = 10 ** (-6 / 20)  # -6 dBFS peak


def lowpass_var(x, alpha):
    """One-pole lowpass with a per-sample coefficient alpha (array)."""
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += alpha[i] * (x[i] - acc)
        y[i] = acc
    return y


def clicks(n, count, decay_ms=(0.4, 2.5), amp=(0.3, 1.0), weights=None):
    """Random crackle impulses (short decaying ticks), optionally weighted in time."""
    out = np.zeros(n)
    if weights is None:
        pos = WRNG.integers(0, n - 200, count)
    else:
        pos = WRNG.choice(n - 200, count, p=weights)
    for i in pos:
        k = int(WRNG.uniform(*decay_ms) * 0.001 * SR * 4) + 8
        tt = np.arange(k) / SR
        tau = WRNG.uniform(*decay_ms) * 0.001
        out[i:i + k] += WRNG.normal(0, 1) * np.exp(-tt / tau) * WRNG.uniform(*amp)
    return out


def static_burst(seconds=0.6):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    white = WRNG.normal(0, 1, n)
    # Falling filter: bright hiss at the hit, dark tail at the end.
    alpha = 0.03 + 0.6 * np.exp(-t * 9)
    body = lowpass_var(white, alpha) * 1.2 + 0.35 * white * np.exp(-t * 14)
    crack = clicks(n, 70, decay_ms=(0.3, 1.5), amp=(0.4, 1.0),
                   weights=(np.exp(-np.arange(n - 200) / SR * 6) / np.sum(np.exp(-np.arange(n - 200) / SR * 6))))
    env = np.minimum(t / 0.002, 1) * np.exp(-t * 5.0) * np.clip((seconds - t) / 0.01, 0, 1)
    return (body * 0.8 + crack * 0.6) * env


def static_loop(seconds=2.0):
    fade = int(0.05 * SR)
    n = int(seconds * SR) + fade
    t = np.arange(n) / SR
    white = WRNG.normal(0, 1, n)
    hiss = lowpass_var(white, np.full(n, 0.35)) * 0.6 + (white - lowpass_var(white, np.full(n, 0.35))) * 0.25
    # Three integer cycles over the loop length keep the wobble seamless.
    wobble = 0.75 + 0.25 * np.sin(2 * np.pi * 3 * t / seconds + 0.4)
    # Two drop-outs away from the seam.
    dropout = np.ones(n)
    for start, length in ((0.35, 0.04), (1.42, 0.025)):
        i0, i1 = int(start * SR), int((start + length) * SR)
        dropout[i0:i1] = 0.05
        dropout[i0:i0 + 66] = np.linspace(1, 0.05, 66)
        dropout[i1 - 66:i1] = np.linspace(0.05, 1, 66)
    crack = clicks(n, 30, decay_ms=(0.5, 2.0), amp=(0.3, 1.0))
    out = (hiss * 0.5 + crack * 0.6) * wobble * dropout
    # Equal-power crossfade of the tail into the head, then trim to length.
    theta = np.linspace(0, np.pi / 2, fade)
    head, tail = out[:fade], out[-fade:]
    out[:fade] = head * np.sin(theta) + tail * np.cos(theta)
    return out[:-fade]


def _formant_env(f, formants):
    """Vocal-tract style envelope: sum of gaussian formant peaks plus a floor."""
    env = np.full(np.shape(f), 0.02)
    for fc, bw, amp in formants:
        env = env + amp * np.exp(-0.5 * ((f - fc) / bw) ** 2)
    return env


def syllable(dur, f0, glide, formants, noise_amt):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = f0 * (1 + glide * t / dur)
    phase = 2 * np.pi * np.cumsum(f) / SR
    voiced = np.zeros(n)
    k = 1
    while k * f0 < 3800:
        voiced += _formant_env(k * f0, formants) / k ** 0.7 * np.sin(k * phase)
        k += 1
    voiced /= np.max(np.abs(voiced)) or 1.0
    # Formant-shaped aspiration noise (spectral filtering via FFT).
    spec = np.fft.rfft(WRNG.normal(0, 1, n))
    spec *= _formant_env(np.fft.rfftfreq(n, 1 / SR), formants)
    hiss = np.fft.irfft(spec, n)
    hiss /= np.max(np.abs(hiss)) or 1.0
    body = voiced * (1 - noise_amt) + hiss * noise_amt
    return body * np.minimum(t / 0.02, 1) * np.sin(np.pi * t / dur) ** 0.7


def random_vowel():
    f1 = WRNG.uniform(300, 800)
    f2 = WRNG.uniform(max(900, f1 + 300), 2500)
    f3 = WRNG.uniform(2500, 3300)
    return [(f1, 70, 1.0), (f2, 110, 0.6), (f3, 160, 0.25)]


def garble(seconds, f0=(100, 160), glide=(-0.3, 0.1), syll=(0.12, 0.25),
           gap=(0.04, 0.3), noise=0.4, pause_chance=0.1, reverse=False,
           drop=None, ring=None, ring_mix=0.0, static=0.0):
    total = int(seconds * SR)
    out = np.zeros(total * 2)
    pos = 0.05
    while pos < seconds * 1.4:
        dur = WRNG.uniform(*syll)
        s = syllable(dur, WRNG.uniform(*f0), WRNG.uniform(*glide), random_vowel(), noise)
        i = int(pos * SR)
        out[i:i + len(s)] += s * WRNG.uniform(0.6, 1.0)
        pos += dur + WRNG.uniform(*gap)
        if WRNG.random() < pause_chance:
            pos += WRNG.uniform(0.25, 0.6)
    y = out[:int(seconds * 1.4 * SR)]
    if drop:  # pitch drop by resampling (ratio < 1 is lower and slower)
        idx = np.arange(int(len(y) / drop)) * drop
        y = np.interp(idx, np.arange(len(y)), y)
    if ring:
        t = np.arange(len(y)) / SR
        y = y * (1 - ring_mix) + y * np.sin(2 * np.pi * ring * t) * ring_mix
    if reverse:
        y = y[::-1]
    y = y[:total]
    if len(y) < total:
        y = np.concatenate([y, np.zeros(total - len(y))])
    fade = int(0.01 * SR)
    y[:fade] *= np.linspace(0, 1, fade)
    y[-fade:] *= np.linspace(1, 0, fade)
    if static:
        y = y + clicks(total, int(seconds * 40), amp=(0.2, 0.8)) * static
        y = y + lowpass_var(WRNG.normal(0, 1, total), np.full(total, 0.2)) * static * 0.5
    return y


VOICE_SPECS = [
    dict(seconds=2.6, f0=(90, 120), glide=(-0.35, -0.15), syll=(0.18, 0.3), gap=(0.05, 0.3),
         noise=0.3, reverse=True),
    dict(seconds=1.8, f0=(200, 260), glide=(0.15, 0.3), syll=(0.08, 0.16), gap=(0.02, 0.12),
         noise=0.5, ring=47, ring_mix=0.5),
    dict(seconds=2.9, f0=(130, 170), glide=(-0.2, 0.0), syll=(0.15, 0.25), gap=(0.1, 0.45),
         noise=0.35, pause_chance=0.35, drop=0.6, static=0.05),
    dict(seconds=2.2, f0=(110, 150), glide=(-0.1, 0.1), syll=(0.12, 0.25), gap=(0.02, 0.5),
         noise=0.85, reverse=True, ring=130, ring_mix=0.3, static=0.08),
]


def make_witness():
    save(ROOT / "sfx" / "static_burst.wav", static_burst(), level=PEAK_MINUS6)
    save(ROOT / "sfx" / "static_loop.wav", static_loop(), loop=True, level=PEAK_MINUS6)
    for i, spec in enumerate(VOICE_SPECS, 1):
        save(ROOT / "voices" / f"garble_{i}.wav", garble(**spec), level=PEAK_MINUS6)


if __name__ == "__main__":
    if sys.argv[1:] == ["witness"]:
        make_witness()
        sys.exit(0)
    save(ROOT / "music" / "festive_jig.wav", jig(), loop=True)
    save(ROOT / "ambience" / "night_wind.wav", wind(), loop=True)
    save(ROOT / "ambience" / "bonfire.wav", fire(), loop=True)
    save(ROOT / "sfx" / "firework.wav", firework())
    save(ROOT / "ambience" / "rain.wav", rain(), loop=True)
    save(ROOT / "sfx" / "thunder_roll.wav", thunder(7.0))
    save(ROOT / "sfx" / "thunder_crack.wav", thunder(5.0, crack=True))
