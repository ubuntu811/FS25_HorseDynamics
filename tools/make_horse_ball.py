#!/usr/bin/env python3
"""The horse ball: a big, bright red sphere that is a dynamic physics body (like the game's football: a root Shape with dynamic="true" compound="true", its visible mesh as the child), the i3d and the
.i3d.shapes written directly with make_hitching_post's shape builder.
  python3 tools/make_horse_ball.py [out dir] [radius m]     -> vehicles/horseBall/horseBall.i3d, horseBall.i3d.shapes (the vehicle's single component)
"""
import math, os, struct, sys
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here)
import make_hitching_post as H
import shapes_io as S

def sphere(r, rings=14, sides=24):
    m = H.Mesh()
    grid = []
    for i in range(rings + 1):
        a = math.pi * i / rings; y = r * math.cos(a); rr = r * math.sin(a)
        row = []
        for j in range(sides + 1):
            b = 2 * math.pi * j / sides; nx, nz = math.cos(b), math.sin(b)
            n = (math.sin(a) * nx, math.cos(a), math.sin(a) * nz)
            row.append(m.vert((rr * nx, y, rr * nz), n, (j / sides, i / rings)))
        grid.append(row)
    for i in range(rings):
        for j in range(sides):
            a, b, c, d = grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]
            if i > 0: m.t.append((a, b, c))          # counter-clockwise seen from outside (the poles degenerate triangles are skipped)
            if i < rings - 1: m.t.append((a, c, d))
    return m

class TMesh(H.Mesh):
    """A mesh with a tangent per vertex (the seams are a normal map)."""
    def __init__(self):
        super().__init__(); self.tan = []
    def vert(self, p, n, uv, tan=(1, 0, 0, 1)):
        self.tan.append(tan); return super().vert(p, n, uv)

GORES = 12                                   # the ball has 12 panels, alternating the two colours; the first and the last ring (the caps) are in the second colour

def panel_meshes(r, rings=14, sides=24):
    """Two meshes (colour 1 panels / colour 2 panels + the two pole caps), each quad with its own vertices: smooth normals, u round the ball, v pole to pole, tangents along u."""
    A, B = TMesh(), TMesh()
    per = sides // GORES
    def corner(m, i, j):
        a = math.pi * i / rings; b = 2 * math.pi * j / sides
        n = (math.sin(a) * math.cos(b), math.cos(a), math.sin(a) * math.sin(b))
        t = (-math.sin(b), 0.0, math.cos(b), 1.0)
        return m.vert((r * n[0], r * n[1], r * n[2]), n, (j / sides, i / rings), t)
    for i in range(rings):
        for j in range(sides):
            cap = i == 0 or i == rings - 1
            m = B if (cap or (j // per) % 2 == 1) else A
            a, b, c, d = corner(m, i, j), corner(m, i, j + 1), corner(m, i + 1, j + 1), corner(m, i + 1, j)
            if i > 0: m.t.append((a, b, c))
            if i < rings - 1: m.t.append((a, c, d))
    return A, B

def seam_normal_map(path, w=1024, h=512):
    """The normal map of the stitched seams: a raised ridge with stitches along every panel boundary (u = k / GORES) and round both caps (v = 1/14 and 13/14)."""
    import numpy as np
    x = np.arange(w)[None, :].repeat(h, 0).astype(float); y = np.arange(h)[:, None].repeat(w, 1).astype(float)
    ridge = np.zeros((h, w))
    for k in range(GORES):
        d = np.abs(x - k * w / GORES); d = np.minimum(d, w - d)
        stitch = 0.65 + 0.35 * (np.sin(2 * np.pi * y / 14.0) > 0)
        ridge += np.exp(-(d / 4.5) ** 2) * stitch
    for v0 in (h / 14.0, h * 13.0 / 14.0):
        d = np.abs(y - v0)
        stitch = 0.65 + 0.35 * (np.sin(2 * np.pi * x / 14.0) > 0)
        ridge += np.exp(-(d / 4.5) ** 2) * stitch
    gy, gx = np.gradient(ridge)
    nx, ny, nz = -gx * 5.0, -gy * 5.0, np.ones_like(ridge)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([(nx / ln * 0.5 + 0.5), (ny / ln * 0.5 + 0.5), (nz / ln * 0.5 + 0.5)], -1)
    rgb = (rgb * 255 + 0.5).astype(np.uint8)
    ppm = path + ".ppm"
    with open(ppm, "wb") as f:
        f.write(b"P6 %d %d 255\n" % (w, h)); f.write(rgb.tobytes())
    os.system('convert "%s" -define dds:compression=dxt5 -define dds:mipmaps=10 "%s"' % (ppm, path)); os.remove(ppm)

def fibonacci_sphere(n, r):
    pts = []
    g = math.pi * (3 - math.sqrt(5))
    for i in range(n):
        y = 1 - 2 * (i + 0.5) / n; rad = math.sqrt(1 - y * y); a = g * i
        pts.append((r * rad * math.cos(a), r * y, r * rad * math.sin(a)))
    return pts

def mesh_volume(P, T):
    v = 0.0
    for k in range(0, len(T), 3):
        a, b, c = P[T[k]], P[T[k + 1]], P[T[k + 2]]
        v += (a[0] * (b[1] * c[2] - b[2] * c[1]) - a[1] * (b[0] * c[2] - b[2] * c[0]) + a[2] * (b[0] * c[1] - b[1] * c[0])) / 6
    return abs(v)

def convex_hull_block(P, T, margin=0.04, n=103, lift=0.0):
    """The collision attachment of a dynamic shape, read off the game's football (shapes of the base game, flags 2): 'cm' + version 4, the vertex count, then 14 floats (the margin 0.04, the volume of the
    mesh, its centre of mass, its 3x3 inertia tensor per unit mass) and the hull's vertices: points of a sphere `margin` inside the mesh's surface (the engine adds the margin back round the hull). Verified on the
    football: 8 + 56 + 103 * 12 = 1300 bytes, the volume and inertia are those of the sphere the mesh is, the vertices lie 0.04 inside it."""
    R = max(math.sqrt(p[0] ** 2 + p[1] ** 2 + p[2] ** 2) for p in P)
    vol = mesh_volume(P, T)
    Req = (3 * vol / (4 * math.pi)) ** (1 / 3)
    I = 0.4 * Req * Req
    hull = fibonacci_sphere(n, R - margin)
    b = b"cm\x04\x00" + struct.pack("<I", len(hull))
    b += struct.pack("<14f", margin, vol, 0, lift, 0, I, 0, 0, 0, I, 0, 0, 0, I)
    for p in hull:
        b += struct.pack("<3f", p[0], p[1] + lift, p[2])
    return b

def build(out, radius, name="horseBall"):
    os.makedirs(out, exist_ok=True)
    m = sphere(radius)
    P, N, U, T, subsets = H.merge([(m, 1)])
    hull = convex_hull_block(P, T, lift=radius)          # (from the sphere centred on the origin, then raised with it)
    P = [(p[0], p[1] + radius, p[2]) for p in P]        # the origin of a vehicle is where it stands: the ball's bottom is at y = 0, its centre (of mass) at y = radius
    # outward check with the vertex normals (the game's winding is counter-clockwise from outside)
    bad = 0
    for k in range(0, len(T), 3):
        a, b, c = P[T[k]], P[T[k+1]], P[T[k+2]]
        e1 = [b[i]-a[i] for i in range(3)]; e2 = [c[i]-a[i] for i in range(3)]
        cr = (e1[1]*e2[2]-e1[2]*e2[1], e1[2]*e2[0]-e1[0]*e2[2], e1[0]*e2[1]-e1[1]*e2[0])
        n = [N[T[k]][i] + N[T[k+1]][i] + N[T[k+2]][i] for i in range(3)]
        if cr[0]*n[0] + cr[1]*n[1] + cr[2]*n[2] < 0: bad += 1
    print("triangles against their normals:", bad, "of", len(T) // 3)
    # what is seen: two colours of panels (two materials), with tangents for the seams' normal map; what collides: the smooth sphere
    A, B = panel_meshes(radius)
    VP, VN, VU, VT, vsub = H.merge([(A, 1), (B, 2)])
    VP = [(p[0], p[1] + radius, p[2]) for p in VP]
    vis = H.shape_entity("horseBall_vis", 1, VP, VN, VU, VT, vsub, ["ball_mat", "ball_mat2"], tangents=A.tan + B.tan)
    col = H.shape_entity("horseBall", 2, P, N, U, T, subsets, ["ball_mat"], attachments=[(2, hull)])
    seam_normal_map(os.path.join(out, "horseBallSeams_normal.dds"))
    hdr = type("Hd", (), {"version": 10, "seed": 91})()
    sf = type("SF", (), {"header": hdr, "entities": [H.Raw(1, vis), H.Raw(1, col)]})()
    S.write(os.path.join(out, name + ".i3d.shapes"), sf)
    xml = f'''<?xml version="1.0" encoding="iso-8859-1"?>

<i3D name="{name}" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">
  <Asset>
    <Export program="make_horse_ball.py" version="1"/>
  </Asset>
  <Files>
    <File fileId="1" filename="$data/shaders/vehicleShader.xml" />
    <File fileId="2" filename="$data/shared/white_diffuse.png" />
    <File fileId="3" filename="horseBallSeams_normal.dds" />
    <File fileId="4" filename="$data/shared/default_vmask.png" />
    <File fileId="5" filename="$data/shared/detailLibrary/calibrated/calibratedPaint_diffuse.png" />
    <File fileId="6" filename="$data/shared/detailLibrary/calibrated/calibratedPaint_normal.png" />
    <File fileId="7" filename="$data/shared/detailLibrary/calibrated/calibratedPaint_specular.png" />
  </Files>
  <Materials>
    <Material name="ball_mat" materialId="1" customShaderId="1">
      <CustomParameter name="clearCoatIntensity" value="0.8"/>
      <CustomParameter name="clearCoatSmoothness" value="0.9"/>
      <CustomParameter name="colorScale" value="0.85 0.04 0.04"/>
      <CustomParameter name="smoothnessScale" value="0.9"/>
      <Custommap name="detailDiffuse" fileId="5"/>
      <Custommap name="detailNormal" fileId="6"/>
      <Custommap name="detailSpecular" fileId="7"/>
      <Texture fileId="2"/>
      <Normalmap fileId="3"/>
      <Glossmap fileId="4"/>
    </Material>
    <Material name="ball_mat2" materialId="2" customShaderId="1">
      <CustomParameter name="clearCoatIntensity" value="0.8"/>
      <CustomParameter name="clearCoatSmoothness" value="0.9"/>
      <CustomParameter name="colorScale" value="0.05 0.2 0.9"/>
      <CustomParameter name="smoothnessScale" value="0.9"/>
      <Custommap name="detailDiffuse" fileId="5"/>
      <Custommap name="detailNormal" fileId="6"/>
      <Custommap name="detailSpecular" fileId="7"/>
      <Texture fileId="2"/>
      <Normalmap fileId="3"/>
      <Glossmap fileId="4"/>
    </Material>
  </Materials>
  <Shapes externalShapesFile="{name}.i3d.shapes">
  </Shapes>
  <Scene>
    <Shape name="horseBall_main_component1" shapeId="2" dynamic="true" compound="true" collisionFilterGroup="0x10004" collisionFilterMask="0xfe3ffb83" linearDamping="0.15" angularDamping="1.0" castsShadows="false" receiveShadows="false" nonRenderable="true" materialIds="1" nodeId="1">
      <Shape name="horseBall_vis" shapeId="1" castsShadows="true" receiveShadows="true" materialIds="1,2" nodeId="2"/>
    </Shape>
  </Scene>

</i3D>
'''
    open(os.path.join(out, name + ".i3d"), "w", encoding="iso-8859-1").write(xml)
    print("wrote", name, "in", out, "verts", len(P), "tris", len(T) // 3, "radius", radius)

import re

# the test sizes (gsBall): { file name: (radius m, component mass kg, label) }; the main ball is vehicles/horseBall/horseBall.xml (hand-written: the shop item), the others are made from it
SIZES = { "horseBallSmall": (0.25, 1.5, "small"), "horseBallLarge": (0.70, 8.0, "large") }

def variants(out):
    main = open(os.path.join(out, "horseBall.xml"), encoding="utf-8").read()
    for name, (radius, mass, label) in SIZES.items():
        build(out, radius, name)
        x = main.replace("vehicles/horseBall/horseBall.i3d", "vehicles/horseBall/%s.i3d" % name)
        x = re.sub(r'<size width="[^"]*" length="[^"]*" height="[^"]*" />', '<size width="%.2f" length="%.2f" height="%.2f" />' % (2 * radius, 2 * radius, 2 * radius), x)
        x = re.sub(r'<component centerOfMass="[^"]*" solverIterationCount="10" mass="[^"]*"', '<component centerOfMass="0 %g 0" solverIterationCount="10" mass="%g"' % (radius, mass), x)
        x = x.replace("<en>Horse ball</en>", "<en>Horse ball (%s, test)</en>" % label).replace("<de>Pferdeball</de>", "<de>Pferdeball (%s, Test)</de>" % label)
        x = x.replace("<showInStore>true</showInStore>", "<showInStore>false</showInStore>")
        open(os.path.join(out, name + ".xml"), "w", encoding="utf-8").write(x)
        print("wrote", name + ".xml", "radius", radius, "mass", mass)

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "vehicles", "horseBall")
    build(out, float(sys.argv[2]) if len(sys.argv) > 2 else 0.45)
    variants(out)
