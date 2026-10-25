"""Generates Echo's placeholder sounds procedurally (no downloaded assets).

Run from the project root:
    python tools/generate_sounds.py            (the sounds the game uses now)
    python tools/generate_sounds.py preview    (the audio pass preview, in
                                                assets/audio/preview/; needs
                                                numpy + scipy)
    python tools/generate_sounds.py preview amb_whale investigate
                                               (only sounds whose name
                                                contains one of the words)

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

# --- Exposed kill: heavy impact + bright metallic ring (pulse + finisher combo) ---
KILL_LENGTH = 1.4
KILL_BOOM_FREQ = 55.0       # Hz of the low impact
KILL_BOOM_DECAY = 0.18
KILL_CRACK = 0.7            # amount of the noise crack on impact
KILL_CRACK_DECAY = 0.02
KILL_RING_ROOT = 880.0      # Hz, the metallic ring...
KILL_RING_PARTIALS = [(1.0, 1.0), (2.76, 0.6), (5.4, 0.35), (8.9, 0.2)]  # bell-like (inharmonic)
KILL_RING_DECAY = 0.45
KILL_RING_GAIN = 0.45
KILL_PEAK = 0.9

# --- Lunge: low rising hiss + growl during the creature's 0.3 s wind-up -----
LUNGE_LENGTH = 0.38
LUNGE_FREQ_START = 90.0     # Hz, the growl rises from here...
LUNGE_FREQ_END = 260.0      # ...to here while the creature coils
LUNGE_HARMONICS = [(1.0, 1.0), (2.0, 0.6), (3.0, 0.3)]
LUNGE_HISS = 0.45           # amount of breathy noise, swelling with the growl
LUNGE_HISS_SMOOTH = 0.6     # 0-1 low-pass of the hiss, higher = darker
LUNGE_SWELL = 0.3           # seconds of the swell, then a quick cut
LUNGE_PEAK = 0.85

# --- Shard: a bright glassy chime when an Echo Shard is collected -----------
SHARD_LENGTH = 1.2
SHARD_ROOT = 1046.5         # Hz (C6)
SHARD_PARTIALS = [(1.0, 1.0), (1.5, 0.55), (2.0, 0.35), (3.01, 0.15)]  # a bright fifth + octave
SHARD_ARPEGGIO = 0.05       # seconds between the partials starting (a tiny sparkle)
SHARD_DECAY = 0.35          # seconds, time constant of each partial
SHARD_PEAK = 0.6

# --- Rumble: deep rolling rock rumble (lockdown doors, collapse) -------------
RUMBLE_LENGTH = 3.0
RUMBLE_SMOOTH = 0.997       # 0-1 low-pass of the noise, higher = deeper
RUMBLE_SWELL = 0.4          # seconds to full volume
RUMBLE_WOBBLE_RATE = 3.5    # Hz of the slow rolling in the loudness
RUMBLE_WOBBLE = 0.35        # amount of that rolling
RUMBLE_TONE = 38.0          # Hz, a low tone under the noise
RUMBLE_TONE_GAIN = 0.25
RUMBLE_FADE_OUT = 1.2       # seconds of fade at the end
RUMBLE_PEAK = 0.85

# --- Rock slam: a heavy stone thud with a short crack (a barrier lands) -------
SLAM_LENGTH = 0.9
SLAM_FREQ = 48.0            # Hz of the thud
SLAM_DECAY = 0.16
SLAM_CRACK = 0.8            # amount of the noise crack on impact
SLAM_CRACK_DECAY = 0.03
SLAM_GRIT = 0.25            # amount of gravel noise trailing after the impact
SLAM_GRIT_DECAY = 0.25
SLAM_PEAK = 0.9

# --- Lockdown clear: a rising, open chord (the doors open again) -------------
CLEAR_LENGTH = 2.2
CLEAR_ROOT = 330.0          # Hz
CLEAR_NOTES = [(1.0, 1.0), (1.25, 0.8), (1.5, 0.7), (2.0, 0.55)]  # a major arpeggio
CLEAR_ARPEGGIO = 0.12       # seconds between the notes starting
CLEAR_DECAY = 0.7           # seconds, time constant of each note
CLEAR_PEAK = 0.7

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


def make_exposed_kill() -> list[float]:
    rng = random.Random(RANDOM_SEED + 6)
    count = int(KILL_LENGTH * SAMPLE_RATE)
    samples = []
    for n in range(count):
        t = n / SAMPLE_RATE
        boom = math.sin(2.0 * math.pi * KILL_BOOM_FREQ * t * (1.0 - 0.3 * min(t / 0.3, 1.0))) * envelope(t, 0.003, KILL_BOOM_DECAY)
        crack = rng.uniform(-1.0, 1.0) * KILL_CRACK * math.exp(-t / KILL_CRACK_DECAY)
        ring = sum(gain * math.sin(2.0 * math.pi * KILL_RING_ROOT * ratio * t) * math.exp(-t * ratio / (KILL_RING_DECAY * 2.0))
                   for ratio, gain in KILL_RING_PARTIALS)
        samples.append(boom + crack + ring * KILL_RING_GAIN * envelope(t, 0.002, KILL_RING_DECAY * 3.0))
    fade_count = int(0.1 * SAMPLE_RATE)
    for k in range(fade_count):
        samples[count - fade_count + k] *= 1.0 - k / fade_count
    return normalize(samples, KILL_PEAK)


def make_lunge() -> list[float]:
    rng = random.Random(RANDOM_SEED + 7)
    count = int(LUNGE_LENGTH * SAMPLE_RATE)
    samples = []
    phase = 0.0
    hiss = 0.0
    for n in range(count):
        t = n / SAMPLE_RATE
        k = min(t / LUNGE_SWELL, 1.0)
        freq = LUNGE_FREQ_START + (LUNGE_FREQ_END - LUNGE_FREQ_START) * k * k
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        tone = sum(gain * math.sin(phase * ratio) for ratio, gain in LUNGE_HARMONICS)
        hiss = hiss + (1.0 - LUNGE_HISS_SMOOTH) * (rng.uniform(-1.0, 1.0) - hiss)
        # Swells while coiling, then cuts off fast (the burst itself is silent).
        env = k * k if t < LUNGE_SWELL else max(0.0, 1.0 - (t - LUNGE_SWELL) / (LUNGE_LENGTH - LUNGE_SWELL))
        samples.append((tone + hiss * LUNGE_HISS * 3.0 * k) * env)
    return normalize(samples, LUNGE_PEAK)


def make_shard() -> list[float]:
    count = int(SHARD_LENGTH * SAMPLE_RATE)
    samples = []
    for n in range(count):
        t = n / SAMPLE_RATE
        value = 0.0
        for i, (ratio, gain) in enumerate(SHARD_PARTIALS):
            start = i * SHARD_ARPEGGIO
            if t >= start:
                value += gain * math.sin(2.0 * math.pi * SHARD_ROOT * ratio * (t - start)) * envelope(t - start, 0.003, SHARD_DECAY)
        samples.append(value)
    fade_count = int(0.1 * SAMPLE_RATE)
    for k in range(fade_count):
        samples[count - fade_count + k] *= 1.0 - k / fade_count
    return normalize(samples, SHARD_PEAK)


def make_rumble() -> list[float]:
    rng = random.Random(RANDOM_SEED + 11)
    count = int(RUMBLE_LENGTH * SAMPLE_RATE)
    samples = []
    low = 0.0
    lower = 0.0
    for n in range(count):
        t = n / SAMPLE_RATE
        # Two low-pass stages: a deep, rolling noise.
        low = low + (1.0 - RUMBLE_SMOOTH) * (rng.uniform(-1.0, 1.0) - low)
        lower = lower + (1.0 - RUMBLE_SMOOTH) * (low - lower)
        tone = math.sin(2.0 * math.pi * RUMBLE_TONE * t) * RUMBLE_TONE_GAIN
        wobble = 1.0 - RUMBLE_WOBBLE * (0.5 + 0.5 * math.sin(2.0 * math.pi * RUMBLE_WOBBLE_RATE * t))
        env = min(t / RUMBLE_SWELL, 1.0) * min((RUMBLE_LENGTH - t) / RUMBLE_FADE_OUT, 1.0)
        samples.append((lower * 40.0 + tone) * wobble * env)
    return normalize(samples, RUMBLE_PEAK)


def make_slam() -> list[float]:
    rng = random.Random(RANDOM_SEED + 12)
    count = int(SLAM_LENGTH * SAMPLE_RATE)
    samples = []
    grit = 0.0
    for n in range(count):
        t = n / SAMPLE_RATE
        thud = math.sin(2.0 * math.pi * SLAM_FREQ * t * (1.0 - 0.3 * min(t / 0.2, 1.0))) * envelope(t, 0.003, SLAM_DECAY)
        crack = rng.uniform(-1.0, 1.0) * SLAM_CRACK * math.exp(-t / SLAM_CRACK_DECAY)
        grit = grit + 0.4 * (rng.uniform(-1.0, 1.0) - grit)
        samples.append(thud + crack + grit * SLAM_GRIT * math.exp(-t / SLAM_GRIT_DECAY))
    return normalize(one_pole_lowpass(samples, 0.3), SLAM_PEAK)


def make_clear() -> list[float]:
    count = int(CLEAR_LENGTH * SAMPLE_RATE)
    samples = []
    for n in range(count):
        t = n / SAMPLE_RATE
        value = 0.0
        for i, (ratio, gain) in enumerate(CLEAR_NOTES):
            start = i * CLEAR_ARPEGGIO
            if t >= start:
                local = t - start
                note = math.sin(2.0 * math.pi * CLEAR_ROOT * ratio * local) + 0.3 * math.sin(4.0 * math.pi * CLEAR_ROOT * ratio * local)
                value += gain * note * envelope(local, 0.02, CLEAR_DECAY)
        samples.append(value)
    fade_count = int(0.2 * SAMPLE_RATE)
    for k in range(fade_count):
        samples[count - fade_count + k] *= 1.0 - k / fade_count
    return normalize(samples, CLEAR_PEAK)


def write_wav(path: Path, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(SAMPLE_RATE)
        data = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples)
        file.writeframes(data)
    print(f"Wrote {path} ({len(samples) / SAMPLE_RATE:.2f}s)")


# =============================================================================
# AUDIO PASS PREVIEW  (python tools/generate_sounds.py preview)
# Writes to assets/audio/preview/ for listening in tools/sound_test.tscn.
# Uses numpy + scipy (only this section; the sounds above need nothing extra).
# Loops are rendered circularly (every tone has a whole number of cycles in the
# loop, noise is filtered and reverbed with circular FFTs), so they repeat
# without a click, and get a WAV "smpl" loop chunk, which Godot reads on
# import ("Detect From WAV"): a replacement file with its own loop points
# works the same way. One-shots get their random pitch / volume in the game.
# =============================================================================

PREVIEW_DIR = OUTPUT_DIR / "preview"
PREVIEW_SEED = 2026

# --- Mix targets (peak, 0-1) per kind of sound --------------------------------
PEAK_AMBIENCE = 0.5
PEAK_MUSIC = 0.6
PEAK_STINGER = 0.75
PEAK_SFX = 0.85
PEAK_SOFT = 0.45            # quiet one-shots (bubbles, movement, hums)

# --- Music grid: every layer shares the tempo, so they stay in step -----------
MUSIC_BPM = 120.0
MUSIC_LOOP = 8.0            # seconds (4 bars) for Tension / Chase / Intense
BOSS_LOOP = 16.0            # seconds (8 bars)
AMBIENCE_LOOP = 24.0        # seconds

# --- Ocean ambience bed -------------------------------------------------------
BED_DRONE = 55.0            # Hz, the deep drone...
BED_DRONE_BEAT = 5.0 / 24.0  # ...and a second one this much higher (slow beating)
BED_DRONE_GAIN = 1.0
BED_PAD_NOTES = [110.0, 164.79, 220.0, 261.625]  # soft filtered pad (A minor)
BED_PAD_GAIN = 0.28
BED_PAD_CUTOFF = 650.0      # Hz
BED_NOISE_GAIN = 0.35
BED_NOISE_CUTOFF = 380.0    # Hz, the underwater noise bed
BED_REVERB_TIME = 4.5       # seconds
BED_REVERB_MIX = 0.45

# --- Reverb (synthetic impulse: decaying, darkening noise) --------------------
REVERB_LOWPASS = 3000.0     # Hz, the tail gets darker than this


try:
    import numpy as np
    from scipy import signal
except ImportError:  # only needed for the preview pass
    np = None
    signal = None


def _t(seconds: float) -> "np.ndarray":
    return np.arange(int(seconds * SAMPLE_RATE)) / SAMPLE_RATE


def _osc(freq, seconds: float = 0.0, partials=((1.0, 1.0),)) -> "np.ndarray":
    """Additive oscillator. freq: a number or an array (glides)."""
    if np.isscalar(freq):
        freq = np.full(int(seconds * SAMPLE_RATE), float(freq))
    phase = 2.0 * np.pi * np.cumsum(freq) / SAMPLE_RATE
    out = np.zeros_like(phase)
    for ratio, gain in partials:
        out += gain * np.sin(phase * ratio)
    return out


def _loop_tone(freq: float, length: float, partials=((1.0, 1.0),)) -> "np.ndarray":
    """A tone with a whole number of cycles in the loop (seamless)."""
    cycles = max(round(freq * length), 1)
    phase = 2.0 * np.pi * cycles * np.arange(int(length * SAMPLE_RATE)) / int(length * SAMPLE_RATE)
    out = np.zeros_like(phase)
    for ratio, gain in partials:
        out += gain * np.sin(phase * round(ratio))
    return out


def _loop_lfo(cycles: int, length: float, depth: float, offset: float = 0.0) -> "np.ndarray":
    """1 - depth .. 1, a whole number of cycles over the loop."""
    n = int(length * SAMPLE_RATE)
    return 1.0 - depth * (0.5 + 0.5 * np.sin(2.0 * np.pi * cycles * np.arange(n) / n + offset))


def _noise(seconds: float, rng) -> "np.ndarray":
    return rng.uniform(-1.0, 1.0, int(seconds * SAMPLE_RATE))


def _filter(x, kind: str, cutoff, order: int = 2):
    sos = signal.butter(order, cutoff, btype=kind, fs=SAMPLE_RATE, output="sos")
    return signal.sosfilt(sos, x)


def _circular_band(x, low: float = 0.0, high: float = 20000.0, soft: float = 0.3):
    """Band filter in the frequency domain (circular: keeps loops seamless)."""
    spectrum = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1.0 / SAMPLE_RATE)
    mask = np.ones_like(freqs)
    if low > 0.0:
        mask *= 1.0 / (1.0 + (low / np.maximum(freqs, 1e-3)) ** (2.0 / soft))
    if high < 20000.0:
        mask *= 1.0 / (1.0 + (freqs / high) ** (2.0 / soft))
    return np.fft.irfft(spectrum * mask, len(x))


def _impulse(seconds: float, rng, lowpass: float = REVERB_LOWPASS):
    t = _t(seconds)
    tail = rng.normal(0.0, 1.0, len(t)) * np.exp(-6.9 * t / seconds)
    tail = _filter(tail, "lowpass", lowpass)
    # Later reflections get darker: a second, darker copy takes over.
    dark = _filter(tail, "lowpass", lowpass * 0.3)
    mix = np.clip(t / seconds, 0.0, 1.0)
    tail = tail * (1.0 - mix) + dark * mix
    return tail / (np.sqrt(np.sum(tail ** 2)) + 1e-9)


def _reverb(x, seconds: float, mix: float, rng, circular: bool = False, tail: bool = True):
    ir = _impulse(seconds, rng)
    if circular:
        # Fold the impulse onto the loop length: the tail wraps into the start.
        n = len(x)
        folded = np.zeros(n)
        for start in range(0, len(ir), n):
            part = ir[start:start + n]
            folded[: len(part)] += part
        wet = np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(folded), n)
        return x * (1.0 - mix) + wet * mix * 3.0
    padded = np.pad(x, (0, len(ir) if tail else 0))
    wet = signal.fftconvolve(padded, ir)[: len(padded)]
    return padded * (1.0 - mix) + wet * mix * 3.0


def _env(t, attack: float, decay: float):
    return np.where(t < attack, t / max(attack, 1e-6), np.exp(-(t - attack) / max(decay, 1e-6)))


def _fade(x, fade_in: float = 0.005, fade_out: float = 0.05):
    n_in = min(int(fade_in * SAMPLE_RATE), len(x))
    n_out = min(int(fade_out * SAMPLE_RATE), len(x))
    x = x.copy()
    if n_in > 0:
        x[:n_in] *= np.linspace(0.0, 1.0, n_in)
    if n_out > 0:
        x[-n_out:] *= np.linspace(1.0, 0.0, n_out)
    return x


def _trim_tail(x, threshold: float = 0.0008):
    """Cuts the silent end of a reverb tail."""
    loud = np.nonzero(np.abs(x) > threshold * np.max(np.abs(x)))[0]
    end = loud[-1] + int(0.05 * SAMPLE_RATE) if len(loud) else len(x)
    return _fade(x[: min(end, len(x))], 0.0, 0.08)


def _norm(x, peak: float):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def _place(buffer, sound, at_seconds: float, gain: float = 1.0, wrap: bool = False):
    """Adds a sound into the buffer at a time (wrap = around the loop's end)."""
    idx = np.arange(len(sound)) + int(at_seconds * SAMPLE_RATE)
    if wrap:
        np.add.at(buffer, idx % len(buffer), sound * gain)
    else:
        keep = idx < len(buffer)
        buffer[idx[keep]] += sound[keep] * gain
    return buffer


def write_wav_np(path: Path, x, loop: bool = False) -> None:
    """16-bit mono WAV; loop=True adds a "smpl" chunk looping the whole file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    data = (np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2").tobytes()
    fmt = struct.pack("<HHIIHH", 1, 1, SAMPLE_RATE, SAMPLE_RATE * 2, 2, 16)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    chunks += b"data" + struct.pack("<I", len(data)) + data
    if loop:
        frames = len(x)
        smpl = struct.pack("<9I", 0, 0, int(1e9 / SAMPLE_RATE), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, frames - 1, 0, 0)
        chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    with open(path, "wb") as file:
        file.write(b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks)
    print(f"Wrote {path.relative_to(OUTPUT_DIR.parent.parent)} ({len(x) / SAMPLE_RATE:.2f}s{', loop' if loop else ''})")


# --- 1. Ocean ambience ----------------------------------------------------------

def make_ocean_bed(rng):
    length = AMBIENCE_LOOP
    drone = _loop_tone(BED_DRONE, length, ((1.0, 1.0), (2.0, 0.25), (3.0, 0.08)))
    drone += _loop_tone(BED_DRONE + BED_DRONE_BEAT, length, ((1.0, 0.9), (2.0, 0.2)))
    drone *= _loop_lfo(2, length, 0.25)
    pad = np.zeros_like(drone)
    for i, note in enumerate(BED_PAD_NOTES):
        saw = tuple((k, 1.0 / k) for k in range(1, 9))
        voice = _loop_tone(note, length, saw) + _loop_tone(note * 1.003, length, saw)
        pad += voice * _loop_lfo(1 + i % 2, length, 0.6, i * 1.7)
    pad = _circular_band(pad, 60.0, BED_PAD_CUTOFF)
    bed = _circular_band(_noise(length, rng), 30.0, BED_NOISE_CUTOFF, 0.5) * _loop_lfo(3, length, 0.4)
    mix = drone * BED_DRONE_GAIN / np.max(np.abs(drone)) \
        + pad * BED_PAD_GAIN / np.max(np.abs(pad)) \
        + bed * BED_NOISE_GAIN / np.max(np.abs(bed))
    mix = _reverb(mix, BED_REVERB_TIME, BED_REVERB_MIX, rng, circular=True)
    return _norm(mix, PEAK_AMBIENCE)


def make_bubbles(rng, count: int):
    out = np.zeros(int(1.2 * SAMPLE_RATE))
    for i in range(count):
        f0 = rng.uniform(450.0, 1300.0)
        dur = rng.uniform(0.03, 0.07)
        t = _t(dur)
        bubble = np.sin(2 * np.pi * np.cumsum(f0 * (1.0 + 1.6 * t / dur)) / SAMPLE_RATE) * _env(t, 0.002, dur * 0.4)
        _place(out, bubble, rng.uniform(0.0, 0.5) if i else 0.0, rng.uniform(0.4, 1.0))
    out = _reverb(_filter(out, "lowpass", 3500.0), 1.2, 0.3, rng)
    return _norm(_trim_tail(out), PEAK_SOFT)


# Whale-like groans: felt more than heard. A deep fundamental (20-60 Hz) with a
# few soft harmonics, gliding very slowly between a handful of pitches (smooth
# cosine steps of several seconds, no wobble), heavily low-passed, then pushed
# far away by a long dark reverb.
WHALE_HARMONICS = ((1.0, 1.0), (2.0, 0.55), (3.0, 0.3), (4.0, 0.16), (5.0, 0.08))
WHALE_LOWPASS = 260.0       # Hz
WHALE_REVERB = 9.0          # seconds of tail
WHALE_REVERB_MIX = 0.8
WHALE_PEAK = 0.22           # quiet: it is far away


def make_whale(rng, pitches, glide_seconds: float):
    """pitches: the Hz it glides through (one glide_seconds step each)."""
    steps = len(pitches) - 1
    seconds = steps * glide_seconds
    t = _t(seconds)
    step = np.minimum((t / glide_seconds).astype(int), steps - 1)
    k = (t - step * glide_seconds) / glide_seconds
    ease = 0.5 - 0.5 * np.cos(np.pi * k)
    a = np.array(pitches[:-1])[step]
    b = np.array(pitches[1:])[step]
    freq = a + (b - a) * ease
    voice = _osc(freq, partials=WHALE_HARMONICS)
    # Slow swell in and out over the whole call.
    voice *= np.sin(np.pi * t / seconds) ** 2
    voice = _filter(voice, "lowpass", WHALE_LOWPASS, 4)
    out = _reverb(voice, WHALE_REVERB, WHALE_REVERB_MIX, rng)
    out = _filter(out, "lowpass", WHALE_LOWPASS * 1.3, 2)
    return _norm(_trim_tail(out, 0.002), WHALE_PEAK)


# --- 2. Music layers (all at MUSIC_BPM) ---------------------------------------

def _beat() -> float:
    return 60.0 / MUSIC_BPM


def _kick(freq_start: float, freq_end: float, decay: float, seconds: float = 0.5):
    t = _t(seconds)
    freq = freq_end + (freq_start - freq_end) * np.exp(-t / 0.04)
    return _osc(freq) * _env(t, 0.003, decay)


def make_tension(rng):
    length = MUSIC_LOOP
    n = int(length * SAMPLE_RATE)
    sub = _loop_tone(41.25, length, ((1.0, 1.0), (2.0, 0.35), (3.0, 0.12)))
    rub = _loop_tone(43.75, length, ((1.0, 0.5), (2.0, 0.15)))
    pulse_env = np.zeros(n)
    t = _t(0.5)
    one = _env(t, 0.04, 0.22)
    for beat in range(int(length / _beat())):
        _place(pulse_env, one, beat * _beat(), 1.0 if beat % 4 == 0 else 0.75, wrap=True)
    layer = np.tanh(1.6 * (sub + rub)) * (0.15 + pulse_env)
    air = _circular_band(_noise(length, rng), 200.0, 900.0) * _loop_lfo(2, length, 0.8) * 0.08
    layer = _circular_band(layer + air, 20.0, 1200.0)
    layer = _reverb(layer, 2.0, 0.25, rng, circular=True)
    return _norm(layer, PEAK_MUSIC)


def make_chase(rng):
    length = MUSIC_LOOP
    n = int(length * SAMPLE_RATE)
    out = np.zeros(n)
    lub = _kick(95.0, 45.0, 0.12)
    dub = _kick(80.0, 42.0, 0.1)
    tom = _kick(140.0, 85.0, 0.18) * 0.5
    for beat in range(int(length / _beat())):
        at = beat * _beat()
        _place(out, lub, at, 1.0, wrap=True)
        _place(out, dub, at + 0.16, 0.6, wrap=True)
        if beat % 4 in (1, 3):
            _place(out, tom, at + _beat() * 0.5, 1.0, wrap=True)
    hat = _filter(_noise(0.05, rng), "highpass", 4000.0) * _env(_t(0.05), 0.001, 0.012)
    for step in range(int(length / (_beat() / 4))):
        _place(out, hat, step * _beat() / 4, 0.05 if step % 2 else 0.09, wrap=True)
    out = _circular_band(out, 25.0, 3500.0)
    out = _reverb(out, 1.4, 0.2, rng, circular=True)
    return _norm(out, PEAK_MUSIC)


def make_intense(rng):
    length = MUSIC_LOOP
    n = int(length * SAMPLE_RATE)
    out = np.zeros(n)
    drive = np.tanh(3.0 * _osc(55.0, 0.25, ((1.0, 1.0), (2.0, 0.4)))) * _env(_t(0.25), 0.005, 0.09)
    taiko = _kick(120.0, 48.0, 0.3, 0.8) + _filter(_noise(0.8, rng), "bandpass", [200.0, 1200.0]) * _env(_t(0.8), 0.001, 0.03) * 0.6
    for eighth in range(int(length / (_beat() / 2))):
        _place(out, drive, eighth * _beat() / 2, 0.8 if eighth % 2 == 0 else 0.55, wrap=True)
    for beat in range(int(length / _beat())):
        if beat % 2 == 0:
            _place(out, taiko, beat * _beat(), 1.0, wrap=True)
    drone = (_loop_tone(55.0, length, ((1.0, 1.0), (2.0, 0.3))) + _loop_tone(58.25, length, ((1.0, 0.8),))) \
        * _loop_lfo(64, length, 0.6)
    scrape = _circular_band(_noise(length, rng), 900.0, 3200.0) * (np.arange(n) % int(2.0 * SAMPLE_RATE) / (2.0 * SAMPLE_RATE)) ** 3
    out = out + np.tanh(drone) * 0.35 + scrape * 0.12
    out = _circular_band(out, 25.0, 5000.0)
    out = _reverb(out, 1.8, 0.22, rng, circular=True)
    return _norm(out, PEAK_MUSIC)


def make_boss(rng):
    length = BOSS_LOOP
    n = int(length * SAMPLE_RATE)
    out = np.zeros(n)
    drum = _kick(110.0, 40.0, 0.35, 1.0) + _filter(_noise(1.0, rng), "lowpass", 900.0) * _env(_t(1.0), 0.002, 0.05) * 0.5
    for bar in range(int(length / (_beat() * 4))):
        start = bar * _beat() * 4
        for offset, gain in ((0.0, 1.0), (1.5, 0.7), (2.0, 0.85), (3.5, 0.5)):
            _place(out, drum, start + offset * _beat(), gain, wrap=True)
    choir = np.zeros(n)
    for i, note in enumerate([73.4375, 87.3125, 110.0, 146.875]):
        saw = tuple((k, 1.0 / k) for k in range(1, 12))
        voice = _loop_tone(note, length, saw) + _loop_tone(note * 1.004, length, saw)
        choir += voice * _loop_lfo(1 + i % 2, length, 0.5, i)
    choir = _circular_band(choir, 250.0, 950.0, 0.4)
    bell = np.zeros(n)
    strike = _osc(220.0, 4.0, ((1.0, 1.0), (2.76, 0.5), (5.4, 0.3), (8.9, 0.15))) * _env(_t(4.0), 0.002, 1.2)
    _place(bell, strike, 0.0, 1.0, wrap=True)
    growl = _loop_tone(36.75, length, ((1.0, 1.0), (2.0, 0.5))) * _loop_lfo(4, length, 0.5)
    mix = out + choir / np.max(np.abs(choir)) * 0.45 + bell * 0.25 + np.tanh(growl) * 0.3
    mix = _circular_band(mix, 25.0, 6000.0)
    mix = _reverb(mix, 3.0, 0.4, rng, circular=True)
    return _norm(mix, PEAK_MUSIC)


# --- Stingers ---------------------------------------------------------------

def _chord(notes, seconds: float, attack: float, decay: float, partials=((1.0, 1.0), (2.0, 0.3), (3.0, 0.1)), stagger: float = 0.0):
    out = np.zeros(int((seconds + stagger * len(notes)) * SAMPLE_RATE))
    for i, note in enumerate(notes):
        t = _t(seconds)
        _place(out, _osc(note, seconds, partials) * _env(t, attack, decay), i * stagger)
    return out


def make_sting_spotted(rng):
    stab = _chord([311.1, 329.6, 466.2], 1.0, 0.004, 0.25, tuple((k, 1.0 / k) for k in range(1, 8)))
    t = _t(len(stab) / SAMPLE_RATE)
    stab *= 1.0 - 0.15 * np.clip(t / 0.4, 0, 1)
    swell = _filter(_noise(len(t) / SAMPLE_RATE, rng), "bandpass", [600.0, 3000.0]) * _env(t, 0.06, 0.2) * 0.4
    out = _filter(np.tanh(2.0 * stab) + swell, "lowpass", 4500.0)
    return _norm(_trim_tail(_reverb(out, 1.6, 0.35, rng)), PEAK_STINGER)


def make_sting_shard(rng):
    out = _chord([880.0, 1108.7, 1318.5, 1760.0], 1.4, 0.003, 0.35, ((1.0, 1.0), (2.0, 0.25), (3.01, 0.1)), stagger=0.08)
    return _norm(_trim_tail(_reverb(out, 2.5, 0.45, rng)), PEAK_STINGER)


def make_sting_lockdown(rng):
    brass = _chord([55.0, 82.5, 110.0, 164.8], 2.0, 0.02, 0.6, tuple((k, 1.0 / k) for k in range(1, 14)))
    brass = _filter(brass, "lowpass", 900.0)
    boom = np.zeros_like(brass)
    _place(boom, _kick(90.0, 32.0, 0.6, 2.0), 0.0)
    ring = np.zeros_like(brass)
    _place(ring, _osc(440.0, 2.0, ((1.0, 1.0), (2.76, 0.5), (5.4, 0.25))) * _env(_t(2.0), 0.002, 0.5), 0.0)
    out = np.tanh(1.5 * brass) + boom * 1.2 + ring * 0.15
    return _norm(_trim_tail(_reverb(out, 2.5, 0.35, rng)), PEAK_STINGER)


def make_sting_doors_open(rng):
    out = _chord([220.0, 330.0, 440.0, 554.4, 659.3], 2.2, 0.25, 0.9, stagger=0.12)
    return _norm(_trim_tail(_reverb(out, 2.5, 0.45, rng)), PEAK_STINGER)


def make_sting_level_complete(rng):
    warm = _chord([110.0, 220.0, 277.2, 329.6, 440.0], 3.5, 0.6, 1.6, tuple((k, 0.8 / k) for k in range(1, 6)))
    warm = _filter(warm, "lowpass", 2500.0)
    sparkle = _chord([1318.5, 1760.0, 2217.5, 2637.0], 1.5, 0.003, 0.4, ((1.0, 1.0), (2.0, 0.2)), stagger=0.15)
    out = warm
    _place(out, sparkle * 0.35, 0.5)
    return _norm(_trim_tail(_reverb(out, 3.5, 0.5, rng)), PEAK_STINGER)


def make_sting_downed(rng):
    out = np.zeros(int(2.4 * SAMPLE_RATE))
    for i, note in enumerate([440.0, 392.0, 329.6]):
        tone = _osc(note * (1.0 - 0.02 * _t(0.7) / 0.7), partials=((1.0, 1.0), (2.0, 0.3))) * _env(_t(0.7), 0.03, 0.3)
        _place(out, tone, i * 0.32, 1.0 - i * 0.15)
    out = _filter(out, "lowpass", 1100.0)
    return _norm(_trim_tail(_reverb(out, 2.2, 0.45, rng)), PEAK_STINGER)


# --- 3. SFX -----------------------------------------------------------------

def make_whoosh(rng, seconds: float, low: float, high: float, body: float):
    t = _t(seconds)
    k = t / seconds
    noise = _noise(seconds, rng)
    # Sweep a band up and back down: the blade cutting the water.
    out = np.zeros_like(noise)
    steps = 24
    for i in range(steps):
        a, b = int(i * len(t) / steps), int((i + 1) * len(t) / steps)
        center = low + (high - low) * np.sin(np.pi * (i + 0.5) / steps)
        out[a:b] = _filter(noise, "bandpass", [center * 0.6, center * 1.4])[a:b]
    shape = np.sin(np.pi * k) ** 2
    tone = _osc(90.0 + 60.0 * k, seconds) * shape * body
    return _norm(_fade(out * shape + tone, 0.002, 0.03), PEAK_SFX * 0.8)


def make_impact(rng, freq: float, decay: float, crunch: float, seconds: float):
    t = _t(seconds)
    thud = _kick(freq * 1.8, freq, decay, seconds)
    click = _filter(_noise(seconds, rng), "highpass", 2500.0) * np.exp(-t / 0.004)
    grit = _filter(_noise(seconds, rng), "bandpass", [300.0, 1800.0]) * np.exp(-t / (decay * 0.8)) * crunch
    return _norm(_fade(thud + click * 0.6 + grit, 0.0, 0.05), PEAK_SFX)


def make_finisher(rng):
    seconds = 2.2
    t = _t(seconds)
    boom = _osc(60.0 * np.exp(-t / 0.6) + 32.0, partials=((1.0, 1.0), (2.0, 0.2))) * _env(t, 0.004, 0.55)
    sub = _osc(30.0, seconds) * _env(t, 0.01, 0.8)
    crack = _filter(_noise(seconds, rng), "highpass", 1800.0) * np.exp(-t / 0.015)
    shimmer = _osc(1320.0, seconds, ((1.0, 1.0), (2.76, 0.6), (5.4, 0.35), (8.9, 0.2))) * _env(t, 0.01, 0.6) \
        * (0.7 + 0.3 * np.sin(2 * np.pi * 9.0 * t))
    out = boom * 1.0 + sub * 0.7 + crack * 0.8 + shimmer * 0.18
    return _norm(_trim_tail(_reverb(out, 2.5, 0.3, rng)), PEAK_SFX)


def make_sonar(rng, freq: float, echoes, cutoff: float, wobble: float, peak: float):
    seconds = 0.6
    t = _t(seconds)
    f = freq * (1.0 - 0.03 * np.clip(t / 0.5, 0, 1)) * (1.0 + wobble * np.sin(2 * np.pi * 7.0 * t))
    ping = _osc(f, partials=((1.0, 1.0), (2.0, 0.22), (2.76, 0.1))) * _env(t, 0.004, 0.3)
    ping = _filter(ping, "lowpass", cutoff)
    out = np.zeros(int(3.5 * SAMPLE_RATE))
    _place(out, ping, 0.0)
    for i, (delay, gain) in enumerate(echoes):
        echo = _filter(ping, "lowpass", cutoff * (0.7 ** (i + 1)))
        _place(out, echo, delay, gain)
    return _norm(_trim_tail(_reverb(out, 3.0, 0.35, rng)), peak)


def make_creature_clicks(rng, pitch: float):
    out = np.zeros(int(0.6 * SAMPLE_RATE))
    at = 0.0
    for i in range(rng.integers(3, 7)):
        t = _t(0.02)
        click = np.sin(2 * np.pi * 2400.0 * pitch * rng.uniform(0.9, 1.1) * t) * np.exp(-t / 0.003)
        _place(out, click, at, rng.uniform(0.5, 1.0))
        at += rng.uniform(0.03, 0.08)
    out = _filter(out, "lowpass", 5000.0 * pitch)
    return _norm(_trim_tail(_reverb(out, 1.0, 0.25, rng)), PEAK_SOFT)


def _rough(t, rate: float, depth: float):
    return 1.0 - depth * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * rate * t)))


# "Investigate" sounds (instead of a growl): deep-sea style, no low noise.
# pitch < 1 = deeper, stretch > 1 = slower (the Sentinel); the boss layers two
# pitches with a tonal sub rumble under them.

def make_chitter(rng, pitch: float, stretch: float = 1.0):
    """Wet clicks / chitters in short bursts."""
    out = np.zeros(int(1.4 * stretch * SAMPLE_RATE))
    at = 0.0
    for burst in range(rng.integers(2, 4)):
        for i in range(rng.integers(5, 11)):
            seconds = 0.018
            t = _t(seconds)
            freq = 1700.0 * pitch * rng.uniform(0.85, 1.15)
            # A resonant tick that drops in pitch a little: the "wet" part.
            tick = np.sin(2 * np.pi * np.cumsum(freq * (1.0 - 0.25 * t / seconds)) / SAMPLE_RATE) * np.exp(-t / 0.0035)
            _place(out, tick, at, rng.uniform(0.45, 1.0))
            at += rng.uniform(0.016, 0.03) * stretch
        at += rng.uniform(0.12, 0.25) * stretch
    out = _filter(out, "bandpass", [500.0 * pitch, 5000.0 * min(pitch, 1.0) + 200.0])
    return _norm(_trim_tail(_reverb(out, 1.0, 0.3, rng)), PEAK_SFX * 0.8)


def make_creak(rng, pitch: float, stretch: float = 1.0):
    """A resonant metallic creak: irregular stick-slip pulses ringing a few
    inharmonic modes (like an old hull bending)."""
    seconds = 1.1 * stretch
    n = int(seconds * SAMPLE_RATE)
    pulses = np.zeros(n)
    at = 0.0
    while at < seconds * 0.85:
        k = at / seconds
        rate = (70.0 + 50.0 * np.sin(np.pi * k)) * pitch * rng.uniform(0.85, 1.15)
        pulses[int(at * SAMPLE_RATE)] = rng.uniform(0.5, 1.0)
        at += 1.0 / rate
    out = np.zeros(n)
    for mode, gain, ring in ((410.0, 1.0, 0.05), (1130.0, 0.6, 0.03), (2210.0, 0.35, 0.02), (3370.0, 0.2, 0.015)):
        freq = mode * pitch
        r = np.exp(-1.0 / (ring * SAMPLE_RATE))
        b = [1.0 - r]
        a = [1.0, -2.0 * r * np.cos(2 * np.pi * freq / SAMPLE_RATE), r * r]
        out += signal.lfilter(b, a, pulses) * gain
    out *= np.sin(np.pi * _t(seconds) / seconds) ** 0.5
    return _norm(_trim_tail(_reverb(out, 1.6, 0.35, rng)), PEAK_SFX * 0.8)


def make_call(rng, pitch: float, stretch: float = 1.0):
    """An eerie tonal call: inharmonic partials, a slow glide, a vowel-like
    formant that opens and closes."""
    seconds = 1.6 * stretch
    t = _t(seconds)
    k = t / seconds
    base = 230.0 * pitch * (1.0 + 0.18 * np.sin(np.pi * k) - 0.12 * k)
    voice = _osc(base, partials=((1.0, 1.0), (2.32, 0.6), (3.87, 0.4), (5.1, 0.25), (6.7, 0.12)))
    out = np.zeros_like(voice)
    steps = 16
    for i in range(steps):
        a, b = int(i * len(t) / steps), int((i + 1) * len(t) / steps)
        center = (500.0 + 700.0 * np.sin(np.pi * (i + 0.5) / steps)) * pitch
        out[a:b] = _filter(voice, "bandpass", [center * 0.6, center * 1.5])[a:b]
    out *= np.sin(np.pi * k) ** 1.2
    return _norm(_trim_tail(_reverb(out, 2.5, 0.45, rng)), PEAK_SFX * 0.75)


def make_boss_layered(rng, maker, sub_hz: float = 34.0):
    """The boss: the same sound at two depths, with a tonal sub rumble under it."""
    deep = maker(rng, 0.5, 1.3)
    mid = maker(rng, 0.75, 1.3)
    seconds = max(len(deep), len(mid)) / SAMPLE_RATE
    t = _t(seconds)
    sub = _osc(sub_hz, seconds, ((1.0, 1.0), (2.0, 0.3))) * (0.6 + 0.4 * np.sin(2 * np.pi * 3.0 * t)) \
        * np.sin(np.pi * t / seconds) ** 1.5
    out = np.zeros(len(t))
    _place(out, deep, 0.0, 1.0)
    _place(out, mid, 0.05, 0.6)
    out += sub * 0.5
    return _norm(_fade(out, 0.005, 0.2), PEAK_SFX * 0.85)


def make_creature_screech(rng, pitch: float):
    seconds = 0.7
    t = _t(seconds)
    rise = np.clip(t / 0.15, 0, 1)
    f = (700.0 + 900.0 * rise - 500.0 * np.clip((t - 0.15) / 0.55, 0, 1)) * pitch
    voice = _osc(f, partials=((1.0, 1.0), (2.0, 0.5), (3.0, 0.35), (4.1, 0.2))) * _rough(t, 55.0, 0.5)
    hiss = _filter(_noise(seconds, rng), "highpass", 1500.0 * pitch) * 0.25
    out = np.tanh(1.5 * (voice + hiss)) * _env(t, 0.01, 0.2)
    out = _filter(out, "lowpass", 6000.0 * pitch)
    return _norm(_trim_tail(_reverb(out, 1.4, 0.3, rng)), PEAK_SFX)


def make_creature_hiss(rng, pitch: float):
    seconds = 0.45
    t = _t(seconds)
    k = np.clip(t / 0.32, 0, 1)
    growl = _osc((90.0 + 170.0 * k ** 2) * pitch, partials=((1.0, 1.0), (2.0, 0.6), (3.0, 0.3)))
    hiss = _filter(_noise(seconds, rng), "bandpass", [1800.0 * pitch, 6000.0 * min(pitch * 1.2, 1.0) + 100.0])
    env = np.where(t < 0.32, k ** 2, np.maximum(0.0, 1.0 - (t - 0.32) / 0.13))
    return _norm(_fade((growl + hiss * 1.4) * env, 0.0, 0.02), PEAK_SFX)


def make_creature_death(rng, pitch: float):
    seconds = 1.5
    t = _t(seconds)
    f = (600.0 * np.exp(-t / 0.5) + 110.0) * pitch * (1.0 + 0.04 * np.sin(2 * np.pi * 6.0 * t))
    wail = _osc(f, partials=((1.0, 1.0), (2.0, 0.4), (3.0, 0.2))) * _env(t, 0.02, 0.5)
    out = wail
    for i in range(10):
        f0 = rng.uniform(200.0, 600.0) * pitch
        bt = _t(0.06)
        bubble = np.sin(2 * np.pi * np.cumsum(f0 * (1.0 + 1.5 * bt / 0.06)) / SAMPLE_RATE) * _env(bt, 0.002, 0.02)
        _place(out, bubble, rng.uniform(0.3, 1.2), rng.uniform(0.2, 0.5))
    closing = np.zeros_like(out)
    steps = 12
    for i in range(steps):
        a, b = int(i * len(t) / steps), int((i + 1) * len(t) / steps)
        closing[a:b] = _filter(out, "lowpass", 4000.0 * pitch * (1.0 - 0.8 * i / steps) + 200.0)[a:b]
    return _norm(_trim_tail(_reverb(closing, 1.8, 0.35, rng)), PEAK_SFX)


def make_swish(rng):
    seconds = 0.35
    t = _t(seconds)
    out = _filter(_noise(seconds, rng), "bandpass", [180.0, rng.uniform(600.0, 950.0)]) * np.sin(np.pi * t / seconds) ** 2
    return _norm(_fade(out), PEAK_SOFT * 0.7)


def make_player_hurt(rng):
    seconds = 0.5
    t = _t(seconds)
    thump = _kick(220.0, 120.0, 0.07, seconds)
    tone = _osc(380.0 * (1.0 - 0.3 * t / seconds), seconds, ((1.0, 1.0), (2.0, 0.3))) * _env(t, 0.005, 0.12) * 0.5
    out = thump + tone
    for i in range(6):
        bt = _t(0.05)
        f0 = rng.uniform(500.0, 1200.0)
        _place(out, np.sin(2 * np.pi * np.cumsum(f0 * (1.0 + 1.5 * bt / 0.05)) / SAMPLE_RATE) * _env(bt, 0.002, 0.015),
               rng.uniform(0.03, 0.3), rng.uniform(0.15, 0.35))
    return _norm(_fade(_filter(out, "lowpass", 2500.0)), PEAK_SFX * 0.8)


def make_player_downed(rng):
    seconds = 1.8
    t = _t(seconds)
    tone = _osc(520.0 * np.exp(-t / 0.9) + 140.0, partials=((1.0, 1.0), (2.0, 0.35), (3.0, 0.1))) * _env(t, 0.02, 0.6)
    out = _filter(tone, "lowpass", 1400.0)
    for i in range(14):
        bt = _t(0.05)
        f0 = rng.uniform(350.0, 900.0)
        _place(out, np.sin(2 * np.pi * np.cumsum(f0 * (1.0 + 1.5 * bt / 0.05)) / SAMPLE_RATE) * _env(bt, 0.002, 0.015),
               rng.uniform(0.2, 1.4), rng.uniform(0.1, 0.3))
    return _norm(_trim_tail(_reverb(out, 2.0, 0.35, rng)), PEAK_SFX * 0.8)


def make_player_revive(rng):
    seconds = 1.4
    t = _t(seconds)
    rise = _osc(220.0 + 220.0 * np.clip(t / 0.8, 0, 1) ** 1.5, partials=((1.0, 1.0), (1.5, 0.4), (2.0, 0.3))) * _env(t, 0.3, 0.5)
    chime = np.zeros_like(rise)
    _place(chime, _osc(880.0, 1.0, ((1.0, 1.0), (1.5, 0.5))) * _env(_t(1.0), 0.003, 0.35), 0.75)
    air = _filter(_noise(seconds, rng), "bandpass", [400.0, 2500.0]) * np.sin(np.pi * t / seconds) ** 2 * 0.25
    out = _filter(rise, "lowpass", 2000.0) + chime * 0.5 + air
    return _norm(_trim_tail(_reverb(out, 2.0, 0.35, rng)), PEAK_SFX * 0.8)


def make_mending_hum(rng):
    length = 4.0
    hum = _loop_tone(220.0, length, ((1.0, 1.0), (2.0, 0.2))) + _loop_tone(330.0, length) * 0.6 + _loop_tone(440.25, length) * 0.4
    hum *= _loop_lfo(2, length, 0.35)
    hum = _circular_band(hum, 100.0, 1200.0)
    return _norm(_reverb(hum, 1.5, 0.3, rng, circular=True), PEAK_SOFT)


def make_low_oxygen(rng):
    out = np.zeros(int(0.7 * SAMPLE_RATE))
    for i, freq in enumerate((880.0, 660.0)):
        beep = _osc(freq, 0.12, ((1.0, 1.0), (3.0, 0.2))) * _env(_t(0.12), 0.005, 0.08)
        _place(out, beep, i * 0.18)
    out = _filter(out, "lowpass", 1500.0)
    return _norm(_fade(out, 0.0, 0.1), PEAK_SFX * 0.6)


def make_low_health(rng):
    out = np.zeros(int(0.75 * SAMPLE_RATE))
    _place(out, _kick(70.0, 42.0, 0.08), 0.0)
    _place(out, _kick(60.0, 38.0, 0.07), 0.2, 0.6)
    return _norm(_fade(_filter(out, "lowpass", 400.0), 0.0, 0.1), PEAK_SFX * 0.7)


def make_shard_hum(rng):
    length = 4.0
    glass = _loop_tone(1046.5, length) + _loop_tone(1047.0, length) * 0.8 + _loop_tone(1569.75, length) * 0.4 \
        + _loop_tone(2093.0, length) * 0.2
    glass *= _loop_lfo(3, length, 0.5)
    return _norm(_reverb(glass, 1.5, 0.4, rng, circular=True), PEAK_SOFT * 0.6)


def make_shard_pickup(rng):
    out = _chord([1046.5, 1568.0, 2093.0, 2637.0], 1.0, 0.002, 0.3, ((1.0, 1.0), (2.0, 0.2)), stagger=0.05)
    return _norm(_trim_tail(_reverb(out, 1.8, 0.35, rng)), PEAK_SFX * 0.75)


def _grind(rng, seconds: float):
    t = _t(seconds)
    jitter = np.repeat(rng.uniform(0.3, 1.0, int(seconds * 40) + 1), SAMPLE_RATE // 40)[: len(t)]
    return _filter(_noise(seconds, rng), "bandpass", [150.0, 900.0]) * jitter


def make_barrier_close(rng):
    out = np.zeros(int(1.6 * SAMPLE_RATE))
    grind = _grind(rng, 0.5) * np.linspace(0.3, 1.0, int(0.5 * SAMPLE_RATE))
    _place(out, grind, 0.0, 0.7)
    _place(out, make_impact(rng, 48.0, 0.25, 0.6, 1.0), 0.45, 1.0)
    return _norm(_trim_tail(_reverb(_filter(out, "lowpass", 3000.0), 1.5, 0.3, rng)), PEAK_SFX)


def make_barrier_open(rng):
    out = np.zeros(int(1.8 * SAMPLE_RATE))
    grind = _grind(rng, 0.9) * np.linspace(1.0, 0.2, int(0.9 * SAMPLE_RATE))
    _place(out, grind, 0.0, 0.7)
    air_t = _t(0.9)
    air = _filter(_noise(0.9, rng), "highpass", 1200.0) * np.sin(np.pi * air_t / 0.9) ** 2 * 0.4
    _place(out, air, 0.5)
    return _norm(_trim_tail(_reverb(_filter(out, "lowpass", 4000.0), 1.5, 0.3, rng)), PEAK_SFX * 0.85)


def make_collapse_rumble(rng):
    length = 6.0
    n = int(length * SAMPLE_RATE)
    rumble = _circular_band(_noise(length, rng), 20.0, 120.0, 0.6) * _loop_lfo(3, length, 0.4)
    hits = np.zeros(n)
    for i in range(7):
        _place(hits, _kick(rng.uniform(60.0, 90.0), 35.0, rng.uniform(0.15, 0.3), 1.0), rng.uniform(0.0, length), rng.uniform(0.3, 0.8), wrap=True)
    out = rumble / np.max(np.abs(rumble)) + hits * 0.6
    return _norm(_reverb(out, 2.0, 0.3, rng, circular=True), PEAK_AMBIENCE)


def make_rock_fall(rng):
    out = np.zeros(int(1.6 * SAMPLE_RATE))
    for i in range(rng.integers(8, 16)):
        seconds = rng.uniform(0.03, 0.1)
        t = _t(seconds)
        low = rng.uniform(250.0, 900.0)
        piece = _filter(_noise(seconds, rng), "bandpass", [low, low * 2.5]) * np.exp(-t / (seconds * 0.3))
        _place(out, piece, rng.uniform(0.0, 0.9) ** 1.5, rng.uniform(0.2, 0.8))
    for i in range(2):
        _place(out, _kick(rng.uniform(80.0, 120.0), 50.0, 0.12), rng.uniform(0.0, 0.4), 0.7)
    out = _filter(out, "lowpass", 3000.0)
    return _norm(_trim_tail(_reverb(out, 1.2, 0.25, rng)), PEAK_SFX * 0.8)


# --- The preview list ---------------------------------------------------------

def _preview_list():
    """(file name, maker(rng), loop) for every preview sound."""
    sounds = [
        ("amb_ocean_bed", make_ocean_bed, True),
    ]
    for i in range(4):
        sounds.append((f"amb_bubbles_{i + 1}", lambda rng, c=i + 1: make_bubbles(rng, c), False))
    sounds += [
        ("amb_whale_1", lambda rng: make_whale(rng, [32.0, 44.0, 36.0, 28.0], 4.5), False),
        ("amb_whale_2", lambda rng: make_whale(rng, [24.0, 30.0, 22.0], 6.0), False),
        ("amb_whale_3", lambda rng: make_whale(rng, [46.0, 58.0, 50.0, 40.0], 3.5), False),
        ("music_tension", make_tension, True),
        ("music_chase", make_chase, True),
        ("music_intense", make_intense, True),
        ("music_boss", make_boss, True),
        ("sting_spotted", make_sting_spotted, False),
        ("sting_shard", make_sting_shard, False),
        ("sting_lockdown", make_sting_lockdown, False),
        ("sting_doors_open", make_sting_doors_open, False),
        ("sting_level_complete", make_sting_level_complete, False),
        ("sting_downed", make_sting_downed, False),
        ("sword_whoosh_1", lambda rng: make_whoosh(rng, 0.2, 700.0, 2600.0, 0.15), False),
        ("sword_whoosh_2", lambda rng: make_whoosh(rng, 0.22, 600.0, 2300.0, 0.2), False),
        ("sword_whoosh_3", lambda rng: make_whoosh(rng, 0.32, 400.0, 1800.0, 0.45), False),
        ("sword_impact", lambda rng: make_impact(rng, 110.0, 0.08, 0.35, 0.4), False),
        ("sword_impact_heavy", lambda rng: make_impact(rng, 70.0, 0.18, 0.6, 0.8), False),
        ("sword_finisher", make_finisher, False),
        ("pulse_ping", lambda rng: make_sonar(rng, 420.0, [(0.32, 0.5), (0.64, 0.3), (0.96, 0.18), (1.28, 0.1)], 4000.0, 0.0, PEAK_SFX), False),
        ("pulse_distress", lambda rng: make_sonar(rng, 330.0, [(0.3, 0.35), (0.6, 0.15)], 900.0, 0.015, PEAK_SFX * 0.55), False),
    ]
    # Creatures: normal, Sentinel (deeper and slower), boss (layered + sub).
    for prefix, pitch, stretch in (("creature", 1.0, 1.0), ("sentinel", 0.72, 1.5), ("boss", 0.5, 1.3)):
        for i in range(3 if prefix == "creature" else 1):
            sounds.append((f"{prefix}_click_{i + 1}", lambda rng, p=pitch: make_creature_clicks(rng, p), False))
        for kind, maker in (("chitter", make_chitter), ("creak", make_creak), ("call", make_call)):
            if prefix == "boss":
                sounds.append((f"boss_investigate_{kind}", lambda rng, m=maker: make_boss_layered(rng, m), False))
            else:
                sounds.append((f"{prefix}_investigate_{kind}", lambda rng, m=maker, p=pitch, st=stretch: m(rng, p, st), False))
        sounds += [
            (f"{prefix}_screech", lambda rng, p=pitch: make_creature_screech(rng, p), False),
            (f"{prefix}_hiss", lambda rng, p=pitch: make_creature_hiss(rng, p), False),
            (f"{prefix}_death", lambda rng, p=pitch: make_creature_death(rng, p), False),
        ]
    for i in range(3):
        sounds.append((f"player_move_{i + 1}", make_swish, False))
    sounds += [
        ("player_hurt", make_player_hurt, False),
        ("player_downed", make_player_downed, False),
        ("player_revive", make_player_revive, False),
        ("player_mending_hum", make_mending_hum, True),
        ("player_low_oxygen", make_low_oxygen, False),
        ("player_low_health", make_low_health, False),
        ("world_shard_hum", make_shard_hum, True),
        ("world_shard_pickup", make_shard_pickup, False),
        ("world_barrier_close", make_barrier_close, False),
        ("world_barrier_open", make_barrier_open, False),
        ("world_collapse_rumble", make_collapse_rumble, True),
    ]
    for i in range(3):
        sounds.append((f"world_rock_fall_{i + 1}", make_rock_fall, False))
    return sounds


def write_preview(filters=()) -> None:
    """Writes every preview sound, or only those whose name contains one of
    the filters (e.g. "amb_whale" "investigate"). Each sound has its own seed
    (from its name), so regenerating some never changes the others."""
    if np is None:
        raise SystemExit("The preview pass needs numpy and scipy: pip install numpy scipy")
    import zlib
    written = 0
    for name, maker, loop in _preview_list():
        if filters and not any(f in name for f in filters):
            continue
        rng = np.random.default_rng([PREVIEW_SEED, zlib.crc32(name.encode())])
        write_wav_np(PREVIEW_DIR / f"{name}.wav", maker(rng), loop)
        written += 1
    print(f"{written} preview sound(s) written")

if __name__ == "__main__":
    import sys
    if "preview" in sys.argv[1:]:
        # Anything after "preview" filters by name, e.g.: preview amb_whale investigate
        write_preview(sys.argv[sys.argv.index("preview") + 1:])
        raise SystemExit(0)
    write_wav(OUTPUT_DIR / "sonar_ping.wav", make_ping())
    write_wav(OUTPUT_DIR / "sonar_tick.wav", make_tick())
    write_wav(OUTPUT_DIR / "creature_heartbeat.wav", make_heartbeat())
    write_wav(OUTPUT_DIR / "oxygen_alarm.wav", make_alarm())
    write_wav(OUTPUT_DIR / "station_refill.wav", make_refill())
    write_wav(OUTPUT_DIR / "ancient_light.wav", make_ancient())
    write_wav(OUTPUT_DIR / "creature_alert.wav", make_alert())
    write_wav(OUTPUT_DIR / "sword_swing.wav", make_swing())
    write_wav(OUTPUT_DIR / "sword_hit.wav", make_hit())
    write_wav(OUTPUT_DIR / "exposed_kill.wav", make_exposed_kill())
    write_wav(OUTPUT_DIR / "creature_lunge.wav", make_lunge())
    write_wav(OUTPUT_DIR / "shard_collect.wav", make_shard())
    write_wav(OUTPUT_DIR / "rumble.wav", make_rumble())
    write_wav(OUTPUT_DIR / "rock_slam.wav", make_slam())
    write_wav(OUTPUT_DIR / "lockdown_clear.wav", make_clear())
