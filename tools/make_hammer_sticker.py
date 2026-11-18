#!/usr/bin/env python3
"""The mouse plaque the Sandbox Hammer screws onto a hall it froze: a 44 cm plate with four screws and the builder mouse of the sticker sheet (hard hat and spanner) printed on its face (front = +z, turned to the wall's normal at run time).
  python3 tools/make_hammer_sticker.py [out dir, default ../FS25_Hammer/stickers]     -> hallSticker.i3d, hallSticker.i3d.shapes, hallSticker_diffuse.dds"""
import os, sys, subprocess, tempfile
import numpy as np
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here)
import make_hitching_post as H
import shapes_io as S
import make_horse_ball_mice as M

SIZE = 0.40            # metres
CELL = 1               # the builder (row 1, column 2 of the sheet)

def main(out):
    os.makedirs(out, exist_ok=True)
    patch = os.path.join(here, "..", "..", "FS25_Hammer", "assets", "frozen_mouse.png")          # the user's embroidered pilot mouse with the snowflake, if it is saved there
    if os.path.exists(patch):
        raw = subprocess.run(["convert", patch, "-background", "none", "-resize", "512x512", "-gravity", "center", "-extent", "512x512", "-depth", "8", "rgba:-"], capture_output=True, check=True).stdout
        im = np.frombuffer(raw, np.uint8).reshape(512, 512, 4).astype(float) / 255
        rgb, alpha = im[..., :3], im[..., 3]
        print("using", patch)
    else:
        with tempfile.TemporaryDirectory() as tmp:
            rgb, alpha = M.cells(tmp, 512)[CELL]
    a = np.clip((alpha - 0.04) / 0.2, 0, 1) if not os.path.exists(patch) else alpha
    # the face: an icy panel (a gradient, a darker border line, a little grain) with the mouse on it, opaque
    N = 512
    yy, xx = np.mgrid[0:N, 0:N] / (N - 1)
    top, bot = np.array([0.86, 0.94, 0.98]), np.array([0.62, 0.80, 0.91])
    bg = top[None, None, :] * (1 - yy[..., None]) + bot[None, None, :] * yy[..., None]
    rng = np.random.default_rng(3)
    bg = bg * (1 + 0.025 * rng.normal(0, 1, (N, N, 1)))
    edge = np.minimum(np.minimum(xx, 1 - xx), np.minimum(yy, 1 - yy))
    bg = np.where(((edge > 0.018) & (edge < 0.03))[..., None], np.array([0.30, 0.50, 0.65]), bg)          # the border line
    bg = np.where((edge <= 0.018)[..., None], np.array([0.46, 0.64, 0.76]), bg)                            # a darker rim outside it
    k = 0.84; m0 = int(N * (1 - k) / 2)
    raw_m = (np.dstack([np.clip(rgb, 0, 1), a]) * 255 + 0.5).astype(np.uint8).tobytes()
    big = subprocess.run(["convert", "-size", "%dx%d" % (rgb.shape[1], rgb.shape[0]), "-depth", "8", "rgba:-", "-filter", "Lanczos", "-resize", "%dx%d!" % (int(N * k), int(N * k)), "-depth", "8", "rgba:-"], input=raw_m, capture_output=True, check=True).stdout
    mouse = np.frombuffer(big, np.uint8).reshape(int(N * k), int(N * k), 4).astype(float) / 255
    face = bg.copy()
    reg = (slice(m0, m0 + mouse.shape[0]), slice(m0, m0 + mouse.shape[1]))
    face[reg] = face[reg] * (1 - mouse[..., 3:4]) + mouse[..., :3] * mouse[..., 3:4]
    rgba = np.dstack([np.clip(face, 0, 1), np.ones((N, N))])
    png = os.path.join(out, "hallSticker_diffuse.png")
    raw = (rgba * 255 + 0.5).astype(np.uint8).tobytes()
    subprocess.run(["convert", "-size", "512x512", "-depth", "8", "rgba:-", png], input=raw, check=True)
    M.tool_dds(png)
    os.remove(png)
    # a small plaque: a flat plate against the wall (back at z = 0, 12 mm thick, 44 cm square), the sticker printed on its face, a screw in each corner. The front is +z: it is turned to the wall's normal at run time.
    plate = H.Mesh(); face = H.Mesh(); screws = H.Mesh()
    PH, PT = 0.22, 0.012
    H.box(plate, 0, 0, -PT / 2, PH, PH, PT / 2)
    hs = 0.20
    q = [(-hs, -hs), (hs, -hs), (hs, hs), (-hs, hs)]
    uvs = [(0, 0), (1, 0), (1, 1), (0, 1)]
    ids = [face.vert((x, y, 0.0006), (0, 0, 1), uv) for (x, y), uv in zip(q, uvs)]
    face.quad(*ids)
    for sx in (-1, 1):
        for sy in (-1, 1):
            m = H.Mesh()
            H.cylinder(m, sx * (PH - 0.022), 0.0, 0.0, 0.006, 0.0095, sides=10)               # a round head 6 mm high, 19 mm across, axis along y ...
            base = len(screws.p)
            for p_, n_, uv_ in zip(m.p, m.n, m.uv):                                              # ... turned so that its axis is z: (x, y, z) -> (x, z + sy*(PH-0.022), y)
                screws.vert((p_[0], p_[2] + sy * (PH - 0.022), p_[1]), (n_[0], n_[2], n_[1]), uv_)
            for a_, b_, c_ in m.t:
                screws.t.append((a_ + base, c_ + base, b_ + base))                              # (the swap of two axes flips the winding)
    P, N, U, T, subsets = H.merge([(plate, 1), (face, 2), (screws, 3)])
    ent = H.shape_entity("hallPlate", 1, P, N, U, T, subsets, ["plate_mat", "sticker_mat", "screw_mat"])
    hdr = type("Hd", (), {"version": 10, "seed": 91})()
    sf = type("SF", (), {"header": hdr, "entities": [H.Raw(1, ent)]})()
    S.write(os.path.join(out, "hallSticker.i3d.shapes"), sf)
    xml = '''<?xml version="1.0" encoding="iso-8859-1"?>

<i3D name="hallSticker" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">
  <Asset>
    <Export program="make_hammer_sticker.py" version="2"/>
  </Asset>
  <Files>
    <File fileId="1" filename="$data/shaders/vehicleShader.xml" />
    <File fileId="2" filename="hallSticker_diffuse.dds" />
    <File fileId="3" filename="$data/shared/default_normal.png" />
    <File fileId="4" filename="$data/shared/default_vmask.png" />
    <File fileId="5" filename="$data/shared/white_diffuse.png" />
    <File fileId="6" filename="$data/shared/detailLibrary/calibrated/calibratedPaint_diffuse.png" />
    <File fileId="7" filename="$data/shared/detailLibrary/calibrated/calibratedPaint_normal.png" />
    <File fileId="8" filename="$data/shared/detailLibrary/calibrated/calibratedPaint_specular.png" />
  </Files>
  <Materials>
    <Material name="plate_mat" materialId="1" customShaderId="1">
      <CustomParameter name="colorScale" value="0.78 0.80 0.80"/>
      <CustomParameter name="smoothnessScale" value="0.35"/>
      <Custommap name="detailDiffuse" fileId="6"/>
      <Custommap name="detailNormal" fileId="7"/>
      <Custommap name="detailSpecular" fileId="8"/>
      <Texture fileId="5"/>
      <Normalmap fileId="3"/>
      <Glossmap fileId="4"/>
    </Material>
    <Material name="sticker_mat" materialId="2" customShaderId="1">
      <CustomParameter name="colorScale" value="1 1 1"/>
      <CustomParameter name="smoothnessScale" value="0.4"/>
      <Custommap name="detailDiffuse" fileId="6"/>
      <Custommap name="detailNormal" fileId="7"/>
      <Custommap name="detailSpecular" fileId="8"/>
      <Texture fileId="2"/>
      <Normalmap fileId="3"/>
      <Glossmap fileId="4"/>
    </Material>
    <Material name="screw_mat" materialId="3" customShaderId="1">
      <CustomParameter name="colorScale" value="0.42 0.43 0.45"/>
      <CustomParameter name="smoothnessScale" value="0.85"/>
      <Custommap name="detailDiffuse" fileId="6"/>
      <Custommap name="detailNormal" fileId="7"/>
      <Custommap name="detailSpecular" fileId="8"/>
      <Texture fileId="5"/>
      <Normalmap fileId="3"/>
      <Glossmap fileId="4"/>
    </Material>
  </Materials>
  <Shapes externalShapesFile="hallSticker.i3d.shapes">
  </Shapes>
  <Scene>
    <Shape name="hallPlate" shapeId="1" castsShadows="true" receiveShadows="true" materialIds="1,2,3" nodeId="1"/>
  </Scene>

</i3D>
'''
    open(os.path.join(out, "hallSticker.i3d"), "w", encoding="iso-8859-1").write(xml)
    print("wrote", out, "verts", len(P), "tris", len(T) // 3)

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "..", "FS25_Hammer", "stickers"))
