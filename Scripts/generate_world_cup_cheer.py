"""Generate an original layered crowd celebration without recorded or third-party audio."""
from pathlib import Path
import math
import random
import struct
import wave

RATE = 44100
DURATION = 7.5
RNG = random.Random(2026)
SAMPLES = []

voices = []
for _ in range(38):
    voices.append((RNG.uniform(125, 310), RNG.uniform(0, math.tau), RNG.uniform(0.35, 1.15)))
for index in range(round(RATE * DURATION)):
    time = index / RATE
    attack = min(1.0, time / 0.16)
    release = min(1.0, (DURATION - time) / 1.25)
    envelope = attack * release
    roar = 0.0
    for frequency, phase, wobble in voices:
        chant = math.sin(math.tau * frequency * time + phase + 0.8 * math.sin(math.tau * wobble * time))
        roar += math.tanh(2.2 * chant) / len(voices)
    noise = RNG.uniform(-1, 1)
    swell = 0.72 + 0.20 * math.sin(math.tau * 0.42 * time) + 0.08 * math.sin(math.tau * 1.7 * time)
    # A short, bright original victory fanfare sits above the crowd at the start.
    fanfare = 0.0
    if time < 2.8:
        notes = [392.0, 523.25, 659.25, 783.99]
        note = notes[min(len(notes) - 1, int(time / 0.55))]
        local = time % 0.55
        note_env = min(1, local / 0.025) * min(1, (0.55 - local) / 0.12)
        fanfare = (math.sin(math.tau * note * time) + 0.35 * math.sin(math.tau * note * 2 * time)) * note_env
    sample = envelope * (0.38 * roar * swell + 0.13 * noise + 0.16 * fanfare)
    SAMPLES.append(struct.pack("<h", round(max(-1, min(1, sample)) * 32767)))

destination = Path(__file__).resolve().parents[1] / "TopScoresSoccer" / "Audio" / "world-cup-cheer.wav"
destination.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(destination), "wb") as audio:
    audio.setnchannels(1)
    audio.setsampwidth(2)
    audio.setframerate(RATE)
    audio.writeframes(b"".join(SAMPLES))
