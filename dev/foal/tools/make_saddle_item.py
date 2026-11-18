#!/usr/bin/env python3
"""The loose saddle as a shop item: the saddle of the horse model (seat, tree, flaps with their edge band) and the panels under it (the suede lining), merged into ONE static mesh in the horse's rest pose, with the missing leather filled in: every triangle of the saddle gets
an inner skin THICK below it (so the flaps and the seat have a back side, seen from below), the panels are added as they are (they do not poke through the saddle: the chain made sure). The straps and the stirrups are not part of it (v0).
  python3 make_saddle_item.py models/horse/horseAdult vehicles/horseSaddle       -> horseSaddle.i3d, .i3d.shapes (after the whole chain: split_tack ... thicken_flaps)
The origin is the bottom of the saddle (a vehicle's origin stands on the floor), the front is +z, one box as the collision hull (mass in the xml, hands pick it up under 200 kg). Material: the game's saddle texture (the suede lining at its uv)."""
import sys, os
import numpy as np
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here); sys.path.insert(0, os.path.join(here, "..", "..", "..", "tools"))
import shift_saddle as SS
import make_hitching_post as H
import make_horse_jumps as J
import shapes_io as S

THICK = 0.0035
STRAP_Z, STRAP_HALF_W, STRAP_T, STRAP_LIFT = 0.125, 0.011, 0.0045, 0.0012      # the clean girth strap of each flap: centre line (horse z), half width, thickness, how far it floats over the flap (m)
STRAP_Y_TOP, STRAP_Y_END, STRAP_STEPS = 1.470, 1.350, 14                       # from under the skirt down to near the flap's lower edge (horse y)
STRAP_U, STRAP_V = 0.457, (0.35, 0.70)      # the strap's strip in the saddle texture: a lighter tan-brown area (the flap's leather is almost black, a strap of the same would not show)

def components(P, T):
    key = {}; weld = np.zeros(len(P), int)
    for i, p in enumerate(P): weld[i] = key.setdefault(tuple(np.round(p, 4)), len(key))
    par = list(range(len(key)))
    def f(x):
        while par[x] != x: par[x] = par[par[x]]; x = par[x]
        return x
    for a, b, c in T:
        par[f(weld[a])] = f(weld[b]); par[f(weld[a])] = f(weld[c])
    return np.array([f(weld[i]) for i in range(len(P))])

PANEL_MARGIN = 0.012                         # the panel stays at least this far inside the leather (m): the saddle is rigid on its bone, the panel follows the skin, in the walk they slide against each other by several mm

def panel_clearance(Q, Pb, Tb):
    """For every panel vertex: how far the outermost saddle surface is beyond it along the ray from the barrel axis (x = 0, y = 1.38); negative = the panel pokes through the leather; nan = nothing there."""
    V0 = Pb[Tb[:, 0]]; E1 = Pb[Tb[:, 1]] - V0; E2 = Pb[Tb[:, 2]] - V0
    out = np.full(len(Q), np.nan)
    for i, q in enumerate(Q):
        o = np.array([0.0, 1.38, q[2]]); d = q - o; d[2] = 0.0; dn = np.linalg.norm(d)
        if dn < 1e-6: continue
        d = d / dn
        h = np.cross(d, E2); a = (E1 * h).sum(1); ok = np.abs(a) > 1e-12
        f = np.where(ok, 1.0 / np.where(ok, a, 1.0), 0.0); sv = o - V0; u = f * (sv * h).sum(1)
        qv = np.cross(sv, E1); v = f * (d * qv).sum(1); t = f * (E2 * qv).sum(1)
        hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 0)
        if hit.any(): out[i] = t[hit].max() - dn
    return out

def push_panel_back(Q, T, Pb, Tb, margin=None):
    """The game's saddle has a pocket at the knee roll that the panel stands out of (up to 22 mm): every vertex that is too close to the leather is moved towards the barrel axis, the move spread over the neighbours so there is no crease."""
    margin = PANEL_MARGIN if margin is None else margin
    cl = panel_clearance(Q, Pb, Tb)
    need = np.where(np.isnan(cl), 0.0, np.maximum(0.0, margin - cl))
    nb = [set() for _ in Q]
    for a, b, c in T:
        nb[a].update((b, c)); nb[b].update((a, c)); nb[c].update((a, b))
    for _ in range(8):
        new = need.copy()
        for i in range(len(Q)):
            if nb[i]: new[i] = max(need[i], 0.85 * np.mean([need[j] for j in nb[i]]))
        need = new
    Q = Q.copy()
    for i, q in enumerate(Q):
        if need[i] <= 0: continue
        d = np.array([q[0], q[1] - 1.38, 0.0]); n = np.linalg.norm(d)
        if n > 1e-6: Q[i] = q - d / n * need[i]
    print("panel pushed back: %d of %d vertices, up to %.1f mm" % (int((need > 1e-4).sum()), len(Q), 1000 * need.max()))
    return Q

def rim_strips(pos, nrm, tan, uv, tris, used, newidx, P, N, Tg, U, Tk, deeper):
    """Closes the rim: along every free edge of the outer skin a strip joins it to the inner skin (without it there is a slit a few mm wide all round, seen from below as thin white lines)."""
    key = {}; weld = {v: key.setdefault(tuple(np.round(P[v], 4)), len(key)) for v in used}
    count = {}
    for t in Tk:
        for a, b in ((t[0], t[1]), (t[1], t[2]), (t[2], t[0])):
            e = tuple(sorted((weld[a], weld[b]))); count[e] = count.get(e, 0) + 1
    made = 0
    for t in Tk:
        fn = np.cross(P[t[1]] - P[t[0]], P[t[2]] - P[t[0]]); fn = fn / (np.linalg.norm(fn) + 1e-12)
        for a, b in ((t[0], t[1]), (t[1], t[2]), (t[2], t[0])):
            if count[tuple(sorted((weld[a], weld[b])))] != 1: continue
            e = P[b] - P[a]; out = np.cross(e, fn); ln = np.linalg.norm(out)
            if ln < 1e-12: continue
            out = out / ln
            base = len(pos)
            for v, down in ((a, 0.0), (a, THICK), (b, THICK), (b, 0.0)):
                pos.append(P[v] - fn * (THICK + deeper.get(v, 0.0) if down else 0.0)); nrm.append(out); tan.append(Tg[v]); uv.append(U[v])
            tris.append([base, base + 1, base + 2]); tris.append([base, base + 2, base + 3]); made += 1
    print("rim strips: %d free edges closed" % made)

def uv_islands(U, T):
    """The UV islands of the triangle list T as lists of triangle indices."""
    key = {}; w = np.zeros(len(U), int)
    for i in range(len(U)): w[i] = key.setdefault((round(float(U[i][0]), 4), round(float(U[i][1]), 4)), len(key))
    par = list(range(len(key)))
    def f(x):
        while par[x] != x: par[x] = par[par[x]]; x = par[x]
        return x
    for t in T:
        par[f(w[t[0]])] = f(w[t[1]]); par[f(w[t[0]])] = f(w[t[2]])
    isl = {}
    for i, t in enumerate(T): isl.setdefault(f(w[t[0]]), []).append(i)
    return list(isl.values())

def girth_details(P, U, T):
    """Mask of the triangles of the game's girth details (small UV islands under 200 cm2, low on the flaps: buckle pieces, billet ends, stitch slivers): rough little boxes that sit proud of the flap; they are dropped and one clean strap is laid on the flap."""
    drop = np.zeros(len(T), bool)
    for ids in uv_islands(U, T):
        ts = T[ids]; v = np.unique(ts.ravel())
        area = sum(np.linalg.norm(np.cross(P[a[1]] - P[a[0]], P[a[2]] - P[a[0]])) / 2 for a in ts)
        if area < 0.02 and P[v][:, 1].mean() < 1.5: drop[ids] = True
    print("girth details dropped: %d triangles" % drop.sum())
    return drop

def fill_holes(P, T, side_x=0.2, y_rng=(1.28, 1.52), z_rng=(-0.03, 0.2), min_area=1e-5, max_area=8e-3):
    """The closed holes in the flap near the girth (the slots the billets went through): every simple cycle of free edges in the window that has no flap in it is filled by ear clipping on its (z, y) projection, with the triangles' own vertices (no new ones). Returns the triangles (vertex indices) for the + and - sides."""
    key = {}; w = np.array([key.setdefault(tuple(np.round(p, 4)), len(key)) for p in P]); pos = {}; vert = {}
    for v in range(len(P)): pos.setdefault(w[v], P[v])
    cnt = {}
    for t in T:
        for a, b in ((t[0], t[1]), (t[1], t[2]), (t[2], t[0])):
            e = frozenset((w[a], w[b])); cnt[e] = cnt.get(e, 0) + 1
            vert.setdefault(w[a], a); vert.setdefault(w[b], b)
    adj = {}
    for e, n in cnt.items():
        if n == 1:
            a, b = tuple(e); adj.setdefault(a, set()).add(b); adj.setdefault(b, set()).add(a)
    out = []
    for sgn in (1, -1):
        inwin = lambda v: sgn * pos[v][0] > side_x and y_rng[0] < pos[v][1] < y_rng[1] and z_rng[0] < pos[v][2] < z_rng[1]
        nodes = {v for v in adj if inwin(v)}
        sub = {v: [u for u in adj[v] if u in nodes] for v in nodes}
        cycles = set()
        def dfs(start, v, path, seen):
            if len(path) > 60: return
            for u in sub[v]:
                if u == start and len(path) >= 3:
                    c = tuple(path); r = min(range(len(c)), key=lambda i: c[i]); c = c[r:] + c[:r]
                    if c[1] > c[-1]: c = (c[0],) + tuple(reversed(c[1:]))
                    cycles.add(c)
                elif u not in seen and u > start:
                    dfs(start, u, path + [u], seen | {u})
        for s in sorted(nodes): dfs(s, s, [s], {s})
        done = set()
        for c in sorted(cycles, key=len):
            pts = np.array([[pos[v][2], pos[v][1]] for v in c])
            area = 0.5 * float(np.sum(pts[:, 0] * np.roll(pts[:, 1], -1) - np.roll(pts[:, 0], -1) * pts[:, 1]))
            if not (min_area < abs(area) < max_area): continue
            tris = ear_clip(pts if area > 0 else pts[::-1], list(c) if area > 0 else list(c)[::-1])
            if not tris: continue
            # a hole has no flap in it: the polygon's interior point is under no triangle of the same sheet
            mid = np.array([pts[:, 0].mean(), pts[:, 1].mean()]); sheet = np.mean([pos[v][0] for v in c])
            inside = False
            for t in T:
                q = P[t]
                if abs(q[:, 0].mean() - sheet) < 0.03 and tri_contains(q[:, [2, 1]], mid): inside = True; break
            if inside: continue
            for a, b, cc in tris:
                n = np.cross(pos[b] - pos[a], pos[cc] - pos[a])
                tri = [vert[a], vert[b], vert[cc]] if n[0] * sgn > 0 else [vert[a], vert[cc], vert[b]]
                out.append(tri)
            done.add(c)
    print("holes filled: %d triangles in %d closed slot(s)" % (len(out), len(done)))
    return np.array(out).reshape(-1, 3)

def tri_contains(q, p):
    def s(a, b, c): return (a[0] - c[0]) * (b[1] - c[1]) - (b[0] - c[0]) * (a[1] - c[1])
    d1, d2, d3 = s(p, q[0], q[1]), s(p, q[1], q[2]), s(p, q[2], q[0])
    return not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))

def ear_clip(pts, ids):
    """Ear clipping of a counter-clockwise polygon (2D points, ids): list of (id, id, id) triangles, [] when it fails."""
    pts = [np.array(p) for p in pts]; ids = list(ids); tris = []; guard = 0
    def cross(a, b, c): return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    while len(ids) > 3 and guard < 5000:
        guard += 1; n = len(ids); clipped = False
        for i in range(n):
            a, b, c = pts[i - 1], pts[i], pts[(i + 1) % n]
            if cross(a, b, c) <= 1e-12: continue
            if any(tri_contains(np.array([a, b, c]), pts[j]) and j not in (i - 1, i, (i + 1) % n) for j in range(n)): continue
            tris.append((ids[i - 1], ids[i], ids[(i + 1) % n])); del pts[i]; del ids[i]; clipped = True; break
        if not clipped: return []
    tris.append(tuple(ids))
    return tris

def flap_hit(side, y, z, P, T):
    """The outermost point of the main body at (y, z) on one side (+1 / -1), found by a ray along -side x from far out; returns (point, unit normal) or None."""
    o = np.array([side * 1.0, y, z]); d = np.array([-float(side), 0.0, 0.0])
    V0 = P[T[:, 0]]; E1 = P[T[:, 1]] - V0; E2 = P[T[:, 2]] - V0
    h = np.cross(d, E2); a = (E1 * h).sum(1); ok = np.abs(a) > 1e-12
    f = np.where(ok, 1.0 / np.where(ok, a, 1.0), 0.0); sv = o - V0; u = f * (sv * h).sum(1)
    qv = np.cross(sv, E1); v = f * (d * qv).sum(1); t = f * (E2 * qv).sum(1)
    hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 0)
    if not hit.any(): return None
    i = np.where(hit)[0][np.argmin(t[hit])]; n = np.cross(E1[i], E2[i]); n = n / np.linalg.norm(n)
    if n[0] * side < 0: n = -n
    return o + d * t[i], n

def make_strap(side, P, T):
    """One clean girth strap lying on the outside of a flap: a flat ribbon (top, bottom and the two long sides) along the surface at z = STRAP_Z, narrowing to a rounded end. Returns pos, nrm, tan, uv, tris (indices from 0) or None."""
    pts = []
    for k in range(STRAP_STEPS + 1):
        y = STRAP_Y_TOP + (STRAP_Y_END - STRAP_Y_TOP) * k / STRAP_STEPS
        hz = []
        for dz in (-STRAP_HALF_W, 0.0, STRAP_HALF_W):
            h = flap_hit(side, y, STRAP_Z + dz, P, T)
            if h is None: break
            hz.append(h)
        if len(hz) < 3: break
        pts.append(hz)
    if len(pts) < 3: return None
    pos, nrm, uv, tris = [], [], [], []
    rows = len(pts)
    for k, hz in enumerate(pts):
        for j, (p, n) in enumerate(hz):
            w = 1.0 if k < rows - 2 else 0.6 if k == rows - 2 else 0.25               # the end narrows towards its tip
            q = hz[1][0] + (p - hz[1][0]) * w
            for top in (1, 0):
                pos.append(q + n * (STRAP_LIFT + STRAP_T * top)); nrm.append(n if top else -n)
                uv.append((STRAP_U + 0.006 * j / 2, STRAP_V[0] + (STRAP_V[1] - STRAP_V[0]) * k / (rows - 1)))
    def vid(k, j, top): return (k * 3 + j) * 2 + (0 if top else 1)
    for k in range(rows - 1):
        for j in range(2):
            for top in (1, 0):
                a, b, c, d = vid(k, j, top), vid(k, j + 1, top), vid(k + 1, j + 1, top), vid(k + 1, j, top)
                tris += [[a, b, c], [a, c, d]]
        for j in (0, 2):                                                               # the long sides
            a, b, c, d = vid(k, j, 1), vid(k, j, 0), vid(k + 1, j, 0), vid(k + 1, j, 1)
            tris += [[a, b, c], [a, c, d]]
    for j in range(2):                                                                 # the lower end cap
        a, b, c, d = vid(rows - 1, j, 1), vid(rows - 1, j + 1, 1), vid(rows - 1, j + 1, 0), vid(rows - 1, j, 0)
        tris += [[a, b, c], [a, c, d]]
    pos = np.array(pos); nrm = np.array(nrm); tris = np.array(tris); whole = pos.mean(0)
    for i, tr in enumerate(tris):                                                      # every triangle faces away from its row's middle (the end cap: away from the whole strap)
        rowids = set(int(v) // 6 for v in tr)
        if len(rowids) == 1:
            r = rowids.pop(); mid = pos[[vid(r, j, tp) for j in range(3) for tp in (0, 1)]].mean(0)
        else:
            mid = whole if (tr // 6).min() == rows - 1 else pos[[vid(int((tr // 6).min()), j, tp) for j in range(3) for tp in (0, 1)]].mean(0)
        g = np.cross(pos[tr[1]] - pos[tr[0]], pos[tr[2]] - pos[tr[0]])
        if g @ (pos[tr].mean(0) - mid) < 0: tris[i] = tr[[0, 2, 1]]
    t = np.tile(np.array([0.0, 1.0, 0.0, 1.0]), (len(pos), 1))
    return pos, nrm, t, np.array(uv), tris

def main(base, out):
    raw, sf = SS.S.read(base + ".i3d.shapes")
    _, seat = SS.load(sf, "saddleShape"); A = SS.arrays(seat)
    _, panel = SS.load(sf, "panelShape"); PA = SS.arrays(panel)
    P, N, Tg, U, T = A["P"], A["N"], A["Tg"], A["U"], A["T"]
    comp = components(P, T)
    ids, counts = np.unique(comp, return_counts=True); main_id = ids[np.argmax(counts)]
    keep_tri = np.array([comp[t[0]] == main_id for t in T])
    idx = np.where(keep_tri)[0]; keep_tri[idx[girth_details(P, U, T[idx])]] = False       # (the rough details leave, the flap under them stays)
    fill = fill_holes(P, T[keep_tri])                                                     # ... and the slots they sat in are filled (with the flap's own vertices)
    if len(fill): T = np.vstack([T, fill]); keep_tri = np.concatenate([keep_tri, np.ones(len(fill), bool)])
    print("saddle: %d triangles, the main body (seat, tree, flaps) %d" % (len(T), keep_tri.sum()))
    used = sorted(set(T[keep_tri].ravel().tolist())); newidx = {v: n for n, v in enumerate(used)}
    pos = [P[v] for v in used]; nrm = [N[v] for v in used]; tan = [Tg[v] for v in used]; uv = [U[v] for v in used]; tris = [[newidx[a] for a in t] for t in T[keep_tri]]
    # the inner skin: a copy of every kept vertex a little below the surface (along its normal, inwards), reversed winding
    base_n = len(pos)
    deeper = {}
    for v in used:
        pos.append(P[v] - N[v] * (THICK + deeper.get(v, 0.0))); nrm.append(-N[v]); t = Tg[v].copy(); t[3] = -t[3]; tan.append(t); uv.append(U[v])
    tris += [[newidx[t[0]] + base_n, newidx[t[2]] + base_n, newidx[t[1]] + base_n] for t in T[keep_tri]]
    rim_strips(pos, nrm, tan, uv, tris, used, newidx, P, N, Tg, U, T[keep_tri], deeper)
    # the clean girth straps, one on each flap
    for side in (1, -1):
        st = make_strap(side, P, T[keep_tri])
        if st is None: print("no strap on side", side); continue
        o = len(pos); pos += list(st[0]); nrm += list(st[1]); tan += list(st[2]); uv += list(st[3]); tris += [[int(a) + o for a in t] for t in st[4]]
        print("girth strap %+d: %d vertices" % (side, len(st[0])))
    # the panels, pushed back out of the leather at the knee roll (both sides, suede uv)
    off = len(pos)
    PQ = push_panel_back(PA["P"], PA["T"], P, T[keep_tri])
    for i in range(len(PA["P"])):
        pos.append(PQ[i]); nrm.append(PA["N"][i]); tan.append(np.array([1.0, 0.0, 0.0, 1.0])); uv.append(PA["U"][i])
    tris += [[int(a) + off for a in t] for t in PA["T"]]
    pos, nrm, tan, uv, tris = np.array(pos), np.array(nrm), np.array(tan), np.array(uv), np.array(tris)
    # a tangent of the panel: along its own surface (the shape carries a frame per vertex in the horse's file; here the x axis is enough for a plain patch of texture)
    lo, hi = pos.min(0), pos.max(0)
    shift = np.array([-(lo[0] + hi[0]) / 2, -lo[1], -(lo[2] + hi[2]) / 2])
    pos = pos + shift
    size = hi - lo; print("saddle item: %d vertices, %d triangles, size x %.2f y %.2f z %.2f m" % (len(pos), len(tris), size[0], size[1], size[2]))
    os.makedirs(out, exist_ok=True)
    vis = H.shape_entity("horseSaddle_vis", 1, [tuple(p) for p in pos], [tuple(n) for n in nrm], [tuple(u) for u in uv], tris.reshape(-1).tolist(),
                         [(0, len(pos), 0, tris.size, 1.0)], ["saddle"], tangents=[tuple(t) for t in tan])
    c = (0.0, size[1] / 2, 0.0); h = (size[0] / 2, size[1] / 2, size[2] / 2)
    body = H.shape_entity("horseSaddle_body", 2, *[(c[0] + sx * h[0], c[1] + sy * h[1], c[2] + sz * h[2]) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)] and (lambda m: (list(m.p), list(m.n), list(m.uv) if hasattr(m, "uv") else [(0, 0)] * len(m.p), [i for t in m.t for i in t], [(0, len(m.p), 0, len([i for t in m.t for i in t]), 1.0)], ["saddle"]))(
        (lambda mm: (H.box(mm, c[0], c[1], c[2], h[0], h[1], h[2]), mm)[1])(H.Mesh())), attachments=[(2, J.hull_block(c, h))])
    hdr = type("Hd", (), {"version": 10, "seed": 83})()
    sfn = type("SF", (), {"header": hdr, "entities": [H.Raw(1, vis), H.Raw(1, body)]})()
    S.write(os.path.join(out, "horseSaddle.i3d.shapes"), sfn)
    xml = f'''<?xml version="1.0" encoding="iso-8859-1"?>

<i3D name="horseSaddle" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">
  <Asset>
    <Export program="make_saddle_item.py" version="1"/>
  </Asset>
  <Files>
    <File fileId="1" filename="$dataS/character/animals/domesticated/horse/saddle_diffuse.png" />
    <File fileId="2" filename="$dataS/character/animals/domesticated/horse/saddle_normal.png" />
    <File fileId="3" filename="$dataS/character/animals/domesticated/horse/saddle_specular.png" />
  </Files>
  <Materials>
    <Material name="saddle_mat" materialId="1">
      <Texture fileId="1" />
      <Normalmap fileId="2" />
      <Glossmap fileId="3" />
    </Material>
  </Materials>
  <Shapes externalShapesFile="horseSaddle.i3d.shapes">
  </Shapes>
  <Scene>
    <Shape name="horseSaddle_main_component1" shapeId="2" dynamic="true" compound="true" density="0.0005" collisionFilterGroup="0x10004" collisionFilterMask="0xfe3ffb83" linearDamping="0.1" angularDamping="0.5" staticFriction="0.8" dynamicFriction="0.6" castsShadows="false" receiveShadows="false" nonRenderable="true" materialIds="1" clipDistance="300" nodeId="1">
      <Shape name="horseSaddle_vis" shapeId="1" castsShadows="true" receiveShadows="true" materialIds="1" clipDistance="300" nodeId="2"/>
    </Shape>
  </Scene>

</i3D>
'''
    open(os.path.join(out, "horseSaddle.i3d"), "w", encoding="iso-8859-1").write(xml)
    print("wrote", out)

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
