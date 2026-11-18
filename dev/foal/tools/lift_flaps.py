#!/usr/bin/env python3
"""Puts the saddle (seat, tree and flaps) ON TOP of the panels (layers 2 and 3 of the bottom-up saddle): the flap sheet of the game's saddle hangs close to the pad, so the 3 to 4 cm thick panel under it pokes through. Every saddle vertex in the flap region
is moved outward (radially, round the barrel's axis x = 0, y = 1.38; z stays) by what is needed to clear the panel's top surface under it by CLEAR, the lift spread smoothly over the neighbouring vertices (the flap drapes over the panel's edge, no step).
  python3 lift_flaps.py models/horse/horseAdult      (after add_panel.py and shift_saddle.py, before reskin_stirrup.py: split_tack, add_halter, rebuild_blanket, add_panel, shift_saddle, lift_flaps, reskin_stirrup)
Safe to run again: dev/foal/blanket_old/<model>_flaps.json holds the hash of the shapes file this script wrote; another hash is a fresh file (redo the chain)."""
import sys, os, json, hashlib
import numpy as np
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here); sys.path.insert(0, os.path.join(here, "..", "..", "..", "tools"))
import shift_saddle as SS

AXIS_Y = 1.38
CLEAR = 0.0045                     # the flap lies this far above the panel's top
REGION = dict(phi=(0.0, 2.8), z=(0.0, 0.46), r=(0.25, 0.5), y_min=1.2)       # the saddle vertices that are flap (and the straps under it)
NEAR = 0.015                       # a panel top vertex counts under a flap vertex within this distance in (angle * 0.32 m, z)
DILATE = 0.02                      # the lift is first spread this far (the flap reaches over the panel's edge) ...
SIGMA = 0.015                      # ... then smoothed

SUBDIV = 2                         # the flap sheet's triangles are split 1 to 4 this many times first: its triangles are big, a lift that exists only at their corners lets the panel poke through between them

def subdivide(A, sel, passes):
    """Midpoint subdivision (1 to 4) of the triangles `sel` of the mesh A (arrays of shift_saddle.arrays), `passes` times. New vertices: position, normal, tangent, uv and skin weights averaged from the edge's ends.
    Returns A with the new vertices and triangles, and for every new vertex on the border of the split region (an edge shared with a triangle that is not split) its two end vertices (the lift of such a vertex is the mean of theirs: no crack)."""
    P, N, Tg, U, W, I = [list(x) for x in (A["P"], A["N"], A["Tg"], A["U"], A["W"], A["I"])]
    T = [list(t) for t in A["T"]]
    key = {}; weld = []
    for pt in A["P"]: weld.append(key.setdefault(tuple(np.round(pt, 4)), len(key)))
    border = {}
    for _ in range(passes):
        chosen = set(sel)
        owners = {}
        for ti, t in enumerate(T):
            for a, b in ((t[0], t[1]), (t[1], t[2]), (t[2], t[0])):
                owners.setdefault(tuple(sorted((weld[a], weld[b]))), []).append(ti)
        mid = {}
        def midpoint(a, b, ti):
            k = (min(a, b), max(a, b))
            if k in mid: return mid[k]
            n = len(P); mid[k] = n
            P.append((np.array(P[a]) + np.array(P[b])) / 2)
            nn = np.array(N[a]) + np.array(N[b]); N.append(nn / max(np.linalg.norm(nn), 1e-12))
            Tg.append((np.array(Tg[a]) + np.array(Tg[b])) / 2); Tg[-1][3] = Tg[a][3]
            U.append((np.array(U[a]) + np.array(U[b])) / 2)
            d = {}
            for src in (a, b):
                for wv, iv in zip(W[src], I[src]):
                    if wv > 0: d[int(iv)] = d.get(int(iv), 0.0) + float(wv) * 0.5
            top4 = sorted(d.items(), key=lambda x: -x[1])[:4]; tot = sum(v for _, v in top4); top4 += [(0, 0.0)] * (4 - len(top4))
            W.append(np.array([v / tot for _, v in top4])); I.append(np.array([i for i, _ in top4]))
            weld.append(key.setdefault(tuple(np.round(P[-1], 4)), len(key)))
            others = [o for o in owners[tuple(sorted((weld[a], weld[b])))] if o != ti]
            if others and any(o not in chosen for o in others): border[n] = (a, b)        # (a free edge, no neighbour at all, is not a border: it can be lifted on its own)
            return n
        newT = []; nsel = set()
        for ti, t in enumerate(T):
            if ti not in chosen: newT.append(t); continue
            a, b, c = t; ab, bc, ca = midpoint(a, b, ti), midpoint(b, c, ti), midpoint(c, a, ti)
            for q in ([a, ab, ca], [ab, b, bc], [ca, bc, c], [ab, bc, ca]):
                nsel.add(len(newT)); newT.append(q)
        T = newT; sel = sorted(nsel)
    out = dict(P=np.array(P), N=np.array(N), Tg=np.array(Tg), U=np.array(U), W=np.array(W), I=np.array(I), T=np.array(T))
    return out, border

def polar(X):
    rel = np.stack([X[:, 0], X[:, 1] - AXIS_Y], 1)
    return np.arctan2(np.abs(rel[:, 0]), rel[:, 1]), np.linalg.norm(rel, axis=1)

def main(base):
    shapes_path = base + ".i3d.shapes"
    state_path = os.path.join(here, "..", "blanket_old", os.path.basename(base) + "_flaps.json")
    digest = hashlib.sha1(open(shapes_path, "rb").read()).hexdigest()
    if os.path.exists(state_path) and json.load(open(state_path)).get("hash") == digest:
        print("flaps already lifted by this script:", base); return
    raw, sf = SS.S.read(shapes_path)
    ks, seat = SS.load(sf, "saddleShape"); A = SS.arrays(seat)
    _, panel = SS.load(sf, "panelShape"); PA = SS.arrays(panel)
    P0 = A["P"]; phi0, r0 = polar(P0)
    reg0 = (phi0 > REGION["phi"][0]) & (phi0 < REGION["phi"][1]) & (P0[:, 2] > REGION["z"][0]) & (P0[:, 2] < REGION["z"][1]) & (r0 > REGION["r"][0]) & (r0 < REGION["r"][1]) & (P0[:, 1] > REGION["y_min"])
    sel = [ti for ti, t in enumerate(A["T"]) if reg0[t].all() and (np.cross(P0[t[1]] - P0[t[0]], P0[t[2]] - P0[t[0]]) @ np.array([P0[t[0]][0], P0[t[0]][1] - AXIS_Y, 0.0])) > 0 and phi0[t].min() > 0.5]
    A, border = subdivide(A, sel, SUBDIV)
    print("flap triangles split %d time(s): %d selected -> mesh now %d vertices, %d triangles" % (SUBDIV, len(sel), len(A["P"]), len(A["T"])))
    P, Q, QN = A["P"], PA["P"], PA["N"]
    qphi, qr = polar(Q)
    top = ((QN[:, 0] * Q[:, 0] + QN[:, 1] * (Q[:, 1] - AXIS_Y)) > 0)             # the panel's outer surface
    phi, r = polar(P)
    reg = (phi > REGION["phi"][0]) & (phi < REGION["phi"][1]) & (P[:, 2] > REGION["z"][0]) & (P[:, 2] < REGION["z"][1]) & (r > REGION["r"][0]) & (r < REGION["r"][1]) & (P[:, 1] > REGION["y_min"])
    idx = np.where(reg)[0]
    raw_lift = np.zeros(len(P))
    for i in idx:
        side = P[i, 0] >= 0
        d = ((qphi - phi[i]) * 0.32) ** 2 + (Q[:, 2] - P[i, 2]) ** 2
        d[(Q[:, 0] >= 0) != side] = 1e9
        near = d < NEAR ** 2                                                    # every panel vertex around it, the pillow's rim and edge too, not only the top: the highest decides
        if near.any():
            raw_lift[i] = max(0.0, float(qr[near].max()) + CLEAR - r[i])
    # spread: the envelope (max over the vertices within DILATE), then a Gaussian average
    pos = np.stack([phi[idx] * 0.32, P[idx, 2], (P[idx, 0] >= 0) * 10.0], 1)
    env = np.zeros(len(idx)); lift = np.zeros(len(idx)); rl = raw_lift[idx]
    for a in range(len(idx)):
        d2 = ((pos - pos[a]) ** 2).sum(1)
        env[a] = rl[d2 < DILATE ** 2].max()
    for a in range(len(idx)):
        d2 = ((pos - pos[a]) ** 2).sum(1)
        w = np.exp(-d2 / (2 * SIGMA ** 2))
        lift[a] = (env * w).sum() / w.sum()
    lift = np.maximum(lift, rl)                                    # never less than the vertex itself needs: the smoothing only adds
    where = {int(i): a for a, i in enumerate(idx)}
    for v, (a, b) in border.items():                                  # a vertex on the border of the split region: the mean of its edge's ends (the chord stays closed)
        if v in where and a in where and b in where: lift[where[v]] = (lift[where[a]] + lift[where[b]]) / 2
    Pn = P.copy()
    for a, i in enumerate(idx):
        rel = np.array([P[i, 0], P[i, 1] - AXIS_Y]); n = np.linalg.norm(rel)
        Pn[i, 0] += rel[0] / n * lift[a]; Pn[i, 1] += rel[1] / n * lift[a]
    A["P"] = Pn
    SS.write(sf, ks, seat, A); SS.S.write(shapes_path, sf)
    digest = hashlib.sha1(open(shapes_path, "rb").read()).hexdigest()
    os.makedirs(os.path.dirname(state_path), exist_ok=True)
    json.dump({"hash": digest}, open(state_path, "w"))
    print("flaps lifted: %d region vertices, %d moved, largest lift %.1f mm, mean of the moved %.1f mm" % (len(idx), int((lift > 0.0005).sum()), 1000 * lift.max(), 1000 * lift[lift > 0.0005].mean() if (lift > 0.0005).any() else 0))

if __name__ == "__main__":
    main(sys.argv[1])
