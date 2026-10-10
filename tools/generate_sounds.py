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

# --- Oxygen alarm: two short descending beeps, muffled like inside a helmet ---
ALARM_FREQS = (880.0, 660.0)  # Hz of the two beeps
ALARM_BEEP = 0.12           # seconds per beep
ALARM_GAP = 0.06            # seconds between the beeps
ALARM_SOFTNESS = 0.6        # 0-1 low-pass amount (helmet muffle)
ALARM_PEAK = 0.6

# --- Station refill: hiss of air with a rising bubbly tone --------------------
REFILL_LENGTH = 1.2
REFILL_HISS = 0.5           # amount of air noise
REFILL_HISS_SMOOTH = 0.7    # 0-1 low-pass of the hiss
REFILL_TONE_START = 220.0   # Hz, rising tone start...
REFILL_TONE_END = 520.0     # ...and end
REFILL_TONE_GAIN = 0.35
REFILL_BUBBLE_RATE = 14.0   # bubbles per second (tremolo on the tone)
REFILL_PEAK = 0.7

# --- Ancient light: slow swelling chord with shimmer --------------------------
ANCIENT_LENGTH = 5.0
ANCIENT_ROOT = 110.0        # Hz
ANCIENT_CHORD = [(1.0, 1.0), (1.5, 0.7), (2.0, 0.6), (2.5, 0.4), (3.0, 0.35), (4.0, 0.2)]
ANCIENT_SWELL = 1.2         # seconds to reach full volume
ANCIENT_DECAY = 2.2         # seconds, time constant of the fade after the swell
ANCIENT_SHIMMER = 0.006     # detune between left/right copies, gives a slow beating
ANCIENT_PEAK = 0.85

# --- Creature alert: short harsh screech when a creature spots a diver -------
ALERT_LENGTH = 0.45
ALERT_FREQ_START = 700.0    # Hz, the screech rises from here...
ALERT_FREQ_PEAK = 1500.0    # ...to here...
ALERT_PEAK_TIME = 0.12      # ...in this many seconds, then falls back a little
ALERT_FREQ_END = 1100.0
ALERT_HARMONICS = [(1.0, 1.0), (2.0, 0.5), (3.0, 0.35), (4.1, 0.2)]  # slightly inharmonic = uglier
ALERT_ROUGHNESS = 0.6       # amount of fast amplitude wobble (raspy throat)
ALERT_ROUGH_RATE = 55.0     # Hz of that wobble
ALERT_NOISE = 0.25
ALERT_ATTACK = 0.01
ALERT_DECAY = 0.16
ALERT_PEAK = 0.8

# --- Sword swing: short airy whoosh (water resistance) ------------------------
SWING_LENGTH = 0.22
SWING_SMOOTH_START = 0.9    # 0-1 low-pass at the start (dull)...
SWING_SMOOTH_PEAK = 0.55    # ...opening up in the middle of the swing (sharper)
SWING_PEAK_TIME = 0.08      # seconds to the loudest point
SWING_PEAK = 0.6

# --- Sword hit: low thud with a short bright click -------------------------
HIT_LENGTH = 0.25
HIT_FREQ = 95.0             # Hz of the thud
HIT_DECAY = 0.06
HIT_CLICK = 0.5             # amount of the bright click on impact
HIT_CLICK_DECAY = 0.004
HIT_PEAK = 0.85

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


def make_alarm() -> list[float]:
    samples = []
    for index, freq in enumerate(ALARM_FREQS):
        count = int(ALARM_BEEP * SAMPLE_RATE)
        for n in range(count):
            t = n / SAMPLE_RATE
            # Short fades at both ends of each beep so it does not click.
            edge = min(t / 0.008, (ALARM_BEEP - t) / 0.008, 1.0)
            tone = math.sin(2.0 * math.pi * freq * t) + 0.3 * math.sin(2.0 * math.pi * freq * 2.0 * t)
            samples.append(tone * edge)
        if index < len(ALARM_FREQS) - 1:
            samples.extend([0.0] * int(ALARM_GAP * SAMPLE_RATE))
    samples = one_pole_lowpass(samples, ALARM_SOFTNESS)
    return normalize(samples, ALARM_PEAK)


def make_refill() -> list[float]:
    rng = random.Random(RANDOM_SEED + 2)
    count = int(REFILL_LENGTH * SAMPLE_RATE)
    hiss = one_pole_lowpass([rng.uniform(-1.0, 1.0) for _ in range(count)], REFILL_HISS_SMOOTH)
    samples = []
    phase = 0.0
    for n in range(count):
        t = n / SAMPLE_RATE
        progress = t / REFILL_LENGTH
        freq = REFILL_TONE_START + (REFILL_TONE_END - REFILL_TONE_START) * progress
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        bubbles = 0.5 + 0.5 * math.sin(2.0 * math.pi * REFILL_BUBBLE_RATE * t)
        tone = math.sin(phase) * REFILL_TONE_GAIN * bubbles
        # Fast attack, hold, fade out over the last third.
        env = min(t / 0.03, 1.0) * min((REFILL_LENGTH - t) / (REFILL_LENGTH / 3.0), 1.0)
        samples.append((hiss[n] * REFILL_HISS + tone) * env)
    return normalize(samples, REFILL_PEAK)


def make_ancient() -> list[float]:
    count = int(ANCIENT_LENGTH * SAMPLE_RATE)
    samples = []
    for n in range(count):
        t = n / SAMPLE_RATE
        value = 0.0
        for ratio, gain in ANCIENT_CHORD:
            freq = ANCIENT_ROOT * ratio
            value += gain * (math.sin(2.0 * math.pi * freq * t)
                             + math.sin(2.0 * math.pi * freq * (1.0 + ANCIENT_SHIMMER) * t)) * 0.5
        if t < ANCIENT_SWELL:
            env = (t / ANCIENT_SWELL) ** 2
        else:
            env = math.exp(-(t - ANCIENT_SWELL) / ANCIENT_DECAY)
        samples.append(value * env)
    fade_count = int(0.3 * SAMPLE_RATE)
    for k in range(fade_count):
        samples[count - fade_count + k] *= 1.0 - k / fade_count
    return normalize(samples, ANCIENT_PEAK)


def make_alert() -> list[float]:
    rng = random.Random(RANDOM_SEED + 3)
    count = int(ALERT_LENGTH * SAMPLE_RATE)
    samples = []
    phase = 0.0
    for n in range(count):
        t = n / SAMPLE_RATE
        if t < ALERT_PEAK_TIME:
            freq = ALERT_FREQ_START + (ALERT_FREQ_PEAK - ALERT_FREQ_START) * (t / ALERT_PEAK_TIME)
        else:
            k = min((t - ALERT_PEAK_TIME) / (ALERT_LENGTH - ALERT_PEAK_TIME), 1.0)
            freq = ALERT_FREQ_PEAK + (ALERT_FREQ_END - ALERT_FREQ_PEAK) * k
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        tone = sum(gain * math.sin(phase * ratio) for ratio, gain in ALERT_HARMONICS)
        rough = 1.0 - ALERT_ROUGHNESS * (0.5 + 0.5 * math.sin(2.0 * math.pi * ALERT_ROUGH_RATE * t))
        noise = rng.uniform(-1.0, 1.0) * ALERT_NOISE
        samples.append((tone * rough + noise) * envelope(t, ALERT_ATTACK, ALERT_DECAY))
    fade_count = int(0.03 * SAMPLE_RATE)
    for k in range(fade_count):
        samples[count - fade_count + k] *= 1.0 - k / fade_count
    return normalize(samples, ALERT_PEAK)


def make_swing() -> list[float]:
    rng = random.Random(RANDOM_SEED + 4)
    count = int(SWING_LENGTH * SAMPLE_RATE)
    samples = []
    filtered = 0.0
    for n in range(count):
        t = n / SAMPLE_RATE
        # The filter opens towards the peak and closes again: a "whoosh".
        closeness = max(0.0, 1.0 - abs(t - SWING_PEAK_TIME) / SWING_PEAK_TIME)
        amount = SWING_SMOOTH_START + (SWING_SMOOTH_PEAK - SWING_SMOOTH_START) * closeness
        filtered = filtered + (1.0 - amount) * (rng.uniform(-1.0, 1.0) - filtered)
        if t < SWING_PEAK_TIME:
            env = t / SWING_PEAK_TIME
        else:
            env = max(0.0, 1.0 - (t - SWING_PEAK_TIME) / (SWING_LENGTH - SWING_PEAK_TIME)) ** 2
        samples.append(filtered * env)
    return normalize(samples, SWING_PEAK)


def make_hit() -> list[float]:
    rng = random.Random(RANDOM_SEED + 5)
    count = int(HIT_LENGTH * SAMPLE_RATE)
    samples = []
    for n in range(count):
        t = n / SAMPLE_RATE
        thud = math.sin(2.0 * math.pi * HIT_FREQ * t * (1.0 - 0.4 * min(t / HIT_LENGTH, 1.0))) * envelope(t, 0.002, HIT_DECAY)
        click = rng.uniform(-1.0, 1.0) * HIT_CLICK * math.exp(-t / HIT_CLICK_DECAY)
        samples.append(thud + click)
    return normalize(samples, HIT_PEAK)


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
    write_wav(OUTPUT_DIR / "oxygen_alarm.wav", make_alarm())
    write_wav(OUTPUT_DIR / "station_refill.wav", make_refill())
    write_wav(OUTPUT_DIR / "ancient_light.wav", make_ancient())
    write_wav(OUTPUT_DIR / "creature_alert.wav", make_alert())
    write_wav(OUTPUT_DIR / "sword_swing.wav", make_swing())
    write_wav(OUTPUT_DIR / "sword_hit.wav", make_hit())
