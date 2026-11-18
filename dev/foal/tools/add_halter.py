#!/usr/bin/env python3
"""Draws the halter's own parts into a baked horse model (after split_tack.py): ONE clean cheek strap per side (the bridle's cheek strap is doubled and carries the bit) and a ring under the chin for the lead rope, as a skinned shape
`halter` (child of the saddle group, last), plus the node `halterRing` (child of Head_M, last) the lead is tied to.
The strap follows the centre line of the model's own cheek shape (so a foal's smaller head works), the ring hangs under the noseband's lowest point at the middle; skin weights are copied from the nearest bridle vertex.
  python3 add_halter.py models/horse/horseAdult     (the same folder + name as split_tack.py)"""
import sys, os, re, copy, math
import numpy as np
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here); sys.path.insert(0, os.path.join(here, "..", "..", "..", "tools"))
import shapes_io as S
import make_hitching_post as H
import make_horse_sulky as K
import split_tack as ST
import add_attach_nodes as AN

STRAP_W, STRAP_T = 0.0125, 0.0028          # half width / half thickness of a strap at the game's size
RING_R, RING_TUBE = 0.024, 0.0032          # ring radius (centre line of the tube) and tube radius
STATIONS = 14

def load(sf, name):
    for k, e in enumerate(sf.entities):
        if e.entity_type.name == "SHAPE":
            s = S.M.parse_shape_entity(e, sf.header.version)
            if s.name == name: return k, s
    raise SystemExit("no shape " + name)

def arrays(s):
    return dict(P=np.array([[p.x, p.y, p.z] for p in s.positions]), U=np.array([[u.u, u.v] for u in s.uv_sets[0]]),
                W=np.array(s.blend_weights), I=np.array(s.blend_indices))

def centreline(pts):
    """pts: the vertices of one cheek strap. Ordered along their long axis (top first), STATIONS means."""
    c = pts.mean(0); u, sv, vt = np.linalg.svd(pts - c, full_matrices=False); ax = vt[0]
    if ax[1] < 0: ax = -ax
    s = (pts - c) @ ax
    edges = np.linspace(s.min(), s.max(), STATIONS + 1)
    path = []
    for a, b in zip(edges[:-1], edges[1:]):
        m = (s >= a) & (s <= b)
        if m.sum() == 0: m = np.abs(s - (a + b) / 2) < (b - a)
        path.append(pts[m].mean(0))
    path = np.array(path)
    sm = path.copy()
    for i in range(1, len(path) - 1): sm[i] = (path[i - 1] + 2 * path[i] + path[i + 1]) / 4
    return sm, float(s.max() - s.min())

def main(base):
    shapes_path, i3d_path = base + ".i3d.shapes", base + ".i3d"
    xml = open(i3d_path, "rb").read().decode("latin-1")
    if 'name="halter"' in xml:
        print("halter already added:", base); return
    assert 'name="cheek"' in xml, "run split_tack.py first"
    raw, sf = S.read(shapes_path)
    _, bridle = load(sf, "bridleShape"); _, cheek = load(sf, "cheekShape"); _, bit = load(sf, "bitShape")
    B, C = arrays(bridle), arrays(cheek)
    # scale of this model's head against the game's: the cheek strap's length
    graw, gsf = S.read(ST.GAME_SHAPES)
    gsh = [s for s in (S.M.parse_shape_entity(e, gsf.header.version) for e in gsf.entities if e.entity_type.name == "SHAPE") if s.name == "saddleShape"][0]
    GP = np.array([[p.x, p.y, p.z] for p in gsh.positions]); gtri = np.array([[t.p1 - 1, t.p2 - 1, t.p3 - 1] for t in gsh.triangles])
    head = ST.head_vertices(GP, gtri); bt = ST.bit_triangles(GP, gtri, head); fl, _ = ST.cheek_flags(GP, gtri, head)
    ch = np.zeros(len(gtri), bool); ch[np.where(bt)[0][fl]] = True
    gv = np.unique(gtri[ch].reshape(-1)); _, glen = centreline(GP[gv][GP[gv][:, 0] > 0])
    mesh = H.Mesh()
    skinW, skinI = [], []
    allP = np.vstack([B["P"], C["P"]]); allW = np.vstack([B["W"], C["W"]]); allI = np.vstack([B["I"], C["I"]])
    def skin_of(p, pool=None):
        P, Wt, It = (allP, allW, allI) if pool is None else pool
        j = int(np.argmin(((P - p) ** 2).sum(1))); return Wt[j], It[j]
    uv = tuple(np.median(C["U"], axis=0))
    def vert(p, n, tang, side_pool=None):
        i = mesh.vert(tuple(p), tuple(n), uv)
        w, ix = skin_of(p, side_pool)
        skinW.append(tuple(w)); skinI.append(tuple(ix)); return i
    scale = None
    for sign in (1, -1):
        side = C["P"][np.sign(C["P"][:, 0]) == sign]
        path, length = centreline(side)
        if scale is None: scale = length / glen
        pool = (side, C["W"][np.sign(C["P"][:, 0]) == sign], C["I"][np.sign(C["P"][:, 0]) == sign])
        hw, ht = STRAP_W * scale, STRAP_T * scale
        frames = []
        for i, p in enumerate(path):
            t = path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]; t = np.array(K.norm(tuple(t)))
            n = np.array([sign, 0.0, 0.0]); n = n - t * (n @ t); n = np.array(K.norm(tuple(n)))
            w = np.array(K.cross(tuple(t), tuple(n)))
            frames.append((p, t, n, w))
        faces = [(+1, 0), (-1, 0), (0, +1), (0, -1)]          # (normal along n, normal along w)
        for fn, fw in faces:
            rows = []
            for p, t, n, w in frames:
                nn = n * fn + w * fw
                a = p + n * ht * fn * (1 if fn else 0) + w * hw * fw * (1 if fw else 0)
                if fn: o1, o2 = a - w * hw, a + w * hw
                else: o1, o2 = a - n * ht, a + n * ht
                rows.append((vert(o1, nn, t, pool), vert(o2, nn, t, pool)))
            for i in range(len(rows) - 1):
                K.oquad(mesh, rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0])
    # the ring: under the lowest point of the noseband at the middle (the plane through the strap direction, hanging on it)
    mid = B["P"][np.abs(B["P"][:, 0]) < 0.02 * scale]
    low = mid[np.argmin(mid[:, 1])]
    R, r = RING_R * scale, RING_TUBE * scale
    centre = low + np.array([0.0, -(R + r * 0.3), 0.0])
    K.torus_ring(mesh, tuple(centre), (0.0, 0.0, 1.0), R, r, major=24, minor=8)
    # skin of the ring's vertices: the noseband vertex nearest the hanging point
    ringpool = (B["P"], B["W"], B["I"])
    n0 = len(skinW)
    for p in mesh.p[n0:]:
        w, ix = skin_of(np.array(p), ringpool); skinW.append(tuple(w)); skinI.append(tuple(ix))
    P = list(mesh.p); N = list(mesh.n); Uv = list(mesh.uv)
    Tr = [i for t in mesh.t for i in t]
    UV = [uv] * len(P)
    # tangents: any unit vector perpendicular to the normal (the leather barely shows its normal map)
    Tg = []
    for n in N:
        u, _ = K.frame_of(K.norm(n)); Tg.append((u[0], u[1], u[2], 1.0))
    sid = max(int(x) for x in re.findall(r'shapeId="(\d+)"', xml)) + 1
    s0 = bridle.subsets[0]
    ent = H.shape_entity("halterShape", sid, P, N, UV, Tr, [(0, len(P), 0, len(Tr), s0.uv_density1)], bridle.material_slot_names, tangents=Tg, skin=(skinW, skinI))
    e_new = copy.copy(sf.entities[load(sf, "bridleShape")[0]]); e_new.data = ent
    sf.entities.append(e_new)
    S.write(shapes_path, sf)
    m = re.search(r'([ \t]*)<Shape name="cheek" ([^>]*?)/>', xml)
    node_id = max(int(x) for x in re.findall(r'nodeId="(\d+)"', xml)) + 1
    attrs = re.sub(r'shapeId="\d+"', 'shapeId="%d"' % sid, m.group(2)); attrs = re.sub(r'nodeId="\d+"', 'nodeId="%d"' % node_id, attrs)
    attrs = 'visibility="false" ' + attrs               # hidden until the script shows it (halter mode: the bridle worn without its bit)
    xml = xml.replace(m.group(0), '%s<Shape name="cheek" %s/>\n%s<Shape name="halter" %s />' % (m.group(1), m.group(2), m.group(1), attrs), 1)
    # the rope's node: under Head_M, last
    Wh = AN.bone_world(xml, "Head_M"); local = (np.linalg.inv(Wh) @ np.append(centre - np.array([0, R, 0]) * 0, 1.0))[:3]
    local = (np.linalg.inv(Wh) @ np.append(centre + np.array([0.0, -R, 0.0]), 1.0))[:3]       # the ring's lowest point: where the clip goes
    xml = re.sub(r'\n[ \t]*<TransformGroup name="halterRing"[^>]*/>', "", xml)
    mh = re.search(r'(\n[ \t]*)<TransformGroup name="Head_M"[^>]*?(?<!/)>', xml)
    depth, close = 1, None
    for tag in re.finditer(r'<TransformGroup\b[^>]*?(/?)>|</TransformGroup>', xml[mh.end():]):
        if tag.group(0).startswith("</"): depth -= 1
        elif tag.group(1) != "/": depth += 1
        if depth == 0: close = mh.end() + tag.start(); break
    nid2 = max(int(x) for x in re.findall(r'nodeId="(\d+)"', xml)) + 1
    ls = xml.rfind("\n", 0, close)
    xml = xml[:ls] + '%s<TransformGroup name="halterRing" translation="%.5f %.5f %.5f" nodeId="%d" />' % (mh.group(1) + "  ", local[0], local[1], local[2], nid2) + xml[ls:]
    open(i3d_path, "wb").write(xml.encode("latin-1"))
    print("%s: halter shape %d verts %d tris (scale %.3f), ring centre %s, halterRing in Head_M %s" % (os.path.basename(base), len(P), len(Tr) // 3, scale, np.round(centre, 3), np.round(local, 4)))

if __name__ == "__main__":
    main(sys.argv[1])
