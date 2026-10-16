"""Pista musical original (libre de derechos) para la demo.

Estilo corporativo tranquilo: pad de acordes, arpegio suave, bajo y un pulso
ligero. Progresión I–V–vi–IV en Re mayor a 96 BPM. Uso:
    python3 musica.py <segundos> <salida.wav>
"""
import sys
import wave

import numpy as np
from scipy.signal import lfilter

SR = 44100
BPM = 96
BEAT = 60.0 / BPM
BAR = 4 * BEAT

# Re mayor: D–A–Bm–G (notas MIDI de cada acorde)
ACORDES = [
    [62, 66, 69, 74],   # D
    [57, 61, 64, 69],   # A
    [59, 62, 66, 71],   # Bm
    [55, 59, 62, 67],   # G
]
BAJOS = [38, 33, 35, 31]


def hz(nota):
    return 440.0 * 2 ** ((nota - 69) / 12)


def envolvente(n, ataque, caida):
    env = np.ones(n)
    a = min(n, int(ataque * SR))
    c = min(n - a, int(caida * SR))
    if a:
        env[:a] = np.linspace(0, 1, a)
    if c:
        env[n - c:] = np.linspace(1, 0, c)
    return env


def pad(nota, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = hz(nota)
    # dos osciladores levemente desafinados + armónico suave = pad cálido
    s = (np.sin(2 * np.pi * f * t) + 0.6 * np.sin(2 * np.pi * f * 1.004 * t)
         + 0.25 * np.sin(2 * np.pi * 2 * f * 0.998 * t))
    return s * envolvente(n, 0.8, 1.2) * 0.05


def pulsada(nota, dur, vol=0.12):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = hz(nota)
    s = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * 3 * f * t) * np.exp(-t * 8)
    return s * np.exp(-t * 3.2) * envolvente(n, 0.005, 0.05) * vol


def bajo(nota, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = hz(nota)
    s = np.sin(2 * np.pi * f * t) + 0.2 * np.sin(2 * np.pi * 2 * f * t)
    return s * envolvente(n, 0.02, 0.25) * 0.16


def bombo(dur=0.35):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 110 * np.exp(-t * 18) + 45
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9) * 0.22


def platillo(dur=0.08, rng=np.random.default_rng(7)):
    n = int(dur * SR)
    t = np.arange(n) / SR
    ruido = rng.standard_normal(n)
    ruido = np.diff(np.concatenate([[0], ruido]))  # pasa-altos simple
    return ruido * np.exp(-t * 70) * 0.014


def poner(buf, s, ini):
    i = int(ini * SR)
    j = min(len(buf), i + len(s))
    if i < len(buf):
        buf[i:j] += s[: j - i]


def componer(segundos):
    total = int((segundos + 2) * SR)
    izq = np.zeros(total)
    der = np.zeros(total)
    compases = int(np.ceil(segundos / BAR)) + 1
    arpegio = [0, 2, 1, 3, 2, 1, 3, 2]
    for c in range(compases):
        ini = c * BAR
        seccion = (c // 8) % 4   # cada 8 compases cambia la textura
        grado = (c + (2 if seccion == 2 else 0)) % 4   # en el respiro: vi–IV–I–V
        acorde = ACORDES[grado]
        for k, nota in enumerate(acorde):
            s = pad(nota, BAR + 0.6)
            poner(izq, s * (1.0 if k % 2 else 0.7), ini)
            poner(der, s * (0.7 if k % 2 else 1.0), ini)
        poner(izq, bajo(BAJOS[grado], BAR * 0.95), ini)
        poner(der, bajo(BAJOS[grado], BAR * 0.95), ini)
        if c >= 2:  # el arpegio entra después de la introducción
            for p in range(8):
                nota = acorde[arpegio[p]] + (12 if seccion in (1, 3) else 0)
                s = pulsada(nota, BEAT * 0.9, 0.07 if seccion == 0 else 0.09)
                pan = 0.35 + 0.3 * (p % 2)
                poner(izq, s * (1 - pan), ini + p * BEAT / 2)
                poner(der, s * pan, ini + p * BEAT / 2)
        if c >= 4 and seccion != 2:  # pulso ligero, con un respiro cada tanto
            for b in range(4):
                poner(izq, bombo(), ini + b * BEAT)
                poner(der, bombo(), ini + b * BEAT)
                poner(izq, platillo() * 0.8, ini + b * BEAT + BEAT / 2)
                poner(der, platillo(), ini + b * BEAT + BEAT / 2)
    # reverberación sencilla (ecos atenuados, cruzados entre canales)
    for retardo, g in [(0.113, 0.28), (0.197, 0.2), (0.31, 0.14), (0.47, 0.09)]:
        d = int(retardo * SR)
        izq[d:] += der[:-d] * g
        der[d:] += izq[:-d] * g
    # filtro pasa-bajos suave (un polo, ~6.5 kHz) para un timbre cálido
    a = np.exp(-2 * np.pi * 6500 / SR)
    izq = lfilter([1 - a], [1, -a], izq)
    der = lfilter([1 - a], [1, -a], der)
    mezcla = np.stack([izq, der], axis=1)[: int(segundos * SR)]
    n = len(mezcla)
    fade_in, fade_out = int(3 * SR), int(5 * SR)
    mezcla[:fade_in] *= np.linspace(0, 1, fade_in)[:, None]
    mezcla[n - fade_out:] *= np.linspace(1, 0, fade_out)[:, None]
    mezcla /= np.max(np.abs(mezcla)) + 1e-9
    return (np.tanh(mezcla * 1.2) * 0.8 * 32767).astype(np.int16)


if __name__ == "__main__":
    seg = float(sys.argv[1])
    datos = componer(seg)
    with wave.open(sys.argv[2], "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(datos.tobytes())
    print("ok", seg, "s")
