"""Tiny procedural sound effects and music loops (16-bit mono WAV)."""
import math
import wave
import numpy as np

SR = 22050


def save(path, data, loop=False):
    data = np.clip(data, -1, 1)
    pcm = (data * 32000).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def t(sec):
    return np.arange(int(SR * sec)) / SR


def env(n, a=0.005, r=0.1):
    e = np.ones(n)
    na, nr = int(SR * a), int(SR * r)
    e[:na] = np.linspace(0, 1, na)
    e[-nr:] *= np.linspace(1, 0, nr)
    return e


def tone(freq, sec, kind="sine", decay=6.0, vol=0.5):
    x = t(sec)
    if kind == "sine":
        s = np.sin(2 * np.pi * freq * x)
    elif kind == "square":
        s = np.sign(np.sin(2 * np.pi * freq * x)) * 0.5
    elif kind == "pluck":
        s = (np.sin(2 * np.pi * freq * x) + 0.5 * np.sin(4 * np.pi * freq * x) + 0.25 * np.sin(6 * np.pi * freq * x)) / 1.75
    elif kind == "tri":
        s = 2 * np.abs(2 * (x * freq - np.floor(x * freq + 0.5))) - 1
    return s * np.exp(-decay * x) * vol * env(len(x), r=0.02)


def noise(sec, vol=0.5, seed=0):
    return np.random.RandomState(seed).uniform(-1, 1, int(SR * sec)) * vol


def lowpass(x, k):
    k = max(1, int(k))
    c = np.cumsum(np.insert(x, 0, 0))
    y = (c[k:] - c[:-k]) / k
    return np.concatenate([y, np.zeros(k - 1)])


def cat(*parts):
    return np.concatenate(parts)


def note(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def music(melody, bass, bpm, kind="pluck", vol=0.28, pad=None):
    beat = 60.0 / bpm
    total = sum(d for _, d in melody) * beat
    out = np.zeros(int(SR * total) + SR)
    pos = 0.0
    for n, d in melody:
        if n is not None:
            s = tone(note(n), d * beat * 1.6, kind, decay=2.5, vol=vol)
            i = int(pos * SR)
            out[i:i + len(s)] += s[: len(out) - i]
        pos += d * beat
    pos = 0.0
    for n, d in bass:
        if n is not None:
            s = tone(note(n), d * beat * 1.2, "tri", decay=1.5, vol=vol * 0.6)
            i = int(pos * SR)
            out[i:i + len(s)] += s[: len(out) - i]
        pos += d * beat
    if pad:
        x = np.arange(len(out)) / SR
        for n in pad:
            out += np.sin(2 * np.pi * note(n) * x) * 0.03
    n = int(SR * total)
    loop = out[:n]
    # fold the tail back into the start so the loop is seamless
    tail = out[n:]
    loop[: len(tail)] += tail
    return loop


def build(out):
    save(f"{out}/blip.wav", tone(880, 0.04, "square", decay=30, vol=0.18))
    save(f"{out}/select.wav", cat(tone(660, 0.05, "square", 20, 0.2), tone(990, 0.07, "square", 20, 0.2)))
    save(f"{out}/pickup.wav", cat(tone(784, 0.07, "pluck", 12, 0.5), tone(1175, 0.15, "pluck", 10, 0.5)))
    save(f"{out}/coin.wav", cat(tone(1319, 0.05, "square", 18, 0.25), tone(1760, 0.18, "square", 14, 0.25)))
    save(f"{out}/quest.wav", cat(*[tone(note(n), 0.16, "pluck", 6, 0.45) for n in (67, 71, 74, 79)]))
    save(f"{out}/clue.wav", cat(tone(note(57), 0.4, "pluck", 3, 0.5), tone(note(60), 0.4, "pluck", 3, 0.5), tone(note(64), 0.8, "pluck", 2, 0.5)))
    d = lowpass(noise(0.25, 0.8, 1), 6) * np.exp(-14 * t(0.25))
    save(f"{out}/door.wav", d + tone(110, 0.25, "sine", 10, 0.4))
    chop = lowpass(noise(0.18, 1.0, 2), 3) * np.exp(-25 * t(0.18)) + tone(180, 0.18, "sine", 20, 0.5)
    save(f"{out}/chop.wav", chop)
    save(f"{out}/hammer.wav", tone(1400, 0.2, "sine", 25, 0.4) + tone(2100, 0.2, "sine", 30, 0.2) + noise(0.2, 0.2, 3) * np.exp(-40 * t(0.2)))
    sp = lowpass(noise(0.5, 0.9, 4), 4) * np.exp(-6 * t(0.5))
    save(f"{out}/splash.wav", sp)
    save(f"{out}/step.wav", lowpass(noise(0.06, 0.5, 5), 8) * np.exp(-50 * t(0.06)))
    save(f"{out}/fail.wav", cat(tone(330, 0.12, "square", 10, 0.2), tone(247, 0.25, "square", 8, 0.2)))
    # ambience: waves (slow swelling filtered noise)
    sec = 12.0
    n = lowpass(noise(sec, 1.0, 7), 18)
    swell = 0.55 + 0.45 * np.sin(2 * np.pi * t(sec) / 6.0) ** 2
    save(f"{out}/amb_sea.wav", n * swell * 0.5)
    wind = lowpass(noise(sec, 1.0, 8), 40) * (0.6 + 0.4 * np.sin(2 * np.pi * t(sec) / 4.0))
    save(f"{out}/amb_wind.wav", wind * 0.6)
    fire = lowpass(noise(6.0, 1.0, 9), 10) * 0.25
    crack = np.random.RandomState(10).rand(len(fire)) > 0.9993
    fire[crack] += 0.6
    save(f"{out}/amb_fire.wav", fire)

    # music: a calm folk tune in D dorian for the village
    M = [(62, 1), (64, 1), (65, 1), (69, 1), (67, 2), (65, 1), (64, 1),
         (62, 1), (60, 1), (62, 2), (None, 2),
         (69, 1), (71, 1), (72, 1), (71, 1), (69, 2), (67, 1), (65, 1),
         (64, 1), (65, 1), (64, 1), (60, 1), (62, 4)]
    B = [(38, 4), (43, 4), (41, 4), (45, 4), (38, 4), (36, 4), (41, 4), (38, 4)]
    save(f"{out}/music_village.wav", music(M + M, B + B, 84))
    # home: slower, warmer
    M2 = [(67, 2), (69, 1), (71, 1), (74, 3), (72, 1), (71, 2), (69, 2), (67, 4),
          (64, 2), (67, 2), (69, 3), (67, 1), (66, 2), (62, 2), (67, 4)]
    B2 = [(43, 4), (48, 4), (47, 4), (43, 4), (40, 4), (45, 4), (43, 4), (43, 4)]
    save(f"{out}/music_home.wav", music(M2, B2, 72, vol=0.25))
    # mystery: sparse notes over a low drone
    M3 = [(57, 3), (None, 1), (60, 2), (59, 2), (None, 2), (56, 4), (None, 2),
          (57, 3), (None, 1), (64, 2), (62, 2), (60, 2), (59, 4), (None, 2)]
    B3 = [(33, 8), (32, 8), (33, 8), (28, 8)]
    save(f"{out}/music_mystery.wav", music(M3, B3, 70, kind="sine", vol=0.22, pad=[45, 52]))
    # estate: elegant waltz-ish arpeggios
    M4 = []
    for root in (60, 65, 67, 60, 57, 62, 67, 60):
        M4 += [(root, 1), (root + 4, 1), (root + 7, 1)]
    B4 = [(36, 3), (41, 3), (43, 3), (36, 3), (33, 3), (38, 3), (43, 3), (36, 3)]
    save(f"{out}/music_estate.wav", music(M4, B4, 96, vol=0.2))
    # ending theme
    M5 = [(62, 2), (66, 2), (69, 2), (74, 4), (73, 2), (71, 2), (69, 4),
          (67, 2), (69, 2), (71, 2), (69, 2), (66, 2), (64, 2), (62, 6)]
    B5 = [(38, 8), (43, 8), (45, 8), (38, 8)]
    save(f"{out}/music_ending.wav", music(M5, B5, 66, vol=0.26, pad=[50, 57]))
