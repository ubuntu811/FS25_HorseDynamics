#!/usr/bin/env python3
"""The horse harness as an object: a collar, two traces and two rings lying on the ground, a dynamic shop vehicle like the ball and the jumps (picked up with the hands, set down anywhere). Put on a horse by
the key next to it (HorseHarnessItem.lua), the harness the scripts draw on the horse is then this one.
  python3 tools/make_horse_harness_item.py [out dir]     -> vehicles/horseHarness/horseHarnessItem.i3d, .i3d.shapes, .xml
The collision is one box (a harness bundle is not a precise shape); the origin is the bottom of the object. Materials: 1 leather, 2 steel."""
import math, os, sys
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here)
import make_hitching_post as H
import make_horse_jumps as J
import shapes_io as S

def rot_x(m, start, angle, pivot_y=0.0):
    c, s = math.cos(angle), math.sin(angle)
    for i in range(start, len(m.p)):
        x, y, z = m.p[i]; y -= pivot_y
        m.p[i] = (x, pivot_y + y * c - z * s, y * s + z * c)
        nx, ny, nz = m.n[i]; m.n[i] = (nx, ny * c - nz * s, ny * s + nz * c)

NAME = "horseHarnessItem"

def build(out):
    os.makedirs(out, exist_ok=True)
    leather, steel = H.Mesh(), H.Mesh()
    # the collar: a padded ring lying flat (the torus builder makes a ring facing +z: turned onto the ground), 56 cm across, 9 cm thick
    start = len(leather.p)
    H.torus(leather, 0, 0, 0, 0.23, 0.045, major=24, minor=10)
    rot_x(leather, start, math.pi / 2)
    for i in range(start, len(leather.p)):
        x, y, z = leather.p[i]; leather.p[i] = (x, y + 0.05, z)
    # two traces: flat straps from the collar's sides, 60 cm long
    for sx in (-1, 1):
        H.box(leather, sx * 0.55, 0.015, 0.0, 0.30, 0.012, 0.025)
        # a ring where the trace meets the collar
        start = len(steel.p)
        H.torus(steel, 0, 0, 0, 0.035, 0.008, major=14, minor=6)
        rot_x(steel, start, math.pi / 2)
        for i in range(start, len(steel.p)):
            x, y, z = steel.p[i]; steel.p[i] = (x + sx * 0.28, y + 0.04, z)
    # a girth strap across the middle
    H.box(leather, 0.0, 0.012, 0.36, 0.20, 0.012, 0.03)
    P, N, U, T, subsets = H.merge([(leather, 1), (steel, 2)])
    vis = H.shape_entity(NAME + "_vis", 1, P, N, U, T, subsets, ["leather", "steel"])
    c, h = (0.0, 0.065, 0.1), (0.46, 0.065, 0.40)
    m = H.Mesh(); H.box(m, c[0], c[1], c[2], h[0], h[1], h[2])
    cp, cn, cu, ct, csub = H.merge([(m, 1)])
    col = H.shape_entity(NAME + "_col", 2, cp, cn, cu, ct, csub, ["leather"], attachments=[(2, J.hull_block(c, h))])
    hdr = type("Hd", (), {"version": 10, "seed": 71})()
    sf = type("SF", (), {"header": hdr, "entities": [H.Raw(1, vis), H.Raw(1, col)]})()
    S.write(os.path.join(out, NAME + ".i3d.shapes"), sf)
    xml = f'''<?xml version="1.0" encoding="iso-8859-1"?>

<i3D name="{NAME}" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">
  <Asset>
    <Export program="make_horse_harness_item.py" version="1"/>
  </Asset>
  <Files/>
  <Materials>
    <Material name="leather" materialId="1" diffuseColor="0.36 0.20 0.10 1" specularColor="0.25 0.25 0.25"/>
    <Material name="steel" materialId="2" diffuseColor="0.55 0.56 0.6 1" specularColor="0.8 0.8 0.8"/>
  </Materials>
  <Shapes externalShapesFile="{NAME}.i3d.shapes">
  </Shapes>
  <Scene>
    <Shape name="{NAME}_main_component1" shapeId="2" dynamic="true" compound="true" collisionFilterGroup="0x10004" collisionFilterMask="0xfe3ffb83" linearDamping="0.2" angularDamping="0.8" staticFriction="1" dynamicFriction="1" castsShadows="false" receiveShadows="false" nonRenderable="true" materialIds="1" nodeId="1">
      <Shape name="{NAME}_vis" shapeId="1" castsShadows="true" receiveShadows="true" materialIds="1,2" nodeId="2"/>
    </Shape>
  </Scene>

</i3D>
'''
    open(os.path.join(out, NAME + ".i3d"), "w", encoding="iso-8859-1").write(xml)
    vx = f'''<?xml version="1.0" encoding="utf-8" standalone="no" ?>
<vehicle type="horseHarnessItem" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="../../../../shared/xml/schema/vehicle.xsd">
    <annotation>The horse harness as an object (FS25_HorseDynamics), made by tools/make_horse_harness_item.py.</annotation>

    <storeData>
        <name>
            <en>Horse harness</en>
            <de>Pferdegeschirr</de>
        </name>
        <functions>
            <function>A collar and traces. Set it down next to a horse you ride and press the attach key (Q) to put it on; press Q again to take it off.</function>
        </functions>
        <image>vehicles/horseHarness/store_horseHarness.dds</image>
        <price>180</price>
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
        <typeDesc>Horse harness</typeDesc>
        <filename>vehicles/horseHarness/{NAME}.i3d</filename>
        <size width="1.0" length="1.0" height="0.2" />
        <canBeReset>true</canBeReset>
        <components maxMass="200">
            <component centerOfMass="0 0.065 0" solverIterationCount="10" mass="8"/>
        </components>
        <showInVehicleMenu>true</showInVehicleMenu>
        <mapHotspot available="false" />
        <input allowed="false"/>
    </base>

    <i3dMappings>
        <i3dMapping id="{NAME}_main_component1" node="0>" />
    </i3dMappings>
</vehicle>
'''
    open(os.path.join(out, NAME + ".xml"), "w", encoding="utf-8").write(vx)
    print("wrote", NAME, "verts", len(P), "tris", len(T) // 3)

if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "vehicles", "horseHarness"))
