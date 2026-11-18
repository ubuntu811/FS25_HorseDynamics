#!/usr/bin/env python3
"""Makes the second coat mask (models/foal/coatMask2.dds): the markings, as gradient fields the shader cuts with a threshold per animal.
The fields are computed in 3D on the game's horse mesh (bind pose) and rasterized into the horse's UV tile, so no seam shows where UV islands meet.
  R = spot density: where a spotted pattern may be and how thick (body and quarters full, neck less, head a third, none on the muzzle, the eyelids, the ears, thin on the lower legs); the spots themselves are made in the shader
  G = blanket gradient (high over the rump, falling toward the withers, belly and legs; ragged edge from noise); the extent setting is the threshold
  B = face marking levels: star 1.0, strip 0.75, snip 0.5 (soft edges); the face setting is the threshold (3 steps: star, blaze, blaze + snip)
  A = sock gradient (1 at the hoof, 0 at the knee / hock, each leg with its own offset and a ragged edge); the sock height setting is the threshold
The shapes are our own sketches of the idea (a blaze, socks, a blanket with spots, snowflake flecks), not copies of any real horse.
Usage: make_coat_mask2.py <HorseModel dir> <out dir> [--preview]     (writes coatMask2.dds uncompressed, since the gradients must not band; --preview also writes side views for a mix of settings)"""
import sys, os, subprocess
import numpy as np
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here)
import shapes_io as S
d, out = sys.argv[1], sys.argv[2]
N = 1024
raw, sf = S.read(os.path.join(d, "horse.i3d.shapes"))
sh = [S.M.parse_shape_entity(e, sf.header.version) for e in sf.entities if e.entity_type.name == "SHAPE"]
b = [s for s in sh if s.name == "bodyShape"][0]
UV = np.array([[u.u, u.v] for u in b.uv_sets[0]])
P3 = np.array([[p.x, p.y, p.z] for p in b.positions]); NR = np.array([[p.x, p.y, p.z] for p in b.normals])

# ---- rasterize position + normal into the tile ----
pos = np.zeros((N, N, 3)); nor = np.zeros((N, N, 3)); have = np.zeros((N, N), bool)
for tri in b.triangles:
    t = [tri.p1 - 1, tri.p2 - 1, tri.p3 - 1]
    p = UV[t] * [N, N]; p[:, 1] = N - p[:, 1]
    x0, x1 = int(max(0, np.floor(p[:, 0].min()))), int(min(N - 1, np.ceil(p[:, 0].max())))
    y0, y1 = int(max(0, np.floor(p[:, 1].min()))), int(min(N - 1, np.ceil(p[:, 1].max())))
    if x1 < x0 or y1 < y0: continue
    xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
    (ax, ay), (bx, by), (cx, cy) = p
    den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    if abs(den) < 1e-9: continue
    l1 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / den; l2 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / den; l3 = 1 - l1 - l2
    ins = (l1 >= -0.02) & (l2 >= -0.02) & (l3 >= -0.02)
    for arr, src in ((pos, P3), (nor, NR)):
        v = l1[..., None] * src[t[0]] + l2[..., None] * src[t[1]] + l3[..., None] * src[t[2]]
        sub = arr[y0:y1 + 1, x0:x1 + 1]; sub[ins] = v[ins]
    hv = have[y0:y1 + 1, x0:x1 + 1]; hv[ins] = True
cover = have.copy()
for _ in range(4):                      # grow into the gaps next to islands so the filter finds values there too
    for arr in (pos, nor):
        acc = np.zeros_like(arr); cnt = np.zeros(have.shape)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            h = np.roll(np.roll(have, dy, 0), dx, 1)
            acc += np.roll(np.roll(arr, dy, 0), dx, 1) * h[..., None]; cnt += h
        fill = (~have) & (cnt > 0)
        arr[fill] = acc[fill] / cnt[fill][:, None]
    g = have.copy()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)): g |= np.roll(np.roll(have, dy, 0), dx, 1)
    have = g
nor /= np.maximum(np.linalg.norm(nor, axis=2, keepdims=True), 1e-6)
X, Y, Z = pos[..., 0], pos[..., 1], pos[..., 2]

# ---- noise helpers (hash based, on 3D positions) ----
def h3(ix, iy, iz, seed):
    n = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791) ^ (seed * 2654435761 & 0xffffffff)
    n = (n ^ (n >> 13)) * 1274126177 & 0xffffffff
    return ((n ^ (n >> 16)) & 0xffff) / 65535.0
def vnoise(x, y, z, scale, seed):
    x, y, z = x / scale, y / scale, z / scale
    ix, iy, iz = np.floor(x).astype(np.int64), np.floor(y).astype(np.int64), np.floor(z).astype(np.int64)
    fx, fy, fz = x - ix, y - iy, z - iz
    fx, fy, fz = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy), fz * fz * (3 - 2 * fz)
    r = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (fx if dx else 1 - fx) * (fy if dy else 1 - fy) * (fz if dz else 1 - fz)
                r = r + w * h3(ix + dx, iy + dy, iz + dz, seed)
    return r
sm = lambda a, e0, e1: np.clip((a - e0) / (e1 - e0), 0, 1) ** 2 * (3 - 2 * np.clip((a - e0) / (e1 - e0), 0, 1))

# ---- R: spot density (0..1): where a spotted pattern may be, and how thick. The spots themselves are made in the shader (procedural, per animal); this map only says where.
# Thick on the body and quarters, thinner down the neck, sparse on the head, none on the muzzle, round the eyes (the lids), nor in the ears, fewer below the knees (hooves are excluded by the coat mask anyway).
density = 1 - 0.4 * sm(Z, 0.75, 1.2)                          # the neck: from full at the withers to 0.6 at the poll
density *= 1 - 0.65 * sm(Z, 1.1, 1.3)                         # the head: about a third
density *= 1 - sm(Z, 1.52, 1.64)                              # the muzzle: none
density *= 0.3 + 0.7 * sm(Y, 0.40, 0.85)                      # the lower legs: thin
density *= 0.75 + 0.25 * sm(-Z, -0.3, 0.7)                    # a little more toward the hindquarters
density *= 1 - sm(Y + 0.0 * Z, 2.05, 2.2) * (Z > 1.1)         # the ears (their tips are the highest part of the head)
eyes_uv = None
try:
    mask1 = subprocess.run(["convert", os.path.join(out, "coatMask.dds"), "-depth", "8", "-resize", "%dx%d!" % (N, N), "rgba:-"], check=True, capture_output=True).stdout
    eyes_uv = np.frombuffer(mask1, np.uint8).reshape(N, N, 4)[..., 1] > 128        # coatMask.dds G = the eyeballs
except Exception as e:
    print("no eye mask (%s): the eyelids are not cleared" % e)
if eyes_uv is not None and (eyes_uv & cover).any():
    ep = pos[eyes_uv & cover]
    for side in (ep[:, 0] > 0, ep[:, 0] <= 0):
        if side.any():
            c = ep[side].mean(0); dd = np.sqrt(((pos - c) ** 2).sum(2))
            density *= sm(dd, 0.045, 0.075)                   # round the eyeball: the lids and their corners stay clear
density *= 0.8 + 0.2 * vnoise(X, Y, Z, 0.35, 41)             # a mild patchiness, so the density is not the same everywhere
R = np.clip(density, 0, 1)

# ---- G: blanket gradient ----
along = np.clip(1 - (Z + 0.84) / 1.75, -0.3, 1)     # 1 at the rump, ~0.1 at the withers, negative in front (neck, head)
high = np.clip((Y - 0.95) / 0.65, 0, 1)             # 0 at the belly, 1 on the back
G = np.clip(0.8 * along + 0.3 * high * (along > 0) + 0.5 * (vnoise(X, Y, Z, 0.28, 11) - 0.5) + 0.12 * (vnoise(X, Y, Z, 0.09, 12) - 0.5) - 0.12, 0, 1)
G[Y < 0.75] *= 0.5                                   # the legs only join in when the blanket grows into a leopard

# ---- B: face levels ----
yline = 2.14 - 0.58 * (Z - 1.2)                      # the upper face line (poll at z 1.2, nose at z 1.66)
tface = (Z - 1.2) / 0.46
onface = (Z > 1.2) & (Z < 1.7) & (Y > yline - 0.12) & (Y < yline + 0.05) & (nor[..., 1] * 0.88 + nor[..., 2] * 0.48 > 0.35)
wob = 0.006 * (vnoise(X, Y, Z, 0.05, 21) - 0.5)
cxl = 0.006 * np.sin(tface * 4.0) + wob               # the stripe wanders a little off the middle line
ell = lambda t, tc, hl: np.sqrt(np.clip(1 - ((t - tc) / hl) ** 2, 0, 1))     # rounded ends
w_strip = (0.020 + 0.012 * sm(tface, 0.3, 0.7)) * ell(tface, 0.56, 0.30) ** 0.5
w_star = 0.034 * ell(tface, 0.31, 0.12)
w_snip = (0.040 + 0.03 * sm(tface, 0.8, 1.0)) * ell(tface, 0.97, 0.20) ** 0.5
lvl = np.zeros(X.shape)
dx = np.abs(X - cxl)
lvl[onface & (dx < w_snip) & (tface > 0.78)] = 0.5
lvl[onface & (dx < w_strip) & (tface > 0.26) & (tface < 0.86)] = 0.75
lvl[onface & (dx < w_star) & (tface > 0.19) & (tface < 0.43)] = 1.0
B = lvl
for _ in range(2):                                   # soften the edges a little
    B = (B + np.roll(B, 1, 0) + np.roll(B, -1, 0) + np.roll(B, 1, 1) + np.roll(B, -1, 1)) / 5

# ---- A: sock gradient ----
leg = Y < 0.68
quad = (X > 0).astype(int) * 2 + (Z > 0.2).astype(int)
legoff = np.choose(quad, [0.02, -0.17, 0.12, -0.05])   # each leg its own height (hind right, front right, hind left, front left)
A = np.clip(1 - Y / 0.62 + legoff + 0.1 * (vnoise(X, Y, Z, 0.05, 31) - 0.5), 0, 1) * leg
A *= np.where(leg, 1.0, 0.0)

fields = np.dstack([R, G, B, A])
# the empty texels around the UV islands take the values of their nearest island texels (not 0): the mip levels average an island with its surroundings, a thin leg's sock gradient fell under the cut-off at a few metres and all but one sock vanished
filled = cover.copy(); fields[~cover] = 0
for _ in range(24):
    acc = np.zeros_like(fields); cnt = np.zeros(filled.shape)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        f = np.roll(np.roll(filled, dy, 0), dx, 1)
        acc += np.roll(np.roll(fields, dy, 0), dx, 1) * f[..., None]; cnt += f
    grow = (~filled) & (cnt > 0)
    fields[grow] = acc[grow] / cnt[grow][:, None]; filled |= grow
img = (np.clip(fields, 0, 1) * 255 + 0.5).astype(np.uint8)
rawf = os.path.join(out, "_mask2.rgba"); img.tofile(rawf)
dds = os.path.join(out, "coatMask2.dds")
subprocess.run(["convert", "-size", "%dx%d" % (N, N), "-depth", "8", "rgba:" + rawf, "-define", "dds:compression=none", dds], check=True)

# The mip levels are made here, not by ImageMagick: a box filter averages a thin mark (the star, the blaze, a sock on a thin leg) into its surroundings until it falls under the shader's threshold, so it vanished
# at a distance (the real cause was ImageMagick weighting the channels by alpha). All four channels are plain 2 x 2 averages here. The level 0 and the header are what ImageMagick wrote.
def rebuild_mips(path, rgba):
    data = open(path, "rb").read()
    header, level0 = data[:128], data[128:128 + N * N * 4]
    arr0 = np.frombuffer(level0, np.uint8).reshape(N, N, 4)
    perm = None
    for flip in (False, True):
        ref = rgba[::-1] if flip else rgba
        for cand in __import__("itertools").permutations(range(4)):
            if np.array_equal(arr0, ref[..., list(cand)]):
                perm, flipped = list(cand), flip
                break
        if perm: break
    assert perm is not None, "could not match the DDS level 0 with the fields (channel order)"
    levels = [rgba[::-1] if flipped else rgba]
    cur = levels[0].astype(np.float32)
    maxch = []                                           # all four channels are plain 2 x 2 averages: max pooling the face and sock fields (tried 2026-11-12) let a leg island's sock values leak over the UV border onto the back island's edge, a white line along the topline; the alpha weighting of ImageMagick was the real bug
    while cur.shape[0] > 1:
        a, b, c, d = cur[0::2, 0::2], cur[0::2, 1::2], cur[1::2, 0::2], cur[1::2, 1::2]
        nxt = (a + b + c + d) / 4
        for ch in maxch:
            nxt[..., ch] = np.maximum(np.maximum(a[..., ch], b[..., ch]), np.maximum(c[..., ch], d[..., ch]))
        cur = nxt
        levels.append(np.clip(cur + 0.5, 0, 255).astype(np.uint8))
    out = bytearray(header)
    for lv in levels:
        out += np.ascontiguousarray(lv[..., perm]).tobytes()
    open(path, "wb").write(bytes(out))
    return len(levels)
n_levels = rebuild_mips(dds, img)
print("mip chain rebuilt with plain averages:", n_levels, "levels")
subprocess.run(["convert", "-size", "%dx%d" % (N, N), "-depth", "8", "rgba:" + rawf, os.path.join(out, "coatMask2_preview.png")], check=True)
os.remove(rawf)
print("wrote", dds)

if "--preview" in sys.argv:
    # emulate the shader's cuts on a bay coat and show the horse from the side and the head from the front, with z-buffered orthographic views
    def cut(vals, face, socks, blanket, keep, flecks, size):
        base = np.array([0.42, 0.22, 0.12]); white = np.array([0.93, 0.93, 0.9])
        col = np.tile(base, X.shape + (1,))
        dots = (vnoise(X, Y, Z, 0.045, 77) > 1 - 0.55 * R * (1 - size)).astype(float)       # (a sample of where the shader would put spots: more where the density is higher)
        bl = sm(G, (1.02 - blanket * 1.07) - 0.03, (1.02 - blanket * 1.07) + 0.03) * (blanket > 0.001)
        col = col * (1 - (bl * (1 - dots * keep))[..., None]) + white * (bl * (1 - dots * keep))[..., None]
        wf = dots * flecks * (1 - bl)
        col = col * (1 - wf[..., None]) + white * wf[..., None]
        th = 1.1 - 0.7 * face
        fm = sm(B, th - 0.05, th + 0.05) * (face > 0.001)
        sk = sm(A, 1 - socks - 0.04, 1 - socks + 0.04) * (socks > 0.001)
        m = np.maximum(fm, sk)
        col = col * (1 - m[..., None]) + white * m[..., None]
        return col
    def view(col, axes, flip, size=(520, 420), box=None):
        # axes: indices of the two world coords that map to image x and y; the third is depth (+ = toward the viewer when flip is 1)
        u, v, w = axes
        pts = pos[cover]; cc = col[cover]
        order = np.argsort(pts[:, w] * flip)
        pts, cc = pts[order], cc[order]
        (u0, u1), (v0, v1) = box
        W, H = size
        ix = ((pts[:, u] - u0) / (u1 - u0) * (W - 1)).astype(int); iy = ((v1 - pts[:, v]) / (v1 - v0) * (H - 1)).astype(int)
        ok = (ix >= 0) & (ix < W) & (iy >= 0) & (iy < H)
        im = np.full((H, W, 3), 0.85); im[iy[ok], ix[ok]] = cc[ok]
        return (im * 255).astype(np.uint8)
    tiles = []
    for name, args in (("face1", (1 / 3, 0, 0, 0, 0, 0.3)), ("face2", (2 / 3, 0, 0, 0, 0, 0.3)), ("face3", (1, 0, 0, 0, 0, 0.3)), ("none", (0, 0, 0, 0, 0, 0.3)), ("blaze+socks", (2 / 3, 0.55, 0, 0, 0, 0.3)), ("snowflake", (0, 0, 0, 0, 1, 0.12)), ("blanket+spots", (0, 0, 0.45, 1, 0, 0.1)), ("leopard", (1, 0.9, 1.0, 1, 0, 0.05))):
        col = cut(None, *args)
        side = view(col, (2, 1, 0), 1, (900, 460), ((-0.9, 1.75), (0.0, 2.3)))
        face = view(col, (0, 1, 2), 1, (110, 150), ((-0.14, 0.14), (1.7, 2.3)))
        head = view(col, (2, 1, 0), 1, (160, 100), ((1.0, 1.7), (1.65, 2.3)))
        tiles.append((name, side, face))
        for tag, im in (("side", side), ("front", face), ("head", head)):
            f = os.path.join(out, "_pv.rgb"); im.tofile(f)
            subprocess.run(["convert", "-size", "%dx%d" % (im.shape[1], im.shape[0]), "-depth", "8", "rgb:" + f, os.path.join(out, "preview_%s_%s.png" % (name.replace("+", "_"), tag))], check=True)
            os.remove(f)
    print("previews written to", out)
