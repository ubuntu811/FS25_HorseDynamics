#!/usr/bin/env python3
"""Paints the saddle blanket's textures from the model's own pad UVs (rebuild_blanket.py writes them: u = distance over the surface from the spine, v = z, 2:1): diffuse, normal (the quilting as relief, texture only, no extra mesh)
and specular. The pad's real outline (the distance to the edge in the unwrap) places the binding band, the gold piping cord and the end of the quilting, so the border follows the pad's curved edge.
  python3 make_blanket_texture.py models/horse/horseAdult <out prefix, e.g. dev/foal/tex/blanketAdult>      (writes <prefix>_diffuse.png, _normal.png, _specular.png)"""
import sys, os, json, subprocess
import numpy as np
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here); sys.path.insert(0, os.path.join(here, "..", "..", "..", "tools"))
import shapes_io as S
import fill_blanket as F

W, H = 2048, 1024
FABRIC = np.array([0.297, 0.240, 0.211])        # the pad's brown as it was (the game's pad fabric, mean of a flat patch)
BINDING = np.array([0.150, 0.115, 0.095])
GOLD = np.array([0.70, 0.55, 0.25])
BINDING_W, PIPING_IN, PIPING_OUT, QUILT_FROM, QUILT_FULL = 0.006, 0.008, 0.015, 0.016, 0.025     # metres from the pad's edge (adult size)
SEAM_L = 0.075                                  # spacing of the quilting's seam lines (adult size): diamonds of this side
NORMAL_STRENGTH = 5.0

def raster_mask(U, T):
    mask = np.zeros((H, W), bool)
    for t in T:
        p = U[t] * [W, H]; p[:, 1] = H - p[:, 1]            # image row = (1 - v) * H
        x0, x1 = int(np.floor(p[:, 0].min())), int(np.ceil(p[:, 0].max())); y0, y1 = int(np.floor(p[:, 1].min())), int(np.ceil(p[:, 1].max()))
        if x1 < x0 or y1 < y0: continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        (ax, ay), (bx, by), (cx, cy) = p
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-9: continue
        l1 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / den; l2 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / den
        ins = (l1 >= -0.01) & (l2 >= -0.01) & (1 - l1 - l2 >= -0.01)
        yy, xx = np.clip(ys.astype(int), 0, H - 1), np.clip(xs.astype(int), 0, W - 1)
        mask[yy[ins], xx[ins]] = True
    return mask

def shift(m, dy, dx):
    q = np.pad(m, 1, constant_values=False if m.dtype == bool else 0)
    return q[1 + dy:q.shape[0] - 1 + dy, 1 + dx:q.shape[1] - 1 + dx]

def edge_distance(mask, maxpx):
    """pixels from the outline, inside the mask (octagonal approximation by alternating 4- and 8-neighbour erosion steps)"""
    dist = np.zeros(mask.shape, np.float32); cur = mask.copy()
    for k in range(1, maxpx + 1):
        nb = cur & shift(cur, 1, 0) & shift(cur, -1, 0) & shift(cur, 0, 1) & shift(cur, 0, -1)
        if k % 2 == 0: nb = nb & shift(cur, 1, 1) & shift(cur, 1, -1) & shift(cur, -1, 1) & shift(cur, -1, -1)
        dist[cur & ~nb] = k; cur = nb
        if not cur.any(): break
    dist[cur] = maxpx
    return dist * 0.8                         # (the mixed steps count a little long)

def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)

def bleed(img, mask, iters=40):
    img = img.copy(); have = mask.copy()
    for _ in range(iters):
        acc = np.zeros_like(img); cnt = np.zeros(mask.shape)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy == 0 and dx == 0: continue
                h = shift(have, dy, dx); acc += shift_img(img, dy, dx) * h[..., None]; cnt += h
        new = ~have & (cnt > 0)
        img[new] = acc[new] / cnt[new][:, None]; have = have | new
    return img

def shift_img(img, dy, dx):
    q = np.pad(img, ((1, 1), (1, 1), (0, 0)), mode="edge")
    return q[1 + dy:q.shape[0] - 1 + dy, 1 + dx:q.shape[1] - 1 + dx]

def save_png(arr, path):
    raw = (np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8).tobytes()
    subprocess.run(["convert", "-size", "%dx%d" % (arr.shape[1], arr.shape[0]), "-depth", "8", "rgb:-", path], input=raw, check=True)

def load_sticker(size=256):
    """RGBA of the tractor mouse: assets/inception.png if it exists (the user's embroidered golden patch), else the tractor cell of the sticker sheet."""
    patch = os.path.join(here, "..", "..", "..", "assets", "inception.png")
    if os.path.exists(patch):
        raw = subprocess.run(["convert", patch, "-background", "none", "-resize", "%dx%d" % (size, size), "-gravity", "center", "-extent", "%dx%d" % (size, size), "-depth", "8", "rgba:-"], capture_output=True, check=True).stdout
        a = np.frombuffer(raw, np.uint8).reshape(size, size, 4).astype(float) / 255
        return a[..., :3], a[..., 3]
    sys.path.insert(0, os.path.join(here, "..", "..", "..", "tools"))
    import tempfile, make_horse_ball_mice as M
    with tempfile.TemporaryDirectory() as tmp:
        cells = M.cells(tmp, size)
    rgb, alpha = cells[5]                                   # row 2, column 3: the mouse on the tractor
    return rgb, np.clip((alpha - 0.04) / 0.2, 0, 1)

EDGE_SMOOTH_M = 0.02                        # smoothing of the distance field along the edge (metres, adult size)
OUTLINE_LEVEL = 0.40                        # (0.5 = the blurred outline on the real edge; lower = a little outward)
OUTLINE_SIGMA_M = 0.025                     # smoothing of the pad's outline for the binding and the piping (metres, adult size)
STICKER_EDGE_M = 0.085                      # the sticker's centre at least this far from the pad's edge
STICKER_M = 0.13                                            # metres (adult size) across
STICKER_SPOTS = [(203, 773, "u-"), (1833, 761, "u+")]       # pixel centres in the 2048 x 1024 texture (the user's green circles: the pad's lower rear corners), and which side (u > 0 / u < 0)

def place_stickers(diffuse, Hh, mask, px_m, d):
    rgb, alpha = load_sticker()
    size = max(8, int(STICKER_M / px_m))
    def resized(img):
        raw = (np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)
        ch = 3 if img.ndim == 3 else 1
        out = subprocess.run(["convert", "-size", "%dx%d" % (img.shape[1], img.shape[0]), "-depth", "8", "rgb:-" if ch == 3 else "gray:-", "-filter", "Lanczos", "-resize", "%dx%d!" % (size, size), "-depth", "8", "rgb:-" if ch == 3 else "gray:-"], input=raw.tobytes(), capture_output=True, check=True).stdout
        return np.frombuffer(out, np.uint8).reshape((size, size, 3) if ch == 3 else (size, size)).astype(float) / 255
    rgb_s, a_s = resized(rgb), resized(alpha)
    for cx, cy, side in STICKER_SPOTS:
        want = (d >= STICKER_EDGE_M) & mask                                   # the sticker's whole disk stays clear of the piping
        ys, xs = np.nonzero(want[:, (0 if cx < W // 2 else W // 2):(W // 2 if cx < W // 2 else W)])
        xs = xs + (0 if cx < W // 2 else W // 2)
        k = np.argmin((xs - cx) ** 2 + (ys - cy) ** 2); cx, cy = int(xs[k]), int(ys[k])
        if side == "u+": r, a = np.swapaxes(rgb_s, 0, 1), np.swapaxes(a_s, 0, 1)                       # seen from outside the texture is mirrored (x is the horse's left): a reflection keeps the mouse the right way round
        else: r, a = np.flip(np.swapaxes(rgb_s, 0, 1), (0, 1)), np.flip(np.swapaxes(a_s, 0, 1), (0, 1))
        y0, x0 = cy - size // 2, cx - size // 2
        region = (slice(y0, y0 + size), slice(x0, x0 + size))
        a3 = a[..., None]
        diffuse[region] = diffuse[region] * (1 - a3) + r * a3
        soft = a.copy()
        for _ in range(3): soft = (soft + shift(soft, 1, 0) + shift(soft, -1, 0) + shift(soft, 0, 1) + shift(soft, 0, -1)) / 5
        stitch = 0.15 * (r @ np.array([0.3, 0.6, 0.1]))
        Hh[region] = Hh[region] + 1.0 * soft + stitch * a
        print("sticker (%s) placed at %d %d, %d px, mask there: %s, edge distance %.1f cm" % (side, cx, cy, size, bool(mask[cy, cx]), d[cy, cx] * 100))

def main(base, prefix):
    name = os.path.basename(base)
    uv = json.load(open(os.path.join(here, "..", "blanket_old", name + "_uv.json")))
    span, scale = uv["span_m"], uv["scale"]
    raw, sf = S.read(base + ".i3d.shapes"); b = F.shapes(sf)["blanketShape"][1]
    U = np.array([[u.u, u.v] for u in b.uv_sets[0]]); T = np.array([[t.p1 - 1, t.p2 - 1, t.p3 - 1] for t in b.triangles])
    mask = raster_mask(U, T)
    px_m = span / W / scale                                    # adult-size metres per pixel
    maxpx = int(0.13 / px_m)
    import make_plain_coats as MP
    d0 = edge_distance(mask, maxpx) * px_m                      # metres (adult size) from the REAL edge of the pad
    # the outline the binding and the piping follow: the real mask blurred and cut a little outward (calm curve, corners rounded, cracks of the raster healed), joined with everything deeper than 1.2 cm inside the real edge (so no black band outside the piping)
    smask = (MP.gaussian_filter(mask.astype(np.float64), OUTLINE_SIGMA_M / px_m) > OUTLINE_LEVEL) | (d0 >= 0.012)
    d = edge_distance(smask, maxpx) * px_m
    # coordinates in metres (adult size), centred; the seams run at 45 degrees (diamonds)
    xx, yy = np.meshgrid((np.arange(W) + 0.5 - W / 2) * px_m, (np.arange(H) + 0.5 - H / 2) * px_m)
    a = (xx + yy) / np.sqrt(2) / SEAM_L; c = (xx - yy) / np.sqrt(2) / SEAM_L
    fa, fc = a - np.floor(a), c - np.floor(c)                  # 0 at a seam line, 1 across the cell
    puff = (np.sin(np.pi * fa) * np.sin(np.pi * fc)) ** 0.55
    qmask = smoothstep(QUILT_FROM, QUILT_FULL, d)
    rng = np.random.default_rng(7)
    noise = rng.normal(0, 1, (H // 4, W // 4)); noise = np.kron(noise, np.ones((4, 4))); noise2 = rng.normal(0, 1, (H, W))
    fine = 0.012 * noise + 0.020 * noise2
    seam = (1 - smoothstep(0.0, 0.035, np.minimum(np.minimum(fa, 1 - fa), np.minimum(fc, 1 - fc)))) * qmask
    diffuse = np.zeros((H, W, 3))
    fabric = FABRIC[None, None, :] * (1 + fine[..., None] + 0.10 * (puff - 0.6)[..., None] * qmask[..., None]) * (1 - 0.35 * seam[..., None])
    diffuse[:] = fabric
    binding = d < PIPING_IN
    diffuse[binding] = (BINDING[None, :] * (1 + 1.5 * fine[binding][:, None]))
    cord = (d >= PIPING_IN) & (d < PIPING_OUT)
    twist = 0.5 + 0.5 * np.sin(2 * np.pi * (xx + yy) / (0.006 * 1.0))
    cordshade = (0.78 + 0.22 * twist) * (0.7 + 0.3 * np.cos((d - (PIPING_IN + PIPING_OUT) / 2) / ((PIPING_OUT - PIPING_IN) / 2) * np.pi / 2))
    diffuse[cord] = (GOLD[None, :] * cordshade[cord][:, None])
    gap = (d >= BINDING_W + 0.004) & (d < PIPING_IN)
    diffuse[gap] = BINDING[None, :] * 0.9
    # relief: the quilting's puffs, the cord (a round ridge), the binding (flat and a little lower)
    Hh = 0.9 * puff * qmask
    ridge = np.where(cord, np.cos((d - (PIPING_IN + PIPING_OUT) / 2) / ((PIPING_OUT - PIPING_IN) / 2) * np.pi / 2), 0.0)
    Hh = Hh + 1.2 * np.clip(ridge, 0, 1) - 0.25 * (d < BINDING_W) + 0.05 * noise2
    place_stickers(diffuse, Hh, mask, px_m, d)
    gy, gx = np.gradient(Hh)
    nx, ny = -gx * NORMAL_STRENGTH, gy * NORMAL_STRENGTH       # (image y points down, v up)
    nz = np.ones_like(nx); ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5
    normal[~mask] = [0.5, 0.5, 1.0]
    # specular: the game's own pad fabric values (a flat patch of the saddle's specular map)
    spec = np.tile(np.array([0.55, 0.45, 0.25]), (H, W, 1))
    try:
        sp = os.path.expanduser("~/fs25_resources/dataS_raw/1.25.1.0/character/animals/domesticated/horse/saddle_specular.dds")
        o = subprocess.run(["convert", sp + "[0]", "-alpha", "off", "-depth", "8", "-resize", "1024x1024!", "rgb:-"], capture_output=True, check=True).stdout
        tx = np.frombuffer(o, np.uint8).reshape(1024, 1024, 3).astype(float) / 255
        patch = tx[int((1 - 0.72) * 1024):int((1 - 0.68) * 1024), int(0.85 * 1024):int(0.89 * 1024)].reshape(-1, 3).mean(0)
        spec[:] = patch; print("specular patch", patch.round(3))
    except Exception as e:
        print("specular fallback:", e)
    spec[cord] = np.array([0.9, 0.6, 0.2])
    for arr_name, arr in (("diffuse", diffuse), ("specular", spec)):
        arr[...] = bleed(arr, mask)
    normal = bleed(normal, mask)
    os.makedirs(os.path.dirname(prefix), exist_ok=True)
    save_png(diffuse, prefix + "_diffuse.png"); save_png(normal, prefix + "_normal.png"); save_png(spec, prefix + "_specular.png")
    print("wrote", prefix, "mask %.0f%% of the texture, px %.2f mm (adult size)" % (100 * mask.mean(), px_m * 1000))

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
