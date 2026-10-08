#!/usr/bin/env python3
"""Rebuild Garden Table's original synthesized sounds using Python standard library.
No samples or third-party music are used. Output is PCM16 mono, 22050 Hz.
"""
from pathlib import Path
import math
import random
import struct
import wave

RATE = 22050
ROOT = Path(__file__).parent
TAU = math.tau


def sound(seconds):
    return [0.0] * int(RATE * seconds)


def note(out, start, duration, midi, gain=0.22, tone="mallet", wrap=False):
    freq = 440.0 * 2.0 ** ((midi - 69) / 12)
    offset = int(start * RATE)
    count = int(duration * RATE)
    for i in range(count):
        t = i / RATE
        x = i / max(1, count - 1)
        attack = min(1.0, t / 0.008)
        release = min(1.0, (duration - t) / 0.04)
        if tone == "pad":
            envelope = math.sin(math.pi * x) ** 1.5
            sample = math.sin(TAU * freq * t) + 0.13 * math.sin(TAU * freq * 2 * t)
        else:
            envelope = attack * release * math.exp(-4.5 * x)
            sample = math.sin(TAU * freq * t) + 0.22 * math.sin(TAU * freq * 2 * t) * math.exp(-8 * x)
            sample += 0.035 * math.sin(TAU * freq * 3 * t)
        index = offset + i
        if wrap:
            index %= len(out)
        if index < len(out):
            out[index] += gain * envelope * sample


def noise(out, duration, gain, seed=32):
    rng = random.Random(seed)
    filtered = 0.0
    for i in range(min(len(out), int(duration * RATE))):
        filtered = filtered * 0.8 + rng.uniform(-1, 1) * 0.2
        out[i] += filtered * gain * (1.0 - i / (duration * RATE)) ** 3


def write(name, out):
    peak = max(abs(v) for v in out) or 1.0
    scale = min(1.0, 0.78 / peak)
    pcm = b"".join(struct.pack("<h", round(max(-1, min(1, v * scale)) * 32767)) for v in out)
    with wave.open(str(ROOT / (name + ".wav")), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(pcm)


def cue(name, seconds, notes, noise_gain=0):
    out = sound(seconds)
    for start, duration, pitch, gain in notes:
        note(out, start, duration, pitch, gain)
    if noise_gain:
        noise(out, min(0.075, seconds), noise_gain)
    write(name, out)


cue("select", 0.14, [(0, 0.13, 81, 0.18)])
cue("move", 0.20, [(0, 0.13, 69, 0.20), (0.035, 0.15, 76, 0.10)], 0.18)
cue("invalid", 0.20, [(0, 0.18, 47, 0.17), (0.025, 0.12, 46, 0.06)], 0.14)
cue("match", 0.43, [(0, 0.32, 76, 0.19), (0.05, 0.32, 81, 0.17), (0.10, 0.30, 88, 0.12)], 0.08)
cue("reveal", 0.31, [(0, 0.20, 67, 0.11), (0.06, 0.21, 71, 0.12), (0.12, 0.18, 74, 0.10)], 0.13)
cue("serve", 0.69, [(0, 0.45, 76, 0.18), (0.11, 0.48, 79, 0.17), (0.23, 0.45, 84, 0.18)])
cue("win", 1.40, [(0, 0.45, 72, 0.19), (0.16, 0.45, 76, 0.18), (0.32, 0.45, 79, 0.18), (0.52, 0.85, 84, 0.19), (0.52, 0.85, 76, 0.10), (0.52, 0.85, 79, 0.09)])
cue("click", 0.10, [(0, 0.085, 74, 0.13)], 0.15)

# Eight bars in C major, 84 BPM. Rounded marimba-like notes and a soft sine pad.
# Every note's decaying tail wraps into the start, producing a seamless loop.
beat = 60.0 / 84.0
music = sound(beat * 32)
chords = [(48, 60, 64, 67), (45, 60, 64, 69), (53, 60, 65, 69), (43, 59, 62, 67)] * 2
melody = [76, 79, 81, 79, 76, 72, 74, 76, 77, 81, 79, 77, 74, 71, 72, 74]
for bar, chord in enumerate(chords):
    start = bar * 4 * beat
    note(music, start, beat * 3.8, chord[0], 0.075, "pad", True)
    for pitch in chord[1:]:
        note(music, start, beat * 4.0, pitch, 0.023, "pad", True)
    for pulse in range(4):
        pitch = chord[1 + pulse % 3]
        note(music, start + pulse * beat, beat * 1.4, pitch, 0.085, wrap=True)
    note(music, start + beat * 0.5, beat * 2.2, melody[bar * 2], 0.09, wrap=True)
    note(music, start + beat * 2.5, beat * 2.0, melody[bar * 2 + 1], 0.07, wrap=True)
write("garden_afternoon", music)
print("Generated eight original cues and the 22.86-second Garden Afternoon loop.")
