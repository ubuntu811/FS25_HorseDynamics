#!/usr/bin/env python3
"""The hitching post: two posts, a rail between them and two steel rings hanging from it, as an i3d + a .i3d.shapes WRITTEN DIRECTLY (v10 SHAPE entities built from scratch; the cipher layer is shapes_io.py).
  python3 tools/make_hitching_post.py [out dir]     -> hitchingPost.i3d, hitchingPost.i3d.shapes (default: placeables/hitchingPost)
Frame: y up, the front of the post (where the horse stands, the rope hangs) is +z. The rings are the tie points: nodes tie1 / tie2 at their centres (HorseTie finds them by name).
Shapes: postShape (what you see: subset 1 wood, subset 2 steel), colShape (boxes of the posts and the rail, no render).
"""
import math, os, struct, sys
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here)
import shapes_io as S

# ---------- the dimensions (metres)
POST_X, POST_R, POST_TOP, POST_SINK = 1.0, 0.09, 1.60, 0.10        # posts at x = +-POST_X, round, 18 cm thick, 10 cm in the ground
RAIL_Y, RAIL_H, RAIL_D = 1.30, 0.10, 0.09                            # rail centre height, its height and depth (square section, 10 x 9 cm), between the posts
RING_X, RING_R, RING_TUBE = 0.50, 0.045, 0.0065                      # rings at x = +-RING_X, hanging from the rail's underside, plane facing the front
SIDES = 14

class Mesh:
    def __init__(self): self.p, self.n, self.uv, self.t = [], [], [], []
    def vert(self, p, n, uv): self.p.append(p); self.n.append(n); self.uv.append(uv); return len(self.p) - 1
    def quad(self, a, b, c, d): self.t += [(a, b, c), (a, c, d)]      # counter-clockwise seen from outside

def box(m, cx, cy, cz, hx, hy, hz, uvscale=1.0):
    faces = [((1, 0, 0), (0, 1, 0), (0, 0, 1)), ((-1, 0, 0), (0, 1, 0), (0, 0, -1)), ((0, 1, 0), (0, 0, 1), (1, 0, 0)),
             ((0, -1, 0), (0, 0, -1), (1, 0, 0)), ((0, 0, 1), (0, 1, 0), (-1, 0, 0)), ((0, 0, -1), (0, 1, 0), (1, 0, 0))]
    h = (hx, hy, hz)
    for n, up, right in faces:
        # the face's centre, then four corners: right*u + up*v
        c = [cx + n[0] * hx, cy + n[1] * hy, cz + n[2] * hz]
        ru = abs(right[0]) * hx + abs(right[1]) * hy + abs(right[2]) * hz
        vu = abs(up[0]) * hx + abs(up[1]) * hy + abs(up[2]) * hz
        idx = []
        for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            p = tuple(c[i] + right[i] * ru * su + up[i] * vu * sv for i in range(3))
            idx.append(m.vert(p, n, ((su + 1) * ru * uvscale, (sv + 1) * vu * uvscale)))
        # winding: (n x) check by the cross product
        a, b, cc = [m.p[i] for i in idx[:3]]
        e1 = tuple(b[i] - a[i] for i in range(3)); e2 = tuple(cc[i] - a[i] for i in range(3))
        cr = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
        if cr[0] * n[0] + cr[1] * n[1] + cr[2] * n[2] > 0: m.quad(*idx)
        else: m.quad(idx[0], idx[3], idx[2], idx[1])

def cylinder(m, cx, cz, y0, y1, r, sides=SIDES, uvscale=1.0):
    # side wall (smooth normals) + a flat top cap
    ring0, ring1 = [], []
    for i in range(sides + 1):
        a = 2 * math.pi * i / sides; nx, nz = math.cos(a), math.sin(a)
        u = i / sides * 2 * math.pi * r * uvscale
        ring0.append(m.vert((cx + r * nx, y0, cz + r * nz), (nx, 0, nz), (u, 0)))
        ring1.append(m.vert((cx + r * nx, y1, cz + r * nz), (nx, 0, nz), (u, (y1 - y0) * uvscale)))
    for i in range(sides):
        m.quad(ring0[i + 1], ring0[i], ring1[i], ring1[i + 1])
    top = m.vert((cx, y1, cz), (0, 1, 0), (0, 0))
    cap = [m.vert((cx + r * math.cos(2 * math.pi * i / sides), y1, cz + r * math.sin(2 * math.pi * i / sides)), (0, 1, 0), (r * uvscale, r * uvscale)) for i in range(sides + 1)]
    for i in range(sides):
        m.t.append((top, cap[i + 1], cap[i]))

def torus(m, cx, cy, cz, R, r, major=20, minor=8):
    # a ring in the x-y plane (it faces +z) round (cx, cy, cz)
    rows = []
    for i in range(major + 1):
        a = 2 * math.pi * i / major; ca, sa = math.cos(a), math.sin(a)
        row = []
        for j in range(minor + 1):
            b = 2 * math.pi * j / minor; cb, sb = math.cos(b), math.sin(b)
            nx, ny, nz = ca * cb, sa * cb, sb
            row.append(m.vert((cx + (R + r * cb) * ca, cy + (R + r * cb) * sa, cz + r * sb), (nx, ny, nz), (i / major, j / minor)))
        rows.append(row)
    for i in range(major):
        for j in range(minor):
            m.quad(rows[i][j], rows[i + 1][j], rows[i + 1][j + 1], rows[i][j + 1])
    return

def merge(parts):
    """parts: list of (Mesh, material slot): returns (positions, normals, uvs, indices, subsets [(fv, nv, fi, ni)])"""
    P, N, U, T, subsets = [], [], [], [], []
    for m, _ in parts:
        fv, fi = len(P), len(T)
        P += m.p; N += m.n; U += m.uv
        for a, b, c in m.t: T += [a + fv, b + fv, c + fv]
        subsets.append((fv, len(m.p), fi, len(m.t) * 3))
    return P, N, U, T, subsets

# ---------- the entity (v10 SHAPE): part header, bounding sphere, counts, options, subsets, slot names, indices, positions, normals, uv1, no attachments
def align(buf, n):
    while len(buf) % n: buf.append(0)

def shape_entity(name, sid, P, N, U, T, subsets, slots, attachments=(), tangents=None):
    assert len(P) <= 65535
    b = bytearray()
    nm = name.encode("ascii"); b += struct.pack("<i", len(nm)); b += nm; align(b, 4); b += struct.pack("<I", sid)
    lo = [min(p[i] for p in P) for i in range(3)]; hi = [max(p[i] for p in P) for i in range(3)]
    c = [(lo[i] + hi[i]) / 2 for i in range(3)]; rad = max(math.dist(c, p) for p in P)
    b += struct.pack("<4f", c[0], c[1], c[2], rad)
    options = 0x3 | (0x80 if tangents is not None else 0)      # normals + uv1 (+ tangents: the normal map needs them)
    b += struct.pack("<IIII", len(T), len(subsets), len(P), options)
    b += struct.pack("<f", 0.0)                       # vtxCompression
    for fv, nv, fi, ni in subsets:
        # uv density: area of uv per area of surface, 1.0 is fine for flat-coloured materials
        b += struct.pack("<IIII", fv, nv, fi, ni) + struct.pack("<f", 1.0)
    for s in slots:
        sn = s.encode("ascii"); b += struct.pack("<H", len(sn)) + sn; align(b, 2)
    align(b, 4)
    b += struct.pack("<%dH" % len(T), *T); align(b, 4)
    for p in P: b += struct.pack("<3f", *p)
    for n in N: b += struct.pack("<3f", *n)
    if tangents is not None:
        for t in tangents: b += struct.pack("<4f", *t)
    for u in U: b += struct.pack("<2f", *u)
    b += struct.pack("<I", len(attachments))          # attachments: (flags, bytes) each (flags 2 = a cooked convex hull, see make_horse_ball.convex_hull_block)
    for flags, data in attachments:
        b += struct.pack("<I", flags) + struct.pack("<i", len(data)) + data
    return bytes(b)

class Raw:                                            # what shapes_io.write wants of an entity
    def __init__(self, t, data): self.type, self.data = t, data

def build(outdir):
    wood, steel = Mesh(), Mesh()
    for sx in (-1, 1):
        cylinder(wood, sx * POST_X, 0, -POST_SINK, POST_TOP, POST_R)
    box(wood, 0, RAIL_Y, 0, POST_X - POST_R, RAIL_H / 2, RAIL_D / 2)
    for sx in (-1, 1):
        torus(steel, sx * RING_X, RAIL_Y - RAIL_H / 2 - RING_R, 0.0, RING_R, RING_TUBE)
    P, N, U, T, subsets = merge([(wood, 1), (steel, 2)])
    post = shape_entity("postShape", 1, P, N, U, T, subsets, ["wood", "steel"])
    col = Mesh()
    for sx in (-1, 1):
        box(col, sx * POST_X, (POST_TOP - POST_SINK) / 2, 0, POST_R, (POST_TOP + POST_SINK) / 2, POST_R)
    box(col, 0, RAIL_Y, 0, POST_X - POST_R, RAIL_H / 2, RAIL_D / 2)
    cp, cn, cu, ct, csub = merge([(col, 1)])
    colent = shape_entity("colShape", 2, cp, cn, cu, ct, csub, ["wood"])
    os.makedirs(outdir, exist_ok=True)
    # a new file: header version 10 with a seed of our own, two SHAPE entities (type 1)
    template = S.R.FileHeader(10, 77) if hasattr(S.R, "FileHeader") and False else None
    hdr = type("H", (), {"version": 10, "seed": 77})()
    sf = type("SF", (), {"header": hdr, "entities": [Raw(1, post), Raw(1, colent)]})()
    S.write(os.path.join(outdir, "hitchingPost.i3d.shapes"), sf)
    ring_y = RAIL_Y - RAIL_H / 2 - RING_R
    xml = f'''<?xml version="1.0" encoding="iso-8859-1"?>

<i3D name="hitchingPost" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">
  <Asset>
    <Export program="make_hitching_post.py" version="1"/>
  </Asset>
  <Files/>
  <Materials>
    <Material name="wood" materialId="1" diffuseColor="0.42 0.27 0.14 1" specularColor="0.2 0.2 0.2"/>
    <Material name="steel" materialId="2" diffuseColor="0.35 0.36 0.38 1" specularColor="0.8 0.8 0.8"/>
  </Materials>
  <Shapes externalShapesFile="hitchingPost.i3d.shapes">
  </Shapes>
  <Scene>
    <TransformGroup name="hitchingPost" nodeId="1">
      <TransformGroup name="clearAreas" nodeId="2">
        <TransformGroup name="clearArea1Start" translation="-1.3 0 -0.4" nodeId="3">
          <TransformGroup name="clearArea1Width" translation="2.6 0 0" nodeId="4"/>
          <TransformGroup name="clearArea1Height" translation="0 0 0.8" nodeId="5"/>
        </TransformGroup>
      </TransformGroup>
      <TransformGroup name="testAreas" nodeId="6">
        <TransformGroup name="testArea1Start" translation="-1.3 0 -0.4" nodeId="7">
          <TransformGroup name="testArea1End" translation="2.6 0 0.8" nodeId="8"/>
        </TransformGroup>
      </TransformGroup>
      <TransformGroup name="ties" nodeId="9">
        <TransformGroup name="tie1" translation="{-RING_X} {ring_y} 0" nodeId="10"/>
        <TransformGroup name="tie2" translation="{RING_X} {ring_y} 0" nodeId="11"/>
      </TransformGroup>
      <TransformGroup name="mesh" nodeId="12">
        <Shape name="postShape" shapeId="1" static="true" castsShadows="true" receiveShadows="true" materialIds="1,2" nodeId="13"/>
        <Shape name="col" shapeId="2" static="true" density="0" collisionFilterGroup="0x3e" collisionFilterMask="0xfffffbff" castsShadows="false" receiveShadows="false" nonRenderable="true" materialIds="1" nodeId="14"/>
      </TransformGroup>
    </TransformGroup>
  </Scene>

</i3D>
'''
    open(os.path.join(outdir, "hitchingPost.i3d"), "w", encoding="iso-8859-1").write(xml)
    print("wrote", outdir, "visual verts", len(P), "tris", len(T) // 3, "collision verts", len(cp))

if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "placeables", "hitchingPost"))
