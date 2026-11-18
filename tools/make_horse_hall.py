#!/usr/bin/env python3
"""The horse hall: the room the shop's 3D preview shows a horse in (instead of the machine workshop): a box of wood panels with a straw floor, a ceiling, a spot light from above and a few warm point lights.
  python3 tools/make_horse_hall.py [out dir]     -> models/hall/horseHall.i3d, horseHall.i3d.shapes
The origin is the middle of the floor (the shop puts the vehicle there); the floor is y = 0; the camera orbits inside, so the room is big (22 x 22 m, 7 m high). Textures are the game's own
($data/fillPlanes/straw_diffuse for the floor, $data/store/ui/shopWood_diffuse for the panels, tinted warm). No collision: it is only to look at."""
import os, sys
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here)
import make_hitching_post as H
import shapes_io as S
from make_horse_ball import TMesh

W, D, HT = 22.0, 22.0, 7.0

def wall(m, origin, u, v, w, h, normal, per_m_u, per_m_v):
    """A quad seen from the side the normal points to (counter-clockwise there): from origin along u (w long) and v (h long); the texture repeats per_m_* times per metre."""
    pts = [origin,
           tuple(origin[i] + u[i] * w for i in range(3)),
           tuple(origin[i] + u[i] * w + v[i] * h for i in range(3)),
           tuple(origin[i] + v[i] * h for i in range(3))]
    uvs = [(0, 0), (w * per_m_u, 0), (w * per_m_u, h * per_m_v), (0, h * per_m_v)]
    idx = [m.vert(p, normal, uv, (u[0], u[1], u[2], 1.0)) for p, uv in zip(pts, uvs)]
    m.quad(*idx)

def build(out):
    os.makedirs(out, exist_ok=True)
    floor = TMesh(); walls = TMesh()
    wall(floor, (-W / 2, 0, D / 2), (1, 0, 0), (0, 0, -1), W, D, (0, 1, 0), 1 / 3.0, 1 / 3.0)                  # straw: one tile per 3 m
    wall(walls, (-W / 2, 0, -D / 2), (1, 0, 0), (0, 1, 0), W, HT, (0, 0, 1), 0.5, 0.5)                           # north wall (looks +z)
    wall(walls, (W / 2, 0, D / 2), (-1, 0, 0), (0, 1, 0), W, HT, (0, 0, -1), 0.5, 0.5)                          # south wall
    wall(walls, (-W / 2, 0, D / 2), (0, 0, -1), (0, 1, 0), D, HT, (1, 0, 0), 0.5, 0.5)                          # west wall
    wall(walls, (W / 2, 0, -D / 2), (0, 0, 1), (0, 1, 0), D, HT, (-1, 0, 0), 0.5, 0.5)                          # east wall
    wall(walls, (-W / 2, HT, -D / 2), (1, 0, 0), (0, 0, 1), W, D, (0, -1, 0), 0.5, 0.5)                          # ceiling
    # every triangle must face the way its normal says (inwards): the cross product against the normal
    for m in (floor, walls):
        for a, b, c in m.t:
            pa, pb, pc = m.p[a], m.p[b], m.p[c]
            e1 = [pb[i] - pa[i] for i in range(3)]; e2 = [pc[i] - pa[i] for i in range(3)]
            cr = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
            n = m.n[a]
            assert cr[0] * n[0] + cr[1] * n[1] + cr[2] * n[2] > 0, "a face looks the wrong way"
    ents = []
    for sid, name, mesh, slot in ((1, "hallFloor", floor, "hall_straw"), (2, "hallWalls", walls, "hall_wood")):
        P, N, U, T, subsets = H.merge([(mesh, 1)])
        ents.append(H.Raw(1, H.shape_entity(name, sid, P, N, U, T, subsets, [slot], tangents=mesh.tan)))
    hdr = type("Hd", (), {"version": 10, "seed": 91})()
    sf = type("SF", (), {"header": hdr, "entities": ents})()
    S.write(os.path.join(out, "horseHall.i3d.shapes"), sf)
    mat = lambda name, mid, tex, color, smooth: f'''    <Material name="{name}" materialId="{mid}" customShaderId="1">
      <CustomParameter name="clearCoatIntensity" value="0"/>
      <CustomParameter name="clearCoatSmoothness" value="0.5"/>
      <CustomParameter name="colorScale" value="{color}"/>
      <CustomParameter name="smoothnessScale" value="{smooth}"/>
      <Custommap name="detailDiffuse" fileId="5"/>
      <Custommap name="detailNormal" fileId="6"/>
      <Custommap name="detailSpecular" fileId="7"/>
      <Texture fileId="{tex}"/>
      <Normalmap fileId="3"/>
      <Glossmap fileId="4"/>
    </Material>
'''
    spot = '<Light name="topLight" translation="0 6.4 0" rotation="-90 0 0" type="spot" color="1 0.850712 0.692" emitDiffuse="true" emitSpecular="true" castShadowMap="true" depthMapBias="0.001" depthMapResolution="2048" softShadowsLightSize="0.001" softShadowsLightDistance="15" softShadowsDepthBiasFactor="5" softShadowsMaxPenumbraSize="0.5" range="22" coneAngle="110" dropOff="4" clipDistance="200" nodeId="4"/>'
    points = "\n".join(f'      <Light name="warmLight{i + 1}" translation="{x} 3.2 {z}" type="point" color="0.55 0.40 0.26" emitDiffuse="true" emitSpecular="true" range="14" clipDistance="200" nodeId="{5 + i}"/>'
                       for i, (x, z) in enumerate(((-7, -7), (7, -7), (-7, 7), (7, 7))))
    xml = f'''<?xml version="1.0" encoding="iso-8859-1"?>

<i3D name="horseHall" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">
  <Asset>
    <Export program="make_horse_hall.py" version="1"/>
  </Asset>
  <Files>
    <File fileId="1" filename="$data/shaders/vehicleShader.xml" />
    <File fileId="2" filename="$data/fillPlanes/straw_diffuse.png" />
    <File fileId="3" filename="$data/shared/default_normal.png" />
    <File fileId="4" filename="$data/shared/default_vmask.png" />
    <File fileId="5" filename="$data/shared/detailLibrary/calibrated/calibratedPaint_diffuse.png" />
    <File fileId="6" filename="$data/shared/detailLibrary/calibrated/calibratedPaint_normal.png" />
    <File fileId="7" filename="$data/shared/detailLibrary/calibrated/calibratedPaint_specular.png" />
    <File fileId="8" filename="$data/store/ui/shopWood_diffuse.png" />
  </Files>
  <Materials>
{mat("hall_straw", 1, 2, "1 1 1", "0.15")}{mat("hall_wood", 2, 8, "0.78 0.55 0.36", "0.25")}  </Materials>
  <Shapes externalShapesFile="horseHall.i3d.shapes">
  </Shapes>
  <Scene>
    <TransformGroup name="horseHall" collision="false" clipDistance="300" nodeId="1">
      <Shape name="hallFloor" shapeId="1" castsShadows="false" receiveShadows="true" materialIds="1" clipDistance="300" nodeId="2"/>
      <Shape name="hallWalls" shapeId="2" castsShadows="false" receiveShadows="true" materialIds="2" clipDistance="300" nodeId="3"/>
      {spot}
{points}
    </TransformGroup>
  </Scene>

</i3D>
'''
    open(os.path.join(out, "horseHall.i3d"), "w", encoding="iso-8859-1").write(xml)
    print("wrote the horse hall in", out)

if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "models", "hall"))
