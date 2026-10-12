#!/usr/bin/env python3
"""Generate the bundled chime sounds (share/sounds/chime-*.wav). Original work, CC0-1.0."""
import math, struct, wave, os
RATE = 22050
def tone(freq, dur, vol=0.35):
    n = int(RATE * dur); out = []
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / 0.008) * math.exp(-t * 7.0)          # soft attack, bell-like decay
        s = math.sin(2 * math.pi * freq * t) + 0.3 * math.sin(2 * math.pi * freq * 2 * t)
        out.append(vol * env * s / 1.3)
    return out
def mix(parts):  # parts: (offset_s, samples)
    n = max(int(o * RATE) + len(s) for o, s in parts); buf = [0.0] * n
    for o, s in parts:
        k = int(o * RATE)
        for i, v in enumerate(s): buf[k + i] += v
    return buf
SOUNDS = {
    "approval": mix([(0, tone(660, 0.45)), (0.14, tone(880, 0.55))]),          # rising: needs you
    "done":     mix([(0, tone(1046.5, 0.6, 0.3))]),                             # single soft high bell
    "error":    mix([(0, tone(330, 0.35)), (0.16, tone(247, 0.5))]),            # falling, low
}
d = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "share", "sounds")
for name, buf in SOUNDS.items():
    with wave.open(os.path.join(d, f"chime-{name}.wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in buf))
