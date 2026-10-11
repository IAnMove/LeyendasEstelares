#!/usr/bin/env python3
"""Original deterministic synthesizer: ambience and short cues, standard library only."""
from array import array
from pathlib import Path
import math
import random
import sys
import wave

OUT = Path(__file__).resolve().parents[1] / "audio"
RATE = 22050


def save(name, duration, sample):
    pcm = array("h")
    for i in range(round(duration * RATE)):
        value = max(-0.95, min(0.95, sample(i / RATE)))
        pcm.append(round(value * 32767))
    if sys.byteorder != "little":
        pcm.byteswap()
    with wave.open(str(OUT / (name + ".wav")), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(pcm.tobytes())


def tone(t, freq):
    return math.sin(math.tau * freq * t)


def motif(t):
    value = 0.0
    for start, freq in [(0.0, 220), (0.4, 330), (0.8, 440)]:
        local = t - start
        if local >= 0:
            value += 0.19 * min(local * 80, 1) * math.exp(-local * 3) * tone(local, freq)
    return value


def main():
    OUT.mkdir(exist_ok=True)
    # Integer cycles over 16 s: the ambient loop joins without a click.
    save("ambience", 16, lambda t: sum(
        0.035 * tone(t, f) * (0.7 + 0.3 * tone(t, 1 / 16))
        for f in [55, 82.5, 110, 164.8125, 220.0625]
    ))
    save("signal", 2.4, motif)
    save("click", 0.08, lambda t: 0.13 * tone(t, 880) * math.sin(math.pi * t / 0.08) ** 2)
    save("tick", 0.03, lambda t: 0.06 * tone(t, 1760) * math.sin(math.pi * t / 0.03) ** 2)
    save("scan", 0.7, lambda t: 0.15 * math.sin(math.tau * (360 * t + 500 * t * t)) * math.sin(math.pi * t / 0.7) ** 2)
    save("jump", 1.1, lambda t: 0.18 * math.sin(math.tau * (50 * t + 160 * t * t)) * math.sin(math.pi * t / 1.1) ** 2)
    save("supply", 0.5, lambda t: 0.13 * tone(t, 440 if t < 0.25 else 660) * math.sin(math.pi * (t % 0.25) / 0.25) ** 2)
    save("trade", 0.6, lambda t: motif(t) * math.sin(math.pi * t / 0.6) ** 2)
    save("warning", 0.8, lambda t: 0.16 * (tone(t, 165) + 0.2 * tone(t, 175)) * math.sin(math.pi * t / 0.8) ** 2)
    rng = random.Random(42)
    save("step", 0.09, lambda t: rng.uniform(-0.12, 0.12) * math.sin(math.pi * t / 0.09) ** 2)
    print(f"Generated 10 original WAV files in {OUT}")


if __name__ == "__main__":
    main()
