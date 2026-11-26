"""Animations de capture de mouvement de la base CMU (Carnegie Mellon University Graphics Lab Motion
Capture Database, mocap.cs.cmu.edu — « free for use in research and commercial projects worldwide »)
recibles sur le squelette Quaternius (nommage UE) puis, par build_gardes_mpfb.py, sur les gardes MPFB.

Fichiers BVH : conversion de Bruce Hahne (cgspeed.com, « no additional restrictions »), copie
https://github.com/sfd158/cmu-mocap, téléchargés dans _sources/cmu/ (ignoré par git) :
    python tools/blender/retarget_cmu.py --telecharger      (ou automatiquement au premier appel)

Principe :
- lecture du BVH (Y vers le haut, 120 i/s), conversion en repère Blender (Z vers le haut, face à -Y),
  sous-échantillonnage à 24 i/s (même cadence que les animations UAL importées) ;
- pour chaque os Quaternius relié à une articulation CMU : orientation monde = orientation monde CMU
  · K · repos Quaternius, K = plus petite rotation qui amène la direction du segment Quaternius au repos
  sur celle du segment CMU au repos (les deux squelettes sont en « T » ou presque) ;
- doigts (absents de la base CMU) : pris dans une pose UAL (poing serré sur la poignée à droite) ;
- marche sur place : dérive de cap et trajectoire retirées linéairement sur un nombre entier de cycles,
  boucle choisie là où la pose de fin ressemble le plus à celle du début, puis fondu de raccord ;
  bassin recalé chaque image pour que le pied le plus bas touche le sol (pas de pieds dans le sol) ;
- animations « vivantes » au pistolet : pose UAL (visée, arme basse) + couche additive tirée d'une
  attente ou d'une marche CMU (écart à la pose moyenne : bassin, jambes, dos, cou) + respiration.
"""
import math
import os
import sys
import urllib.request

import numpy as np

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
CMU_DIR = os.path.join(ROOT, "_sources", "cmu")
URL = "https://raw.githubusercontent.com/sfd158/cmu-mocap/master/data/%03d/%s.bvh"
FPS_SORTIE = 24          # cadence des actions importées depuis UAL1 (scène Blender par défaut)

# os Quaternius -> (articulation CMU, articulation enfant donnant la direction du segment ; None = K identité)
CORRESP = {
    "pelvis": ("Hips", None), "spine_01": ("LowerBack", "Spine"), "spine_02": ("Spine", "Spine1"),
    "spine_03": ("Spine1", None), "neck_01": ("Neck", "Neck1"), "Head": ("Head", None),
}
for _s, _S in (("l", "Left"), ("r", "Right")):
    CORRESP.update({
        "clavicle_" + _s: (_S + "Shoulder", _S + "Arm"), "upperarm_" + _s: (_S + "Arm", _S + "ForeArm"),
        "lowerarm_" + _s: (_S + "ForeArm", _S + "Hand"), "hand_" + _s: (_S + "Hand", _S + "FingerBase"),
        "thigh_" + _s: (_S + "UpLeg", _S + "Leg"), "calf_" + _s: (_S + "Leg", _S + "Foot"),
        "foot_" + _s: (_S + "Foot", _S + "ToeBase"), "ball_" + _s: (_S + "ToeBase", "@fin"),
    })
# os Quaternius enfant donnant la direction du segment au repos
QDIR = {"spine_01": "spine_02", "spine_02": "spine_03", "neck_01": "Head"}
for _s in "lr":
    QDIR.update({"clavicle_" + _s: "upperarm_" + _s, "upperarm_" + _s: "lowerarm_" + _s,
                 "lowerarm_" + _s: "hand_" + _s, "hand_" + _s: "middle_01_" + _s,
                 "thigh_" + _s: "calf_" + _s, "calf_" + _s: "foot_" + _s, "foot_" + _s: "ball_" + _s,
                 "ball_" + _s: "ball_leaf_" + _s})

# prises CMU : nom de l'animation produite -> réglages
#   prise, début/fin de la zone de recherche (s), durée de boucle min/max (s), fondu (images 24 i/s),
#   type « marche » (déplacement retiré, cap = sens de marche) ou « attente » (cap moyen), sol recalé
PRISES = {
    "Cmu_Attente_Loop": dict(prise="77_02", regard=-6, zone=(1.0, 40.0), boucle=(6.0, 8.0), fondu=14, type="attente"),
    "Cmu_Regard_Loop": dict(prise="77_05", zone=(0.3, 4.2), boucle=(2.6, 3.8), fondu=12, type="attente"),
    "Cmu_Marche_Loop": dict(prise="35_01", regard=-4, zone=(0.5, 3.0), boucle=(0.9, 1.3), fondu=3, type="marche"),
    "Cmu_Marche_Lente_Loop": dict(prise="07_04", regard=-5, zone=(0.4, 3.6), boucle=(1.1, 1.6), fondu=3, type="marche"),
    "Cmu_Course_Loop": dict(prise="35_17", regard=-3, zone=(0.3, 1.2), boucle=(0.55, 0.85), fondu=2, type="marche", sol=False),
}
TOUTES_PRISES = sorted({p["prise"] for p in PRISES.values()})

# doigts et os sans équivalent CMU : pris dans une pose UAL
DOIGTS = ("thumb", "index", "middle", "ring", "pinky")


def log(*a):
    print("[cmu]", *a, flush=True)


def telecharger(prises=TOUTES_PRISES):
    os.makedirs(CMU_DIR, exist_ok=True)
    for p in prises:
        out = os.path.join(CMU_DIR, p + ".bvh")
        if os.path.exists(out) and os.path.getsize(out) > 1000:
            continue
        url = URL % (int(p.split("_")[0]), p)
        log("téléchargement", url)
        with urllib.request.urlopen(url, timeout=60) as r, open(out, "wb") as f:
            f.write(r.read())


# ---------------------------------------------------------------- lecture BVH

class Bvh:
    def __init__(self, path):
        self.noms, self.parent, self.offset, self.canaux, self.fin = [], [], [], [], {}
        toks = open(path, encoding="utf-8", errors="replace").read().split()
        i, pile = 0, []
        while toks[i] != "MOTION":
            t = toks[i]
            if t in ("ROOT", "JOINT"):
                self.noms.append(toks[i + 1])
                self.parent.append(pile[-1] if pile else -1)
                self.canaux.append([])
                self.offset.append(None)
                cur = len(self.noms) - 1
                i += 2
            elif t == "End":
                cur = ("fin", pile[-1])
                i += 2
            elif t == "{":
                pile.append(cur)
                i += 1
            elif t == "}":
                pile.pop()
                i += 1
            elif t == "OFFSET":
                v = [float(x) for x in toks[i + 1:i + 4]]
                if isinstance(pile[-1], tuple):
                    self.fin[pile[-1][1]] = np.array(v)
                else:
                    self.offset[pile[-1]] = np.array(v)
                i += 4
            elif t == "CHANNELS":
                n = int(toks[i + 1])
                self.canaux[pile[-1]] = toks[i + 2:i + 2 + n]
                i += 2 + n
            else:
                i += 1
        n_img = int(toks[i + 2])
        self.dt = float(toks[i + 5])
        data = np.array(toks[i + 6:], dtype=np.float64)
        self.data = data.reshape(n_img, -1)
        self.index = {n: k for k, n in enumerate(self.noms)}

    def globales(self, pas):
        """Rotations (N, J, 3, 3) et positions (N, J, 3) monde, repère BVH, une image sur « pas »."""
        d = self.data[::pas]
        N, J = len(d), len(self.noms)
        R = np.zeros((N, J, 3, 3))
        P = np.zeros((N, J, 3))
        col = 0
        for j in range(J):
            loc = np.tile(np.eye(3), (N, 1, 1))
            pos = np.tile(self.offset[j], (N, 1))
            for c in self.canaux[j]:
                v = d[:, col]
                col += 1
                if c.endswith("position"):
                    pos[:, "XYZ".index(c[0])] = v
                else:
                    a = np.radians(v)
                    ca, sa = np.cos(a), np.sin(a)
                    m = np.tile(np.eye(3), (N, 1, 1))
                    ax = "XYZ".index(c[0])
                    i1, i2 = [k for k in range(3) if k != ax]
                    m[:, i1, i1] = ca
                    m[:, i2, i2] = ca
                    if ax == 1:     # rotation Y : signe inversé dans le plan (Z, X)
                        m[:, i1, i2] = sa
                        m[:, i2, i1] = -sa
                    else:
                        m[:, i1, i2] = -sa
                        m[:, i2, i1] = sa
                    loc = loc @ m
            p = self.parent[j]
            if p < 0:
                R[:, j] = loc
                P[:, j] = pos
            else:
                R[:, j] = R[:, p] @ loc
                P[:, j] = P[:, p] + np.einsum("nij,j->ni", R[:, p], self.offset[j])
        return R, P


# BVH (x, y, z) -> Blender (x, -z, y)
M_AXES = np.array([[1.0, 0, 0], [0, 0, -1.0], [0, 1.0, 0]])


def _rz(a):
    c, s = np.cos(a), np.sin(a)
    m = np.zeros(np.shape(a) + (3, 3))
    m[..., 0, 0] = c
    m[..., 0, 1] = -s
    m[..., 1, 0] = s
    m[..., 1, 1] = c
    m[..., 2, 2] = 1
    return m


def _quat(m):
    from mathutils import Matrix
    return Matrix(m.tolist()).to_quaternion()


def charger_prise(nom, reglage, q_info):
    """Lit une prise, la met sur place, choisit la boucle ; renvoie (rotations monde CMU en repère Blender
    (L+1, J, 3, 3), positions du bassin (L+1, 3) déjà à l'échelle Quaternius, objet Bvh)."""
    b = Bvh(os.path.join(CMU_DIR, reglage["prise"] + ".bvh"))
    pas = max(1, int(round(1.0 / (b.dt * FPS_SORTIE))))
    R, P = b.globales(pas)
    R = np.einsum("ab,njbc,dc->njad", M_AXES, R, M_AXES)
    P = np.einsum("ab,nkb->nka", M_AXES, P)
    J = b.index
    # échelle : longueur cuisse + jambe
    lc = np.linalg.norm(b.offset[J["LeftLeg"]]) + np.linalg.norm(b.offset[J["LeftFoot"]])
    ech = q_info["jambe"] / lc
    N = len(R)
    fps = FPS_SORTIE
    a0 = int(reglage["zone"][0] * fps)
    a1 = min(N - 1, int(reglage["zone"][1] * fps))
    lmin, lmax = int(reglage["boucle"][0] * fps), int(reglage["boucle"][1] * fps)
    k = reglage["fondu"]
    # rotations locales (invariantes au cap) pour comparer les poses
    loc = np.einsum("njik,njkl->njil", np.transpose(R[:, b.parent], (0, 1, 3, 2)), R)
    loc[:, 0] = np.eye(3)
    hips = P[:, J["Hips"]]
    # cap des hanches
    lh = P[:, J["LeftUpLeg"]] - P[:, J["RightUpLeg"]]
    cap = np.unwrap(np.arctan2(lh[:, 1], lh[:, 0]))     # 0 quand la gauche est +X (face à -Y)
    best = None
    for s in range(max(a0, k + 1), a1 - lmin):
        for L in range(lmin, min(lmax, a1 - s) + 1):
            d = np.sum((loc[s] - loc[s + L]) ** 2)
            d += 4.0 * np.sum((loc[s + 1] - loc[s] - loc[s + L + 1] + loc[s + L]) ** 2) if s + L + 1 < N else 9
            d += 0.02 * (hips[s, 2] - hips[s + L, 2]) ** 2
            d += 3.0 * (cap[s + L] - cap[s]) ** 2 + 0.5 * float(np.ptp(cap[s:s + L + 1]) ** 2)
            if reglage["type"] != "marche":    # attente : pas de pas de côté pendant la boucle
                seg = hips[s:s + L + 1]
                d += 40.0 * (np.ptp(seg[:, 0]) ** 2 + np.ptp(seg[:, 1]) ** 2) / lc ** 2
            if best is None or d < best[0]:
                best = (d, s, L)
    _, s, L = best
    log(nom, reglage["prise"], "boucle images %d-%d (%.2f s), écart %.3f" % (s, s + L, L / fps, best[0]))
    t = np.arange(N, dtype=np.float64)
    derive = (cap[s + L] - cap[s]) * (t - s) / L
    if reglage["type"] == "marche":
        dep = hips[s + L] - hips[s]
        phi = math.atan2(dep[1], dep[0])
        base = -math.pi / 2 - phi            # sens de marche -> -Y
        vitesse = math.hypot(dep[0], dep[1]) * ech / (L / fps)
    else:
        base = -float(np.mean(cap[s:s + L] - derive[s:s + L]))
        vitesse = 0.0
    beta = base - derive
    Rz = _rz(beta)
    R = np.einsum("nab,nkbc->nkac", Rz, R)
    hp = np.einsum("nab,nb->na", Rz, hips)
    # trajectoire retirée (linéaire sur la boucle), échelle Quaternius
    tr = hp[s] + np.outer((t - s) / L, hp[s + L] - hp[s])
    pel = np.zeros((N, 3))
    pel[:, :2] = (hp[:, :2] - tr[:, :2])
    pel[:, :2] -= pel[s:s + L, :2].mean(axis=0)
    pel[:, 2] = hp[:, 2]
    pel *= ech
    # boucle : images s .. s+L (la dernière = la première), fondu des k dernières vers s-k..s-1
    out_R = R[s:s + L + 1].copy()
    out_P = pel[s:s + L + 1].copy()
    for i in range(L - k, L):
        w = (i - (L - k) + 1) / (k + 1)
        w = w * w * (3 - 2 * w)
        for j in range(R.shape[1]):
            qa = _quat(out_R[i, j])
            qb = _quat(R[s + i - L, j])
            qb.make_compatible(qa)
            out_R[i, j] = np.array(qa.slerp(qb, w).to_matrix())
        out_P[i] = out_P[i] * (1 - w) + pel[s + i - L] * w
    out_R[L] = out_R[0]
    out_P[L] = out_P[0]
    log(nom, "vitesse de marche %.2f m/s (gabarit Quaternius)" % vitesse)
    return out_R, out_P, b


# ---------------------------------------------------------------- construction des actions

def _rot(m):
    from mathutils import Matrix
    return Matrix(m.tolist())


def creer_actions(q, acts_ual, set_action):
    """Crée sur l'armature Quaternius « q » les actions CMU (et composites) ; renvoie {nom: action}."""
    import bpy
    from mathutils import Matrix, Vector, Quaternion
    telecharger()
    sc = bpy.context.scene
    mw = q.matrix_world
    rN = {b.name: mw @ b.matrix_local for b in q.data.bones}
    rN_inv = {k: v.inverted() for k, v in rN.items()}
    R0 = {k: v.to_3x3().normalized() for k, v in rN.items()}
    ordre = []
    pile = [b for b in q.data.bones if b.parent is None]
    while pile:
        bb = pile.pop(0)
        ordre.append(bb.name)
        pile.extend(bb.children)
    parent = {b.name: (b.parent.name if b.parent else None) for b in q.data.bones}
    tete = {b.name: (mw @ b.head_local) for b in q.data.bones}
    q_info = {"jambe": (tete["calf_l"] - tete["thigh_l"]).length + (tete["foot_l"] - tete["calf_l"]).length}

    def echantillon(act, f):
        """Rotations monde et position du bassin d'une pose UAL."""
        set_action(q, act)
        sc.frame_set(int(f))
        W = {}
        for b in ordre:
            W[b] = (mw @ q.pose.bones[b].matrix).to_3x3().normalized()
        return W, (mw @ q.pose.bones["pelvis"].matrix).translation.copy()

    def locales(W):
        return {b: (W[parent[b]].transposed() @ W[b]) if parent[b] else W[b].copy() for b in ordre}

    def monde(Lr):
        W = {}
        for b in ordre:
            W[b] = (W[parent[b]] @ Lr[b]) if parent[b] else Lr[b].copy()
        return W

    ref_arme, _ = echantillon(acts_ual["Pistol_Idle_Loop"], 0)
    ref_repos, _ = echantillon(acts_ual["Idle_Loop"], 0)
    L_arme, L_repos = locales(ref_arme), locales(ref_repos)

    def doigts_ref(b):
        """Main droite : poing fermé sur la poignée ; main gauche : main relâchée."""
        return L_arme[b] if b.endswith("_r") else L_repos[b]

    def poses_cmu(nom, reg):
        """Liste de dicts {os: rotation monde} + positions du bassin, pour une prise CMU."""
        Rc, Pc, b = charger_prise(nom, reg, q_info)
        Jx = b.index
        K = {}
        for qb, (c, enf) in CORRESP.items():
            if enf is None or qb not in QDIR:
                K[qb] = Matrix.Identity(3)
                continue
            dC = b.fin[Jx[c]] if enf == "@fin" else b.offset[Jx[enf]]
            dC = M_AXES @ dC
            dQ = tete[QDIR[qb]] - tete[qb]
            if np.linalg.norm(dC) < 1e-6:
                K[qb] = Matrix.Identity(3)
            else:
                K[qb] = dQ.normalized().rotation_difference(Vector(dC.tolist()).normalized()).to_matrix()
        poses = []
        for i in range(len(Rc)):
            W = {}
            for bn in ordre:
                if bn in CORRESP:
                    W[bn] = _rot(Rc[i, Jx[CORRESP[bn][0]]]) @ K[bn] @ R0[bn]
                elif parent[bn] is None:
                    W[bn] = R0[bn].copy()
                else:
                    W[bn] = W[parent[bn]] @ doigts_ref(bn)
            pos = Vector((rN["pelvis"].translation.x + Pc[i, 0], rN["pelvis"].translation.y + Pc[i, 1], Pc[i, 2]))
            poses.append((W, pos))
        # regard : tête et cou redressés pour que le regard moyen soit presque horizontal (les sujets
        # CMU regardent souvent le sol) ; la moitié de la correction sur le cou, le reste sur la tête
        cible = reg.get("regard")
        if cible is not None:
            av = Vector((0.0, -1.0, 0.0))
            def pente(W):
                f = W["Head"] @ R0["Head"].transposed() @ av
                return math.asin(max(-1.0, min(1.0, f.z)))
            moy_p = sum(pente(W) for W, _ in poses[:-1]) / (len(poses) - 1)
            delta = math.radians(cible) - moy_p
            log(nom, "regard moyen %.0f° corrigé de %+.0f°" % (math.degrees(moy_p), math.degrees(delta)))
            for W, _ in poses:
                f = W["Head"] @ R0["Head"].transposed() @ av
                axe = f.cross(Vector((0.0, 0.0, 1.0)))
                if axe.length < 1e-6:
                    continue
                axe.normalize()
                for bn, part in (("neck_01", 0.5), ("Head", 1.0)):
                    rm = Matrix.Rotation(delta * part, 3, axe)
                    W[bn] = rm @ W[bn]
                for bn in ordre:                       # doigts / os non reliés sous la tête : suivent
                    if bn not in CORRESP and parent[bn] in ("Head", "neck_01"):
                        W[bn] = W[parent[bn]] @ doigts_ref(bn)
        return poses

    def positions(W, pel):
        """Cinématique directe : position de chaque os (monde)."""
        W4 = {}
        for bn in ordre:
            p = parent[bn]
            if p is None:
                pos = rN[bn].translation.copy()
            elif bn == "pelvis":
                pos = pel
            else:
                pos = (W4[p] @ rN_inv[p] @ rN[bn]).translation
            W4[bn] = Matrix.Translation(pos) @ W[bn].to_4x4()
        return W4

    def recaler_sol(poses, lisse=True):
        """Bassin remonté/abaissé pour que le point le plus bas des pieds touche le sol."""
        z0 = {"foot": tete["foot_l"].z, "ball": tete["ball_l"].z, "ball_leaf": tete["ball_leaf_l"].z}
        m = []
        for W, pel in poses:
            W4 = positions(W, pel)
            m.append(min(W4[k + "_" + s].translation.z - z0[k] for k in z0 for s in "lr"))
        m = np.array(m)
        if lisse:
            m2 = m.copy()
            n = len(m) - 1        # la dernière image = la première
            for i in range(n):
                m2[i] = (m[(i - 1) % n] + 2 * m[i] + m[(i + 1) % n]) / 4
            m2[n] = m2[0]
            m = m2
        else:
            m[:] = np.median(m)
        return [(W, pel - Vector((0, 0, float(mi)))) for (W, pel), mi in zip(poses, m)]

    def vers_action(nom, poses):
        if q.animation_data is None:
            q.animation_data_create()
        act = bpy.data.actions.new(nom)
        q.animation_data.action = act
        prev = {}
        for f, (W, pel) in enumerate(poses):
            W4 = positions(W, pel)
            for bn in ordre:
                p = parent[bn]
                basis = (rN_inv[bn] @ W4[bn]) if p is None else (rN_inv[bn] @ rN[p]) @ W4[p].inverted() @ W4[bn]
                loc, qr, _ = basis.decompose()
                if bn in prev:
                    qr.make_compatible(prev[bn])
                prev[bn] = qr
                pb = q.pose.bones[bn]
                pb.rotation_mode = "QUATERNION"
                pb.rotation_quaternion = qr
                pb.location = loc
                pb.keyframe_insert("rotation_quaternion", frame=f, group=bn)
                pb.keyframe_insert("location", frame=f, group=bn)
        q.animation_data.action = None
        log("action", nom, len(poses), "images (%.2f s)" % ((len(poses) - 1) / FPS_SORTIE))
        return act

    def additive(base_act, base_frames, prise, gains, respiration=0.0, bras=0.0):
        """Pose UAL + écarts d'une prise CMU à sa pose moyenne (couche additive) + respiration."""
        n = len(prise) - 1
        # pose moyenne de la prise (locales)
        Ls = [locales(W) for W, _ in prise]
        moy = {}
        for bn in ordre:
            qs = [L[bn].to_quaternion() for L in Ls[:n]]
            a = qs[0]
            acc = np.zeros(4)
            for qq in qs:
                if qq.dot(a) < 0:
                    qq = -qq
                acc += np.array(qq[:])
            moy[bn] = Quaternion(acc / np.linalg.norm(acc)).to_matrix()
        pel_moy = sum((p for _, p in prise[:n]), Vector()) / n
        out = []
        f0, f1 = base_frames
        for i in range(n + 1):
            fb = f0 + (f1 - f0) * (i % n) / n if f1 > f0 else f0
            Wu, pel_u = echantillon(base_act, round(fb))
            Lu = locales(Wu)
            Lc = Ls[i % n]
            L = {}
            for bn in ordre:
                g = gains.get(bn, gains.get("*", 0.0))
                if g == 0.0 or any(bn.startswith(d) for d in DOIGTS):
                    L[bn] = Lu[bn]
                    continue
                dq = (moy[bn].transposed() @ Lc[bn]).to_quaternion()     # écart local à la moyenne
                if g != 1.0:
                    dq = Quaternion().slerp(dq, g)
                L[bn] = Lu[bn] @ dq.to_matrix()
            W = monde(L)
            # respiration (nombre entier de souffles par boucle, ~3,6 s chacun) : poitrine qui se
            # soulève, épaules qui montent un peu ; rotations exprimées dans le monde (X = axe latéral)
            if respiration:
                nb = max(1, round(n / FPS_SORTIE / 3.6))
                a = math.radians(respiration * math.sin(2 * math.pi * nb * (i % n) / n))
                rots = {"spine_02": Matrix.Rotation(0.5 * a, 3, "X"), "spine_03": Matrix.Rotation(0.6 * a, 3, "X"),
                        "clavicle_l": Matrix.Rotation(-0.9 * a, 3, "Y"), "clavicle_r": Matrix.Rotation(0.9 * a, 3, "Y")}
                for bn, rw in rots.items():
                    L[bn] = L[bn] @ (W[bn].transposed() @ rw @ W[bn])
                W = monde(L)
            pel = pel_u + (prise[i % n][1] - pel_moy) * gains.get("pelvis_pos", 1.0)
            out.append((W, pel))
        return out

    res = {}
    cmu = {}
    for nom, reg in PRISES.items():
        poses = poses_cmu(nom, reg)
        if reg.get("sol", True):
            poses = recaler_sol(poses)
        else:
            poses = recaler_sol(poses, lisse=False)
        cmu[nom] = poses
        res[nom] = vers_action(nom, poses)
    # composites au pistolet
    jambes = {"pelvis": 1.0, "pelvis_pos": 1.0, "*": 0.0}
    for s in "lr":
        jambes.update({"thigh_" + s: 1.0, "calf_" + s: 1.0, "foot_" + s: 1.0, "ball_" + s: 1.0})
    dos = dict(jambes, spine_01=0.8, spine_02=0.6, spine_03=0.5, neck_01=0.5, Head=0.4)
    vis = dict(jambes, spine_01=0.6, spine_02=0.35, spine_03=0.25, neck_01=0.3, Head=0.25)
    att = cmu["Cmu_Attente_Loop"]
    aim = acts_ual["Pistol_Aim_Neutral"]
    idle = acts_ual["Pistol_Idle_Loop"]
    poses = recaler_sol(additive(aim, (0, 0), att, vis, respiration=1.4))
    res["Visee_Vivante_Loop"] = vers_action("Visee_Vivante_Loop", poses)
    poses = recaler_sol(additive(idle, (0, 0), att, dos, respiration=1.8))
    res["Pistolet_Attente_Vivante_Loop"] = vers_action("Pistolet_Attente_Vivante_Loop", poses)
    # marche prudente : arme tenue à deux mains, basse (pose UAL) sur une marche lente CMU ;
    # marche en visée : même marche sous la pose de visée (dos et cou moins mobiles)
    lente = cmu["Cmu_Marche_Lente_Loop"]
    prud = dict(jambes, spine_01=0.7, spine_02=0.5, spine_03=0.4, neck_01=0.4, Head=0.4)
    poses = recaler_sol(additive(idle, (0, 0), lente, prud, respiration=0.0))
    res["Cmu_Marche_Prudente_Loop"] = vers_action("Cmu_Marche_Prudente_Loop", poses)
    marche = dict(jambes, spine_01=0.5, spine_02=0.3, spine_03=0.2, neck_01=0.2, Head=0.2)
    poses = recaler_sol(additive(aim, (0, 0), lente, marche, respiration=0.0))
    res["Visee_Marche_Loop"] = vers_action("Visee_Marche_Loop", poses)
    return res


if __name__ == "__main__" and "--telecharger" in sys.argv:
    telecharger()
