#!/usr/bin/env python3
"""Draws the saddle's PANELS into a baked horse model (after split_tack.py and rebuild_blanket.py): two stuffed pillows left and right of the spine with the gullet (a channel) between them, lying on the pad and going down the flanks (the thick parts that carry the flaps),
as the skinned shape `panel` (child of the saddle group, last). Bottom up: the panel is the first thing of the saddle that touches the blanket; the seat and the flaps come on top of it.
The panel's underside follows the pad's top surface (a radius field round the barrel's axis made of the blanket's outward vertices), its top is a pillow (flat top, round edges). Skin weights are copied from the nearest pad vertex, so it moves with the pad.
  python3 add_panel.py models/horse/horseAdult           (the same folder + name as split_tack.py; run again to redraw the shape in place)
Shown and hidden by the tack piece `panel` (HorseTack: bit 16, console: hdTack panel on|off)."""
import sys, os, re, copy, math
import numpy as np
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here); sys.path.insert(0, os.path.join(here, "..", "..", "..", "tools"))
import shapes_io as S
import make_hitching_post as H
import make_horse_sulky as K

Z0, Z1 = -0.06, 0.46                      # the panel's rear and front end (horse coordinates, adult), along the horse
GULLET = 0.030                            # half width of the channel between the panels (metres from the spine at the top)
WING_U = 0.12                             # the foot's lower edge is a shallow U: at its rear and front end it stops this much higher (radians) than in the middle (the flap on top covers the rest)
PHI_STEM = 0.42                           # the panel is an L in plan: a stem along the gullet (this wide, radians round the barrel from the spine) ...
FOOT = (0.60, 0.76)                       # ... and a foot at the front that goes out and down the flank (from WING): the foot grows between these two points along the panel (0 = rear end, 1 = front end)
WING = 1.74                               # how far down the flanks the foot goes at its widest: the angle (radians) round the barrel from the spine, 1.57 = level with the barrel's axis
AXIS_Y = 1.38                             # the height of the barrel's axis the angles are measured round (the pad's cross section is about a circle of this centre)
THICK_BACK = 0.030                        # the stem along the gullet is a thick padded roll (the dark L of the reference photo) ... 
THICK_FLANK = 0.038                       # ... and so is the foot at the front
BEND = (0.30, 0.75)                       # the corner of the L: the thickness grows between these two angles round the barrel (radians from the spine)
LIFT = 0.001                              # the underside floats this much above the pad's top (no z-fighting)
NU, NV = 30, 36                           # grid across / along
EDGE_POWER = 4.0                          # the pillow's profile: (1 - |t|^p)^0.5, flat on top, round at the edges
SEAT_MARGIN = 0.004                       # the stem's top stays this far below the saddle's top where the seat lies over it (the panel never pokes out at the wrist)
PANEL_RED = False                         # True: plain red for fitting (a material without texture), False: the saddle's suede lining
PANEL_UV = (0.955, 0.50)                  # a plain patch of the suede lining in the saddle's diffuse texture (the light taupe frame right of the seat)
PANEL_MAT = '<Material name="panel_mat" materialId="6" diffuseColor="0.85 0.05 0.05 1">\n    </Material>'      # plain red while it is being fitted (no texture)
FRONT_MARGIN = 0.006                      # the panel's front end lies this far inside the saddle's front contour (taken from the saddle's own vertices at every angle round the barrel)
PANEL_SKIN = "body"                       # "body" or "spine": what the panel is skinned to over the back
SPINE_FULL, SPINE_FREE = 1.0, 1.6              # angle round the barrel (radians): 100 % back bone up to the first, the pad's own weights from the second
FRONT_SLOPE = 0.04                        # metres of front edge per radian at most
FRONT_SQUARE = 0.04                       # the front end is square (the flap's front edge is a straight line): it rounds off only in the last 4 % of the length
END_SHAPE = 0.18                          # how far the ends pinch in (the panel's outline is a rounded rectangle)

def load(sf, name):
    for k, e in enumerate(sf.entities):
        if e.entity_type.name == "SHAPE":
            s = S.M.parse_shape_entity(e, sf.header.version)
            if s.name == name: return k, s
    return None, None

def arrays(s):
    return dict(P=np.array([[p.x, p.y, p.z] for p in s.positions]), N=np.array([[p.x, p.y, p.z] for p in s.normals]), U=np.array([[u.u, u.v] for u in s.uv_sets[0]]),
                W=np.array(s.blend_weights), I=np.array(s.blend_indices))

def radius_field(P, N):
    """r of the pad's outer surface at (angle, z): the distance from the barrel's axis (x = 0, y = AXIS_Y) of the nearest outward vertices (inverse distance weighting in angle * 0.4 m and z)"""
    rel = np.stack([P[:, 0], P[:, 1] - AXIS_Y], 1); r = np.linalg.norm(rel, axis=1)
    out = (N[:, 0] * rel[:, 0] + N[:, 1] * rel[:, 1]) / np.maximum(r, 1e-9) > 0.3
    phi = np.arctan2(rel[:, 0], rel[:, 1])
    pts = np.stack([phi[out] * 0.4, P[out, 2]], 1); rr = r[out]
    def r_at(ph, z):
        d = (pts[:, 0] - ph * 0.4) ** 2 + (pts[:, 1] - z) ** 2
        k = np.argpartition(d, 6)[:6]; w = 1.0 / (d[k] + 1e-6)
        return float((rr[k] * w).sum() / w.sum())
    return r_at

def profile(t):
    """0..1 across a pillow (t in 0..1): flat on top, round at both edges"""
    a = abs(2 * t - 1)
    return math.sqrt(max(0.0, 1.0 - a ** EDGE_POWER))

def main(base):
    shapes_path, i3d_path = base + ".i3d.shapes", base + ".i3d"
    xml = open(i3d_path, "rb").read().decode("latin-1")
    assert 'name="blanket"' in xml, "run split_tack.py and rebuild_blanket.py first"
    if PANEL_RED:
        if 'name="panel_mat"' not in xml:
            xml = xml.replace('</Materials>', '  ' + PANEL_MAT + '\n  </Materials>', 1)
        xml = re.sub(r'(<Shape name="panel" [^>]*?materialIds=")\d+(")', r'\g<1>6\2', xml)
    else:                                                                       # the saddle's own material (its texture has the suede lining of the panels)
        xml = re.sub(r'(<Shape name="panel" [^>]*?materialIds=")\d+(")', r'\g<1>%s\2' % re.search(r'name="saddleSeat"[^>]*materialIds="(\d+)"', xml).group(1), xml)
    open(i3d_path, "wb").write(xml.encode("latin-1"))
    raw, sf = S.read(shapes_path)
    kb, blanket = load(sf, "blanketShape"); ks, seat = load(sf, "saddleShape")
    B = arrays(blanket); Sd = arrays(seat)
    r_at = radius_field(B["P"], B["N"])
    topmask = B["N"][:, 1] > 0.5
    SP = Sd["P"][(Sd["P"][:, 1] > 1.5) & (np.abs(Sd["P"][:, 0]) < 0.15)]
    SEAT_END = float(SP[:, 2].max())                                      # the seat's furthest forward vertex over the middle
    def seat_top(z):
        """the saddle's top height along its middle at z (None where the seat is not over the middle: in front of the tree)"""
        m = np.abs(SP[:, 2] - z) < 0.03
        return float(SP[m, 1].max()) if m.any() else None
    # the front end follows the saddle's own front contour: the furthest forward point of the saddle at each angle round the barrel (the flap's front edge, the seat's front over the middle), less a few millimetres
    SA = Sd["P"][Sd["P"][:, 1] > 1.0]
    sphi = np.arctan2(np.abs(SA[:, 0]), SA[:, 1] - AXIS_Y)
    centres = np.arange(0.1, 2.15, 0.1); fronts = []
    for c in centres:
        band = (sphi >= c - 0.12) & (sphi < c + 0.12)
        fronts.append(float(SA[band, 2].max()) - (FRONT_MARGIN * 2 if c < 0.55 else FRONT_MARGIN) if band.any() else None)
    known = [(c, f) for c, f in zip(centres, fronts) if f is not None]
    # the front may change by at most FRONT_SLOPE metres per radian (a steeper edge makes the grid rows cross, folded triangles are culled and show as black slits): a running minimum both ways
    grid_phi = np.arange(0.0, 2.2, 0.02)
    grid_f = np.minimum(Z1, np.interp(grid_phi, [c for c, _ in known], [f for _, f in known]))
    for k in range(1, len(grid_f)):
        grid_f[k] = min(grid_f[k], grid_f[k - 1] + FRONT_SLOPE * 0.02)
    for k in range(len(grid_f) - 2, -1, -1):
        grid_f[k] = min(grid_f[k], grid_f[k + 1] + FRONT_SLOPE * 0.02)
    def front_at(phi):
        return float(np.interp(phi, grid_phi, grid_f))
    TP, TW, TI = B["P"][topmask], B["W"][topmask], B["I"][topmask]
    mesh = H.Mesh(); skinW, skinI = [], []
    # the panel is skinned to the BACK BONE, as the saddle on top of it is (rigid on Spine1_M): the vertebrae do not move when the horse breathes, the belly does (belly1_M). Over the back (angle up to SPINE_FULL) it is 100 % Spine1_M, towards the flank
    # (to SPINE_FREE) it blends into the pad's own weights, so its lower edge still follows the barrel
    blanket_ids = [int(v) for v in re.search(r'<Shape name="blanket"[^>]*skinBindNodeIds="([^"]*)"', xml).group(1).split()]
    spine_id = int(re.search(r'<TransformGroup name="Spine1_M"[^>]*nodeId="(\d+)"', xml).group(1)); SPINE = blanket_ids.index(spine_id)
    # PANEL_SKIN = "body": over the back the panel takes the skin weights of the nearest BODY vertex (its top line then moves with the horse's own back, to the millimetre); "spine": all Spine1_M (rigid like the saddle)
    body_ids = [int(v) for v in re.search(r'<Shape name="body"[^>]*skinBindNodeIds="([^"]*)"', xml).group(1).split()]
    to_panel = {i: blanket_ids.index(nid) for i, nid in enumerate(body_ids) if nid in blanket_ids}
    _, bodyshape = load(sf, "bodyShape"); BD = arrays(bodyshape)
    back = np.where(BD["P"][:, 1] > 1.35)[0]
    def body_weights(p):
        k = back[int(np.argmin(((BD["P"][back] - np.array(p)) ** 2).sum(1)))]
        d = {}
        for wv, iv in zip(BD["W"][k], BD["I"][k]):
            if wv > 0 and int(iv) in to_panel: d[to_panel[int(iv)]] = d.get(to_panel[int(iv)], 0.0) + float(wv)
        tot = sum(d.values())
        return {i: v / tot for i, v in d.items()} if tot > 0 else {SPINE: 1.0}
    def spine_blend(p, tw, ti):
        ph = math.atan2(abs(p[0]), p[1] - AXIS_Y)
        t = min(1.0, max(0.0, (ph - SPINE_FULL) / (SPINE_FREE - SPINE_FULL))); t = t * t * (3 - 2 * t)         # 0 = the back's skin, 1 = the pad's weights
        d = {}
        for wv, iv in zip(tw, ti):
            if wv > 0: d[int(iv)] = d.get(int(iv), 0.0) + float(wv) * t
        back_w = body_weights(p) if PANEL_SKIN == "body" else {SPINE: 1.0}
        for iv, wv in back_w.items(): d[iv] = d.get(iv, 0.0) + wv * (1.0 - t)
        top4 = sorted(d.items(), key=lambda a: -a[1])[:4]; tot = sum(v for _, v in top4)
        top4 += [(0, 0.0)] * (4 - len(top4))
        return tuple(v / tot for _, v in top4), tuple(i for i, _ in top4)
    uv = PANEL_UV if not PANEL_RED else tuple(np.median(Sd["U"], axis=0))

    def surface(sign, top):
        """one pillow (sign +1 left, -1 right), its top (or its underside) as a grid in (angle round the barrel, z); lies on the pad and goes down the flank"""
        grid = []
        pos = np.zeros((NV + 1, NU + 1, 3))
        for j in range(NV + 1):
            v = j / NV
            if v < 0.5:                                                    # rear end: rounded
                reach = END_SHAPE + (1 - END_SHAPE) * math.sqrt(max(0.0, 1.0 - abs(2 * v - 1) ** 6))
            else:                                                          # front end: square, rounded only at the very end
                reach = 1.0 - (1.0 - END_SHAPE) * max(0.0, (v - (1.0 - FRONT_SQUARE)) / FRONT_SQUARE) ** 2
            phi_g = math.asin(min(0.9, GULLET / 0.31))
            f = min(1.0, max(0.0, (v - FOOT[0]) / (FOOT[1] - FOOT[0]))); f = f * f * (3 - 2 * f)
            tt = min(1.0, max(0.0, (v - FOOT[0]) / (1.0 - FOOT[0])))
            wing = WING - WING_U * (2 * tt - 1) ** 2
            phi_max = phi_g + (PHI_STEM + (wing - PHI_STEM) * f - phi_g) * reach
            for i in range(NU + 1):
                u = i / NU; ph = sign * (phi_g + (phi_max - phi_g) * u)
                zend = front_at(abs(ph))
                z = Z0 + (zend - Z0) * v
                rb = r_at(ph, z) + LIFT
                t = min(1.0, max(0.0, (abs(ph) - BEND[0]) / (BEND[1] - BEND[0]))); t = t * t * (3 - 2 * t)
                h = (THICK_BACK + (THICK_FLANK - THICK_BACK) * t) * profile(u) * profile(v) if top else 0.0
                r = rb + h
                if top and abs(ph) < 1.1:
                    fz = min(1.0, max(0.0, (SEAT_END + 0.03 - z) / 0.03)); fz = fz * fz * (3 - 2 * fz)      # the seat's last 3 cm: the stem's thickness fades out in front of it (no step: a step folds the grid)
                    fphi = min(1.0, max(0.0, (abs(ph) - 0.55) / 0.55)); fphi = fphi * fphi * (3 - 2 * fphi)  # (the foot, further down, keeps its thickness)
                    r = rb + (r - rb) * (fphi + (1.0 - fphi) * fz)
                    if abs(ph) < 0.9 and fz > 0:
                        yt = seat_top(min(z, SEAT_END))
                        if yt is not None:
                            r = max(rb, min(r, (yt - SEAT_MARGIN - AXIS_Y) / math.cos(ph)))
                pos[j, i] = (r * math.sin(ph), AXIS_Y + r * math.cos(ph), z)
        # normals from the grid (the top's point away from the barrel's axis, the underside's towards it)
        nrm = np.zeros_like(pos)
        for j in range(NV + 1):
            for i in range(NU + 1):
                du = pos[j, min(i + 1, NU)] - pos[j, max(i - 1, 0)]; dv = pos[min(j + 1, NV), i] - pos[max(j - 1, 0), i]
                n = np.cross(dv, du); l = np.linalg.norm(n)
                n = n / l if l > 1e-12 else np.array([0.0, 1.0, 0.0])
                radial = np.array([pos[j, i, 0], pos[j, i, 1] - AXIS_Y, 0.0])
                if n @ radial < 0: n = -n
                nrm[j, i] = n if top else -n
        for j in range(NV + 1):
            row = []
            for i in range(NU + 1):
                p = pos[j, i]; n = nrm[j, i]
                idx = mesh.vert(tuple(p), tuple(n), uv)
                k = int(np.argmin(((TP - p) ** 2).sum(1)))
                w, ix = spine_blend(p, TW[k], TI[k])
                skinW.append(w); skinI.append(ix)
                row.append(idx)
            grid.append(row)
        for j in range(NV):
            for i in range(NU):
                K.oquad(mesh, grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])
        return grid

    for sign in (1, -1):
        surface(sign, True)
        surface(sign, False)
    P = list(mesh.p); N = list(mesh.n); Tr = [i for t in mesh.t for i in t]
    UV = [uv] * len(P)
    Tg = []
    for n in N:
        u, _ = K.frame_of(K.norm(n)); Tg.append((u[0], u[1], u[2], 1.0))
    s0 = seat.subsets[0]
    kp, panel = load(sf, "panelShape")
    sid = panel.id if panel is not None else max(int(x) for x in re.findall(r'shapeId="(\d+)"', xml)) + 1
    ent = H.shape_entity("panelShape", sid, P, N, UV, Tr, [(0, len(P), 0, len(Tr), s0.uv_density1)], seat.material_slot_names, tangents=Tg, skin=(skinW, skinI))
    if kp is not None:
        sf.entities[kp].data = ent
        print("panel redrawn in place: %d vertices, %d triangles" % (len(P), len(Tr) // 3))
    else:
        e_new = copy.copy(sf.entities[ks]); e_new.data = ent
        sf.entities.append(e_new)
        m = re.search(r'([ \t]*)<Shape name="halter" ([^>]*?)/>', xml)
        assert m is not None, "run add_halter.py first (the panel goes in after the halter)"
        node_id = max(int(x) for x in re.findall(r'nodeId="(\d+)"', xml)) + 1
        attrs = re.sub(r'shapeId="\d+"', 'shapeId="%d"' % sid, m.group(2)); attrs = re.sub(r'nodeId="\d+"', 'nodeId="%d"' % node_id, attrs)
        attrs = re.sub(r'visibility="[^"]*"\s*', "", attrs); attrs = re.sub(r'materialIds="\d+"', 'materialIds="6"', attrs)
        xml = xml.replace(m.group(0), '%s<Shape name="halter" %s/>\n%s<Shape name="panel" visibility="false" %s />' % (m.group(1), m.group(2), m.group(1), attrs), 1)
        open(i3d_path, "wb").write(xml.encode("latin-1"))
        print("panel added: %d vertices, %d triangles, shape %d" % (len(P), len(Tr) // 3, sid))
    S.write(shapes_path, sf)

if __name__ == "__main__":
    main(sys.argv[1])
