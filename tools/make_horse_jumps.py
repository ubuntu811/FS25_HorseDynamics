#!/usr/bin/env python3
"""Two simple horse jumps as placeables (meshes and .i3d.shapes written directly, like the hitching post):
  jumpCross      a low cross-pole: two white X stands, a bar in green and white (the bar 55 cm up)
  jumpStandards  a jump with two posts on cross feet, pins every 30 cm, a red and natural bar on the pin at 90 cm
  python3 tools/make_horse_jumps.py [out dir]      -> placeables/jumps/<name>.i3d, .i3d.shapes (the placeable xmls are hand-written)
Frame: y up, the front of the jump (the horse comes from +z or -z, it is symmetric) with the bar along x. Materials: 1 white wood, 2 the first stripe colour, 3 the second stripe colour.
"""
import math, os, sys
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here)
import make_hitching_post as H
import shapes_io as S

def rot_z(m, start, angle, pivot):
    """Turns the vertices (and normals) added since index `start` round the z axis through pivot = (px, py)."""
    c, s = math.cos(angle), math.sin(angle)
    for i in range(start, len(m.p)):
        x, y, z = m.p[i]; x -= pivot[0]; y -= pivot[1]
        m.p[i] = (pivot[0] + x * c - y * s, pivot[1] + x * s + y * c, z)
        nx, ny, nz = m.n[i]; m.n[i] = (nx * c - ny * s, nx * s + ny * c, nz)

def board(m, cx, cy, cz, length, width, thick, angle):
    """A board whose long side is vertical (y) turned by `angle` round z about its centre."""
    start = len(m.p)
    H.box(m, cx, cy, cz, width / 2, length / 2, thick / 2)
    rot_z(m, start, angle, (cx, cy))

def bar(m_list, x0, x1, y, z, r, stripe_len, slot_a=1, slot_b=2):
    """A bar along x from x0 to x1, in stripes: alternating into the two meshes (slot_a / slot_b of m_list)."""
    n = max(1, int(round((x1 - x0) / stripe_len)))
    seg = (x1 - x0) / n
    for k in range(n):
        m = m_list[k % 2]
        start = len(m.p)
        H.cylinder(m, 0, 0, 0, seg, r, sides=12)          # a vertical cylinder of length `seg` ...
        # ... turned to lie along x (round z by -90 degrees) and put in place
        rot_z(m, start, -math.pi / 2, (0, 0))
        for i in range(start, len(m.p)):
            px, py, pz = m.p[i]; m.p[i] = (px + x0 + k * seg, py + y, pz + z)

def entity_pair(out_name, white, a, b, col):
    parts = [(white, 1), (a, 2), (b, 3)]
    P, N, U, T, subsets = H.merge(parts)
    vis = H.shape_entity("%s_vis" % out_name, 1, P, N, U, T, subsets, ["white", "stripeA", "stripeB"])
    cp, cn, cu, ct, csub = H.merge([(col, 1)])
    ent = H.shape_entity("col", 2, cp, cn, cu, ct, csub, ["white"])
    return vis, ent

def jump_cross():
    white, a, b, col = H.Mesh(), H.Mesh(), H.Mesh(), H.Mesh()
    for sx in (-1, 1):
        x = sx * 1.1
        board(white, x, 0.34, -0.012, 0.76, 0.10, 0.045, math.radians(32))
        board(white, x, 0.34, 0.012, 0.76, 0.10, 0.045, math.radians(-32))
        H.box(white, x, 0.03, 0, 0.05, 0.03, 0.40)                # the foot, along z
        H.box(col, x, 0.33, 0, 0.32, 0.33, 0.05)                  # (collision: the X as one thin box)
        H.box(col, x, 0.03, 0, 0.05, 0.03, 0.40)
    bar([a, b], -1.3, 1.3, 0.55, 0.0, 0.035, 0.26)
    H.box(col, 0, 0.55, 0, 1.3, 0.035, 0.035)
    return entity_pair("jumpCross", white, a, b, col)

def jump_standards():
    white, a, b, col = H.Mesh(), H.Mesh(), H.Mesh(), H.Mesh()
    for sx in (-1, 1):
        x = sx * 1.2
        H.box(white, x, 0.70, 0, 0.03, 0.70, 0.03)                 # the post, 1.4 m
        H.box(white, x, 0.025, 0, 0.35, 0.025, 0.05)              # the cross foot: along z ...
        H.box(white, x, 0.025, 0, 0.05, 0.025, 0.35)              # ... and along x
        for h in (0.3, 0.6, 0.9, 1.2):                             # pins on the inner side
            H.box(white, x - sx * 0.055, h, 0, 0.025, 0.012, 0.03)
        H.box(col, x, 0.70, 0, 0.03, 0.70, 0.03)
        H.box(col, x, 0.025, 0, 0.35, 0.025, 0.05)
        H.box(col, x, 0.025, 0, 0.05, 0.025, 0.35)
    bar([a, b], -1.2, 1.2, 0.9 + 0.012 + 0.035, 0.0, 0.035, 0.30)
    H.box(col, 0, 0.947, 0, 1.2, 0.035, 0.035)
    return entity_pair("jumpStandards", white, a, b, col)

MATERIALS = {
    "jumpCross": ('0.96 0.96 0.94 1', '0.62 0.85 0.10 1', '0.96 0.96 0.94 1'),
    "jumpStandards": ('0.96 0.96 0.94 1', '0.82 0.08 0.10 1', '0.80 0.66 0.46 1'),
}

def write(name, vis, col, out, width, depth):
    hdr = type("Hd", (), {"version": 10, "seed": 61 if name == "jumpCross" else 67})()
    sf = type("SF", (), {"header": hdr, "entities": [H.Raw(1, vis), H.Raw(1, col)]})()
    S.write(os.path.join(out, name + ".i3d.shapes"), sf)
    w, a, b = MATERIALS[name]
    hx, hz = width / 2, depth / 2
    xml = f'''<?xml version="1.0" encoding="iso-8859-1"?>

<i3D name="{name}" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">
  <Asset>
    <Export program="make_horse_jumps.py" version="1"/>
  </Asset>
  <Files/>
  <Materials>
    <Material name="white" materialId="1" diffuseColor="{w}" specularColor="0.3 0.3 0.3"/>
    <Material name="stripeA" materialId="2" diffuseColor="{a}" specularColor="0.3 0.3 0.3"/>
    <Material name="stripeB" materialId="3" diffuseColor="{b}" specularColor="0.3 0.3 0.3"/>
  </Materials>
  <Shapes externalShapesFile="{name}.i3d.shapes">
  </Shapes>
  <Scene>
    <TransformGroup name="{name}" nodeId="1">
      <TransformGroup name="clearAreas" nodeId="2">
        <TransformGroup name="clearArea1Start" translation="{-hx} 0 {-hz}" nodeId="3">
          <TransformGroup name="clearArea1Width" translation="{width} 0 0" nodeId="4"/>
          <TransformGroup name="clearArea1Height" translation="0 0 {depth}" nodeId="5"/>
        </TransformGroup>
      </TransformGroup>
      <TransformGroup name="testAreas" nodeId="6">
        <TransformGroup name="testArea1Start" translation="{-hx} 0 {-hz}" nodeId="7">
          <TransformGroup name="testArea1End" translation="{width} 0 {depth}" nodeId="8"/>
        </TransformGroup>
      </TransformGroup>
      <TransformGroup name="mesh" nodeId="9">
        <Shape name="{name}_vis" shapeId="1" static="true" castsShadows="true" receiveShadows="true" materialIds="1,2,3" nodeId="10"/>
        <Shape name="col" shapeId="2" static="true" density="0" collisionFilterGroup="0x3e" collisionFilterMask="0xfffffbff" castsShadows="false" receiveShadows="false" nonRenderable="true" materialIds="1" nodeId="11"/>
      </TransformGroup>
    </TransformGroup>
  </Scene>

</i3D>
'''
    open(os.path.join(out, name + ".i3d"), "w", encoding="iso-8859-1").write(xml)

def build(out):
    os.makedirs(out, exist_ok=True)
    for name, fn, width, depth in (("jumpCross", jump_cross, 3.2, 1.0), ("jumpStandards", jump_standards, 3.2, 1.0)):
        vis, col = fn()
        write(name, vis, col, out, width, depth)
        print("wrote", name)

if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "placeables", "jumps"))
