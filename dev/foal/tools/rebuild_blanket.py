#!/usr/bin/env python3
"""Rebuilds the saddle blanket as ONE even sheet that lies on the horse: the body mesh's own triangles under the pad (subdivided once so the edge is smooth), lifted 1 cm along the body's normals, so it is the same height everywhere,
follows the back, and has no seams or holes by construction. The pad's region is the frame of the game's pad plus its opening (what fill_blanket.py covered); the saddle's strap pieces that sit in the frame (the girth billets under
the pad, UV khaki) go back to the saddle shape. Texture: a plain fabric patch for now. Skin weights: the nearest old pad vertex.
  python3 rebuild_blanket.py models/horse/horseAdult      (after split_tack.py and fill_blanket.py; the first run keeps the old pad in dev/foal/blanket_old/<model>.npz, later runs start from it)"""
import sys, os, re, copy
import numpy as np
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here); sys.path.insert(0, os.path.join(here, "..", "..", "..", "tools"))
import shapes_io as S
import make_hitching_post as H
import make_horse_sulky as K

LIFT = 0.013                                  # metres at the adult's size: where the top surface starts, before the smoothing
TOP_MIN = 0.011                               # the top never closer to the body than this
THICK = 0.008                                 # the pad's thickness: its underside is this far below the top (so 3 mm off the body at the closest)
FRAME_VERTS, FRAME_TRIS = 430, 658
LOW_LIFT = 0.02                             # extra metres (adult) of clearance at the pad's lower edge (the belly swings in the walk)
FRONT_ROUND = 0.14                          # metres (adult) the pad's front edge is pulled back at the flanks (the front corners are rounded)
SADDLE_ORIG_VERTS = 2057                    # the game's saddle shape (after the bridle, bit and blanket were cut out of it) before the billets were added
SMALL_PART = 0.12                           # metres (adult): saddle pieces smaller than this (bounding box diagonal) are moved rigidly
GIRTH_Z0, GIRTH_Z1, GIRTH_Y0 = 0.24, 0.44, 1.10   # the girth's footprint on the flank (adult size): the pad covers it
GIRTH_LEG_MAX = 0.6                         # skin carried more than this by the front leg stays out
GIRTH_EXTEND = True                         # (the girth band is no longer stretched up to the flap: its billets and buckles reach there instead, see girth_details.py)
GIRTH_COLS = 8                              # vertices across the girth band's new top edge
GIRTH_ROWS = 20                              # rows added to the girth band's top
GIRTH_STEP = 0.0145                          # metres (adult) per row: 7 x 4 cm = the band reaches up under the saddle flap
GIRTH_LIFT = 0.016                          # metres (adult) the extended band lies above the pad
EDGE_FADE = 0.05                            # metres (adult): the pull-out fades to zero across the last this much of the pad's edge
FILL_RADIUS, FILL_FROM, FILL_MAX, FILL_KEEP = 0.03, 0.02, 0.09, 0.010   # the filler under the saddle (metres, adult): the saddle point must be within this horizontal radius; gaps between 2 and 9 cm are filled up to 1 cm below the saddle
SADDLE_GAP = 0.019                          # metres (adult) the saddle leather stays above the pad where they overlap
FLOOR_RINGS = 7                             # reach (in vertex rings, ~1 cm each) of the smooth floor push
FRONT_LIFT = 0.03                           # extra metres (adult) of clearance where the skin's leg weight is at the limit
FRONT_CLOSE = 0.12                          # metres (adult): dents of the selected region's side outline narrower than about twice this are closed (the front edge's dent over the shoulder)
FRONT_EXTEND = 0.0                          # metres (adult) the pad's side outline is pushed forward of the game's pad
FRONT_TRIM = 0.0                            # (a plain trim of the front edge, metres at the adult's size: 0, the leg bones decide now)
LEG_WEIGHT_TOP = 0.9                        # the limit at the top of the pad (see above)
RIGID_FROM = 0.7                            # fraction of the pad's height from which the weights turn rigid (a strip along the spine); below it the pad is relative to the mesh under it
STIFF = 0.0                                 # share of the rigid back-bone weights at the pad's lower edge; at the top (the spine) the pad is fully rigid, in between it gives gradually: the hanging sides swing out, the top does not bend
LEG_WEIGHT_MAX = float(os.environ.get("LEG_WEIGHT_MAX", 0.3))                       # body vertices carried by more than this by the front leg bones (shoulder, leg, foot) are not under the pad
OPEN = 0.22                                 # corners of the pad's side outline are rounded to about this radius (metres, adult); lobes narrower than twice this are cut
CLOSE = 0.09                                # notches in the pad's side outline narrower than about twice this (metres, adult) are closed: one clean rounded edge
BORDER_ITERATIONS = 30                      # smoothing of the pad's outline along itself
SMOOTH_ITERATIONS = 110                     # the reach of the smoothing is about the square root of this, in vertex spacings (~1 cm)
UV_WINDOW = (0.871, 0.699, 0.871, 0.699)  # ONE flat spot of the pad fabric (the flattest in diffuse and normal map): an even colour, so the shape reads without texture stripes
STRAP_U, STRAP_V = (0.55, 0.66), 0.125        # the khaki billets of the frame: u range, and v < STRAP_V or v > 1 - STRAP_V

def shapes(sf):
    out = {}
    for k, e in enumerate(sf.entities):
        if e.entity_type.name == "SHAPE":
            s = S.M.parse_shape_entity(e, sf.header.version); out.setdefault(s.name, (k, s))
    return out

def arrays(s):
    return dict(P=np.array([[p.x, p.y, p.z] for p in s.positions]), N=np.array([[p.x, p.y, p.z] for p in s.normals]), Tg=np.array([[p.x, p.y, p.z, p.w] for p in s.tangents]),
                U=np.array([[u.u, u.v] for u in s.uv_sets[0]]), W=np.array(s.blend_weights), I=np.array(s.blend_indices), T=np.array([[t.p1 - 1, t.p2 - 1, t.p3 - 1] for t in s.triangles]))

def entity(sf, k, s, A, T):
    s0 = s.subsets[0]
    sf.entities[k].data = H.shape_entity(s.name, s.id, [tuple(p) for p in A["P"]], [tuple(n) for n in A["N"]], [tuple(u) for u in A["U"]], T.reshape(-1).tolist(), [(0, len(A["P"]), 0, T.size, s0.uv_density1)],
                                         s.material_slot_names, tangents=[tuple(t) for t in A["Tg"]], skin=([tuple(w) for w in A["W"]], [tuple(i) for i in A["I"]]))

def vertex_normals(P, T):
    key = {}; wid = np.zeros(len(P), int)
    for i, p in enumerate(np.round(P, 4)): wid[i] = key.setdefault(tuple(p), len(key))
    n = np.zeros((len(key), 3))
    fn = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    for k in range(3): np.add.at(n, wid[T[:, k]], fn)
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    return n[wid]

def main(base):
    shapes_path = base + ".i3d.shapes"; name = os.path.basename(base)
    cache = os.path.join(here, "..", "blanket_old", name + ".npz")
    raw, sf = S.read(shapes_path); sh = shapes(sf)
    kb, blanket = sh["blanketShape"]; ks, seat = sh["saddleShape"]
    if os.path.exists(cache):
        z = np.load(cache); old = {k: z[k] for k in z.files}; print("starting from the saved old pad", cache)
    else:
        os.makedirs(os.path.dirname(cache), exist_ok=True)
        A = arrays(blanket); F = A["T"][:FRAME_TRIS]
        cu = A["U"][F].mean(1)
        strap = (cu[:, 0] > STRAP_U[0]) & (cu[:, 0] < STRAP_U[1]) & ((cu[:, 1] < STRAP_V) | (cu[:, 1] > 1 - STRAP_V))
        print("%d strap triangles of the frame go back to the saddle" % strap.sum())
        # the saddle shape gets those triangles (with copies of their vertices)
        SA = arrays(seat); used = np.unique(F[strap].reshape(-1)); remap = {int(v): len(SA["P"]) + i for i, v in enumerate(used)}
        add = {k: A[k][used] for k in ("P", "N", "Tg", "U", "W", "I")}
        newT = np.array([[remap[int(v)] for v in t] for t in F[strap]])
        SA2 = {k: np.vstack([SA[k], add[k]]) for k in ("P", "N", "Tg", "U", "W", "I")}
        entity(sf, ks, seat, SA2, np.vstack([SA["T"], newT]))
        keep = np.vstack([F[~strap], A["T"][FRAME_TRIS:]])         # the frame without the billets, and the fill
        old = dict(P=A["P"], W=A["W"], I=A["I"], T=keep, U=A["U"], N=A["N"], Tg=A["Tg"])
        np.savez(cache, **old)
    P, T = old["P"], old["T"]
    scale = (np.ptp(P[:FRAME_VERTS][:, 0])) / 0.69        # (the adult pad is 0.69 m wide)
    lift = LIFT * scale
    # dense samples of the old pad's surface (frame + opening)
    ws = [(a / 9, b / 9, 1 - a / 9 - b / 9) for a in range(10) for b in range(10 - a)]
    tri3 = P[T]; samp = np.concatenate([w[0] * tri3[:, 0] + w[1] * tri3[:, 1] + w[2] * tri3[:, 2] for w in ws])
    # the horse's body around it, subdivided once
    _, body = sh["bodyShape"]; BA = arrays(body)
    BP, BT = BA["P"], BA["T"]
    BN = vertex_normals(BP, BT)
    # how much each body vertex is carried by the front leg (shoulder, leg and foot bones): the pad must not sit on anything that moves with the leg
    import xml.etree.ElementTree as ET
    root = ET.fromstring(open(base + ".i3d", "rb").read())
    nodenames = {int(g.get("nodeId")): g.get("name") for g in root.iter("TransformGroup") if g.get("nodeId")}
    bodynode = [e for e in root.iter("Shape") if e.get("name") == "body"][0]
    bind = [nodenames[int(v)] for v in bodynode.get("skinBindNodeIds").split()]
    legbone = np.array([n.startswith("front") or n.startswith("frKnee") for n in bind])
    FW = (BA["W"] * legbone[BA["I"]]).sum(1)
    lo, hi = samp.min(0) - 0.06, samp.max(0) + 0.06
    cen = BP[BT].mean(1)
    cand = BT[(cen > lo).all(1) & (cen < hi).all(1)]
    P0, N0 = BP, BN
    mids = {}; newP = [p for p in BP]; newN = [n for n in BN]; newF = [f for f in FW]
    def mid(a, b):
        k = (min(a, b), max(a, b))
        if k not in mids:
            mids[k] = len(newP); m = (newP[a] + newP[b]) / 2; n = newN[a] + newN[b]; newP.append(m); newN.append(n / np.linalg.norm(n)); newF.append((newF[a] + newF[b]) / 2)
        return mids[k]
    sub = []
    for a, b, c in cand:
        ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
        sub += [(a, ab, ca), (ab, b, bc), (ca, bc, c), (ab, bc, ca)]
    SP, SN, SF = np.array(newP), np.array(newN), np.array(newF); ST = np.array(sub)
    # which body vertices lie under the pad: inside the old pad's SILHOUETTE seen from the side (z, y: the authored outline, smooth; the gaps and notches of a nearest-vertex test are closed) and near the pad's surface
    used = np.unique(ST.reshape(-1)); UP = SP[used]
    cell = 0.005 * scale
    z0, y0 = samp[:, 2].min() - 0.02, samp[:, 1].min() - 0.02
    gz, gy = int((samp[:, 2].max() - z0) / cell) + 6, int((samp[:, 1].max() - y0) / cell) + 6
    mask = np.zeros((gz, gy), bool)
    mask[((samp[:, 2] - z0) / cell).astype(int), ((samp[:, 1] - y0) / cell).astype(int)] = True
    def grow(m):
        q = np.pad(m, 1); return q[1:-1, 1:-1] | q[:-2, 1:-1] | q[2:, 1:-1] | q[1:-1, :-2] | q[1:-1, 2:]
    def grow8(m):
        q = np.pad(m, 1); out = m.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1): out |= q[1 + dy:q.shape[0] - 1 + dy, 1 + dx:q.shape[1] - 1 + dx]
        return out
    def disk(m, k, inv=False):
        if inv: m = ~m
        for i in range(k): m = grow8(m) if i % 2 else grow(m)       # alternating diamond / square steps: a round-ish disk
        return ~m if inv else m
    k = int(CLOSE * scale / cell)
    mask = disk(disk(mask, k), k, inv=True) if False else mask
    for _ in range(1):
        m = disk(mask, k); mask = disk(m, k, inv=True)                # closing: notches filled
    k2 = int(OPEN * scale / cell)
    m = disk(mask, k2, inv=True); mask = disk(m, k2)                  # opening: lobes cut, corners rounded to about this radius
    kx = int(FRONT_EXTEND * scale / cell)                              # the front edge pushed forward (+z): the pad comes out in front of the saddle's flap
    if kx > 0:
        shf = np.zeros_like(mask); shf[kx:] = mask[:-kx]; mask = mask | shf
    kf = int(FRONT_TRIM * scale / cell)                                # the front edge pulled back (+z is forward): room for the front leg
    if kf > 0:
        shf = np.zeros_like(mask); shf[:-kf] = mask[kf:]; mask = mask & shf
        m = disk(mask, k2 // 2, inv=True); mask = disk(m, k2 // 2)     # (the trimmed corners rounded again)
    zi = np.clip(((UP[:, 2] - z0) / cell).astype(int), 0, gz - 1); yi = np.clip(((UP[:, 1] - y0) / cell).astype(int), 0, gy - 1)
    insil = mask[zi, yi] & (((UP[:, 2] - z0) / cell) >= 0) & (((UP[:, 1] - y0) / cell) >= 0)
    dist = np.full(len(UP), np.inf)
    for i in range(0, len(samp), 4000):
        dist = np.minimum(dist, np.sqrt(((samp[i:i + 4000, None, :] - UP[None, :, :]) ** 2).sum(2)).min(0))
    ylo, yhi = samp[:, 1].min(), samp[:, 1].max()
    tt = np.clip((SP[used][:, 1] - (ylo + 0.55 * (yhi - ylo))) / (0.30 * (yhi - ylo)), 0, 1)
    legmax = LEG_WEIGHT_MAX + (LEG_WEIGHT_TOP - LEG_WEIGHT_MAX) * tt            # higher up (the withers, under the saddle's wrist) the scapula's share may be larger: the pad comes further forward there
    hit = np.zeros(len(SP), bool); hit[used] = insil & (dist < 0.10 * scale) & (SF[used] < legmax)
    # the leg-weight cut can bend inward where the shoulder blade's weights peak (a dent in the front edge): close the selected region in the side view and take the vertices inside the closed shape back in
    hu = hit[used]; m2 = np.zeros_like(mask); m2[zi[hu], yi[hu]] = True
    k3 = int(FRONT_CLOSE * scale / cell)
    m2 = disk(disk(m2, k3), k3, inv=True)
    add = m2[zi, yi] & (dist < 0.10 * scale) & (SF[used] < 0.9)
    hit[used] = hit[used] | add
    # the front corners at the lower sides stuck out forward as two horns: the front edge curves back towards the flanks (a pad's front is rounded, not squared)
    zf = SP[used][:, 2][hit[used]].max()
    ax_ = np.abs(SP[used][:, 0]) / scale
    zlim = zf - FRONT_ROUND * scale * np.clip((ax_ - 0.14) / 0.14, 0, 1) ** 1.5
    hit[used] = hit[used] & (SP[used][:, 2] <= zlim)
    # the girth band (z 0.27 .. 0.41 at the adult's size) lies on the pad: the pad covers its whole footprint, whatever the leg-weight cut and the rounding decided (skin that the leg drags too much stays out)
    gz_ = (SP[used][:, 2] >= GIRTH_Z0 * scale) & (SP[used][:, 2] <= GIRTH_Z1 * scale) & (SP[used][:, 1] >= GIRTH_Y0 * scale)
    hit[used] = hit[used] | (insil & (dist < 0.10 * scale) & gz_ & (SF[used] < GIRTH_LEG_MAX))
    count = hit[ST].sum(1)
    inside = count >= 2
    # close small holes: a sub-triangle with at least two kept neighbours is kept
    edge = {}
    for k, t in enumerate(ST):
        for a, b in ((0, 1), (1, 2), (2, 0)): edge.setdefault((min(t[a], t[b]), max(t[a], t[b])), []).append(k)
    for _ in range(2):
        add = []
        for k, t in enumerate(ST):
            if inside[k]: continue
            nb = 0
            for a, b in ((0, 1), (1, 2), (2, 0)):
                nb += any(inside[j] for j in edge[(min(t[a], t[b]), max(t[a], t[b]))] if j != k)
            if nb >= 2: add.append(k)
        inside[add] = True
    R = ST[inside]
    uv = np.unique(R.reshape(-1)); rm = -np.ones(len(SP), int); rm[uv] = np.arange(len(uv))
    hb = np.clip((SP[uv][:, 1] - samp[:, 1].min()) / (np.ptp(samp[:, 1]) + 1e-9), 0, 1)
    NP = SP[uv] + SN[uv] * (lift + FRONT_LIFT * scale * np.clip(SF[uv] / LEG_WEIGHT_MAX, 0, 1) + LOW_LIFT * scale * (1 - hb) ** 2)[:, None]; NN = SN[uv]; NT = rm[R]      # where the skin carries some leg weight the pad stands off further: the game's body weights are not mirror-symmetric, and the leg drags that skin more than the pad can follow
    # outward winding
    fn = np.cross(NP[NT[:, 1]] - NP[NT[:, 0]], NP[NT[:, 2]] - NP[NT[:, 0]])
    flip = (fn * NN[NT].mean(1)).sum(1) < 0
    NT[flip] = NT[flip][:, [0, 2, 1]]
    import fill_blanket as FB
    tl = FB.loops_of(NP, NT)
    print('top sheet boundary loops: %d (1 = a single outline, more = holes): sizes %s' % (len(tl), [len(l) for l in tl]))
    # an even top line: the sheet bridges the horse's bumps (a pad's job is to spread the pressure): low-pass the shape (Taubin: no shrinking), then never closer to the body than half the lift
    nb = [set() for _ in range(len(NP))]
    for a, b, c in NT:
        nb[a] |= {b, c}; nb[b] |= {a, c}; nb[c] |= {a, b}
    def smooth(Q, f):
        out = Q.copy()
        for i, n in enumerate(nb):
            if n: out[i] = Q[i] + f * (Q[list(n)].mean(0) - Q[i])
        return out
    Q = NP.copy()
    for _ in range(SMOOTH_ITERATIONS):
        Q = smooth(Q, 0.5); Q = smooth(Q, -0.53)
    # the outline: the stair-steps of the body's triangles are rounded off along the edge itself (1D smoothing of each boundary loop)
    ecount = {}
    for a, b, c in NT:
        for u, v in ((a, b), (b, c), (c, a)): ecount[(u, v)] = ecount.get((u, v), 0) + 1
    nxt = {u: v for (u, v), c in ecount.items() if (v, u) not in ecount}
    seen = set()
    for start in list(nxt):
        if start in seen: continue
        loop = [start]; seen.add(start); cur = nxt[start]
        while cur not in seen and cur in nxt:
            loop.append(cur); seen.add(cur); cur = nxt[cur]
        if len(loop) < 8: continue
        idx = np.array(loop)
        for _ in range(BORDER_ITERATIONS):
            for f in (0.5, -0.53):
                B = Q[idx]; Q[idx] = B + f * ((np.roll(B, 1, 0) + np.roll(B, -1, 0)) / 2 - B)
    bodypt = SP[uv]
    d = ((Q - bodypt) * NN).sum(1)
    # the floor (never closer than TOP_MIN) as a SMOOTH push: the shortfall is spread over the neighbours (max, then averaged), so there is no crease where the pad meets a bump of the horse
    D = np.maximum(0.0, TOP_MIN * scale - d)
    def spread(F, rings):
        for _ in range(rings):
            F = np.array([max(F[i], max((F[j] for j in nb[i]), default=0.0)) for i in range(len(F))])
        return F
    Dd = spread(D, FLOOR_RINGS)
    for _ in range(FLOOR_RINGS):
        Dd = np.array([(Dd[i] + sum(Dd[j] for j in nb[i])) / (1 + len(nb[i])) for i in range(len(Dd))])
    Dd = np.maximum(Dd * 1.15, D)
    Q = Q + NN * Dd[:, None]
    # a filler under the saddle: where the game's rigid saddle sits above the pad (its rear edge floats over the loin dip) the pad rises to just below it, as a smooth wedge, so no opening shows between them
    sadc = os.path.join(here, "..", "blanket_old", name + "_saddle.npz")
    if os.path.exists(sadc):
        sp = np.load(sadc)["P"][:2057]
        sp = sp[sp[:, 1] > Q[:, 1].min() + 0.06 * scale]
        rise = np.zeros(len(Q))
        for i0 in range(0, len(Q), 400):
            dx = Q[i0:i0 + 400, None, 0] - sp[None, :, 0]; dz = Q[i0:i0 + 400, None, 2] - sp[None, :, 2]
            near = (dx * dx + dz * dz) < (FILL_RADIUS * scale) ** 2
            yy = np.where(near & (sp[None, :, 1] > Q[i0:i0 + 400, None, 1]), sp[None, :, 1], np.inf).min(1)       # the saddle's lowest point above this pad point
            gap = yy - Q[i0:i0 + 400, 1]
            ok = (gap > FILL_FROM * scale) & (gap < FILL_MAX * scale)
            rise[i0:i0 + 400] = np.where(ok, gap - FILL_KEEP * scale, 0.0)
        for _ in range(8):
            rise = np.array([(rise[i] + sum(rise[j] for j in nb[i])) / (1 + len(nb[i])) for i in range(len(rise))])      # smooth wedge
        Q[:, 1] += rise
        print("filler under the saddle: %d pad vertices raised, up to %.1f mm" % ((rise > 1e-4).sum(), 1000 * rise.max()))
    print("smoothed: the sheet lies %.1f .. %.1f mm off the body (was an even %.1f)" % (((Q - bodypt) * NN).sum(1).min() * 1000, ((Q - bodypt) * NN).sum(1).max() * 1000, lift * 1000))
    NP = Q
    NN = vertex_normals(NP, NT)
    # extrude: the underside (the top moved down by the pad's thickness, facing the horse) and a wall round the edge
    n0 = len(NP); thick = THICK * scale
    bot = NP - NN * thick
    sheetN = NN
    topT = NT; botT = NT[:, [0, 2, 1]] + n0
    ec = {}
    for a, b, c in NT:
        for u, v in ((a, b), (b, c), (c, a)): ec[(u, v)] = ec.get((u, v), 0) + 1
    edges = [(u, v) for (u, v), c in ec.items() if (v, u) not in ec]          # directed boundary edges (the sheet's inside is on the left)
    centre = NP.mean(0)
    wallP, wallN, wallT = [], [], []
    for u, v in edges:
        a, b, c, d = NP[u], NP[v], bot[v], bot[u]
        nrm = np.cross(b - a, d - a); nrm /= max(np.linalg.norm(nrm), 1e-12)
        if nrm @ ((a + b) / 2 - centre) < 0: nrm = -nrm
        wbase = n0 * 2 + len(wallP)
        wallP += [a, b, c, d]; wallN += [nrm] * 4
        t1, t2 = (wbase, wbase + 1, wbase + 2), (wbase, wbase + 2, wbase + 3)
        if np.cross(b - a, c - a) @ nrm < 0: t1, t2 = t1[::-1], t2[::-1]
        wallT += [t1, t2]
    NPo = NP
    NP = np.vstack([NPo, bot] + ([np.array(wallP)] if wallP else []))
    NNall = np.vstack([NN, -NN] + ([np.array(wallN)] if wallN else []))
    NT = np.vstack([topT, botT] + ([np.array(wallT)] if wallT else []))
    wallsrc = [u for u, v in edges for _ in range(2)] + []
    srcmap = np.concatenate([np.arange(n0), np.arange(n0), np.array([k for u, v in edges for k in (u, v, v, u)], dtype=int)])
    NN = NNall
    # texture: a plain fabric patch, stretched over the sheet; tangents along +x; skin from the nearest old pad vertex
    # UV: u = distance over the pad's surface from the spine line (signed by side: the quilting runs evenly over the back and down the flanks), v = z along the horse; one scale for both, so the texture's metres are real metres
    import heapq
    adj = [[] for _ in range(n0)]
    for a, b, c in NT[:len(topT)]:
        for x_, y_ in ((a, b), (b, c), (c, a)):
            dlen = float(np.linalg.norm(NPo[x_] - NPo[y_])); adj[x_].append((y_, dlen)); adj[y_].append((x_, dlen))
    dist = np.full(n0, np.inf); pq = []
    for i in np.where(np.abs(NPo[:, 0]) < 0.012 * scale)[0]:
        dist[i] = 0.0; pq.append((0.0, int(i)))
    heapq.heapify(pq)
    while pq:
        dd_, i = heapq.heappop(pq)
        if dd_ > dist[i]: continue
        for j, l in adj[i]:
            if dd_ + l < dist[j]: dist[j] = dd_ + l; heapq.heappush(pq, (dd_ + l, j))
    sgeo = np.where(NPo[:, 0] >= 0, 1.0, -1.0) * dist
    SPAN = max(np.ptp(sgeo) * 1.06, np.ptp(NPo[:, 2]) * 2 * 1.06)          # metres across the texture's width; its height is half of that (a 2:1 texture, 2048 x 1024)
    smid, zmid = (sgeo.max() + sgeo.min()) / 2, (NPo[:, 2].max() + NPo[:, 2].min()) / 2
    NU = np.c_[(sgeo - smid) / SPAN + 0.5, (NPo[:, 2] - zmid) / (SPAN / 2) + 0.5]
    import json
    json.dump({"span_m": SPAN, "scale": scale}, open(os.path.join(here, "..", "blanket_old", name + "_uv.json"), "w"))
    # tangents along u (per vertex from the triangles' UV derivatives), w = handedness against +v
    NUf = NU[srcmap]; Tacc = np.zeros((len(NP), 3)); Bacc = np.zeros((len(NP), 3))
    for a, b, c in NT:
        e1, e2 = NP[b] - NP[a], NP[c] - NP[a]; d1, d2 = NUf[b] - NUf[a], NUf[c] - NUf[a]
        det = d1[0] * d2[1] - d2[0] * d1[1]
        if abs(det) < 1e-12: continue
        tt_ = (e1 * d2[1] - e2 * d1[1]) / det; bb_ = (e2 * d1[0] - e1 * d2[0]) / det
        for v_ in (a, b, c): Tacc[v_] += tt_; Bacc[v_] += bb_
    Tn = Tacc - NN * (Tacc * NN).sum(1, keepdims=True)
    for i_ in range(len(Tn)):
        if np.linalg.norm(Tn[i_]) < 1e-9: Tn[i_] = K.frame_of(K.norm(tuple(NN[i_])))[0]       # (the wall's vertices: no UV area)
    Tn /= np.maximum(np.linalg.norm(Tn, axis=1, keepdims=True), 1e-12)
    wsign = np.where((np.cross(NN, Tn) * Bacc).sum(1) >= 0, 1.0, -1.0)
    NTg = np.c_[Tn, wsign]
    W, I = old["W"], old["I"]; Wn, In = [], []
    for i in range(0, n0, 2000):
        j = np.argmin(((NPo[i:i + 2000, None, :] - P[None, :, :]) ** 2).sum(2), axis=1); Wn.append(W[j]); In.append(I[j])
    Wtop, Itop = np.vstack(Wn), np.vstack(In)
    # a stiff pad: EVERY vertex carries the saddle's own average skin weights, so the pad moves as one rigid piece with the saddle and does not follow the skin underneath
    SW = arrays(sh["saddleShape"][1]); acc = {}
    ymax = SW["P"][:, 1].max(); xs = np.ptp(SW["P"][:, 0])
    top = np.where((np.abs(SW["P"][:, 0]) < 0.2 * xs) & (SW["P"][:, 1] > ymax - 0.25 * (ymax - SW["P"][:, 1].min())))[0]      # the seat's own top middle: the bones that carry the back, not the leg joints the flaps and straps lean on
    for v in top:
        for k in range(4): acc[int(SW["I"][v, k])] = acc.get(int(SW["I"][v, k]), 0.0) + float(SW["W"][v, k])
    top4 = sorted(acc.items(), key=lambda a: -a[1])[:4]; tot = sum(w for _, w in top4)
    rigid_w = np.array([w / tot for _, w in top4] + [0.0] * (4 - len(top4))); rigid_i = np.array([i for i, _ in top4] + [0] * (4 - len(top4)))
    print("rigid pad weights:", [(i, round(w, 3)) for i, w in zip(rigid_i, rigid_w)])
    # stiff, but not a block: the rigid back bones mixed with the game's own local weights WITHOUT the leg joints (a fully rigid pad cut through the horse's rump and flanks in the idle pose)
    import xml.etree.ElementTree as ET2
    r2 = ET2.fromstring(open(base + ".i3d", "rb").read()); nn2 = {int(g.get("nodeId")): g.get("name") for g in r2.iter("TransformGroup") if g.get("nodeId")}
    seatnode = [e for e in r2.iter("Shape") if e.get("name") == "saddleSeat"][0]
    sbind = [nn2[int(v)] for v in seatnode.get("skinBindNodeIds").split()]
    legidx = {i for i, n in enumerate(sbind) if "forLeg" in n or n.startswith("front") or n.startswith("frKnee")}
    Wmix = np.zeros((len(NP), 4)); Imix = np.zeros((len(NP), 4), int)
    rig = {int(i): float(w) for i, w in zip(rigid_i, rigid_w)}
    # the "rigid" strip along the spine takes the weights of the skin ON the spine line at the same position along the horse (not a fixed mix of bones: in the walk the trunk rolls and a fixed mix shears against the sides)
    to_saddle0 = {n: i for i, n in enumerate(sbind)}
    spine_ok = (np.abs(BP[:, 0]) < 0.03 * scale)
    def spine_weights(zv):
        cand = np.where(spine_ok & (np.abs(BP[:, 2] - zv) < 0.02 * scale))[0]
        if len(cand) == 0: return rig
        j = cand[np.argmax(BP[cand, 1])]
        d = {}
        for k in range(4):
            b_i = int(BA["I"][j, k]); w = float(BA["W"][j, k]); nme = bind[b_i]
            if w > 0 and nme in to_saddle0 and to_saddle0[nme] not in legidx: d[to_saddle0[nme]] = d.get(to_saddle0[nme], 0.0) + w
        t = sum(d.values())
        return {i: w / t for i, w in d.items()} if t > 0 else rig
    # the lower part hugs the skin: the weights of the body vertex under it (mapped to the saddle's bone list by bone name, leg bones dropped), so there is nothing to clip through while the spine rolls
    to_saddle = {n: i for i, n in enumerate(sbind)}
    bodyidx = {}
    for b_i, n in enumerate(bind):
        if n in to_saddle and to_saddle[n] not in legidx: bodyidx[b_i] = to_saddle[n]
    nearj = np.zeros(n0, int)
    for i in range(0, n0, 1000):
        nearj[i:i + 1000] = np.argmin(((bodypt[i:i + 1000, None, :] - BP[None, :, :]) ** 2).sum(2), axis=1)
    for v in range(len(NP)):
        j = nearj[srcmap[v]]; loc = {}
        for k in range(4):
            b_i = int(BA["I"][j, k]); w = float(BA["W"][j, k])
            if w > 0 and b_i in bodyidx: loc[bodyidx[b_i]] = loc.get(bodyidx[b_i], 0.0) + w
        tl = sum(loc.values())
        hrel = (NP[v, 1] - NP[:n0, 1].min()) / max(np.ptp(NP[:n0, 1]), 1e-9)
        stiff = STIFF + (1.0 - STIFF) * min(max((hrel - RIGID_FROM) / (1.0 - RIGID_FROM), 0.0), 1.0)
        rigv = spine_weights(NP[v, 2]) if stiff > 0 else rig
        mix = {i: stiff * w for i, w in rigv.items()}
        if tl > 0:
            for i, w in loc.items(): mix[i] = mix.get(i, 0.0) + (1 - stiff) * w / tl
        else:
            mix = dict(rigv)
        top = sorted(mix.items(), key=lambda a: -a[1])[:4]; t = sum(w for _, w in top)
        for k, (i, w) in enumerate(top): Imix[v, k] = i; Wmix[v, k] = w / t
    NA = dict(P=NP, N=NN, Tg=NTg, U=NUf, W=Wmix, I=Imix)
    # the saddle's girth straps and buckles lie on the horse's skin where the pad is now: pull every saddle vertex that sits inside the pad's thickness out to just above the pad (fading out at the pad's edge)
    SAD = arrays(seat); sadcache = os.path.join(here, "..", "blanket_old", name + "_saddle.npz")
    if os.path.exists(sadcache):
        z = np.load(sadcache)
        SAD["P"] = z["P"]                                                    # (the saddle as the game made it, before any pull-out)
        if "W" in z.files: SAD["W"], SAD["I"] = z["W"], z["I"]
        else: np.savez(sadcache, P=z["P"], W=SAD["W"], I=SAD["I"])
    else: np.savez(sadcache, P=SAD["P"], W=SAD["W"], I=SAD["I"])
    SAD["W"], SAD["I"] = SAD["W"].copy(), SAD["I"].copy()
    # the two khaki billet pieces of the old pad frame (the vertices appended to the game's saddle: numbers >= SADDLE_ORIG_VERTS) are deleted: with the new pad they hang there for no reason
    if len(SAD["P"]) > SADDLE_ORIG_VERTS:
        keept = (SAD["T"] < SADDLE_ORIG_VERTS).all(1)
        for k_ in ("P", "N", "Tg", "U", "W", "I"): SAD[k_] = SAD[k_][:SADDLE_ORIG_VERTS]
        SAD["T"] = SAD["T"][keept]
        print("saddle: the old billet pieces are deleted (%d triangles)" % (~keept).sum())
    padtop = NPo; padn = SN[uv]; ht = ((NPo - bodypt) * padn).sum(1)
    # distance (over the sheet) of every pad vertex from the pad's edge: the push fades to zero across the last EDGE_FADE of it, so whatever hangs over the edge (the stirrup leather) keeps its own shape
    ec2 = {}
    for a_, b_, c_ in topT:
        for u_, v_ in ((a_, b_), (b_, c_), (c_, a_)):
            kk_ = (min(u_, v_), max(u_, v_)); ec2[kk_] = ec2.get(kk_, 0) + 1
    edist = np.full(n0, np.inf); pq2 = []
    for (u_, v_), c_ in ec2.items():
        if c_ == 1:
            for x_ in (u_, v_):
                if edist[x_] > 0: edist[x_] = 0.0; pq2.append((0.0, int(x_)))
    heapq.heapify(pq2)
    while pq2:
        dd_, i_ = heapq.heappop(pq2)
        if dd_ > edist[i_]: continue
        for j_, l_ in adj[i_]:
            if dd_ + l_ < edist[j_]: edist[j_] = dd_ + l_; heapq.heappush(pq2, (dd_ + l_, j_))
    efade = np.clip(edist / (EDGE_FADE * scale), 0.0, 1.0)
    # the girth band's vertices (UV island u 0.20..0.31, v < 0.41, 54 vertices per side) are exempt from the edge fade: the girth always lies OVER the blanket
    par0 = list(range(len(SAD["P"])))
    def find0(a):
        while par0[a] != a: par0[a] = par0[par0[a]]; a = par0[a]
        return a
    for a_, b_, c_ in SAD["T"]:
        ra_, rb_, rc_ = find0(a_), find0(b_), find0(c_); par0[rb_] = ra_; par0[rc_] = ra_
    isl0 = np.array([find0(i_) for i_ in range(len(SAD["P"]))])
    girth_set = set()
    for root_ in np.unique(isl0):
        idx0 = np.where(isl0 == root_)[0]; uv0 = SAD["U"][idx0]
        if len(idx0) == 54 and 0.20 <= uv0[:, 0].min() and uv0[:, 0].max() <= 0.31 and uv0[:, 1].max() < 0.41: girth_set.update(int(i_) for i_ in idx0)
    P_base = SAD["P"].copy()                     # (the game's saddle positions, before any pull-out)
    import stirrup_bones as SB0
    stirrup_sets_ = SB0.stirrup_sets(SAD, P_base, scale)
    stirrup_all = set(int(v) for B_, S_ in stirrup_sets_.values() for v in np.concatenate([B_, S_]))
    moved = 0; shared = 0; maxpush = 0.0; pushvec = np.zeros_like(SAD["P"])
    for v in range(len(SAD["P"])):
        pv = SAD["P"][v]
        d2 = ((padtop - pv) ** 2).sum(1); j = int(np.argmin(d2))
        if d2[j] > (0.07 * scale) ** 2: continue
        q, n = bodypt[j], padn[j]
        rel = pv - q; h = float(rel @ n); tang = float(np.linalg.norm(rel - h * n))
        w = min(max(1.0 - (tang - 0.02 * scale) / (0.03 * scale), 0.0), 1.0)
        push = max(0.0, ht[j] + SADDLE_GAP * scale - h) * w * (1.0 if v in girth_set else efade[j])
        if push > 0 and h > -0.02 * scale:
            SAD["P"][v] = pv + n * push; pushvec[v] = n * push; moved += 1; maxpush = max(maxpush, push)
        # saddle and pad share the pad's skin weights where they overlap (the game's saddle weights include the leg joints: in the walk the saddle leather cut through the pad)
        share = 0.0 if v in stirrup_all else w * (1.0 if v in girth_set else efade[j]) * min(max(1.0 - (h - ht[j]) / (0.05 * scale), 0.0), 1.0) if h > -0.02 * scale else 0.0
        if share > 0:
            mix = {}
            for k in range(4):
                if SAD["W"][v, k] > 0: mix[int(SAD["I"][v, k])] = mix.get(int(SAD["I"][v, k]), 0.0) + (1 - share) * float(SAD["W"][v, k])
                if Wmix[j, k] > 0: mix[int(Imix[j, k])] = mix.get(int(Imix[j, k]), 0.0) + share * float(Wmix[j, k])
            top = sorted(mix.items(), key=lambda a: -a[1])[:4]; tt = sum(x for _, x in top)
            for k in range(4):
                if k < len(top): SAD["I"][v, k] = top[k][0]; SAD["W"][v, k] = top[k][1] / tt
                else: SAD["W"][v, k] = 0.0
            shared += 1
    # small parts (buckles, billet ends) move as ONE rigid unit: the same push and the same skin weights for every vertex of the piece, or they are stretched and bent (that was the weird detail at the girth)
    import split_tack as ST
    comp = ST.components(SAD["P"] - pushvec, SAD["T"])
    rigid_n = 0
    for c in np.unique(comp):
        idx = np.where(comp == c)[0]
        q = (SAD["P"] - pushvec)[idx]
        if np.linalg.norm(q.max(0) - q.min(0)) > SMALL_PART * scale or np.linalg.norm(pushvec[idx], axis=1).max() == 0: continue
        k = idx[np.argmax(np.linalg.norm(pushvec[idx], axis=1))]
        SAD["P"][idx] = (SAD["P"] - pushvec)[idx] + pushvec[k]
        SAD["W"][idx] = SAD["W"][k]; SAD["I"][idx] = SAD["I"][k]; rigid_n += 1
    print("saddle: %d small parts moved as one rigid piece" % rigid_n)
    import stirrup_bones as SB
    # the riding pose: the iron under the rider's foot (measured with hdStirrup measure: dev/foal/stirrup_feet.json); the game's flat hanging iron stays the leading pose
    import json
    feetall = json.load(open(os.path.join(here, "..", "stirrup_feet.json")))
    poses = SB.ride_pose(P_base, stirrup_sets_, os.path.join(base + ".i3d"), feetall.get(name), feetall.get("sole", 0.045))
    pj = os.path.join(here, "..", "stirrup_pose.json")
    allp = json.load(open(pj)) if os.path.exists(pj) else {}
    allp[name] = {("L" if sd > 0 else "R"): v_ for sd, v_ in poses.items()}
    json.dump(allp, open(pj, "w"), indent=1)
    with open(os.path.join(here, "..", "..", "..", "scripts", "HorseStirrupPose.lua"), "w") as lf:
        lf.write("-- generated by dev/foal/tools/rebuild_blanket.py (stirrup_bones.ride_pose): the RIDING pose of each stirrup bone (the iron under the rider's foot) as a local translation (q is the identity), c = the iron's centre relative to the pivot\nHorseStirrup = HorseStirrup or {}\nHorseStirrup.POSES = {\n")
        for mname, sides in allp.items():
            lf.write("    %s = {\n" % mname)
            for tag, v_ in sides.items():
                lf.write("        %s = { q = { %s }, t = { %s }, c = { %s } },\n" % (tag, ", ".join("%.6f" % x_ for x_ in v_["q"]), ", ".join("%.6f" % x_ for x_ in v_["t"]), ", ".join("%.6f" % x_ for x_ in v_["c"])))
            lf.write("    },\n")
        lf.write("}\n")
    for sd, v_ in poses.items(): print("saddle: stirrup riding pose " + ("L" if sd > 0 else "R") + ": " + v_["info"])
    for line_ in SB.apply(SAD, P_base, stirrup_sets_, os.path.join(base + ".i3d"), scale): print("saddle: stirrups: " + line_)
    # the girth band (the saddle's UV island u 0.21..0.30, v < 0.40, 54 vertices per side) ends low on the flank: extend it up along the pad, 1 cm above it, until it disappears under the saddle flap (the blanket lies under the girth)
    par_ = list(range(len(SAD["P"])))
    def find_(a):
        while par_[a] != a: par_[a] = par_[par_[a]]; a = par_[a]
        return a
    for a_, b_, c_ in SAD["T"]:
        ra_, rb_, rc_ = find_(a_), find_(b_), find_(c_); par_[rb_] = ra_; par_[rc_] = ra_
    isl_ = np.array([find_(i_) for i_ in range(len(SAD["P"]))])
    ext_added = 0
    for root_ in (np.unique(isl_) if GIRTH_EXTEND else []):
        idx = np.where(isl_ == root_)[0]
        uvq = SAD["U"][idx]
        if len(idx) != 54 or not (0.20 <= uvq[:, 0].min() and uvq[:, 0].max() <= 0.31 and uvq[:, 1].max() < 0.41): continue
        # the band's texture runs along its length: v changes with the height; the extension continues that, mirrored back into the band's own v range (the grain is lengthwise, so the repeat does not show)
        vmin_, vmax_ = SAD["U"][idx][:, 1].min(), SAD["U"][idx][:, 1].max()
        slope_ = np.polyfit(SAD["P"][idx][:, 1], SAD["U"][idx][:, 1], 1)[0]
        def reflect_(v_):
            L_ = vmax_ - vmin_; t_ = (v_ - vmin_) % (2 * L_)
            return vmin_ + (t_ if t_ <= L_ else 2 * L_ - t_)
        side = 1.0 if SAD["P"][idx][:, 0].mean() > 0 else -1.0
        ytop = SAD["P"][idx][:, 1].max()
        # the whole top edge across the band's width: in each of GIRTH_COLS slices along z the highest vertex
        zq = SAD["P"][idx][:, 2]; edges_ = np.linspace(zq.min() - 1e-6, zq.max() + 1e-6, GIRTH_COLS + 1)
        pick_ = []
        for a_, b_ in zip(edges_[:-1], edges_[1:]):
            sel_ = idx[(zq >= a_) & (zq < b_)]
            if len(sel_): pick_.append(sel_[np.argmax(SAD["P"][sel_][:, 1])])
        top = np.array(sorted(set(int(v) for v in pick_), key=lambda v: SAD["P"][v][2]))
        padv = np.where(np.sign(NPo[:, 0]) == side)[0]
        rows = [top]
        for k in range(1, GIRTH_ROWS + 1):
            frac = k / GIRTH_ROWS
            new = []
            for t_ in top:
                z0, y0 = SAD["P"][t_][2], SAD["P"][t_][1]
                yk = y0 + k * GIRTH_STEP * scale
                j = padv[np.argmin((NPo[padv, 2] - z0) ** 2 + (NPo[padv, 1] - yk) ** 2)]
                lift0 = float(((SAD["P"][t_] - NPo[j]) * NN[j]).sum())
                pos = NPo[j] + NN[j] * ((1 - frac) * max(lift0, 0.0) + frac * GIRTH_LIFT * scale)
                wmap = {}
                for kk in range(4):
                    if SAD["W"][t_, kk] > 0: wmap[int(SAD["I"][t_, kk])] = wmap.get(int(SAD["I"][t_, kk]), 0.0) + (1 - frac) * float(SAD["W"][t_, kk])
                    if Wmix[j, kk] > 0: wmap[int(Imix[j, kk])] = wmap.get(int(Imix[j, kk]), 0.0) + frac * float(Wmix[j, kk])
                tw = sorted(wmap.items(), key=lambda a: -a[1])[:4]; tt_ = sum(x_ for _, x_ in tw)
                wv = np.zeros(4); iv = np.zeros(4, int)
                for kk, (i_, w_) in enumerate(tw): iv[kk] = i_; wv[kk] = w_ / tt_
                n_idx = len(SAD["P"])
                SAD["P"] = np.vstack([SAD["P"], pos]); SAD["N"] = np.vstack([SAD["N"], NN[j]]); SAD["Tg"] = np.vstack([SAD["Tg"], SAD["Tg"][t_]])
                SAD["U"] = np.vstack([SAD["U"], [SAD["U"][t_][0], reflect_(SAD["U"][t_][1] + slope_ * (pos[1] - SAD["P"][t_][1]))]]); SAD["W"] = np.vstack([SAD["W"], wv]); SAD["I"] = np.vstack([SAD["I"], iv])
                new.append(n_idx)
            rows.append(np.array(new))
        tris_ = []
        for r0, r1 in zip(rows[:-1], rows[1:]):
            for a_ in range(len(r0) - 1):
                q = [r0[a_], r0[a_ + 1], r1[a_ + 1], r1[a_]]
                for tri_ in ((q[0], q[1], q[2]), (q[0], q[2], q[3])):
                    nrm = np.cross(SAD["P"][tri_[1]] - SAD["P"][tri_[0]], SAD["P"][tri_[2]] - SAD["P"][tri_[0]])
                    tris_.append(tri_ if nrm @ SAD["N"][tri_[0]] >= 0 else (tri_[0], tri_[2], tri_[1]))
        SAD["T"] = np.vstack([SAD["T"], np.array(tris_)])
        ext_added += 1
    print("saddle: the girth is extended up under the flap on %d side(s)" % ext_added)
    entity(sf, ks, seat, SAD, SAD["T"])
    print("saddle: %d vertices pulled out over the pad (largest %.1f mm), %d share the pad's skin weights" % (moved, maxpush * 1000, shared))
    entity(sf, kb, blanket, NA, NT)
    S.write(shapes_path, sf)
    print("%s: blanket = %d triangles, %d vertices, lifted %.1f mm (scale %.2f)" % (name, len(NT), len(NP), lift * 1000, scale))

if __name__ == "__main__":
    main(sys.argv[1])
