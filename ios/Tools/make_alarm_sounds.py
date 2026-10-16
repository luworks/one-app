#!/usr/bin/env python3
"""Synthesizes the app's alarm tones into ios/One/Sounds/*.caf (numpy + macOS afconvert).

AlarmKit cannot use Apple's ringtones, only sound files bundled with the app, so the tones are made here: soft, musical,
about 28 seconds long (the limit is 30) and getting a little louder as they go, so they wake you gently.
Run:  python3 ios/Tools/make_alarm_sounds.py
"""
import os, subprocess, tempfile, wave
import numpy as np

SR = 44100
LENGTH = 28.0
OUT = os.path.join(os.path.dirname(__file__), "..", "One", "Sounds")

N = dict(G4=392.0, A4=440.0, B4=493.88, C5=523.25, D5=587.33, E5=659.25, F5=698.46, G5=783.99, A5=880.0, B5=987.77,
         C6=1046.5, D6=1174.66, E6=1318.5, G6=1568.0, E4=329.63, C4=261.63)


def tone(freq, dur, partials, amps, decays, attack=0.004, vibrato=0.0):
    t = np.arange(int(SR * dur)) / SR
    y = np.zeros_like(t)
    for p, a, d in zip(partials, amps, decays):
        f = freq * p
        if f >= SR / 2: continue
        ph = 2 * np.pi * f * t + (vibrato * np.sin(2 * np.pi * 5.2 * t) if vibrato else 0)
        y += a * np.sin(ph) * np.exp(-d * t)
    env = np.minimum(1, t / attack) * np.minimum(1, (dur - t) / 0.03)
    return y * env


def bell(f, dur=2.5):    return tone(f, dur, [1, 2.76, 5.4, 8.93], [1, .35, .18, .08], [1.6, 2.6, 4, 6])
def chime(f, dur=3.5):   return tone(f, dur, [1, 2.0, 3.01, 4.2], [1, .3, .12, .05], [1.0, 1.8, 2.6, 4])
def marimba(f, dur=1.0): return tone(f, dur, [1, 4.0, 9.9], [1, .35, .08], [5, 11, 22], attack=0.002)
def glass(f, dur=4.0):   return tone(f, dur, [1, 2.0, 3.0, 4.07], [1, .45, .2, .1], [0.9, 1.5, 2.2, 3], attack=0.02, vibrato=0.25)
def kalimba(f, dur=1.6): return tone(f, dur, [1, 5.4, 12.0], [1, .12, .03], [3.2, 9, 18], attack=0.002)
def piano(f, dur=2.5):   return tone(f, dur, [1, 2, 3, 4, 5, 6], [1, .5, .28, .16, .08, .04], [1.3, 1.8, 2.4, 3, 3.8, 4.6], attack=0.006)
def crystal(f, dur=1.5): return tone(f, dur, [1, 2.0, 3.0, 5.0], [1, .5, .25, .12], [3, 4.5, 6, 9], attack=0.002, vibrato=0.1)
def beep(f, dur=0.22):   return tone(f, dur, [1, 2], [1, .12], [0, 0], attack=0.012)


def place(buf, y, start):
    i = int(start * SR)
    if i >= len(buf): return
    j = min(len(buf), i + len(y))
    buf[i:j] += y[:j - i]


def cycle(notes, voice, length, gain=1.0):
    """notes: (start, freq name, optional gain) within one cycle; repeated to fill the tone."""
    buf = np.zeros(int(SR * LENGTH))
    t = 0.0
    while t < LENGTH:
        for item in notes:
            s, n = item[0], item[1]
            g = item[2] if len(item) > 2 else 1.0
            place(buf, voice(N[n]) * g * gain, t + s)
        t += length
    return buf


def reverb(y, seconds=0.9, mix=0.22):
    rng = np.random.default_rng(7)
    n = int(SR * seconds)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / (SR * seconds / 5))
    ir[0] = 0
    ir /= np.abs(ir).sum() * 0.35
    wet = np.fft.irfft(np.fft.rfft(y, len(y) + n) * np.fft.rfft(ir, len(y) + n))[:len(y)]
    return (1 - mix) * y + mix * wet


def finish(y):
    y = reverb(y)
    t = np.arange(len(y)) / SR
    y *= 0.55 + 0.45 * np.minimum(1, t / 20.0)          # a little louder over the first 20 s
    y *= np.minimum(1, (LENGTH - t) / 0.4) * np.minimum(1, t / 0.02)
    y /= max(1e-9, np.abs(y).max()) / 0.85
    return y


TONES = {
    "Daybreak": lambda: cycle([(0, "C5"), (.5, "E5"), (1.0, "G5"), (1.5, "C6"), (2.2, "E6", .8), (3.4, "G5", .7), (3.9, "C6", .7),
                               (4.4, "E6", .7), (5.2, "D6", .6)], bell, 7.0),
    "Chimes": lambda: cycle([(0, "C6"), (.7, "A5"), (1.3, "G5"), (2.2, "E5"), (3.0, "D5"), (3.5, "G5", .8), (4.4, "C6", .8)], chime, 7.0, .9),
    "Marimba": lambda: cycle([(0, "C5"), (.25, "E5"), (.5, "G5"), (.75, "E5"), (1.0, "C5"), (1.25, "E5"), (1.5, "G5"), (1.75, "C6"),
                              (2.5, "D5"), (2.75, "F5"), (3.0, "A5"), (3.25, "F5"), (3.5, "D5"), (3.75, "F5"), (4.0, "A5"), (4.25, "D6")],
                             marimba, 5.5),
    "Glass": lambda: cycle([(0, "C6"), (1.4, "G5"), (2.8, "E6"), (4.4, "D6"), (5.8, "G5", .8)], glass, 8.0, .85),
    "Ripple": lambda: cycle([(0, "C5"), (.2, "D5"), (.4, "E5"), (.6, "G5"), (.8, "A5"), (1.0, "C6"), (1.4, "A5"), (1.6, "G5"), (1.8, "E5"),
                             (2.0, "D5"), (2.2, "C5")], kalimba, 4.2),
    "Morning Piano": lambda: cycle([(0, "G4"), (.6, "C5"), (1.2, "E5"), (1.8, "G5"), (3.0, "E5", .8), (3.6, "D5", .8), (4.2, "C5", .9),
                                    (5.4, "E5", .8), (6.0, "D5", .7), (6.6, "C5", .8)], piano, 9.0),
    "Beacon": lambda: cycle([(0, "A5"), (.3, "D6"), (1.2, "A5"), (1.5, "D6")], beep, 2.4, .8),
    "Crystal": lambda: cycle([(0, "E5"), (.15, "G5"), (.3, "B5"), (.45, "E6"), (.6, "G6", .8), (.75, "E6"), (.9, "B5"), (1.05, "G5")],
                             crystal, 2.4, .85),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, build in TONES.items():
        y = finish(build())
        with tempfile.TemporaryDirectory() as tmp:
            wav = os.path.join(tmp, name + ".wav")
            with wave.open(wav, "wb") as w:
                w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
                w.writeframes((y * 32767).astype(np.int16).tobytes())
            dest = os.path.join(OUT, name.replace(" ", "") + ".caf")
            subprocess.run(["afconvert", "-f", "caff", "-d", "ima4", wav, dest], check=True)
        print("wrote", dest, f"{os.path.getsize(dest) / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
