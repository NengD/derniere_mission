# Prépare les sons du jeu à partir des paquets CC0 téléchargés dans _sources/sons.
# À lancer avec le Python de Blender (numpy + aud fournis) :
#   blender -b --factory-startup -P tools/blender/make_sounds.py
# Écrit des WAV 16 bits mono 44,1 kHz dans assets/sons/.
import os
import sys
import wave
import numpy as np
import aud

RACINE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(RACINE, "_sources", "sons")
ARENE = os.path.abspath(os.path.join(RACINE, "..", "arene_v2", "assets", "sounds"))
DST = os.path.join(RACINE, "assets", "sons")
SR = 44100
os.makedirs(DST, exist_ok=True)


def charger(chemin):
    s = aud.Sound(chemin)
    rate, _ch = s.specs
    d = np.asarray(s.data(), dtype=np.float32)
    if d.ndim == 2:
        d = d.mean(axis=1)
    if int(rate) != SR:
        n = int(len(d) * SR / rate)
        d = np.interp(np.linspace(0, len(d) - 1, n), np.arange(len(d)), d).astype(np.float32)
    return d


def departs(d, seuil=0.3, ecart=1.5):
    """Instants (échantillons) où le son dépasse seuil × crête, espacés d'au moins `ecart` s."""
    env = np.abs(d)
    lim = env.max() * seuil
    res = []
    i = 0
    while i < len(env):
        if env[i] > lim:
            res.append(i)
            i += int(ecart * SR)
        else:
            i += 1
    return res


def rogner(d, seuil_db=-50.0):
    env = np.abs(d)
    lim = env.max() * (10 ** (seuil_db / 20))
    idx = np.where(env > lim)[0]
    if len(idx) == 0:
        return d
    return d[max(0, idx[0] - int(0.003 * SR)): idx[-1] + 1]


def fondu(d, entree=0.002, sortie=0.05):
    d = d.copy()
    a = min(len(d), int(entree * SR))
    b = min(len(d), int(sortie * SR))
    if a > 0:
        d[:a] *= np.linspace(0, 1, a)
    if b > 0:
        d[-b:] *= np.linspace(1, 0, b) ** 2
    return d


def normaliser(d, crete_db=-1.0):
    m = np.abs(d).max()
    if m <= 0:
        return d
    return d * (10 ** (crete_db / 20) / m)


def ecrire(nom, d, crete_db=-1.0, entree=0.002, sortie=0.05):
    d = normaliser(fondu(d, entree, sortie), crete_db)
    pcm = (np.clip(d, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(DST, nom + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("  %-22s %.2f s" % (nom, len(d) / SR))


def tirs(fichier, prefixe, duree, crete_db=-0.5):
    d = charger(os.path.join(SRC, "firearm", "Prepared SFX Library", fichier))
    for k, t in enumerate(departs(d)):
        debut = max(0, t - int(0.004 * SR))
        ecrire("%s_%d" % (prefixe, k + 1), d[debut: debut + int(duree * SR)], crete_db, 0.001, duree * 0.5)


def simple(nom, chemin, crete_db=-1.0, max_s=None, seuil_db=-50.0, sortie=0.05):
    d = rogner(charger(chemin), seuil_db)
    if max_s:
        d = d[: int(max_s * SR)]
    ecrire(nom, d, crete_db, 0.002, sortie)


# ---------- sons synthétisés ----------
rng = np.random.default_rng(7)


def t_(duree):
    return np.arange(int(duree * SR)) / SR


def douille(k):
    # petit tube de laiton qui rebondit sur le béton : partiels aigus amortis, 2-3 rebonds
    out = np.zeros(int(0.7 * SR), np.float32)
    f0 = 3200 + 400 * k
    pos = 0.0
    amp = 1.0
    for r in range(3):
        t = t_(0.12)
        s = sum(np.sin(2 * np.pi * f0 * m * t + rng.random() * 6) / (1 + i) for i, m in enumerate((1.0, 2.76, 5.4)))
        s = s * np.exp(-t * 55) + rng.normal(0, 0.15, len(t)) * np.exp(-t * 300)
        i0 = int(pos * SR)
        out[i0: i0 + len(s)] += (s * amp)[: len(out) - i0]
        pos += 0.09 + 0.05 * rng.random() - r * 0.02
        amp *= 0.45
    return out


def clic_vide():
    t = t_(0.08)
    s = rng.normal(0, 1, len(t)) * np.exp(-t * 400) + np.sin(2 * np.pi * 1900 * t) * np.exp(-t * 120) * 0.4
    return s


def coeur():
    # deux coups sourds (lub-dub), pour la boucle de blessure
    out = np.zeros(int(0.85 * SR), np.float32)
    for dec, f, a in ((0.0, 52, 1.0), (0.17, 64, 0.7)):
        t = t_(0.22)
        s = np.sin(2 * np.pi * f * t * (1 - 0.3 * t)) * np.exp(-t * 22) * a
        i0 = int(dec * SR)
        out[i0: i0 + len(s)] += s
    return out


def gresil(duree):
    t = t_(duree)
    s = rng.normal(0, 1, len(t))
    crep = (rng.random(len(t)) > 0.9985) * rng.normal(0, 4, len(t))
    env = np.minimum(1, t / 0.01) * np.minimum(1, (duree - t) / 0.04)
    return (s * 0.35 + crep) * env


def bip_radio():
    t = t_(0.09)
    return np.sin(2 * np.pi * 1450 * t) * 0.6 + gresil(0.09) * 0.2


def main():
    print("Tirs")
    tirs("Walther PPQ/X_39P.wav", "tir_pistolet", 1.3)
    tirs("Walther PPQ/X_31P.wav", "tir_pistolet_loin", 1.8, -3.0)
    tirs("Bersa/F_47P.wav", "tir_garde", 1.3)
    tirs("Bersa/F_41P.wav", "tir_garde_loin", 1.8, -3.0)
    print("Rechargement et arme")
    simple("chargeur_sortie", os.path.join(SRC, "clipload2.wav"), -4.0)
    simple("chargeur_entree", os.path.join(SRC, "clipload1.wav"), -3.0)
    simple("culasse", os.path.join(SRC, "singlebullet1.wav"), -3.0)
    for k in range(3):
        ecrire("douille_%d" % (k + 1), douille(k), -14.0, 0.0005, 0.1)
    ecrire("clic_vide", clic_vide(), -8.0, 0.0005, 0.02)
    print("Pas")
    for k in range(4):
        simple("pas_dur_%d" % (k + 1), os.path.join(SRC, "owlish", "Footsteps", "hard-footstep%d.wav" % (k + 1)), -6.0, 0.6)
        simple("pas_doux_%d" % (k + 1), os.path.join(SRC, "owlish", "Footsteps", "step%d.wav" % (k + 1)), -8.0, 0.6)
    print("Corps")
    simple("respiration_calme", os.path.join(SRC, "owlish", "Human", "breath-male.wav"), -10.0)
    simple("respiration_peur", os.path.join(SRC, "owlish", "Human", "scared-breathing.wav"), -8.0)
    simple("respiration_affolee", os.path.join(SRC, "owlish", "Human", "freakedbreath.wav"), -8.0)
    simple("souffle_coupe", os.path.join(SRC, "owlish", "Human", "gasp1.wav"), -4.0, 1.2)
    simple("toux", os.path.join(SRC, "owlish", "Human", "cough1.wav"), -6.0)
    simple("cri", os.path.join(SRC, "owlish", "Human", "SCREAM.wav"), -2.0, 2.5)
    ecrire("coeur", coeur(), -3.0, 0.001, 0.05)
    for k in range(4):
        p = os.path.join(ARENE, "douleur_%d.wav" % (k + 1))
        if os.path.exists(p):
            simple("douleur_%d" % (k + 1), p, -2.0)
    print("Impacts")
    for k in range(3):
        simple("impact_chair_%d" % (k + 1), os.path.join(SRC, "owlish", "Impacts", "fruit%d.wav" % (k + 1)), -3.0, 0.5)
        simple("impact_beton_%d" % (k + 1), os.path.join(SRC, "sfx100", "sfx100v2_hit_0%d.ogg" % (k + 1)), -6.0, 0.6)
    for k in range(2):
        simple("impact_metal_%d" % (k + 1), os.path.join(SRC, "sfx100", "sfx100v2_metal_hit_0%d.ogg" % (k + 1)), -6.0, 0.9)
    simple("chute_corps", os.path.join(SRC, "owlish", "Impacts", "clamour1.wav"), -4.0, 1.0)
    print("Radio")
    ecrire("radio_bip", bip_radio(), -8.0, 0.001, 0.01)
    ecrire("radio_gresil", gresil(0.35), -12.0, 0.005, 0.1)
    print("Ambiance")
    simple("amb_machines", os.path.join(SRC, "sfx100", "sfx100v2_loop_machine_01.ogg"), -10.0, None, -80.0, 0.0)
    simple("amb_grillons", os.path.join(SRC, "owlish", "Ambience", "night-crickets-ambience-on-rural-property.wav"), -12.0, 30.0, -80.0, 0.0)
    simple("amb_hangar", os.path.join(SRC, "sfx100", "sfx100v2_loop_ambient_01.ogg"), -10.0, None, -80.0, 0.0)


main()
sys.exit(0)
