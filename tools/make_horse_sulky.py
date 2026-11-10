#!/usr/bin/env python3
"""The sulky: a plain modern two-wheeled cart for one horse, a vehicle store item (trailer-type: its one drawbar eye hitches to the horse's hook like a wagon's). i3d + .i3d.shapes written directly with
make_hitching_post's shape builder; the two spoked wheels are generated here (a thin tyre, a rim, a hub, 24 crossed spokes).
  python3 tools/make_horse_sulky.py [out dir]     -> vehicles/horseSulky/horseSulky.i3d, .i3d.shapes, .xml
Frame: y up, +z forward (to the horse), the origin on the ground under the axle. The axle is at y = WHEEL_R; the shafts run from the front of the side rails to ONE eye at the apex (an A-frame), where the node
"attacherJoint" sits (turned 90 degrees about y like the game's own trailers' eyes). The weight is just behind the axle and a skid at the back keeps the shafts about level when nobody holds them.
Materials: 1 frame (dark steel), 2 seat (black), 3 tyre, 4 rim (bright metal).
"""
import math, os, struct, sys
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here)
import make_hitching_post as H
import shapes_io as S

WHEEL_R, TYRE_R, TRACK = 0.46, 0.026, 0.64        # wheel radius (tyre outside), tyre tube radius, x of the wheel centres
RAIL_X, RAIL_Y = 0.40, 0.56                       # the side rails
TUBE = 0.017
EYE = (0.0, 0.70, 1.92)                           # the drawbar eye (apex of the shafts)
MASS = 45.0

# ---------- vector helpers
def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def add(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def mul(a, k): return (a[0] * k, a[1] * k, a[2] * k)
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def norm(a):
    l = math.sqrt(dot(a, a)); return (a[0] / l, a[1] / l, a[2] / l)

def oquad(m, a, b, c, d):
    """a quad whose triangles face the way the first vertex's normal points."""
    pa, pb, pc = m.p[a], m.p[b], m.p[c]
    if dot(cross(sub(pb, pa), sub(pc, pa)), m.n[a]) >= 0: m.quad(a, b, c, d)
    else: m.quad(a, d, c, b)

def frame_of(axis):
    """two unit vectors perpendicular to the axis"""
    ref = (0, 1, 0) if abs(axis[1]) < 0.9 else (1, 0, 0)
    u = norm(cross(axis, ref)); v = cross(axis, u)
    return u, v

def tube(m, p0, p1, r, sides=8):
    """a round tube from p0 to p1 (smooth sides, flat caps)"""
    ax = norm(sub(p1, p0)); u, v = frame_of(ax)
    ring0, ring1 = [], []
    for i in range(sides + 1):
        a = 2 * math.pi * i / sides
        n = add(mul(u, math.cos(a)), mul(v, math.sin(a)))
        ring0.append(m.vert(add(p0, mul(n, r)), n, (i / sides, 0)))
        ring1.append(m.vert(add(p1, mul(n, r)), n, (i / sides, 1)))
    for i in range(sides):
        oquad(m, ring0[i], ring0[i + 1], ring1[i + 1], ring1[i])
    for p, d in ((p0, mul(ax, -1)), (p1, ax)):
        c = m.vert(p, d, (0.5, 0.5))
        cap = []
        for i in range(sides + 1):
            a = 2 * math.pi * i / sides
            cap.append(m.vert(add(p, mul(add(mul(u, math.cos(a)), mul(v, math.sin(a))), r)), d, (0.5, 0.5)))
        for i in range(sides):
            a, b = cap[i], cap[i + 1]
            if dot(cross(sub(m.p[a], m.p[c]), sub(m.p[b], m.p[c])), d) >= 0: m.t.append((c, a, b))
            else: m.t.append((c, b, a))

def torus_ring(m, centre, axis, R, r, major=36, minor=6):
    """a torus round `centre` in the plane perpendicular to `axis`"""
    u, v = frame_of(norm(axis)); ax = norm(axis)
    rows = []
    for i in range(major + 1):
        a = 2 * math.pi * i / major; d = add(mul(u, math.cos(a)), mul(v, math.sin(a)))
        row = []
        for j in range(minor + 1):
            b = 2 * math.pi * j / minor
            n = add(mul(d, math.cos(b)), mul(ax, math.sin(b)))
            p = add(centre, add(mul(d, R + r * math.cos(b)), mul(ax, r * math.sin(b))))
            row.append(m.vert(p, n, (i / major, j / minor)))
        rows.append(row)
    for i in range(major):
        for j in range(minor):
            oquad(m, rows[i][j], rows[i + 1][j], rows[i + 1][j + 1], rows[i][j + 1])

def obox(m, c, axes, h):
    """an oriented box: centre, three unit axes, half extents (flat faces)"""
    for k in range(3):
        for s in (-1, 1):
            n = mul(axes[k], s); o1, o2 = axes[(k + 1) % 3], axes[(k + 2) % 3]
            fc = add(c, mul(n, h[k]))
            idx = []
            for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                p = add(fc, add(mul(o1, h[(k + 1) % 3] * su), mul(o2, h[(k + 2) % 3] * sv)))
                idx.append(m.vert(p, n, ((su + 1) * 0.1, (sv + 1) * 0.1)))
            oquad(m, *idx)

# ---------- collision hulls: an oriented box as a convex-hull block ('cm' v4: margin, volume, centre of mass, inertia per unit mass, hull vertices inset by the margin)
def hull_block(c, axes, h):
    margin = min(0.02, 0.35 * min(h))
    vol = 8 * h[0] * h[1] * h[2]
    d = [(h[1] ** 2 + h[2] ** 2) / 3, (h[0] ** 2 + h[2] ** 2) / 3, (h[0] ** 2 + h[1] ** 2) / 3]
    inertia = [sum(axes[k][i] * d[k] * axes[k][j] for k in range(3)) for i in range(3) for j in range(3)]
    b = b"cm\x04\x00" + struct.pack("<I", 8)
    b += struct.pack("<14f", margin, vol, c[0], c[1], c[2], *inertia)
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                p = add(c, add(mul(axes[0], sx * (h[0] - margin)), add(mul(axes[1], sy * (h[1] - margin)), mul(axes[2], sz * (h[2] - margin)))))
                b += struct.pack("<3f", *p)
    return b

def seg_box(p0, p1, half_a, half_b):
    """an oriented box along p0 -> p1 (its length axis), with the given half sizes across"""
    ax = norm(sub(p1, p0)); u, v = frame_of(ax)
    c = mul(add(p0, p1), 0.5); L = math.dist(p0, p1) / 2
    return c, (u, v, ax), (half_a, half_b, L)

def aabb_box(c, hx, hy, hz):
    return c, ((1, 0, 0), (0, 1, 0), (0, 0, 1)), (hx, hy, hz)

# ---------- the sulky body
def body():
    frame, seat, boxes = H.Mesh(), H.Mesh(), []
    def rail(p0, p1, r=TUBE, sides=8):
        tube(frame, p0, p1, r, sides)
    # side rails and cross tubes
    for sx in (-1, 1):
        rail((sx * RAIL_X, RAIL_Y, -0.58), (sx * RAIL_X, RAIL_Y, 0.46))
    rail((-RAIL_X, RAIL_Y, -0.58), (RAIL_X, RAIL_Y, -0.58))
    rail((-RAIL_X, RAIL_Y, 0.46), (RAIL_X, RAIL_Y, 0.46))
    rail((-RAIL_X, RAIL_Y, -0.05), (RAIL_X, RAIL_Y, -0.05))
    # the axle, and a strut from it up to each side rail
    rail((-(TRACK - 0.04), WHEEL_R, 0), (TRACK - 0.04, WHEEL_R, 0), r=0.014)
    for sx in (-1, 1):
        rail((sx * 0.30, WHEEL_R, 0), (sx * RAIL_X, RAIL_Y, -0.05))
        rail((sx * 0.30, WHEEL_R, 0), (sx * RAIL_X, RAIL_Y, 0.10))
    # the shafts: from the front corners to the one eye, two tubes meeting at the apex
    for sx in (-1, 1):
        rail((sx * RAIL_X, RAIL_Y, 0.46), EYE, r=0.019)
    # a brace between the shafts, a third of the way along
    t = 0.45
    bx = RAIL_X * (1 - t)
    by = RAIL_Y + (EYE[1] - RAIL_Y) * t
    bz = 0.46 + (EYE[2] - 0.46) * t
    rail((-bx, by, bz), (bx, by, bz), r=0.013)
    # the foot bar
    rail((-0.22, 0.50, 0.40), (0.22, 0.50, 0.40), r=0.014)
    for sx in (-1, 1):
        rail((sx * 0.22, 0.50, 0.40), (sx * 0.22, RAIL_Y, 0.40), r=0.012)
    # the rear skid: two legs down to a small shoe each
    for sx in (-1, 1):
        rail((sx * 0.22, RAIL_Y, -0.58), (sx * 0.22, 0.05, -0.64), r=0.014)
        H.box(frame, sx * 0.22, 0.02, -0.67, 0.03, 0.02, 0.10)
    # the eye: a steel ring on the apex, lying flat
    torus_ring(frame, (EYE[0], EYE[1], EYE[2] + 0.045), (0, 1, 0), 0.040, 0.008, major=24, minor=6)
    # the seat: a pad on a plate and a back
    obox(seat, (0, RAIL_Y + 0.055, -0.25), ((1, 0, 0), (0, 1, 0), (0, 0, 1)), (0.21, 0.04, 0.20))
    ang = math.radians(-14)                                           # the back leans back a little
    ay = (0, math.cos(ang), math.sin(ang)); az = (0, -math.sin(ang), math.cos(ang))
    obox(seat, (0, RAIL_Y + 0.27, -0.48), ((1, 0, 0), ay, az), (0.20, 0.17, 0.03))
    rail((-0.15, RAIL_Y, -0.45), (-0.15, RAIL_Y + 0.14, -0.45), r=0.012)
    rail((0.15, RAIL_Y, -0.45), (0.15, RAIL_Y + 0.14, -0.45), r=0.012)

    # collision: the frame as one block, the seat back, the shafts (oriented), the skid shoes
    boxes.append(aabb_box((0, RAIL_Y, -0.06), RAIL_X + 0.02, 0.06, 0.54))
    boxes.append(aabb_box((0, RAIL_Y + 0.27, -0.48), 0.20, 0.17, 0.04))
    for sx in (-1, 1):
        boxes.append(seg_box((sx * RAIL_X, RAIL_Y, 0.46), EYE, 0.02, 0.02))
        boxes.append(aabb_box((sx * 0.22, 0.12, -0.65), 0.03, 0.12, 0.11))
    return frame, seat, boxes

def wheel():
    """The wheel, axis along x, centred on the origin: thin tyre, rim, hub, crossed spokes."""
    tyre, rim = H.Mesh(), H.Mesh()
    torus_ring(tyre, (0, 0, 0), (1, 0, 0), WHEEL_R - TYRE_R, TYRE_R, major=48, minor=8)
    torus_ring(rim, (0, 0, 0), (1, 0, 0), WHEEL_R - 2 * TYRE_R - 0.006, 0.008, major=48, minor=6)
    tube(rim, (-0.035, 0, 0), (0.035, 0, 0), 0.032, sides=12)
    spokes = 24
    r_hub, r_rim = 0.030, WHEEL_R - 2 * TYRE_R - 0.012
    for i in range(spokes):
        a = 2 * math.pi * i / spokes
        side = 1 if i % 2 == 0 else -1
        hub = (side * 0.026, r_hub * math.cos(a), r_hub * math.sin(a))
        # the rim end sits on the other side of the rim plane: crossed lacing
        a2 = a + side * 0.12
        rm = (-side * 0.004, r_rim * math.cos(a2), r_rim * math.sin(a2))
        tube(rim, hub, rm, 0.0028, sides=4)
    return tyre, rim

MATERIALS = [("frame", '0.13 0.14 0.16 1', "0.5 0.5 0.5"), ("seat", '0.04 0.04 0.05 1', "0.2 0.2 0.2"),
             ("tyre", '0.03 0.03 0.03 1', "0.1 0.1 0.1"), ("rim", '0.78 0.80 0.83 1', "0.7 0.7 0.7")]

def write(out):
    os.makedirs(out, exist_ok=True)
    name = "horseSulky"
    frame, seat, boxes = body()
    P, N, U, T, subsets = H.merge([(frame, 1), (seat, 2)])
    ents = [H.shape_entity("sulky_vis", 1, P, N, U, T, subsets, ["frame", "seat"])]
    tyre, rim = wheel()
    P, N, U, T, subsets = H.merge([(tyre, 3), (rim, 4)])
    ents.append(H.shape_entity("sulky_wheel", 2, P, N, U, T, subsets, ["tyre", "rim"]))
    for i, (c, axes, h) in enumerate(boxes):
        m = H.Mesh()
        # a placeholder mesh of the box (the physics uses the hull block)
        obox(m, c, axes, h)
        cp, cn, cu, ct, csub = H.merge([(m, 1)])
        ents.append(H.shape_entity("sulky_col%d" % (i + 1), i + 3, cp, cn, cu, ct, csub, ["frame"], attachments=[(2, hull_block(c, axes, h))]))
    hdr = type("Hd", (), {"version": 10, "seed": 73})()
    sf = type("SF", (), {"header": hdr, "entities": [H.Raw(1, e) for e in ents]})()
    S.write(os.path.join(out, name + ".i3d.shapes"), sf)

    n = len(boxes)
    kids = "\n".join('      <Shape name="sulky_col%d" shapeId="%d" compoundChild="true" static="false" density="0.0005" collisionFilterGroup="0x10000" collisionFilterMask="0xfe1ffb83" castsShadows="false" receiveShadows="false" nonRenderable="true" materialIds="1" nodeId="%d"/>' % (i, i + 2, 20 + i) for i in range(2, n + 1))
    mats = "\n".join('    <Material name="%s" materialId="%d" diffuseColor="%s" specularColor="%s"/>' % (nm, k + 1, d, s) for k, (nm, d, s) in enumerate(MATERIALS))
    ex, ey, ez = EYE
    xml = f'''<?xml version="1.0" encoding="iso-8859-1"?>

<i3D name="{name}" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">
  <Asset>
    <Export program="make_horse_sulky.py" version="1"/>
  </Asset>
  <Files/>
  <Materials>
{mats}
  </Materials>
  <Shapes externalShapesFile="{name}.i3d.shapes">
  </Shapes>
  <Scene>
    <Shape name="{name}_main_component1" shapeId="3" dynamic="true" compound="true" density="0.0005" collisionFilterGroup="0x10004" collisionFilterMask="0xfe1ffb83" linearDamping="0.02" angularDamping="0.1" castsShadows="false" receiveShadows="false" nonRenderable="true" materialIds="1" nodeId="1">
      <Shape name="sulky_vis" shapeId="1" castsShadows="true" receiveShadows="true" materialIds="1,2" nodeId="2"/>
{kids}
      <TransformGroup name="attacherJoint" translation="{ex} {ey} {ez}" rotation="0 90 0" nodeId="3"/>
      <TransformGroup name="wheelLeft" translation="{TRACK} {WHEEL_R} 0" nodeId="4">
        <Shape name="sulky_wheelL" shapeId="2" castsShadows="true" receiveShadows="true" materialIds="3,4" nodeId="5"/>
      </TransformGroup>
      <TransformGroup name="wheelRight" translation="{-TRACK} {WHEEL_R} 0" nodeId="6">
        <Shape name="sulky_wheelR" shapeId="2" castsShadows="true" receiveShadows="true" materialIds="3,4" nodeId="7"/>
      </TransformGroup>
    </Shape>
  </Scene>

</i3D>
'''
    open(os.path.join(out, name + ".i3d"), "w", encoding="iso-8859-1").write(xml)

    vx = f'''<?xml version="1.0" encoding="utf-8" standalone="no" ?>
<vehicle type="horseSulky" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="../../../../shared/xml/schema/vehicle.xsd">
    <annotation>Sulky (FS25_HorseDynamics), made by tools/make_horse_sulky.py.</annotation>

    <storeData>
        <name>
            <en>Sulky</en>
            <de>Sulky</de>
        </name>
        <functions>
            <function>A plain, modern two-wheeled cart for one horse. Hitch it to a horse in its harness at the drawbar eye, like a wagon.</function>
        </functions>
        <image>vehicles/horseSulky/store_horseSulky.dds</image>
        <price>650</price>
        <lifetime>1000</lifetime>
        <category>trailer</category>
        <brand>NONE</brand>
        <showInStore>true</showInStore>
        <canBeSold>true</canBeSold>
        <allowLeasing>false</allowLeasing>
        <financeCategory>TRAILERS</financeCategory>
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
        <typeDesc>Sulky</typeDesc>
        <filename>vehicles/horseSulky/{name}.i3d</filename>
        <size width="1.4" length="2.9" height="1.1" lengthOffset="0.6"/>
        <components maxMass="400">
            <component centerOfMass="0 0.50 -0.12" solverIterationCount="10" mass="{MASS:g}"/>
        </components>
        <schemaOverlay attacherJointPosition="0 0" name="IMPLEMENT" />
        <mapHotspot type="TOOL_TRAILED" />
    </base>

    <wheels>
        <wheelConfigurations>
            <wheelConfiguration name="$l10n_configuration_valueDefault" price="0" saveId="DEFAULT">
                <wheels>
                    <wheel isLeft="true">
                        <physics repr="wheelLeft" radius="{WHEEL_R}" width="0.05" mass="0.012" restLoad="0.1" forcePointRatio="0.15" initialCompression="5" suspTravel="0.04" spring="40" damper="15"/>
                    </wheel>
                    <wheel isLeft="false">
                        <physics repr="wheelRight" radius="{WHEEL_R}" width="0.05" mass="0.012" restLoad="0.1" forcePointRatio="0.15" initialCompression="5" suspTravel="0.04" spring="40" damper="15"/>
                    </wheel>
                </wheels>
            </wheelConfiguration>
        </wheelConfigurations>
    </wheels>

    <attachable>
        <inputAttacherJoints>
            <inputAttacherJoint node="attacherJoint" jointType="trailer" attacherHeight="{ey:g}" />
        </inputAttacherJoints>
        <brakeForce force="0.05" maxForce="0.15" maxForceMass="400"/>
    </attachable>

    <i3dMappings>
        <i3dMapping id="{name}_main_component1" node="0>" />
        <i3dMapping id="attacherJoint" node="0>{n}" />
        <i3dMapping id="wheelLeft" node="0>{n + 1}" />
        <i3dMapping id="wheelRight" node="0>{n + 2}" />
    </i3dMappings>
</vehicle>
'''
    open(os.path.join(out, name + ".xml"), "w", encoding="utf-8").write(vx)
    print("wrote", name, "with", n, "collision boxes")

if __name__ == "__main__":
    write(sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "vehicles", "horseSulky"))
