#!/usr/bin/env python3
"""Splits the game's saddle shape (saddle + bridle in ONE skinned mesh) of a baked horse model into a saddle and a bridle shape, so each can be shown and hidden on its own (the tack room vision, memory:
project-fs25-tack-room-vision). The mesh is 15 connected pieces: the head group (the big bridle, the noseband, the bit rings) lies at z > 1.0, the saddle group (seat, stirrups, leathers) behind. Whole pieces go to
one side, vertices keep their weights and bone indices (both shapes use the saddle node's skinBindNodeIds list, so nothing is remapped).
  python3 split_tack.py models/horse/horseAdult          (the folder + the model name without extension: .i3d, .i3d.shapes)
In the i3d the saddle node (the game's equipmentNode, same index path) becomes a GROUP holding the bridle (child 0) and the seat shape (saddleSeat): the game shows both together, the script can hide either alone.
Run it after every bake (the bake writes the model afresh from the game's files), like make_coat_shader.py."""
import sys, os, re, copy
import numpy as np
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here); sys.path.insert(0, os.path.join(here, "..", "..", "..", "tools"))
import shapes_io as S
import make_hitching_post as H

BRIDLE_FROM_Z = 1.0
GAME_SHAPES = os.path.expanduser("~/fs25_resources/HorseModel/horse.i3d.shapes")

def components(P, tri):
    key = {}; wid = np.zeros(len(P), int)
    for i, p in enumerate(np.round(P, 4)):
        wid[i] = key.setdefault(tuple(p), len(key))
    parent = list(range(len(key)))
    def f(a):
        while parent[a] != a: parent[a] = parent[parent[a]]; a = parent[a]
        return a
    for a, b, c in tri:
        ra, rb, rc = f(wid[a]), f(wid[b]), f(wid[c]); parent[rb] = ra; parent[rc] = ra
    return np.array([f(wid[i]) for i in range(len(P))])

def piece(sh, P, N, Tg, U, W, I, tri, vmask, name, sid):
    remap = -np.ones(len(P), int); remap[vmask] = np.arange(vmask.sum())
    tmask = vmask[tri[:, 0]]
    T = remap[tri[tmask]].reshape(-1).tolist()
    s0 = sh.subsets[0]
    nv = int(vmask.sum())
    return H.shape_entity(name, sid, [tuple(p) for p in P[vmask]], [tuple(n) for n in N[vmask]], [tuple(u) for u in U[vmask]], T, [(0, nv, 0, len(T), s0.uv_density1)], sh.material_slot_names,
                          tangents=[tuple(t) for t in Tg[vmask]], skin=([tuple(w) for w in W[vmask]], [tuple(i) for i in I[vmask]]))

def regroup(xml):
    """The saddle node becomes a GROUP (the game's equipmentNode, shown and hidden as before) holding the bridle (child 0, the same index path as before) and the saddle's seat: each can be hidden alone."""
    m = re.search(r'([ \t]*)<Shape name="saddle" ([^>]*?)>\s*<Shape name="bridle" ([^>]*?)/>\s*</Shape>', xml)
    if m is None:
        return xml, False
    indent, seat, bridle = m.group(1), m.group(2), m.group(3)
    node_id = max(int(x) for x in re.findall(r'nodeId="(\d+)"', xml)) + 1
    seat = re.sub(r'visibility="[^"]*"\s*', "", seat).strip().replace('name="saddle"', 'name="saddleSeat"')
    new = ('%s<TransformGroup name="saddle" visibility="false" nodeId="%d">\n%s  <Shape name="bridle" %s />\n%s  <Shape name="saddleSeat" %s />\n%s</TransformGroup>'
           % (indent, node_id, indent, bridle, indent, seat, indent))
    return xml.replace(m.group(0), new, 1), True

def main(base):
    shapes_path, i3d_path = base + ".i3d.shapes", base + ".i3d"
    raw, sf = S.read(shapes_path)
    xml = open(i3d_path, "rb").read().decode("latin-1")
    if 'name="bridle"' in xml:
        xml, changed = regroup(xml)
        if changed: open(i3d_path, "wb").write(xml.encode("latin-1"))
        print("already split:", base, "(regrouped)" if changed else ""); return
    idx, sh = None, None
    for k, e in enumerate(sf.entities):
        if e.entity_type.name == "SHAPE":
            cand = S.M.parse_shape_entity(e, sf.header.version)
            if cand.name == "saddleShape": idx, sh = k, cand
    assert sh is not None and sh.blend_weights, "no skinned saddleShape in " + shapes_path
    P = np.array([[p.x, p.y, p.z] for p in sh.positions]); N = np.array([[p.x, p.y, p.z] for p in sh.normals])
    Tg = np.array([[p.x, p.y, p.z, p.w] for p in sh.tangents]); U = np.array([[u.u, u.v] for u in sh.uv_sets[0]])
    W = np.array(sh.blend_weights); I = np.array(sh.blend_indices)
    tri = np.array([[t.p1 - 1, t.p2 - 1, t.p3 - 1] for t in sh.triangles])
    # which vertices are the bridle: decided on the GAME's own saddle mesh (the head group lies at z > 1.0 there), then taken over by vertex number: a baked model keeps the game's vertex order (the bake only
    # moves vertices), so a foal whose head sits lower splits the same way
    graw, gsf = S.read(GAME_SHAPES)
    gsh = [S.M.parse_shape_entity(e, gsf.header.version) for e in gsf.entities if e.entity_type.name == "SHAPE"]
    gsh = [s for s in gsh if s.name == "saddleShape"][0]
    assert len(gsh.positions) == len(P), "the model's saddle shape has another vertex count than the game's"
    GP = np.array([[p.x, p.y, p.z] for p in gsh.positions]); gtri = np.array([[t.p1 - 1, t.p2 - 1, t.p3 - 1] for t in gsh.triangles])
    comp = components(GP, gtri)
    bridle = np.zeros(len(P), bool)
    for cid in np.unique(comp):
        m = comp == cid
        if GP[m][:, 2].mean() > BRIDLE_FROM_Z: bridle |= m
    assert bridle.any() and (~bridle).any(), "the split found only one side"
    sid_saddle = sh.id
    sid_bridle = max(int(x) for x in re.findall(r'shapeId="(\d+)"', xml)) + 1
    saddle_bytes = piece(sh, P, N, Tg, U, W, I, tri, ~bridle, "saddleShape", sid_saddle)
    bridle_bytes = piece(sh, P, N, Tg, U, W, I, tri, bridle, "bridleShape", sid_bridle)
    ent_bridle = copy.copy(sf.entities[idx])
    sf.entities[idx].data = saddle_bytes
    ent_bridle.data = bridle_bytes
    sf.entities.append(ent_bridle)
    S.write(shapes_path, sf)
    # the scene: the bridle node is the saddle node's child with the same bind list
    m = re.search(r'<Shape name="saddle" ([^>]*?)/>', xml)
    attrs = m.group(1)
    node_id = max(int(x) for x in re.findall(r'nodeId="(\d+)"', xml)) + 1
    child = re.sub(r'shapeId="\d+"', 'shapeId="%d"' % sid_bridle, attrs)
    child = re.sub(r'nodeId="\d+"', 'nodeId="%d"' % node_id, child)
    child = re.sub(r'visibility="[^"]*"\s*', "", child).strip()
    indent = re.search(r'\n(\s*)<Shape name="saddle"', xml).group(1)
    new = '<Shape name="saddle" %s>\n%s  <Shape name="bridle" %s />\n%s</Shape>' % (attrs.rstrip(), indent, child, indent)
    xml = xml.replace(m.group(0), new, 1)
    xml, _ = regroup(xml)
    open(i3d_path, "wb").write(xml.encode("latin-1"))
    print("split %s: saddle %d verts, bridle %d verts (new shape id %d, node %d)" % (os.path.basename(base), (~bridle).sum(), bridle.sum(), sid_bridle, node_id))

def piece_tris(sh, P, N, Tg, U, W, I, tri, tsel, name, sid):
    """Like piece(), but by triangles: vertices that both sides use are copied to both."""
    used = np.zeros(len(P), bool); used[tri[tsel].reshape(-1)] = True
    remap = -np.ones(len(P), int); remap[used] = np.arange(used.sum())
    T = remap[tri[tsel]].reshape(-1).tolist()
    s0 = sh.subsets[0]; nv = int(used.sum())
    return H.shape_entity(name, sid, [tuple(p) for p in P[used]], [tuple(n) for n in N[used]], [tuple(u) for u in U[used]], T, [(0, nv, 0, len(T), s0.uv_density1)], sh.material_slot_names,
                          tangents=[tuple(t) for t in Tg[used]], skin=([tuple(w) for w in W[used]], [tuple(i) for i in I[used]]))

# The "bit" piece: the bit, its rings and the whole cheek strap that holds them (crown junction down to the ring, buckles included). Without it the bridle is a halter (crown, browband, noseband, throatlatch).
# Chosen on the GAME's saddle mesh: the strap runs along one line in the side view (z, y); the noseband crosses it (its UV islands span both sides), the throatlatch hangs at z ~ 1.21.
BIT_LINE_A, BIT_LINE_B, BIT_HALF_WIDTH = (1.204, 2.0455), (1.487, 1.8293), 0.024

def bit_triangles(P, tri, head):
    """bool per triangle of the whole mesh: true for the bit's triangles (all on the head group)."""
    par = list(range(len(P)))
    def f(a):
        while par[a] != a: par[a] = par[par[a]]; a = par[a]
        return a
    for a, b, c in tri:
        ra, rb, rc = f(a), f(b), f(c); par[rb] = ra; par[rc] = ra
    isl = np.array([f(i) for i in range(len(P))])
    cross = np.zeros(len(P), bool)
    for r in np.unique(isl[head]):
        q = isl == r
        if P[q][:, 0].min() < -0.03 and P[q][:, 0].max() > 0.03: cross |= q
    A, B = np.array(BIT_LINE_A), np.array(BIT_LINE_B); d = B - A; L = np.linalg.norm(d); u = d / L
    cen = P[tri].mean(1)
    zy = cen[:, [2, 1]] - A; t = zy @ u / L; off = np.abs(zy[:, 0] * u[1] - zy[:, 1] * u[0])
    inband = (t >= -0.02) & (t <= 1.03) & (off < BIT_HALF_WIDTH) & (np.abs(cen[:, 0]) >= 0.03)
    tri_cross = cross[tri[:, 0]]
    comp = components(P, tri)
    rings = np.zeros(len(P), bool)
    for c in np.unique(comp[head]):
        q = comp == c
        if P[q][:, 1].min() > 1.75 and P[q][:, 2].mean() > 1.45 and q.sum() < 200: rings |= q
    return head[tri[:, 0]] & ((inband & ~tri_cross) | rings[tri[:, 0]])

def cheek_flags(P, tri, head):
    """For the bit's triangles (game order): true for those above the noseband, i.e. the strap from the crown down to where the noseband meets it. A halter keeps that strap; what lies below it only holds the bit."""
    par = list(range(len(P)))
    def f(a):
        while par[a] != a: par[a] = par[par[a]]; a = par[a]
        return a
    for a, b, c in tri:
        ra, rb, rc = f(a), f(b), f(c); par[rb] = ra; par[rc] = ra
    isl = np.array([f(i) for i in range(len(P))])
    cross = np.zeros(len(P), bool)
    for r in np.unique(isl[head]):
        q = isl == r
        if P[q][:, 0].min() < -0.03 and P[q][:, 0].max() > 0.03: cross |= q
    A, B = np.array(BIT_LINE_A), np.array(BIT_LINE_B); d = B - A; L = np.linalg.norm(d); u = d / L
    zy = P[:, [2, 1]] - A; tv = zy @ u / L; off = np.abs(zy[:, 0] * u[1] - zy[:, 1] * u[0])
    near = cross & (off < 0.02) & (tv > 0.4) & (np.abs(P[:, 0]) >= 0.03)
    t_cut = tv[near].min() + CHEEK_BELOW_NOSEBAND
    bit = bit_triangles(P, tri, head)
    cen_t = (tv[tri].mean(1))
    rings = np.zeros(len(P), bool)
    comp = components(P, tri)
    for c in np.unique(comp[head]):
        q = comp == c
        if P[q][:, 1].min() > 1.75 and P[q][:, 2].mean() > 1.45 and q.sum() < 200: rings |= q
    cheek = bit & (cen_t < t_cut) & ~rings[tri[:, 0]]
    return cheek[bit], t_cut

CHEEK_BELOW_NOSEBAND = 0.03          # the strap goes a little past the noseband's attachment

def head_vertices(P, tri):
    comp = components(P, tri)
    head = np.zeros(len(P), bool)
    for c in np.unique(comp):
        if P[comp == c][:, 2].mean() > BRIDLE_FROM_Z: head |= comp == c
    return head

def split_bit(base):
    """The bridle shape's bit pieces (see above) become a shape of their own, the fourth child of the saddle group. Triangle order of the bridle shape is the game's (the bake keeps it)."""
    shapes_path, i3d_path = base + ".i3d.shapes", base + ".i3d"
    xml = open(i3d_path, "rb").read().decode("latin-1")
    if 'name="bit"' in xml:
        print("bit already split:", base); return
    assert 'name="blanket"' in xml, "run the blanket split first"
    graw, gsf = S.read(GAME_SHAPES)
    gsh = [S.M.parse_shape_entity(e, gsf.header.version) for e in gsf.entities if e.entity_type.name == "SHAPE"]
    gsh = [s for s in gsh if s.name == "saddleShape"][0]
    GP = np.array([[p.x, p.y, p.z] for p in gsh.positions]); gtri = np.array([[t.p1 - 1, t.p2 - 1, t.p3 - 1] for t in gsh.triangles])
    head = head_vertices(GP, gtri)
    bit_g = bit_triangles(GP, gtri, head)
    bridle_tris = head[gtri[:, 0]]                       # the triangles the bridle shape was made of, in this order
    bit_in_bridle = bit_g[bridle_tris]
    raw, sf = S.read(shapes_path)
    idx, sh = None, None
    for k, e in enumerate(sf.entities):
        if e.entity_type.name == "SHAPE":
            cand = S.M.parse_shape_entity(e, sf.header.version)
            if cand.name == "bridleShape": idx, sh = k, cand
    P = np.array([[p.x, p.y, p.z] for p in sh.positions]); N = np.array([[p.x, p.y, p.z] for p in sh.normals])
    Tg = np.array([[p.x, p.y, p.z, p.w] for p in sh.tangents]); U = np.array([[u.u, u.v] for u in sh.uv_sets[0]])
    W = np.array(sh.blend_weights); I = np.array(sh.blend_indices)
    tri = np.array([[t.p1 - 1, t.p2 - 1, t.p3 - 1] for t in sh.triangles])
    assert len(tri) == len(bit_in_bridle), "the bridle shape has another triangle count (%d) than the game's head group (%d)" % (len(tri), len(bit_in_bridle))
    sid_bit = max(int(x) for x in re.findall(r'shapeId="(\d+)"', xml)) + 1
    rest_bytes = piece_tris(sh, P, N, Tg, U, W, I, tri, ~bit_in_bridle, "bridleShape", sh.id)
    bit_bytes = piece_tris(sh, P, N, Tg, U, W, I, tri, bit_in_bridle, "bitShape", sid_bit)
    ent = copy.copy(sf.entities[idx])
    sf.entities[idx].data = rest_bytes
    ent.data = bit_bytes
    sf.entities.append(ent)
    S.write(shapes_path, sf)
    m = re.search(r'([ \t]*)<Shape name="blanket" ([^>]*?)/>', xml)
    node_id = max(int(x) for x in re.findall(r'nodeId="(\d+)"', xml)) + 1
    attrs = re.sub(r'shapeId="\d+"', 'shapeId="%d"' % sid_bit, m.group(2))
    attrs = re.sub(r'nodeId="\d+"', 'nodeId="%d"' % node_id, attrs)
    new = '%s<Shape name="blanket" %s/>\n%s<Shape name="bit" %s />' % (m.group(1), m.group(2), m.group(1), attrs)
    open(i3d_path, "wb").write(xml.replace(m.group(0), new, 1).encode("latin-1"))
    print("bit split %s: bit %d triangles, bridle %d (new shape id %d, node %d)" % (os.path.basename(base), bit_in_bridle.sum(), (~bit_in_bridle).sum(), sid_bit, node_id))

def split_cheek(base):
    """The bit shape's upper strap (see cheek_flags) becomes the shape `cheek`: bridle + cheek = a halter, plus the bit = the bridle."""
    shapes_path, i3d_path = base + ".i3d.shapes", base + ".i3d"
    xml = open(i3d_path, "rb").read().decode("latin-1")
    if 'name="cheek"' in xml:
        print("cheek already split:", base); return
    assert 'name="bit"' in xml, "run the bit split first"
    graw, gsf = S.read(GAME_SHAPES)
    gsh = [S.M.parse_shape_entity(e, gsf.header.version) for e in gsf.entities if e.entity_type.name == "SHAPE"]
    gsh = [s for s in gsh if s.name == "saddleShape"][0]
    GP = np.array([[p.x, p.y, p.z] for p in gsh.positions]); gtri = np.array([[t.p1 - 1, t.p2 - 1, t.p3 - 1] for t in gsh.triangles])
    head = head_vertices(GP, gtri)
    flags, t_cut = cheek_flags(GP, gtri, head)
    raw, sf = S.read(shapes_path)
    idx, sh = None, None
    for k, e in enumerate(sf.entities):
        if e.entity_type.name == "SHAPE":
            cand = S.M.parse_shape_entity(e, sf.header.version)
            if cand.name == "bitShape": idx, sh = k, cand
    P = np.array([[p.x, p.y, p.z] for p in sh.positions]); N = np.array([[p.x, p.y, p.z] for p in sh.normals])
    Tg = np.array([[p.x, p.y, p.z, p.w] for p in sh.tangents]); U = np.array([[u.u, u.v] for u in sh.uv_sets[0]])
    W = np.array(sh.blend_weights); I = np.array(sh.blend_indices)
    tri = np.array([[t.p1 - 1, t.p2 - 1, t.p3 - 1] for t in sh.triangles])
    assert len(tri) == len(flags), "the bit shape has another triangle count (%d) than expected (%d)" % (len(tri), len(flags))
    sid = max(int(x) for x in re.findall(r'shapeId="(\d+)"', xml)) + 1
    rest_bytes = piece_tris(sh, P, N, Tg, U, W, I, tri, ~flags, "bitShape", sh.id)
    cheek_bytes = piece_tris(sh, P, N, Tg, U, W, I, tri, flags, "cheekShape", sid)
    ent = copy.copy(sf.entities[idx])
    sf.entities[idx].data = rest_bytes
    ent.data = cheek_bytes
    sf.entities.append(ent)
    S.write(shapes_path, sf)
    m = re.search(r'([ \t]*)<Shape name="bit" ([^>]*?)/>', xml)
    node_id = max(int(x) for x in re.findall(r'nodeId="(\d+)"', xml)) + 1
    attrs = re.sub(r'shapeId="\d+"', 'shapeId="%d"' % sid, m.group(2))
    attrs = re.sub(r'nodeId="\d+"', 'nodeId="%d"' % node_id, attrs)
    new = '%s<Shape name="bit" %s/>\n%s<Shape name="cheek" %s />' % (m.group(1), m.group(2), m.group(1), attrs)
    open(i3d_path, "wb").write(xml.replace(m.group(0), new, 1).encode("latin-1"))
    print("cheek split %s: cheek %d triangles, bit %d (cut at t=%.3f, new shape id %d, node %d)" % (os.path.basename(base), flags.sum(), (~flags).sum(), t_cut, sid, node_id))

def split_blanket(base):
    """The saddle shape's biggest UV island (a rounded sheet wider than the saddle, draped over the back: 430 of its ~1350 vertices) is the saddle blanket: it becomes a shape of its own, the third child of the saddle group."""
    shapes_path, i3d_path = base + ".i3d.shapes", base + ".i3d"
    xml = open(i3d_path, "rb").read().decode("latin-1")
    if 'name="blanket"' in xml:
        print("blanket already split:", base); return
    assert 'name="saddleSeat"' in xml, "run the bridle split first"
    raw, sf = S.read(shapes_path)
    idx, sh = None, None
    for k, e in enumerate(sf.entities):
        if e.entity_type.name == "SHAPE":
            cand = S.M.parse_shape_entity(e, sf.header.version)
            if cand.name == "saddleShape": idx, sh = k, cand
    P = np.array([[p.x, p.y, p.z] for p in sh.positions]); N = np.array([[p.x, p.y, p.z] for p in sh.normals])
    Tg = np.array([[p.x, p.y, p.z, p.w] for p in sh.tangents]); U = np.array([[u.u, u.v] for u in sh.uv_sets[0]])
    W = np.array(sh.blend_weights); I = np.array(sh.blend_indices)
    tri = np.array([[t.p1 - 1, t.p2 - 1, t.p3 - 1] for t in sh.triangles])
    par = list(range(len(P)))
    def f(a):
        while par[a] != a: par[a] = par[par[a]]; a = par[a]
        return a
    for a, b, c in tri:
        ra, rb, rc = f(a), f(b), f(c); par[rb] = ra; par[rc] = ra
    isl = np.array([f(i) for i in range(len(P))])
    roots, counts = np.unique(isl, return_counts=True)
    blanket = isl == roots[counts.argmax()]
    q = P[blanket]
    assert 400 <= blanket.sum() <= 460, "the biggest island is not the blanket (%d verts)" % blanket.sum()
    sid_blanket = max(int(x) for x in re.findall(r'shapeId="(\d+)"', xml)) + 1
    seat_bytes = piece(sh, P, N, Tg, U, W, I, tri, ~blanket, "saddleShape", sh.id)
    blanket_bytes = piece(sh, P, N, Tg, U, W, I, tri, blanket, "blanketShape", sid_blanket)
    ent = copy.copy(sf.entities[idx])
    sf.entities[idx].data = seat_bytes
    ent.data = blanket_bytes
    sf.entities.append(ent)
    S.write(shapes_path, sf)
    m = re.search(r'([ \t]*)<Shape name="saddleSeat" ([^>]*?)/>', xml)
    node_id = max(int(x) for x in re.findall(r'nodeId="(\d+)"', xml)) + 1
    attrs = re.sub(r'shapeId="\d+"', 'shapeId="%d"' % sid_blanket, m.group(2))
    attrs = re.sub(r'nodeId="\d+"', 'nodeId="%d"' % node_id, attrs)
    new = '%s<Shape name="saddleSeat" %s/>\n%s<Shape name="blanket" %s />' % (m.group(1), m.group(2), m.group(1), attrs)
    open(i3d_path, "wb").write(xml.replace(m.group(0), new, 1).encode("latin-1"))
    print("blanket split %s: blanket %d verts, saddle %d verts (new shape id %d, node %d)" % (os.path.basename(base), blanket.sum(), (~blanket).sum(), sid_blanket, node_id))

if __name__ == "__main__":
    main(sys.argv[1])
    split_blanket(sys.argv[1])
    split_bit(sys.argv[1])
    split_cheek(sys.argv[1])
