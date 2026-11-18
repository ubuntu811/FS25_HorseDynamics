#!/usr/bin/env python3
"""Fills the opening of the saddle blanket: the game's pad is only a frame (the middle of its UV rectangle is the saddle's own leather), so with the saddle off the horse's back showed through. This adds a cover over the opening
that follows the horse's back (heights from the model's own body mesh, plus the frame's clearance) and uses a plain patch of the pad's fabric texture. Skin weights come from the nearest frame vertex.
  python3 fill_blanket.py models/horse/horseAdult     (after split_tack.py; idempotent)"""
import sys, os, re, copy
import numpy as np
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here); sys.path.insert(0, os.path.join(here, "..", "..", "..", "tools"))
import shapes_io as S
import make_hitching_post as H
import make_horse_sulky as K

FRAME_VERTS = 430                     # the blanket shape before the fill (split_tack.py)
UV_WINDOW = (0.80, 0.13, 0.92, 0.37)  # a plain patch of the pad's fabric in the saddle texture: u0 v0 u1 v1
GRID = 0.025

def shapes(sf):
    out = {}
    for k, e in enumerate(sf.entities):
        if e.entity_type.name == "SHAPE":
            s = S.M.parse_shape_entity(e, sf.header.version); out.setdefault(s.name, (k, s))
    return out

def loops_of(P, T):
    key = {}; wid = np.zeros(len(P), int)
    for i, p in enumerate(np.round(P, 4)): wid[i] = key.setdefault(tuple(p), len(key))
    from collections import Counter
    ec = Counter()
    for t in T:
        for a, c in ((0, 1), (1, 2), (2, 0)): ec[tuple(sorted((wid[t[a]], wid[t[c]])))] += 1
    adj = {}
    for (a, c), n in ec.items():
        if n == 1: adj.setdefault(a, []).append(c); adj.setdefault(c, []).append(a)
    rep = {}
    for i, w in enumerate(wid): rep.setdefault(w, i)
    seen, loops = set(), []
    for s0 in list(adj):
        if s0 in seen: continue
        loop = [s0]; seen.add(s0); cur = s0; prev = None
        while True:
            nx = [n for n in adj[cur] if n != prev and n not in seen]
            if not nx: break
            prev, cur = cur, nx[0]; seen.add(cur); loop.append(cur)
        loops.append([rep[w] for w in loop])
    return loops

def in_poly(pts, poly):
    x, z = pts[:, 0], pts[:, 1]; inside = np.zeros(len(pts), bool)
    n = len(poly)
    for i in range(n):
        x1, z1 = poly[i]; x2, z2 = poly[(i + 1) % n]
        c = ((z1 > z) != (z2 > z)) & (x < (x2 - x1) * (z - z1) / (z2 - z1 + 1e-12) + x1)
        inside ^= c
    return inside

def delaunay(pts):
    """Bowyer-Watson on 2D points (n x 2): list of index triples."""
    n = len(pts)
    lo, hi = pts.min(0), pts.max(0); d = (hi - lo).max() * 20
    sup = np.array([[lo[0] - d, lo[1] - d], [lo[0] + 3 * d, lo[1] - d], [lo[0], lo[1] + 3 * d]])
    P = np.vstack([pts, sup]); tris = [(n, n + 1, n + 2)]
    def circ(t):
        a, b, c = P[list(t)]; A = np.array([b - a, c - a]); r = np.array([(b @ b - a @ a) / 2, (c @ c - a @ a) / 2])
        try: o = np.linalg.solve(A, r)
        except np.linalg.LinAlgError: return None
        return o, np.sum((o - a) ** 2)
    cc = {tris[0]: circ(tris[0])}
    for i in range(n):
        p = P[i]; bad = [t for t in tris if cc[t] is not None and np.sum((cc[t][0] - p) ** 2) < cc[t][1] - 1e-14]
        edges = {}
        for t in bad:
            for e in ((t[0], t[1]), (t[1], t[2]), (t[2], t[0])):
                k = tuple(sorted(e)); edges[k] = edges.get(k, 0) + 1
        for t in bad: tris.remove(t); cc.pop(t)
        for (a, b), c in edges.items():
            if c == 1:
                t = (a, b, i); tris.append(t); cc[t] = circ(t)
    return [t for t in tris if max(t) < n]

def main(base):
    shapes_path, i3d_path = base + ".i3d.shapes", base + ".i3d"
    raw, sf = S.read(shapes_path)
    sh = shapes(sf)
    kb, blanket = sh["blanketShape"]
    if len(blanket.positions) > FRAME_VERTS:
        print("blanket already filled:", base); return
    P = np.array([[p.x, p.y, p.z] for p in blanket.positions]); Nn = np.array([[p.x, p.y, p.z] for p in blanket.normals])
    Tg = np.array([[p.x, p.y, p.z, p.w] for p in blanket.tangents]); U = np.array([[u.u, u.v] for u in blanket.uv_sets[0]])
    W = np.array(blanket.blend_weights); I = np.array(blanket.blend_indices)
    T = np.array([[t.p1 - 1, t.p2 - 1, t.p3 - 1] for t in blanket.triangles])
    loops = loops_of(P, T)
    assert len(loops) == 2, "expected two boundary loops, found %d" % len(loops)
    # the opening is the loop on the horse's side of the frame: the one with the smaller area in the top view
    def area(l):
        q = P[l][:, [0, 2]]; return abs(sum(q[i, 0] * q[(i + 1) % len(q), 1] - q[(i + 1) % len(q), 0] * q[i, 1] for i in range(len(q)))) / 2
    inner = min(loops, key=area)
    poly = P[inner][:, [0, 2]]
    # the horse's back: the body mesh seen from above
    _, body = sh["bodyShape"]
    BP = np.array([[p.x, p.y, p.z] for p in body.positions]); BT = np.array([[t.p1 - 1, t.p2 - 1, t.p3 - 1] for t in body.triangles])
    lo, hi = poly.min(0) - 0.08, poly.max(0) + 0.08
    cen = BP[BT].mean(1)
    cand = BT[(cen[:, 0] > lo[0]) & (cen[:, 0] < hi[0]) & (cen[:, 2] > lo[1]) & (cen[:, 2] < hi[1]) & (cen[:, 1] > P[:, 1].min() - 0.1)]
    A, B, C = BP[cand][:, 0], BP[cand][:, 1], BP[cand][:, 2]
    def top(x, z):
        d = (B[:, 2] - C[:, 2]) * (A[:, 0] - C[:, 0]) + (C[:, 0] - B[:, 0]) * (A[:, 2] - C[:, 2])
        l1 = ((B[:, 2] - C[:, 2]) * (x - C[:, 0]) + (C[:, 0] - B[:, 0]) * (z - C[:, 2])) / np.where(np.abs(d) < 1e-12, 1e-12, d)
        l2 = ((C[:, 2] - A[:, 2]) * (x - C[:, 0]) + (A[:, 0] - C[:, 0]) * (z - C[:, 2])) / np.where(np.abs(d) < 1e-12, 1e-12, d)
        ok = (l1 >= -1e-6) & (l2 >= -1e-6) & (l1 + l2 <= 1 + 1e-6)
        if not ok.any(): return None
        y = l1[ok] * A[ok, 1] + l2[ok] * B[ok, 1] + (1 - l1[ok] - l2[ok]) * C[ok, 1]
        return float(y.max())
    clear = []
    for i in inner:
        h = top(P[i, 0], P[i, 2])
        if h is not None: clear.append(P[i, 1] - h)
    clear = float(np.median(clear)); print("opening: %d boundary verts, frame clearance over the back: median %.3f m (min %.3f max %.3f)" % (len(inner), clear, min(clear_ := [P[i, 1] - top(P[i, 0], P[i, 2]) for i in inner if top(P[i, 0], P[i, 2]) is not None]), max(clear_)))
    clear = max(clear, 0.004)
    # interior points: a grid inside the opening, kept away from the rim; with the rim points they are triangulated
    gx = np.arange(poly[:, 0].min(), poly[:, 0].max(), GRID); gz = np.arange(poly[:, 1].min(), poly[:, 1].max(), GRID)
    G = np.array([[x, z] for x in gx for z in gz]); G = G[in_poly(G, poly)]
    dmin = np.min(np.linalg.norm(G[:, None, :] - poly[None, :, :], axis=2), axis=1); G = G[dmin > GRID * 0.7]
    pts2 = np.vstack([poly, G])
    tris = delaunay(pts2)
    keep = [t for t in tris if in_poly(pts2[list(t)].mean(0)[None, :], poly)[0]]
    ys = []
    for k, (x, z) in enumerate(pts2):
        if k < len(inner): ys.append(P[inner[k], 1])
        else:
            h = top(x, z); ys.append((h if h is not None else np.nan) + clear)
    ys = np.array(ys); bad = np.isnan(ys)
    if bad.any():
        for k in np.where(bad)[0]: ys[k] = np.nanmean(ys[np.argsort(np.linalg.norm(pts2 - pts2[k], axis=1))[:6]])
    V = np.c_[pts2[:, 0], ys, pts2[:, 1]]
    # up-facing winding; normals from the triangles (smoothed)
    out = []
    for a, b, c in keep:
        n = np.cross(V[b] - V[a], V[c] - V[a])
        out.append((a, b, c) if n[1] >= 0 else (a, c, b))
    Nv = np.zeros_like(V)
    for a, b, c in out:
        n = np.cross(V[b] - V[a], V[c] - V[a])
        for k in (a, b, c): Nv[k] += n
    Nv /= np.maximum(np.linalg.norm(Nv, axis=1, keepdims=True), 1e-9)
    u0, v0, u1, v1 = UV_WINDOW
    ux = (V[:, 0] - V[:, 0].min()) / (np.ptp(V[:, 0]) + 1e-9); uz = (V[:, 2] - V[:, 2].min()) / (np.ptp(V[:, 2]) + 1e-9)
    UVn = np.c_[u0 + ux * (u1 - u0), v0 + uz * (v1 - v0)]
    Wn, In = [], []
    for v in V:
        j = int(np.argmin(((P - v) ** 2).sum(1))); Wn.append(W[j]); In.append(I[j])
    # tangent along +x
    Tn = np.tile([1.0, 0.0, 0.0, 1.0], (len(V), 1))
    n0 = len(P)
    allP = np.vstack([P, V]); allN = np.vstack([Nn, Nv]); allT = np.vstack([Tg, Tn]); allU = np.vstack([U, UVn]); allW = np.vstack([W, Wn]); allI = np.vstack([I, In])
    Tr = T.reshape(-1).tolist() + [n0 + i for t in out for i in t]
    s0 = blanket.subsets[0]
    ent = H.shape_entity("blanketShape", blanket.id, [tuple(p) for p in allP], [tuple(n) for n in allN], [tuple(u) for u in allU], Tr, [(0, len(allP), 0, len(Tr), s0.uv_density1)], blanket.material_slot_names,
                         tangents=[tuple(t) for t in allT], skin=([tuple(w) for w in allW], [tuple(i) for i in allI]))
    sf.entities[kb].data = ent
    S.write(shapes_path, sf)
    print("%s: filled the opening with %d triangles (%d new vertices); blanket now %d vertices" % (os.path.basename(base), len(out), len(V), len(allP)))

if __name__ == "__main__":
    main(sys.argv[1])
