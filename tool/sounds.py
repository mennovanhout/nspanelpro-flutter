"""Synthesises assets/sounds/*.wav. Run from the repo root: python tool/sounds.py

Every sound is a few sine partials and an envelope: nothing sampled, nothing to
license. Keep them short and distinct; the panel's speaker is small and mono.
The list at the bottom is the one lib/audio/sounds.dart and the README carry.
"""
import math, os, random, wave, struct

SR = 22050
BELL = [(1, 1.0), (2, 0.45), (3, 0.22), (4.2, 0.12), (5.4, 0.06)]
SOFT = [(1, 1.0), (2, 0.25), (3, 0.08)]
BUZZ = [(1, 1.0), (3, 0.33), (5, 0.2), (7, 0.14), (9, 0.11)]


def tone(freq, dur, amp=0.5, partials=SOFT, attack=0.005, decay=None, glide=None, am=None):
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        f = freq if glide is None else freq + (glide - freq) * (t / dur)
        env = min(1.0, t / attack) if attack else 1.0
        if decay:
            env *= math.exp(-t / decay)
        env *= min(1.0, (dur - t) / 0.01)
        if am:
            env *= 0.5 + 0.5 * math.sin(2 * math.pi * am * t)
        v = sum(a * math.sin(2 * math.pi * f * m * t) for m, a in partials)
        out.append(amp * env * v)
    return out


def thud(dur=0.12, amp=0.9):
    n = int(SR * dur)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = 160 * math.exp(-t * 25) + 55
        ph += 2 * math.pi * f / SR
        env = math.exp(-t * 28)
        out.append(amp * env * (math.sin(ph) + 0.3 * (random.random() * 2 - 1) * math.exp(-t * 80)))
    return out


def silence(dur):
    return [0.0] * int(SR * dur)


def seq(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


def overlay(base, part, at):
    out = list(base)
    start = int(SR * at)
    need = start + len(part) - len(out)
    if need > 0:
        out.extend([0.0] * need)
    for i, v in enumerate(part):
        out[start + i] += v
    return out


def notes(freqs, dur, gap=0.0, **kw):
    return seq(*[seq(tone(f, dur, **kw), silence(gap)) for f in freqs])


def write(name, samples, peak=0.9):
    m = max(abs(v) for v in samples) or 1.0
    data = b"".join(struct.pack("<h", int(max(-1, min(1, v / m * peak)) * 32767)) for v in samples)
    with wave.open(os.path.join("assets", "sounds", name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


C5, D5, E5, G5, A5, C6, E6 = 523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1318.5

random.seed(1)
SOUNDS = {
    # name: (description, samples)
    "doorbell": ("ding-dong", overlay(tone(E5, 1.6, partials=BELL, decay=0.5), tone(C5, 1.8, partials=BELL, decay=0.7), 0.45)),
    "chime": ("one bell", tone(A5, 2.0, partials=BELL, decay=0.9)),
    "notify": ("two soft notes, a plain notification", overlay(tone(G5, 0.8, partials=SOFT, decay=0.3), tone(C6, 1.0, partials=SOFT, decay=0.4), 0.16)),
    "pop": ("a click, for a button", tone(900, 0.04, partials=SOFT, decay=0.012)),
    "alert": ("three beeps", notes([1000] * 3, 0.12, gap=0.1, partials=BUZZ, amp=0.6)),
    "warning": ("two falling tones, twice: a door left open, a leak", seq(notes([620, 420], 0.28, gap=0.04, partials=BUZZ), silence(0.3), notes([620, 420], 0.28, gap=0.04, partials=BUZZ))),
    "alarm": ("a siren, three seconds: smoke, intrusion", seq(*[tone(f, 0.25, partials=BUZZ, attack=0.02) for f in [750, 1000] * 6])),
    "armed": ("three rising beeps", notes([600, 800, 1000], 0.1, gap=0.06, partials=BUZZ)),
    "disarmed": ("three falling beeps", notes([1000, 800, 600], 0.1, gap=0.06, partials=BUZZ)),
    "success": ("a rising arpeggio: something completed", seq(notes([C5, E5, G5], 0.12, partials=SOFT), tone(C6, 0.9, partials=BELL, decay=0.35))),
    "error": ("two low buzzes: something failed", seq(tone(220, 0.15, partials=BUZZ), silence(0.08), tone(180, 0.3, partials=BUZZ))),
    "knock": ("three knocks on wood", seq(thud(), silence(0.16), thud(), silence(0.16), thud(), silence(0.3))),
    "ring": ("a phone ringing", seq(*[seq(tone(440, 0.4, partials=[(1, 1), (480 / 440, 1)], attack=0.01), silence(0.2)) for _ in range(2)], silence(0.6), *[seq(tone(440, 0.4, partials=[(1, 1), (480 / 440, 1)], attack=0.01), silence(0.2)) for _ in range(2)])),
    "timer": ("a kitchen timer", seq(tone(1900, 1.1, partials=BELL, am=24), silence(0.25), tone(1900, 1.1, partials=BELL, am=24))),
    "laundry": ("a little tune: the washer is done", seq(notes([C5, E5, G5, E5], 0.17, partials=BELL, decay=0.25), tone(C6, 1.0, partials=BELL, decay=0.4))),
    "door_open": ("a short slide up", tone(400, 0.16, glide=640, partials=SOFT, attack=0.01)),
    "door_close": ("a short slide down", tone(640, 0.16, glide=400, partials=SOFT, attack=0.01)),
    "battery": ("two quiet low beeps", notes([420] * 2, 0.1, gap=0.1, partials=SOFT, amp=0.35)),
    "morning": ("a gentle rising phrase", seq(notes([C5, D5, E5], 0.3, partials=SOFT, decay=0.5), overlay(tone(G5, 1.4, partials=SOFT, decay=0.6), tone(C6, 1.4, partials=SOFT, decay=0.6, amp=0.4), 0.0))),
    "goodnight": ("a slow falling phrase, quiet", notes([G5, E5, C5], 0.55, partials=SOFT, decay=0.6, amp=0.4)),
}

if __name__ == "__main__":
    os.makedirs(os.path.join("assets", "sounds"), exist_ok=True)
    for name, (desc, samples) in SOUNDS.items():
        write(name, samples, peak=0.6 if name in ("battery", "goodnight", "pop") else 0.9)
        print(f"{name:11} {len(samples)/SR:4.1f}s  {desc}")
    # the Dart list and the README table are generated from the same dict
    with open(os.path.join("lib", "audio", "sounds.dart"), "w", newline="\n") as f:
        f.write("// Generated by tool/sounds.py - edit that, not this.\n\n")
        f.write("/// The built-in sounds, `sound:<name>` in an announcement.\n")
        f.write("const Map<String, String> kSounds = {\n")
        for name, (desc, _) in SOUNDS.items():
            f.write(f"  '{name}': '{desc}',\n")
        f.write("};\n")
