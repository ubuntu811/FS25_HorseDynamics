#!/usr/bin/env python3
"""Gives the saddle's flaps their leather thickness (layer 3 of the bottom-up saddle): the game's flap is ONE sheet. Here every free edge (the bottom, the front and the rear edge of the flap) gets an edge band THICK deep (towards the horse):
what you see from the front is a 3.5 mm welted edge, not a paper sheet. The new vertices copy the skin weights and uv of the vertices they come from.
  python3 thicken_flaps.py models/horse/horseAdult      (after lift_flaps.py: split_tack, add_halter, rebuild_blanket, add_panel, shift_saddle, lift_flaps, thicken_flaps, reskin_stirrup)
Safe to run again: dev/foal/blanket_old/<model>_thick.json holds the hash of the shapes file this script wrote."""
import sys, os, json, hashlib
import numpy as np
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here); sys.path.insert(0, os.path.join(here, "..", "..", "..", "tools"))
import shift_saddle as SS
import lift_flaps as LF

THICK = 0.0035                     # leather thickness, metres
AXIS_Y = 1.38
REGION = dict(phi=(0.55, 2.0), z=(0.0, 0.46), r=(0.25, 0.5), y_min=1.2)

def main(base):
    shapes_path = base + ".i3d.shapes"
    state_path = os.path.join(here, "..", "blanket_old", os.path.basename(base) + "_thick.json")
    digest = hashlib.sha1(open(shapes_path, "rb").read()).hexdigest()
    if os.path.exists(state_path) and json.load(open(state_path)).get("hash") == digest:
        print("flaps already thickened by this script:", base); return
    raw, sf = SS.S.read(shapes_path)
    ks, seat = SS.load(sf, "saddleShape"); A = SS.arrays(seat)
    P, N, Tg, U, W, I, T = A["P"], A["N"], A["Tg"], A["U"], A["W"], A["I"], A["T"]
    phi, r = LF.polar(P)
    reg = (phi > REGION["phi"][0]) & (phi < REGION["phi"][1]) & (P[:, 2] > REGION["z"][0]) & (P[:, 2] < REGION["z"][1]) & (r > REGION["r"][0]) & (r < REGION["r"][1]) & (P[:, 1] > REGION["y_min"])
    inreg = reg[T].all(1)
    # the flap's own triangles: the outward-facing ones (the region also catches bits of the girth strap behind it)
    tri = np.where(inreg)[0]
    keep = []
    for t in tri:
        a, b, c = P[T[t]]; g = np.cross(b - a, c - a); cen = (a + b + c) / 3
        rad = np.array([cen[0], cen[1] - AXIS_Y, 0.0]); rad /= np.linalg.norm(rad)
        if g @ rad > 0 and np.linalg.norm(g) > 1e-9: keep.append(t)
    tri = np.array(keep)
    print("flap triangles taken:", len(tri))
    # welded ids (the mesh has split vertices on uv seams) and free edges of the whole mesh
    key = {}; weld = np.zeros(len(P), int)
    for i, p in enumerate(P): weld[i] = key.setdefault(tuple(np.round(p, 4)), len(key))
    count = {}
    for t in T:
        for a, b in ((t[0], t[1]), (t[1], t[2]), (t[2], t[0])):
            k = tuple(sorted((weld[a], weld[b]))); count[k] = count.get(k, 0) + 1
    # the edge band along every free edge (the bottom, the front and the rear edge of the flap): a strip THICK deep between the outer edge and the same edge moved towards the axis. The inner surface itself is not built: nobody sees it.
    def inner(v):
        rad = np.array([P[v, 0], P[v, 1] - AXIS_Y]); rad /= np.linalg.norm(rad)
        return P[v] - np.array([rad[0], rad[1], 0.0]) * THICK
    # an edge that only looks free: the flap was split but its neighbour (the seat, the girth) was not, so half edges meet the neighbour's whole edge. Such an edge lies on an edge of a triangle that is not part of the flap.
    others = np.setdiff1d(np.arange(len(T)), tri)
    seg_a = np.vstack([P[T[others][:, 0]], P[T[others][:, 1]], P[T[others][:, 2]]]); seg_b = np.vstack([P[T[others][:, 1]], P[T[others][:, 2]], P[T[others][:, 0]]])
    seg_d = seg_b - seg_a; seg_l2 = np.maximum((seg_d ** 2).sum(1), 1e-18)
    def on_neighbour_edge(m):
        tt = np.clip(((m - seg_a) * seg_d).sum(1) / seg_l2, 0.0, 1.0)
        return bool(((seg_a + seg_d * tt[:, None] - m) ** 2).sum(1).min() < 0.0004 ** 2)
    nP, nN, nTg, nU, nW, nI, newT = [], [], [], [], [], [], []
    bands = 0; base_n = len(P)
    for t in tri:
        for a, b in ((T[t][0], T[t][1]), (T[t][1], T[t][2]), (T[t][2], T[t][0])):
            if count[tuple(sorted((weld[a], weld[b])))] != 1: continue
            if on_neighbour_edge((P[a] + P[b]) / 2): continue
            outward = np.cross(P[b] - P[a], N[a] + N[b])                  # away from the flap's inside, in the surface
            quad = [P[a], P[b], inner(b), inner(a)]; src = [a, b, b, a]
            g = np.cross(quad[1] - quad[0], quad[3] - quad[0])
            if np.linalg.norm(g) < 1e-12: continue
            order = [0, 1, 2, 3]
            if g @ outward < 0: order = [1, 0, 3, 2]                      # wind the face so that it looks away from the flap's inside
            g = np.cross(quad[order[1]] - quad[order[0]], quad[order[3]] - quad[order[0]]); g /= np.linalg.norm(g)
            base_i = base_n + len(nP)
            for o in order:
                nP.append(quad[o]); nN.append(g); nTg.append(Tg[src[o]]); nU.append(U[src[o]]); nW.append(W[src[o]]); nI.append(I[src[o]])
            newT += [[base_i, base_i + 1, base_i + 2], [base_i, base_i + 2, base_i + 3]]
            bands += 1
    A["P"] = np.vstack([P, np.array(nP)]); A["N"] = np.vstack([N, np.array(nN)]); A["Tg"] = np.vstack([Tg, np.array(nTg)]); A["U"] = np.vstack([U, np.array(nU)])
    A["W"] = np.vstack([W, np.array(nW)]); A["I"] = np.vstack([I, np.array(nI)]); A["T"] = np.vstack([T, np.array(newT)])
    SS.write(sf, ks, seat, A); SS.S.write(shapes_path, sf)
    digest = hashlib.sha1(open(shapes_path, "rb").read()).hexdigest()
    os.makedirs(os.path.dirname(state_path), exist_ok=True)
    json.dump({"hash": digest}, open(state_path, "w"))
    print("flap edges thickened: %d edge band quads, thickness %.1f mm" % (bands, 1000 * THICK))

if __name__ == "__main__":
    main(sys.argv[1])
