"""Genera los efectos de sonido del juego (síntesis simple, estilo arcade).

Uso:  python3 tools/make_sfx.py
Escribe los .wav en assets/audio/sfx/. Mono, 16 bits, 22050 Hz.
Los sonidos que terminan en _loop se pueden repetir sin cortes.
"""
import os
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "sfx")
rng = np.random.default_rng(7)


def t(seconds):
    return np.arange(int(SR * seconds)) / SR


def env(n, attack=0.005, decay=None, curve=4.0):
    """Ataque rápido y caída exponencial hasta el final."""
    x = np.arange(n) / SR
    a = np.clip(x / max(attack, 1e-4), 0.0, 1.0)
    total = n / SR
    d = np.exp(-curve * x / (decay or total))
    return a * d


def lowpass(x, cutoff):
    """Pasa-bajos de un polo; cutoff puede variar en el tiempo (array)."""
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        k = 1.0 - np.exp(-2.0 * np.pi * cutoff[i] / SR)
        acc += k * (x[i] - acc)
        y[i] = acc
    return y


def bandpass(x, center, q=4.0):
    """Filtro de estado variable (pasa-banda) con centro que puede variar."""
    center = np.broadcast_to(np.asarray(center, dtype=float), x.shape)
    low = band = 0.0
    y = np.zeros_like(x)
    damp = 1.0 / q
    for i in range(len(x)):
        f = 2.0 * np.sin(np.pi * min(center[i], SR / 4) / SR)
        high = x[i] - low - damp * band
        band += f * high
        low += f * band
        y[i] = band
    return y


def sweep(f0, f1, seconds, shape="sine"):
    tt = t(seconds)
    freq = f0 * (f1 / f0) ** (tt / seconds)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    if shape == "square":
        return np.sign(np.sin(phase)) * 0.6
    if shape == "tri":
        return 2 / np.pi * np.arcsin(np.sin(phase))
    return np.sin(phase)


def tone(freq, seconds, harmonics=(1.0, 0.3, 0.1)):
    tt = t(seconds)
    s = sum(a * np.sin(2 * np.pi * freq * (i + 1) * tt) for i, a in enumerate(harmonics))
    return s / sum(harmonics)


def noise(seconds):
    return rng.uniform(-1.0, 1.0, int(SR * seconds))


def concat(*parts):
    return np.concatenate(parts)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def seamless(x, fade=0.08):
    """Para loops: mezcla el final con el principio para que no haga clic."""
    n = int(SR * fade)
    head, body, tail = x[:n], x[n:-n], x[-n:]
    ramp = np.linspace(0.0, 1.0, n)
    return concat(body, tail * (1 - ramp) + head * ramp)


def save(name, x, gain=0.9):
    x = np.asarray(x, dtype=float)
    peak = np.max(np.abs(x)) or 1.0
    x = x / peak * gain
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"{name}.wav  {len(x) / SR:.2f} s")


def splash(seconds=0.7, bright=3500.0, thump=True):
    n = noise(seconds)
    cutoff = bright * np.exp(-3.0 * t(seconds) / seconds) + 300
    s = lowpass(n, cutoff) * env(len(n), 0.004, seconds * 0.6)
    if thump:
        s = mix(s, 0.5 * sweep(140, 60, 0.25) * env(int(SR * 0.25), 0.002))
    return s


def main():
    os.makedirs(OUT, exist_ok=True)
    # Caer al agua.
    save("splash", splash(0.75))
    # Atravesar una ola que rompe: chapuzón grande que barre.
    big = noise(1.0)
    big = bandpass(big, 400 + 2600 * np.exp(-2.5 * t(1.0)), q=1.2) * env(len(big), 0.01, 0.8, 3.0)
    save("wave_punch", mix(big, 0.7 * splash(0.9, 5000)))
    # Pop: "bloop" que sube + salpicada chica.
    save("pop", mix(sweep(260, 950, 0.14) * env(int(SR * 0.14), 0.002), 0.35 * splash(0.3, 4000, False)))
    # Saltito.
    save("hop", sweep(240, 480, 0.09, "tri") * env(int(SR * 0.09), 0.002) * 0.7)
    # Aterrizar en el agua.
    save("land", splash(0.3, 2500, True), 0.7)
    # Turbo: soplido que sube + zumbido.
    w = noise(0.9)
    whoosh = bandpass(w, 300 + 2500 * (t(0.9) / 0.9) ** 1.5, q=3.0) * env(len(w), 0.05, 0.9, 2.0)
    buzz = 0.25 * sweep(110, 330, 0.9, "square") * env(int(SR * 0.9), 0.02, 0.9, 2.5)
    save("turbo", mix(whoosh, lowpass(buzz, 1500)))
    # Círculo de velocidad: tres notas brillantes.
    notes = [tone(f, 0.12, (1.0, 0.4, 0.2)) * env(int(SR * 0.12), 0.003, 0.12) for f in (880, 1320, 1760)]
    save("ring", concat(*notes, np.zeros(int(SR * 0.05))), 0.7)
    # Truco logrado: dos notas que suben.
    ok = [tone(f, 0.15, (1.0, 0.5, 0.25)) * env(int(SR * 0.15), 0.003, 0.15) for f in (659, 988)]
    save("trick_ok", concat(*ok), 0.7)
    # Truco fallido: "wah" que baja.
    wah = sweep(420, 140, 0.5, "tri") * env(int(SR * 0.5), 0.01, 0.5, 1.5)
    save("trick_fail", lowpass(wah, 1800), 0.8)
    # Choque con una roca: golpe seco.
    thud = sweep(110, 45, 0.35) * env(int(SR * 0.35), 0.001, 0.35, 5.0)
    crack = lowpass(noise(0.12), 2000) * env(int(SR * 0.12), 0.001, 0.12, 6.0)
    save("crash", mix(thud, 0.6 * crack))
    # Tirar a alguien con el derrape: "bonk" cartoon.
    save("bonk", sweep(620, 180, 0.22, "tri") * env(int(SR * 0.22), 0.002, 0.22, 2.0), 0.8)
    # Spamear para subirse: toquecito.
    save("mash", tone(1250, 0.035, (1.0,)) * env(int(SR * 0.035), 0.001, 0.035, 5.0), 0.5)
    # Cuenta regresiva y largada.
    save("beep", tone(660, 0.16, (1.0, 0.3)) * env(int(SR * 0.16), 0.003, 0.16, 2.0), 0.7)
    save("go", tone(990, 0.45, (1.0, 0.4, 0.15)) * env(int(SR * 0.45), 0.003, 0.45, 2.0), 0.8)
    # Nueva vuelta.
    lap = [tone(f, 0.13, (1.0, 0.3)) * env(int(SR * 0.13), 0.003, 0.13) for f in (880, 1175)]
    save("lap", concat(*lap), 0.7)
    # Llegada: fanfarria corta.
    fan = [tone(f, d, (1.0, 0.5, 0.25)) * env(int(SR * d), 0.004, d, 2.0)
           for f, d in ((523, 0.12), (659, 0.12), (784, 0.12), (1047, 0.45))]
    save("finish", concat(*fan), 0.8)
    # Derrape (loop): siseo de agua.
    d = noise(1.2)
    save("drift_loop", seamless(bandpass(d, 1800, q=0.8) + 0.3 * lowpass(d, 600)), 0.6)
    # Mar de fondo (loop): olas suaves que van y vienen.
    length = 6.0
    o = lowpass(noise(length), 500)
    swell = 0.55 + 0.45 * np.sin(2 * np.pi * t(length) / (length / 2)) ** 2
    save("ocean_loop", seamless(o * swell, 0.4), 0.5)


if __name__ == "__main__":
    main()
