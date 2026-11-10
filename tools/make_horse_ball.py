#!/usr/bin/env python3
"""The horse ball: a big, bright red sphere that is a dynamic physics body (like the game's football: a root Shape with dynamic="true" compound="true", its visible mesh as the child), the i3d and the
.i3d.shapes written directly with make_hitching_post's shape builder.
  python3 tools/make_horse_ball.py [out dir] [radius m]     -> models/ball/horseBall.i3d, horseBall.i3d.shapes
"""
import math, os, sys
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

def build(out, radius):
    os.makedirs(out, exist_ok=True)
    m = sphere(radius)
    P, N, U, T, subsets = H.merge([(m, 1)])
    # outward check with the vertex normals (the game's winding is counter-clockwise from outside)
    bad = 0
    for k in range(0, len(T), 3):
        a, b, c = P[T[k]], P[T[k+1]], P[T[k+2]]
        e1 = [b[i]-a[i] for i in range(3)]; e2 = [c[i]-a[i] for i in range(3)]
        cr = (e1[1]*e2[2]-e1[2]*e2[1], e1[2]*e2[0]-e1[0]*e2[2], e1[0]*e2[1]-e1[1]*e2[0])
        n = [N[T[k]][i] + N[T[k+1]][i] + N[T[k+2]][i] for i in range(3)]
        if cr[0]*n[0] + cr[1]*n[1] + cr[2]*n[2] < 0: bad += 1
    print("triangles against their normals:", bad, "of", len(T) // 3)
    vis = H.shape_entity("horseBall_vis", 1, P, N, U, T, subsets, ["red"])
    col = H.shape_entity("horseBall", 2, P, N, U, T, subsets, ["red"])
    hdr = type("Hd", (), {"version": 10, "seed": 91})()
    sf = type("SF", (), {"header": hdr, "entities": [H.Raw(1, vis), H.Raw(1, col)]})()
    S.write(os.path.join(out, "horseBall.i3d.shapes"), sf)
    xml = f'''<?xml version="1.0" encoding="iso-8859-1"?>

<i3D name="horseBall" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">
  <Asset>
    <Export program="make_horse_ball.py" version="1"/>
  </Asset>
  <Files/>
  <Materials>
    <Material name="red" materialId="1" diffuseColor="0.95 0.04 0.04 1" specularColor="0.7 0.7 0.7"/>
  </Materials>
  <Shapes externalShapesFile="horseBall.i3d.shapes">
  </Shapes>
  <Scene>
    <Shape name="horseBall" shapeId="2" dynamic="true" compound="true" density="0.01" collisionFilterGroup="0x4003c" collisionFilterMask="0xfffffbff" castsShadows="false" receiveShadows="false" nonRenderable="true" materialIds="1" nodeId="1">
      <Shape name="horseBall_vis" shapeId="1" castsShadows="true" receiveShadows="true" materialIds="1" nodeId="2"/>
    </Shape>
  </Scene>

</i3D>
'''
    open(os.path.join(out, "horseBall.i3d"), "w", encoding="iso-8859-1").write(xml)
    print("wrote", out, "verts", len(P), "tris", len(T) // 3, "radius", radius)

if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "models", "ball"), float(sys.argv[2]) if len(sys.argv) > 2 else 0.45)
