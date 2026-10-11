#!/usr/bin/env python3
"""Generates the app's built-in background music.

Every sound is synthesised from scratch here (sine/saw/noise oscillators, envelopes, a noise-based reverb): there are no
samples, no recordings and no third-party material. The output is dedicated to the public domain under CC0 1.0, so it can be
used in any video, commercial or not, with no attribution.

Usage: python3 tools/generate_music.py <output_dir>     (needs numpy and macOS `afconvert` to make AAC .m4a files)
"""
import json, os, subprocess, sys, wave
import numpy as np

SR = 44100
rng_global = np.random.default_rng(7)

# ---------- helpers -----------------------------------------------------------------------------------------------
NOTE = {'C': 0, 'C#': 1, 'D': 2, 'Eb': 3, 'E': 4, 'F': 5, 'F#': 6, 'G': 7, 'Ab': 8, 'A': 9, 'Bb': 10, 'B': 11}
def midi(name, octave): return 12 * (octave + 1) + NOTE[name]
def hz(m): return 440.0 * 2 ** ((m - 69) / 12)

CH = {'maj7': [0, 4, 7, 11], 'min7': [0, 3, 7, 10], 'dom7': [0, 4, 7, 10], 'maj': [0, 4, 7], 'min': [0, 3, 7],
      'min9': [0, 3, 7, 10, 14], 'maj9': [0, 4, 7, 11, 14], 'dom13': [0, 4, 10, 14, 21], 'sus2': [0, 2, 7]}

def env(n, a=0.005, d=0.1, s=0.7, r=0.1):
    e = np.ones(n)
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    na = min(na, n); e[:na] = np.linspace(0, 1, max(na, 1))
    nd = min(nd, n - na); e[na:na + nd] = np.linspace(1, s, max(nd, 1))
    e[na + nd:] = s
    nr = min(nr, n); e[n - nr:] *= np.linspace(1, 0, max(nr, 1))
    return e

def expdecay(n, tau): return np.exp(-np.arange(n) / (tau * SR))

def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    k = a ** np.arange(int(8 / (1 - a)) if a < 0.9999 else 4000)
    k = k[:min(len(k), 4000)]
    k = k * (1 - a)
    return np.convolve(x, k)[:len(x)]

def highpass(x, cutoff): return x - lowpass(x, cutoff)

def sine(f, n, ph=0.0): return np.sin(2 * np.pi * f * np.arange(n) / SR + ph)

def rhodes(f, dur, vel=0.6):
    n = int(dur * SR); t = np.arange(n) / SR
    mod = np.sin(2 * np.pi * f * 1.0 * t) * 1.6 * np.exp(-t * 5.0)
    tone = np.sin(2 * np.pi * f * t + mod) + 0.35 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t * 6)
    return vel * tone * np.exp(-t * 1.4) * env(n, 0.004, 0.05, 1, 0.12)

def pluck(f, dur, vel=0.5, bright=1.0):
    n = int(dur * SR); t = np.arange(n) / SR
    y = sum((1 / h) * np.sin(2 * np.pi * f * h * t) * np.exp(-t * (2.5 + 1.8 * h) / bright) for h in range(1, 8))
    return vel * 0.6 * y * env(n, 0.002, 0.02, 1, 0.05)

def piano(f, dur, vel=0.5):
    n = int(dur * SR); t = np.arange(n) / SR
    y = sum((1 / h ** 1.15) * np.sin(2 * np.pi * f * h * (1 + 0.0004 * h * h) * t) * np.exp(-t * (1.1 + 0.9 * h)) for h in range(1, 9))
    return vel * 0.7 * y * env(n, 0.003, 0.05, 1, 0.2)

def pad(freqs, dur, vel=0.25, attack=0.6, release=0.8, bright=5):
    n = int(dur * SR); t = np.arange(n) / SR
    y = np.zeros(n)
    for f in freqs:
        for det in (-0.0035, 0.0, 0.0035):
            ff = f * (1 + det)
            y += sum((1 / h) * np.sin(2 * np.pi * ff * h * t + h) for h in range(1, bright))
    return vel * y / (len(freqs) * 3) * env(n, attack, 0.1, 0.9, release)

def saw_bass(f, dur, vel=0.5, cutoff=500):
    n = int(dur * SR); t = np.arange(n) / SR
    y = 2 * ((f * t) % 1.0) - 1
    return vel * lowpass(y, cutoff) * env(n, 0.003, 0.08, 0.7, 0.05)

def sub(f, dur, vel=0.6):
    n = int(dur * SR); t = np.arange(n) / SR
    return vel * (np.sin(2 * np.pi * f * t) + 0.18 * np.sin(4 * np.pi * f * t)) * env(n, 0.006, 0.05, 0.85, 0.08)

def kick(vel=0.9):
    n = int(0.35 * SR); t = np.arange(n) / SR
    f = 45 + 95 * np.exp(-t * 28)
    return vel * np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)

def snare(vel=0.5, rng=rng_global):
    n = int(0.25 * SR); t = np.arange(n) / SR
    noise = highpass(rng.standard_normal(n), 1500) * np.exp(-t * 22)
    tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 28)
    return vel * (0.8 * noise + 0.5 * tone)

def clap(vel=0.5, rng=rng_global):
    n = int(0.22 * SR); y = np.zeros(n)
    for off in (0, 0.012, 0.024):
        k = int(off * SR); m = n - k
        y[k:] += highpass(rng.standard_normal(m), 1200) * np.exp(-np.arange(m) / (0.05 * SR))
    return vel * 0.5 * y

def hat(vel=0.25, dur=0.05, rng=rng_global):
    n = int(dur * SR)
    return vel * highpass(rng.standard_normal(n), 6500) * np.exp(-np.arange(n) / (dur * 0.35 * SR))

def bell(f, dur, vel=0.4):
    n = int(dur * SR); t = np.arange(n) / SR
    y = np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 3) + 0.25 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t * 6)
    return vel * 0.6 * y * np.exp(-t * 2.2) * env(n, 0.002, 0.02, 1, 0.1)

def reverb(x, seconds=1.4, wet=0.25, seed=3, damp=3500):
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / (seconds * 0.22 * SR))
    ir = lowpass(ir, damp)
    ir /= np.sqrt(np.sum(ir ** 2))
    size = 1 << int(np.ceil(np.log2(len(x) + n)))
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:len(x) + n]
    return y

def place(buf, sig, t0):
    i = int(t0 * SR)
    if i >= len(buf): return
    j = min(len(buf), i + len(sig)); buf[i:j] += sig[:j - i]

def finish(left, right, bars_len, target_rms=0.085):
    """Folds the reverb tail back onto the start (so it loops without a gap), normalises and returns int16 stereo."""
    out = []
    for ch in (left, right):
        body = ch[:bars_len].copy(); tail = ch[bars_len:]
        body[:min(len(tail), bars_len)] += tail[:bars_len]
        out.append(body)
    st = np.stack(out, 1)
    st -= st.mean(0)
    rms = np.sqrt(np.mean(st ** 2)); st *= target_rms / max(rms, 1e-9)
    peak = np.max(np.abs(st))
    if peak > 0.92: st *= 0.92 / peak
    fade = int(0.004 * SR); st[:fade] *= np.linspace(0, 1, fade)[:, None]; st[-fade:] *= np.linspace(1, 0, fade)[:, None]
    return (st * 32767).astype(np.int16)

# ---------- track styles ------------------------------------------------------------------------------------------
def build(track):
    bpm = track['bpm']; beat = 60.0 / bpm; bar = 4 * beat; bars = track['bars']
    total = int(bars * bar * SR); pad_tail = int(2.5 * SR)
    L = np.zeros(total + pad_tail); R = np.zeros(total + pad_tail)
    rng = np.random.default_rng(track['seed'])
    prog = track['prog']; style = track['style']; swing = track.get('swing', 0.0)

    def add(sig, t, pan=0.0, gain=1.0):
        place(L, sig * gain * (1 - max(pan, 0)), t); place(R, sig * gain * (1 + min(pan, 0)), t)

    scale = [0, 2, 4, 7, 9, 12, 14, 16, 19]       # major pentatonic degrees (for melodies)
    for b in range(bars):
        root_name, kind, octv = prog[b % len(prog)]
        root = midi(root_name, octv); chord = [root + i for i in CH[kind]]
        t0 = b * bar
        if style == 'lofi':
            voicing = [chord[0], chord[1] + 12 if len(chord) > 1 else chord[0], chord[2], chord[3] if len(chord) > 3 else chord[2] + 12]
            for k, (off, vel) in enumerate([(0, 0.42), (2.5, 0.3)]):
                for i, m in enumerate(voicing):
                    add(rhodes(hz(m), 1.6, vel), t0 + off * beat + i * 0.012 + rng.uniform(0, 0.006), pan=-0.2 + 0.13 * i)
            add(sub(hz(root - 24), beat * 1.4, 0.7), t0); add(sub(hz(root - 24 + (7 if b % 2 else 0)), beat * 0.9, 0.55), t0 + 2.5 * beat)
            add(kick(1.5), t0); add(kick(1.0), t0 + 2.75 * beat)
            add(snare(0.95, rng), t0 + beat); add(snare(1.0, rng), t0 + 3 * beat)
            for h in range(8):
                add(hat(0.2 if h % 2 else 0.34, 0.04, rng), t0 + h * beat / 2 + (swing * beat / 2 if h % 2 else 0), pan=0.3)
        elif style == 'pop':
            for i in range(8):
                m = chord[[0, 2, 1, 2, 0, 2, 1, 3 % len(chord)][i]] + 12
                add(pluck(hz(m), beat * 0.9, 0.42), t0 + i * beat / 2, pan=-0.3 + 0.08 * i)
            add(pad([hz(m) for m in chord], bar, 0.20, 0.3, 0.4, 4), t0)
            add(pluck(hz(root - 12), beat * 1.6, 0.6, 0.6), t0); add(pluck(hz(root - 12 + 7), beat, 0.5, 0.6), t0 + 2 * beat)
            add(kick(0.75), t0); add(kick(0.65), t0 + 2 * beat)
            add(clap(0.5, rng), t0 + beat); add(clap(0.5, rng), t0 + 3 * beat)
            for h in range(8): add(hat(0.18 if h % 2 else 0.26, 0.04, rng), t0 + h * beat / 2, pan=0.35)
            mel = [scale[int(rng.integers(0, 5))] for _ in range(4)]
            if b % 2 == 1:
                for i, d in enumerate(mel): add(bell(hz(root + 12 + d), beat * 1.6, 0.28), t0 + i * beat, pan=0.2)
        elif style == 'synth':
            for i in range(8): add(saw_bass(hz(root - 24), beat / 2 * 0.9, 0.55, 420), t0 + i * beat / 2)
            add(pad([hz(m) for m in chord], bar, 0.26, 0.5, 0.6, 6), t0)
            arp = [0, 1, 2, 3, 2, 1, 2, 3]
            for i in range(16):
                m = chord[arp[i % 8] % len(chord)] + 12
                f = hz(m); n = int(beat / 4 * 1.6 * SR); tt = np.arange(n) / SR
                sig = lowpass(np.sign(np.sin(2 * np.pi * f * tt)) * 0.5, 2600) * np.exp(-tt * 9)
                add(sig * 0.5, t0 + i * beat / 4, pan=-0.4 + 0.05 * i)
            for q in range(4): add(kick(0.7), t0 + q * beat)
            for h in range(4): add(hat(0.22, 0.06, rng), t0 + h * beat + beat / 2, pan=0.3)
        elif style == 'ambient':
            if b % 2 == 0:
                add(pad([hz(m) for m in chord] + [hz(chord[0] + 12)], bar * 2, 0.42, 2.2, 2.5, 6), t0)
                add(pad([hz(chord[-1] + 24)], bar * 2, 0.07, 3.0, 3.0, 3), t0, pan=0.4)
            add(sub(hz(root - 12), bar * 0.95, 0.35), t0)
            if b % 4 == 3:
                add(bell(hz(chord[int(rng.integers(0, len(chord)))] + 24), 3.5, 0.18), t0 + beat * float(rng.integers(0, 3)), pan=-0.3)
        elif style == 'corp':
            for i in range(8):
                m = chord[[0, 1, 2, 1, 0, 1, 2, 3 % len(chord)][i]] + 12
                add(bell(hz(m), beat * 1.2, 0.26), t0 + i * beat / 2, pan=-0.25 + 0.07 * i)
            add(pad([hz(m) for m in chord], bar, 0.22, 0.4, 0.5, 5), t0)
            for i in range(8): add(sub(hz(root - 24), beat / 2 * 0.8, 0.5), t0 + i * beat / 2)
            add(kick(0.7), t0); add(kick(0.6), t0 + 2 * beat); add(clap(0.42, rng), t0 + beat); add(clap(0.42, rng), t0 + 3 * beat)
            for h in range(8): add(hat(0.14, 0.035, rng), t0 + h * beat / 2, pan=0.3)
        elif style == 'piano':
            for i, m in enumerate(chord):
                add(piano(hz(m), 3.2, 0.5), t0 + i * 0.045, pan=-0.2 + 0.1 * i)
            add(piano(hz(root - 12), 3.0, 0.5), t0)
            for i in range(4):
                if rng.random() < 0.75:
                    d = scale[int(rng.integers(0, 6))]
                    add(piano(hz(root + 12 + d), 1.8, 0.4), t0 + i * beat + (0.5 * beat if rng.random() < 0.3 else 0), pan=0.25)
        elif style == 'lounge':
            voicing = [chord[1], chord[2], chord[3] if len(chord) > 3 else chord[0] + 12, chord[4] if len(chord) > 4 else chord[1] + 12]
            for off in (0, 1.5, 2.5):
                for i, m in enumerate(voicing): add(rhodes(hz(m), 1.0, 0.3), t0 + off * beat + i * 0.01, pan=-0.25 + 0.15 * i)
            walk = [root - 24, root - 24 + 4, root - 24 + 7, root - 24 + 5]
            for i, m in enumerate(walk): add(pluck(hz(m), beat * 0.95, 0.55, 0.5), t0 + i * beat)
            for h in range(8):
                add(hat(0.34 if h % 2 == 0 else 0.2, 0.08, rng), t0 + h * beat / 2 + (swing * beat / 2 if h % 2 else 0), pan=0.3)
            add(kick(1.1), t0); add(kick(0.7), t0 + 2.5 * beat); add(snare(0.6, rng), t0 + beat); add(snare(0.6, rng), t0 + 3 * beat)

    cutoff = track.get('lp')
    if cutoff: L = lowpass(L, cutoff); R = lowpass(R, cutoff)
    wet = track.get('wet', 0.2); secs = track.get('rev', 1.4)
    rl = reverb(L, secs, seed=11); rr = reverb(R, secs, seed=12)
    n = max(len(L), len(rl))
    Lw = np.zeros(n); Rw = np.zeros(n)
    Lw[:len(L)] += L; Rw[:len(R)] += R
    Lw[:len(rl)] += wet * rl; Rw[:len(rr)] += wet * rr
    if track.get('crackle'):
        c = (rng.random(n) < 0.0009) * rng.standard_normal(n) * 0.05
        Lw += highpass(c, 1500) ; Rw += highpass(np.roll(c, 91), 1500)
    return finish(Lw, Rw, total, track.get('rms', 0.085))

TRACKS = [
    dict(id='soft-focus', title='Soft Focus', mood='Lo-Fi', bpm=78, bars=16, seed=1, style='lofi', swing=0.18, lp=5200, wet=0.22, crackle=True,
         prog=[('C', 'maj7', 3), ('A', 'min7', 2), ('F', 'maj7', 3), ('G', 'dom7', 2)]),
    dict(id='sunny-lo-fi', title='Sunny Lo-Fi', mood='Lo-Fi', bpm=86, bars=16, seed=2, style='lofi', swing=0.22, lp=6000, wet=0.2, crackle=True,
         prog=[('F', 'maj7', 3), ('E', 'min7', 3), ('D', 'min7', 3), ('C', 'maj7', 3)]),
    dict(id='morning-light', title='Morning Light', mood='Upbeat', bpm=112, bars=16, seed=3, style='pop', wet=0.18,
         prog=[('C', 'maj', 3), ('G', 'maj', 2), ('A', 'min', 2), ('F', 'maj', 3)]),
    dict(id='night-drive', title='Night Drive', mood='Electronic', bpm=102, bars=16, seed=4, style='synth', wet=0.22, lp=7500,
         prog=[('A', 'min', 2), ('F', 'maj', 2), ('C', 'maj', 3), ('G', 'maj', 2)]),
    dict(id='open-space', title='Open Space', mood='Ambient', bpm=60, bars=16, seed=5, style='ambient', wet=0.5, rev=3.0, rms=0.075,
         prog=[('D', 'sus2', 3), ('Bb', 'maj7', 2), ('G', 'maj7', 2), ('A', 'sus2', 2)]),
    dict(id='keynote', title='Keynote', mood='Commercial', bpm=100, bars=16, seed=6, style='corp', wet=0.18,
         prog=[('D', 'maj', 3), ('A', 'maj', 2), ('B', 'min', 2), ('G', 'maj', 2)]),
    dict(id='quiet-piano', title='Quiet Piano', mood='Instrumental', bpm=72, bars=16, seed=8, style='piano', wet=0.32, rev=2.2, rms=0.08,
         prog=[('Eb', 'maj7', 3), ('C', 'min7', 3), ('Ab', 'maj7', 2), ('Bb', 'dom7', 2)]),
    dict(id='bright-lounge', title='Bright Lounge', mood='Lounge', bpm=104, bars=16, seed=9, style='lounge', swing=0.3, wet=0.18, lp=7000,
         prog=[('D', 'min9', 3), ('G', 'dom13', 2), ('C', 'maj9', 3), ('A', 'dom7', 2)]),
]

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else 'Music'
    os.makedirs(out, exist_ok=True)
    meta = []
    for t in TRACKS:
        pcm = build(t)
        wav = os.path.join(out, t['id'] + '.wav'); m4a = os.path.join(out, t['id'] + '.m4a')
        with wave.open(wav, 'wb') as w:
            w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
        subprocess.run(['afconvert', '-f', 'm4af', '-d', 'aac', '-b', '128000', wav, m4a], check=True)
        os.remove(wav)
        dur = len(pcm) / SR
        meta.append({'id': t['id'], 'title': t['title'], 'mood': t['mood'], 'bpm': t['bpm'], 'seconds': round(dur, 1),
                     'file': t['id'] + '.m4a', 'license': 'CC0-1.0'})
        print(f"{t['id']:14s} {dur:5.1f}s  {os.path.getsize(m4a) / 1024:6.0f} KB")
    with open(os.path.join(out, 'music.json'), 'w') as f: json.dump(meta, f, indent=2)

if __name__ == '__main__': main()
