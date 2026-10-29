"""Generates Zemu's sound packs into app/src/main/assets/sounds/pack-<name>/ (python3 tools/make_sound_packs.py)."""
import os, wave
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "app", "src", "main", "assets", "sounds")


def t(dur):
    return np.arange(int(SR * dur)) / SR


def env(dur, attack=0.004, decay=0.08):
    x = t(dur)
    e = np.exp(-x / decay)
    a = int(SR * attack)
    e[:a] *= np.linspace(0, 1, a)
    return e


def lowpass(x, cutoff):
    a = 1 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x); s = 0.0
    for i, v in enumerate(x):
        s += a * (v - s); y[i] = s
    return y


def seq(*parts, gap=0.0):
    """Notes one after another, each starting gap seconds after the previous one started (overlapping)."""
    n = max(int(SR * gap) * i + len(p) for i, p in enumerate(parts))
    out = np.zeros(n)
    for i, p in enumerate(parts):
        s = int(SR * gap) * i
        out[s:s + len(p)] += p
    return out


def echo(x, delay=0.12, feedback=0.35, taps=3):
    d = int(SR * delay)
    out = np.concatenate([x, np.zeros(d * taps)])
    for k in range(1, taps + 1):
        out[d * k:d * k + len(x)] += x * feedback ** k
    return out


# ---- Instruments ----

def wood(f, dur=0.12):
    x = t(dur)
    return (np.sin(2 * np.pi * f * x) + 0.25 * np.sin(2 * np.pi * f * 3.93 * x) * env(dur, decay=0.012)) * env(dur, 0.002, 0.035)


def bubble(f0, f1, dur=0.07):
    x = t(dur)
    f = f0 + (f1 - f0) * (x / dur)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(dur, 0.003, dur / 3)


def keys(f, dur=0.35):
    x = t(dur)
    s = sum(np.sin(2 * np.pi * f * n * x) / n ** 2 for n in range(1, 6))
    return lowpass(s * env(dur, 0.006, 0.12), 1400)


def cosmic(f, dur=0.25):
    x = t(dur)
    s = np.sin(2 * np.pi * f * x) + 0.6 * np.sin(2 * np.pi * f * 1.004 * x) + 0.15 * np.sin(2 * np.pi * f * 2 * x)
    return s * env(dur, 0.015, 0.07)


def retro(f, dur=0.06):
    x = t(dur)
    sq = np.sign(np.sin(2 * np.pi * f * x))
    return lowpass(sq * env(dur, 0.002, dur / 2.5), 1200)


def note(n):
    """Semitones from A4."""
    return 440 * 2 ** (n / 12)


C3, E3, G3, A3, C4, D4, E4, G4, A4 = (note(n) for n in (-21, -17, -14, -12, -9, -7, -5, -2, 0))

PACKS = {
    "wood": dict(
        move=wood(G3, 0.09),
        select=seq(wood(C4), wood(G4), gap=0.06),
        hold=seq(wood(C4), wood(E4), wood(G4, 0.2), gap=0.07),
        back=seq(wood(G4), wood(C4), gap=0.06),
    ),
    "bubbles": dict(
        move=bubble(380, 620, 0.05),
        select=bubble(300, 700, 0.09),
        hold=seq(bubble(260, 520, 0.08), bubble(340, 760, 0.09), gap=0.08),
        back=bubble(620, 280, 0.09),
    ),
    "keys": dict(
        move=keys(E4, 0.12),
        select=seq(keys(C4), keys(G4), gap=0.05),
        hold=seq(keys(C4, 0.5), keys(E4, 0.5), keys(G4, 0.5), keys(C4 * 2, 0.6), gap=0.06),
        back=seq(keys(G4), keys(D4), gap=0.06),
    ),
    "cosmic": dict(
        move=cosmic(A3, 0.12),
        select=echo(seq(cosmic(D4), cosmic(A4), gap=0.07)),
        hold=echo(seq(cosmic(A3), cosmic(D4), cosmic(E4), cosmic(A4, 0.4), gap=0.08)),
        back=echo(seq(cosmic(A4), cosmic(D4), gap=0.07)),
    ),
    "retro": dict(
        move=retro(A3, 0.035),
        select=seq(retro(C4), retro(G4, 0.09), gap=0.05),
        hold=seq(retro(C4), retro(E4), retro(G4), retro(C4 * 2, 0.12), gap=0.05),
        back=seq(retro(G4), retro(C4, 0.09), gap=0.05),
    ),
}

# Quiet: move the quietest (it repeats), the rest a little louder.
LEVEL = dict(move=0.22, select=0.3, hold=0.3, back=0.28)

for pack, sounds in PACKS.items():
    d = os.path.join(OUT, f"pack-{pack}")
    os.makedirs(d, exist_ok=True)
    for name, s in sounds.items():
        fade = int(SR * 0.01)
        s = s.copy(); s[-fade:] *= np.linspace(1, 0, fade)
        s = s / np.abs(s).max() * LEVEL[name]
        with wave.open(os.path.join(d, f"{name}.wav"), "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
            w.writeframes((s * 32767).astype("<i2").tobytes())
    print(pack, {k: f"{len(v) / SR:.2f}s" for k, v in sounds.items()})
