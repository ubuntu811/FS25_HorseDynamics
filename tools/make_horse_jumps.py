#!/usr/bin/env python3
"""Two horse jumps as shop vehicles (dynamic objects like the horse ball and the game's pallets: bought in the shop, picked up with the hands, set down anywhere, knocked over by a horse):
  jumpCross      a low cross-pole: two white X stands (in the plane across the bar), a bar in green and white (the bar 50 cm up), 12 kg
  jumpStandards  a jump with two posts on cross feet, pins every 30 cm, a red and natural bar on the pin at 90 cm, 15 kg
  python3 tools/make_horse_jumps.py [out dir]      -> vehicles/horseJumps/<name>.i3d, .i3d.shapes, .xml (the vehicle xml)
A jump is not one convex shape, so its body is a compound: the first collision box is the root shape, the others are compoundChild shapes (as in the game's pallets); each has its own cooked convex hull
block (make_horse_ball.hull_block: the 8 corners `margin` inside the box, the volume, the centre of mass and the inertia of the box). The origin is the bottom of the jump (a vehicle's origin stands on the floor).
Materials: 1 white wood, 2 the first stripe colour, 3 the second stripe colour.
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

def rot_x(m, start, angle, pivot):
    """Turns the vertices (and normals) added since index `start` round the x axis through pivot = (py, pz)."""
    c, s = math.cos(angle), math.sin(angle)
    for i in range(start, len(m.p)):
        x, y, z = m.p[i]; y -= pivot[0]; z -= pivot[1]
        m.p[i] = (x, pivot[0] + y * c - z * s, pivot[1] + y * s + z * c)
        nx, ny, nz = m.n[i]; m.n[i] = (nx, ny * c - nz * s, ny * s + nz * c)

def board_x(m, cx, cy, cz, length, width, thick, angle):
    """A board whose long side is vertical, its flat face looking along the bar (x), turned by `angle` round x about its centre: one arm of an X stand in the y-z plane."""
    start = len(m.p)
    H.box(m, cx, cy, cz, thick / 2, length / 2, width / 2)
    rot_x(m, start, angle, (cy, cz))

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

def hull_block(c, h):
    """The collision block of a box (centre c, half extents h): 'cm' + version 4, 8 vertices, 14 floats (margin, volume, centre of mass, inertia per unit mass about it) and the vertices."""
    import struct
    margin = min(0.04, 0.35 * min(h))
    vol = 8 * h[0] * h[1] * h[2]
    ixx, iyy, izz = (h[1] ** 2 + h[2] ** 2) / 3, (h[0] ** 2 + h[2] ** 2) / 3, (h[0] ** 2 + h[1] ** 2) / 3
    b = b"cm\x04\x00" + struct.pack("<I", 8)
    b += struct.pack("<14f", margin, vol, c[0], c[1], c[2], ixx, 0, 0, 0, iyy, 0, 0, 0, izz)
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                b += struct.pack("<3f", c[0] + sx * (h[0] - margin), c[1] + sy * (h[1] - margin), c[2] + sz * (h[2] - margin))
    return b

def shapes_of(name, white, a, b, boxes):
    """entity 1 = what is seen; entities 2.. = one collision box each (each with its hull block)."""
    P, N, U, T, subsets = H.merge([(white, 1), (a, 2), (b, 3)])
    ents = [H.shape_entity("%s_vis" % name, 1, P, N, U, T, subsets, ["white", "stripeA", "stripeB"])]
    for i, (c, h) in enumerate(boxes):
        m = H.Mesh(); H.box(m, c[0], c[1], c[2], h[0], h[1], h[2])
        cp, cn, cu, ct, csub = H.merge([(m, 1)])
        ents.append(H.shape_entity("%s_col%d" % (name, i + 1), i + 2, cp, cn, cu, ct, csub, ["white"], attachments=[(2, hull_block(c, h))]))
    return ents

def jump_cross():
    """Two X stands (in the y-z plane: the X faces along the bar), the bar resting in the V at the top of each: with an arm tilt of 32 degrees a bar of radius 3.5 cm sits 6.6 cm above the crossing."""
    white, a, b, col = H.Mesh(), H.Mesh(), H.Mesh(), []
    for sx in (-1, 1):
        x = sx * 1.1
        board_x(white, x - 0.012, 0.43, 0, 0.80, 0.10, 0.045, math.radians(32))
        board_x(white, x + 0.012, 0.43, 0, 0.80, 0.10, 0.045, math.radians(-32))
        H.box(white, x, 0.03, 0, 0.06, 0.03, 0.40)                # the base plank, along z, under the lower arms
        col.append(((x, 0.03, 0), (0.06, 0.03, 0.40)))            # (collision boxes: the base, the X as one thin box)
        col.append(((x, 0.43, 0), (0.05, 0.32, 0.27)))
    bar([a, b], -1.3, 1.3, 0.43 + 0.066, 0.0, 0.035, 0.26)
    col.append(((0, 0.50, 0), (1.3, 0.035, 0.035)))
    return shapes_of("jumpCross", white, a, b, col)

def jump_standards():
    white, a, b, col = H.Mesh(), H.Mesh(), H.Mesh(), []
    for sx in (-1, 1):
        x = sx * 1.2
        H.box(white, x, 0.70, 0, 0.03, 0.70, 0.03)                 # the post, 1.4 m
        H.box(white, x, 0.025, 0, 0.35, 0.025, 0.05)              # the cross foot: along z ...
        H.box(white, x, 0.025, 0, 0.05, 0.025, 0.35)              # ... and along x
        for h in (0.3, 0.6, 0.9, 1.2):                             # pins on the inner side
            H.box(white, x - sx * 0.055, h, 0, 0.025, 0.012, 0.03)
        col.append(((x, 0.025, 0), (0.35, 0.025, 0.05)))           # (collision boxes: the two feet, the post)
        col.append(((x, 0.025, 0), (0.05, 0.025, 0.35)))
        col.append(((x, 0.70, 0), (0.03, 0.70, 0.03)))
    bar([a, b], -1.2, 1.2, 0.9 + 0.012 + 0.035, 0.0, 0.035, 0.30)
    col.append(((0, 0.947, 0), (1.2, 0.035, 0.035)))
    return shapes_of("jumpStandards", white, a, b, col)

MATERIALS = {
    "jumpCross": ('0.96 0.96 0.94 1', '0.62 0.85 0.10 1', '0.96 0.96 0.94 1'),
    "jumpStandards": ('0.96 0.96 0.94 1', '0.82 0.08 0.10 1', '0.80 0.66 0.46 1'),
}

VEHICLE = {   # name: (store name, price, mass kg, centre of mass y, width, depth, height, text)
    "jumpCross": ("Horse jump: cross-pole", 90, 12.0, 0.25, 3.2, 1.0, 0.8, "A low cross-pole jump (bar at 50 cm). Pick it up with your hands, set it down where you want; a horse that hits it knocks it over."),
    "jumpStandards": ("Horse jump: standards", 120, 15.0, 0.5, 3.2, 1.0, 1.4, "A jump on two posts with pins every 30 cm (bar at 90 cm). Pick it up with your hands, set it down where you want; a horse that hits it knocks it over."),
}

def write(name, ents, out):
    hdr = type("Hd", (), {"version": 10, "seed": 61 if name == "jumpCross" else 67})()
    sf = type("SF", (), {"header": hdr, "entities": [H.Raw(1, e) for e in ents]})()
    S.write(os.path.join(out, name + ".i3d.shapes"), sf)
    w, a, b = MATERIALS[name]
    title, price, mass, comy, width, depth, height, text = VEHICLE[name]
    n = len(ents) - 1                                        # the number of collision boxes: shape ids 2 .. n + 1; the first is the root
    kids = "\n".join('      <Shape name="%s_col%d" shapeId="%d" compoundChild="true" static="false" density="0.0005" collisionFilterGroup="0x10000" collisionFilterMask="0xfe3dfb83" castsShadows="false" receiveShadows="false" nonRenderable="true" materialIds="1" nodeId="%d"/>' % (name, i, i + 1, 10 + i) for i in range(2, n + 1))
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
    <Shape name="{name}_main_component1" shapeId="2" dynamic="true" compound="true" density="0.0005" collisionFilterGroup="0x10004" collisionFilterMask="0xfe3ffb83" linearDamping="0.1" angularDamping="0.5" castsShadows="false" receiveShadows="false" nonRenderable="true" materialIds="1" nodeId="1">
      <Shape name="{name}_vis" shapeId="1" castsShadows="true" receiveShadows="true" materialIds="1,2,3" nodeId="2"/>
{kids}
    </Shape>
  </Scene>

</i3D>
'''
    open(os.path.join(out, name + ".i3d"), "w", encoding="iso-8859-1").write(xml)
    vx = f'''<?xml version="1.0" encoding="utf-8" standalone="no" ?>
<vehicle type="horseJump" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="../../../../shared/xml/schema/vehicle.xsd">
    <annotation>{title} (FS25_HorseDynamics), made by tools/make_horse_jumps.py.</annotation>

    <storeData>
        <name>
            <en>{title}</en>
        </name>
        <functions>
            <function>{text}</function>
        </functions>
        <image>vehicles/horseJumps/store_{name}.dds</image>
        <price>{price}</price>
        <lifetime>1000</lifetime>
        <category>objectAnimal</category>
        <brand>NONE</brand>
        <showInStore>true</showInStore>
        <canBeSold>true</canBeSold>
        <allowLeasing>false</allowLeasing>
        <financeCategory>OTHER</financeCategory>
        <vertexBufferMemoryUsage>0</vertexBufferMemoryUsage>
        <indexBufferMemoryUsage>0</indexBufferMemoryUsage>
        <textureMemoryUsage>0</textureMemoryUsage>
        <instanceVertexBufferMemoryUsage>0</instanceVertexBufferMemoryUsage>
        <instanceIndexBufferMemoryUsage>0</instanceIndexBufferMemoryUsage>
        <storeIconRendering>
            <settings cameraXRot="-15" cameraYRot="35" />
        </storeIconRendering>
        <audioMemoryUsage>0</audioMemoryUsage>
    </storeData>

    <base>
        <typeDesc>Horse jump</typeDesc>
        <filename>vehicles/horseJumps/{name}.i3d</filename>
        <size width="{width}" length="{depth}" height="{height}" />
        <canBeReset>true</canBeReset>
        <components maxMass="200">
            <component centerOfMass="0 {comy} 0" solverIterationCount="10" mass="{mass:g}"/>
        </components>
        <showInVehicleMenu>true</showInVehicleMenu>
        <mapHotspot available="false" />
        <input allowed="false"/>
    </base>

    <i3dMappings>
        <i3dMapping id="{name}_main_component1" node="0>" />
    </i3dMappings>
</vehicle>
'''
    open(os.path.join(out, name + ".xml"), "w", encoding="utf-8").write(vx)

def build(out):
    os.makedirs(out, exist_ok=True)
    for name, fn in (("jumpCross", jump_cross), ("jumpStandards", jump_standards)):
        ents = fn()
        write(name, ents, out)
        print("wrote", name, "with", len(ents) - 1, "collision boxes")

if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "vehicles", "horseJumps"))
