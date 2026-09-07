"""Generate the game's original whistle cue, without recorded or third-party audio."""
from pathlib import Path
import math
import random
import struct
import wave

rate = 44100
duration = 0.32
rng = random.Random(4)
samples = []
phase = 0.0
for index in range(round(rate * duration)):
    time = index / rate
    frequency = 2450 + 75 * math.sin(2 * math.pi * 31 * time)
    phase += 2 * math.pi * frequency / rate
    envelope = min(1, time / 0.018) * min(1, (duration - time) / 0.07)
    flutter = 0.73 + 0.27 * math.sin(2 * math.pi * 43 * time)
    tone = 0.65 * math.sin(phase) + 0.24 * math.sin(phase * 1.31)
    breath = rng.uniform(-1, 1) * 0.05
    sample = (tone * flutter + breath) * envelope * 0.6
    samples.append(struct.pack("<h", round(max(-1, min(1, sample)) * 32767)))

destination = Path(__file__).resolve().parents[1] / "TopScoresSoccer" / "Audio" / "referee-whistle.wav"
destination.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(destination), "wb") as audio:
    audio.setnchannels(1)
    audio.setsampwidth(2)
    audio.setframerate(rate)
    audio.writeframes(b"".join(samples))
