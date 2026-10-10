"""Generates Echo's placeholder sounds procedurally (no downloaded assets).

Run from the project root:
    python tools/generate_sounds.py

Writes 16-bit mono .wav files to assets/audio/. Tweak the constants below and
run it again; Godot re-imports the files automatically.
"""

import math
import random
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 44100
OUTPUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "audio"

# --- Ping: deep sonar ping with a long decaying echo tail -------------------
PING_LENGTH = 4.0           # seconds, including the echo tail
PING_FREQ = 420.0           # Hz, fundamental of the ping
PING_GLIDE = 0.03           # pitch drops by this fraction during the ping
PING_PARTIALS = [(1.0, 1.0), (2.0, 0.22), (2.76, 0.10)]  # (frequency ratio, gain)
PING_ATTACK = 0.004         # seconds
PING_DECAY = 0.35           # seconds, time constant of the direct ping
ECHO_DELAY = 0.30           # seconds between repeating echoes
ECHO_FEEDBACK = 0.5         # each echo is this loud compared to the previous one
ECHO_DAMPING = 0.35         # 0-1, how much each echo loses its high frequencies
REVERB_MIX = 0.35           # 0-1, amount of diffuse "water" reverb
PING_FADE_OUT = 0.4         # seconds of fade at the very end
PING_PEAK = 0.85

# --- Tick: soft short click when the wave front hits a rock -----------------
TICK_LENGTH = 0.09
TICK_FREQ = 1700.0
TICK_PARTIAL = (1.6, 0.35)
TICK_ATTACK = 0.001
TICK_DECAY = 0.012
TICK_NOISE = 0.25           # amount of noise in the first milliseconds
TICK_NOISE_DECAY = 0.003
TICK_SOFTNESS = 0.5         # 0-1 low-pass amount, higher = softer
TICK_PEAK = 0.7

# --- Heartbeat: low "lub-dub" thump with a rumble, looped by the creature -----
HEART_LENGTH = 0.75         # seconds of one beat (the game repeats it)
HEART_FREQ_START = 58.0     # Hz, each thump glides down from here...
HEART_FREQ_END = 36.0       # ...to here
HEART_GLIDE_TIME = 0.08     # seconds the glide takes
HEART_SECOND_DELAY = 0.19   # seconds between "lub" and "dub"
HEART_SECOND_GAIN = 0.65    # "dub" is quieter than "lub"
HEART_ATTACK = 0.006
HEART_DECAY = 0.07          # seconds, time constant of each thump
HEART_HARMONIC = (2.0, 0.25)  # (frequency ratio, gain): a bit of body so small speakers hear it
HEART_RUMBLE = 0.18         # amount of low noise rumble under the beat
HEART_RUMBLE_SMOOTH = 0.995  # 0-1 low-pass of the rumble noise, higher = deeper
HEART_RUMBLE_DECAY = 0.35   # seconds, time constant of the rumble
HEART_PEAK = 0.9

RANDOM_SEED = 7


def envelope(t: float, attack: float, decay: float) -> float:
    if t < attack:
        return t / attack
    return math.exp(-(t - attack) / decay)


def one_pole_lowpass(samples: list[float], amount: float) -> list[float]:
    out = []
    previous = 0.0
    for s in samples:
        previous = previous + (1.0 - amount) * (s - previous)
        out.append(previous)
    return out


def comb(samples: list[float], delay_s: float, feedback: float, damping: float) -> list[float]:
    delay = int(delay_s * SAMPLE_RATE)
    buffer = [0.0] * delay
    out = []
    index = 0
    filtered = 0.0
    for s in samples:
        delayed = buffer[index]
        filtered = delayed * (1.0 - damping) + filtered * damping
        buffer[index] = s + filtered * feedback
        index = (index + 1) % delay
        out.append(delayed)
    return out


def allpass(samples: list[float], delay_s: float, gain: float) -> list[float]:
    delay = int(delay_s * SAMPLE_RATE)
    buffer = [0.0] * delay
    out = []
    index = 0
    for s in samples:
        delayed = buffer[index]
        y = -gain * s + delayed
        buffer[index] = s + gain * y
        index = (index + 1) % delay
        out.append(y)
    return out


def normalize(samples: list[float], peak: float) -> list[float]:
    loudest = max(abs(s) for s in samples) or 1.0
    return [s / loudest * peak for s in samples]


def make_ping() -> list[float]:
    count = int(PING_LENGTH * SAMPLE_RATE)
    # Direct ping with a slight downward pitch glide.
    dry = []
    phase = 0.0
    for n in range(count):
        t = n / SAMPLE_RATE
        freq = PING_FREQ * (1.0 - PING_GLIDE * min(t / 0.5, 1.0))
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        tone = sum(gain * math.sin(phase * ratio) for ratio, gain in PING_PARTIALS)
        dry.append(tone * envelope(t, PING_ATTACK, PING_DECAY))

    # Long echo tail: repeating, darkening echoes.
    echoes = comb(dry, ECHO_DELAY, ECHO_FEEDBACK, ECHO_DAMPING)

    # Diffuse reverb (small Schroeder reverb) so the tail feels like open water.
    reverb_in = [d + e for d, e in zip(dry, echoes)]
    combs = [comb(reverb_in, d, 0.78, 0.4) for d in (0.0297, 0.0371, 0.0411, 0.0437)]
    reverb = [sum(values) * 0.25 for values in zip(*combs)]
    reverb = allpass(allpass(reverb, 0.005, 0.7), 0.0017, 0.7)

    mixed = [d + e * 0.8 + r * REVERB_MIX for d, e, r in zip(dry, echoes, reverb)]

    fade_count = int(PING_FADE_OUT * SAMPLE_RATE)
    for k in range(fade_count):
        mixed[count - fade_count + k] *= 1.0 - k / fade_count
    return normalize(mixed, PING_PEAK)


def make_tick() -> list[float]:
    rng = random.Random(RANDOM_SEED)
    count = int(TICK_LENGTH * SAMPLE_RATE)
    samples = []
    ratio, partial_gain = TICK_PARTIAL
    for n in range(count):
        t = n / SAMPLE_RATE
        phase = 2.0 * math.pi * TICK_FREQ * t
        tone = math.sin(phase) + partial_gain * math.sin(phase * ratio)
        noise = rng.uniform(-1.0, 1.0) * TICK_NOISE * math.exp(-t / TICK_NOISE_DECAY)
        samples.append(tone * envelope(t, TICK_ATTACK, TICK_DECAY) + noise)
    samples = one_pole_lowpass(samples, TICK_SOFTNESS)
    return normalize(samples, TICK_PEAK)


def thump(t: float) -> float:
    if t < 0.0:
        return 0.0
    glide = min(t / HEART_GLIDE_TIME, 1.0)
    freq = HEART_FREQ_START + (HEART_FREQ_END - HEART_FREQ_START) * glide
    # Phase from the integral of the gliding frequency, so the pitch drop is smooth.
    if t < HEART_GLIDE_TIME:
        phase = 2.0 * math.pi * (HEART_FREQ_START * t + (HEART_FREQ_END - HEART_FREQ_START) * t * t / (2.0 * HEART_GLIDE_TIME))
    else:
        phase = 2.0 * math.pi * (HEART_FREQ_START * HEART_GLIDE_TIME + (HEART_FREQ_END - HEART_FREQ_START) * HEART_GLIDE_TIME / 2.0
                                 + freq * (t - HEART_GLIDE_TIME))
    ratio, gain = HEART_HARMONIC
    tone = math.sin(phase) + gain * math.sin(phase * ratio)
    return tone * envelope(t, HEART_ATTACK, HEART_DECAY)


def make_heartbeat() -> list[float]:
    rng = random.Random(RANDOM_SEED + 1)
    count = int(HEART_LENGTH * SAMPLE_RATE)
    noise = one_pole_lowpass([rng.uniform(-1.0, 1.0) for _ in range(count)], HEART_RUMBLE_SMOOTH)
    loudest_noise = max(abs(n) for n in noise) or 1.0
    samples = []
    for n in range(count):
        t = n / SAMPLE_RATE
        beat = thump(t) + HEART_SECOND_GAIN * thump(t - HEART_SECOND_DELAY)
        rumble = noise[n] / loudest_noise * HEART_RUMBLE * envelope(t, HEART_ATTACK, HEART_RUMBLE_DECAY)
        samples.append(beat + rumble)
    # Short fade at the end so the loop point does not click.
    fade_count = int(0.02 * SAMPLE_RATE)
    for k in range(fade_count):
        samples[count - fade_count + k] *= 1.0 - k / fade_count
    return normalize(samples, HEART_PEAK)


def write_wav(path: Path, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(SAMPLE_RATE)
        data = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples)
        file.writeframes(data)
    print(f"Wrote {path} ({len(samples) / SAMPLE_RATE:.2f}s)")


if __name__ == "__main__":
    write_wav(OUTPUT_DIR / "sonar_ping.wav", make_ping())
    write_wav(OUTPUT_DIR / "sonar_tick.wav", make_tick())
    write_wav(OUTPUT_DIR / "creature_heartbeat.wav", make_heartbeat())
