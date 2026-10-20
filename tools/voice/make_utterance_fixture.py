# Writes Fixtures/voice/utterance-synthetic-16k.wav. Run: python3 tools/voice/make_utterance_fixture.py > Fixtures/voice/utterance-synthetic-16k.wav
import math, random, struct, sys

RATE = 16_000
random.seed(20261018)  # fixed seed: the fixture is reproducible

def level_to_amp(db):
    return 10 ** (db / 20)

def quiet(seconds, db=-74.0):
    amp = level_to_amp(db)
    return [random.gauss(0, amp) for _ in range(int(seconds * RATE))]

def burst(seconds, db):
    # Noise with a slow 3 Hz swell so it reads as a syllable-like run, not a flat hiss.
    amp = level_to_amp(db) * math.sqrt(2)
    n = int(seconds * RATE)
    return [random.gauss(0, amp) * (0.7 + 0.3 * math.sin(2 * math.pi * 3 * i / RATE)) for i in range(n)]

signal = (
    quiet(0.5)
    + burst(1.2, -20)
    + quiet(0.3, -60)
    + burst(0.6, -20)
    + quiet(1.2)
)
pcm = b"".join(struct.pack("<h", max(-32768, min(32767, int(round(s * 32767))))) for s in signal)
header = (
    b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVE"
    + b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, RATE, RATE * 2, 2, 16)
    + b"data" + struct.pack("<I", len(pcm))
)
sys.stdout.buffer.write(header + pcm)
