#!/usr/bin/env python3
"""Makes the coat mask texture of the foal shader (models/foal/coatMask.dds) from the game's horse mesh: one tile in the horse's UV layout (the same layout every coat tile of the atlas has).
  R = coat skin (what a tint / shade may change), G = eyeballs (gloss), B = hooves, A = pattern A (the white patches of the game's Pinto tile, inside the coat)
Triangles are classified by the bones that carry their vertices (eyes, hooves, tongue) and by the fixed corner of the tile the mouth interior lives in, rasterized into the tile and grown by 2 px so no seams stay open.
Usage: make_coat_mask.py <HorseModel dir (horse.i3d, .shapes, horse_diffuse.dds)> <out dir for coatMask.dds + preview png>"""
import sys, os, subprocess, xml.etree.ElementTree as ET
import numpy as np
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here)
import shapes_io as S
d, out = sys.argv[1], sys.argv[2]
N = 1024
root = ET.parse(os.path.join(d, "horse.i3d")).getroot()
names = {int(g.get("nodeId")): g.get("name") for g in root.iter("TransformGroup") if g.get("nodeId")}
body = [s for s in root.iter("Shape") if s.get("name") == "body"][0]
bind = [names[int(x)] for x in body.get("skinBindNodeIds").split()]
raw, sf = S.read(os.path.join(d, "horse.i3d.shapes"))
sh = [S.M.parse_shape_entity(e, sf.header.version) for e in sf.entities if e.entity_type.name == "SHAPE"]
b = [s for s in sh if s.name == "bodyShape"][0]
UV = np.array([[u.u, u.v] for u in b.uv_sets[0]]); W = np.array(b.blend_weights); I = np.array(b.blend_indices)
dom = [bind[I[v, W[v].argmax()]] for v in range(len(UV))]
EYE = {"Eye_R", "Eye_L"}; HOOF = {"hoofFrontLeft", "hoofFrontRight", "hoofBackLeft", "hoofBackRight", "frontToes_L", "frontToes_R", "backToes_L", "backToes_R"}
chan = np.zeros((N, N, 4), np.uint8)
def fill(tri, c):
    p = UV[list(tri)] * [N, N]; p[:, 1] = N - p[:, 1]                # image row 0 = the top of the tile (v = 1)
    x0, x1 = int(max(0, np.floor(p[:, 0].min()))), int(min(N - 1, np.ceil(p[:, 0].max())))
    y0, y1 = int(max(0, np.floor(p[:, 1].min()))), int(min(N - 1, np.ceil(p[:, 1].max())))
    if x1 < x0 or y1 < y0: return
    xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
    (ax, ay), (bx, by), (cx, cy) = p
    den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    if abs(den) < 1e-9: return
    l1 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / den; l2 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / den
    inside = (l1 >= -0.02) & (l2 >= -0.02) & (1 - l1 - l2 >= -0.02)
    chan[y0:y1 + 1, x0:x1 + 1, c][inside] = 255
for tri in b.triangles:
    t = (tri.p1 - 1, tri.p2 - 1, tri.p3 - 1)      # (1-based in the parsed model)
    ds = [dom[v] for v in t]; cu, cv = UV[list(t)].mean(0)
    if sum(x in EYE for x in ds) >= 2: fill(t, 1)
    elif sum(x in HOOF for x in ds) >= 2: fill(t, 2)
    elif sum(x == "tongue3_M" for x in ds) >= 2 or (cu < 0.31 and cv > 0.78): fill(t, 3)        # (mouth interior: kept out of the coat, no channel of its own)
    else: fill(t, 0)
def grow(a, n=2):
    a = a.copy()
    for _ in range(n):
        g = a.copy()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            g = np.maximum(g, np.roll(np.roll(a, dy, 0), dx, 1))
        a = g
    return a
R, G, B, M = (grow(chan[:, :, c]) for c in range(4))
R[(G > 0) | (B > 0) | (M > 0)] = 0
# pattern A: the white patches of the game's Pinto tile (second tile of the bottom row of the atlas), inside the coat
atlas = os.path.join(out, "_atlas.png")
subprocess.run(["convert", os.path.join(d, "horse_diffuse.dds"), "-alpha", "off", atlas], check=True)
tile = os.path.join(out, "_pinto.rgb")
subprocess.run(["convert", atlas, "-crop", "1024x1024+1024+1024", "+repage", "-depth", "8", "rgb:" + tile], check=True)
pinto = np.fromfile(tile, np.uint8).reshape(N, N, 3).astype(float)
mn, mx = pinto.min(2), pinto.max(2)
A = ((mn > 0.50 * 255) & (mx - mn < 0.24 * 255)).astype(np.uint8) * 255
A[R == 0] = 0
img = np.dstack([R, G, B, A]).astype(np.uint8)
rawf = os.path.join(out, "_mask.rgba"); img.tofile(rawf)
png = os.path.join(out, "coatMask_preview.png")
subprocess.run(["convert", "-size", "%dx%d" % (N, N), "-depth", "8", "rgba:" + rawf, png], check=True)
dds = os.path.join(out, "coatMask.dds")
subprocess.run(["convert", "-size", "%dx%d" % (N, N), "-depth", "8", "rgba:" + rawf, "-define", "dds:compression=dxt5", dds], check=True)
for f in (atlas, tile, rawf): os.remove(f)
print("coat %.0f%%, eyes %.1f%%, hooves %.1f%%, pattern %.1f%% of the tile -> %s" % tuple(list(100 * (x > 0).mean() for x in (R, G, B, A)) + [dds]))
