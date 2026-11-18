#!/usr/bin/env python3
"""Paint the native white (blaze, socks) out of the game's coat atlas so only our shader markings remain.
Only tiles (2,0) and (2,1) are touched; the pinto tile stays. Writes a PNG atlas (convert with textureTool)."""
import sys, subprocess, os
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
import bc3

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SRC = os.path.expanduser("~/fs25_resources/dataS_raw/1.25.1.0/character/animals/domesticated/horse/horse_diffuse.dds")
LUM = np.array([0.299, 0.587, 0.114])
TILES = [(2, 0), (2, 1)]
FACE = (slice(100, 540), slice(0, 170))     # rows, cols of the face island's blaze strip
LEGS = (slice(668, 990), slice(290, 770))     # the sock blocks only (not the hoof-shoe rims at the bottom left, not stray light fur)

def gaussian_filter(a, sigma):
    r = int(3 * sigma + 1)
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2); k /= k.sum()
    for ax in (0, 1):
        pad = [(0, 0)] * a.ndim; pad[ax] = (r, r)
        p = np.pad(a, pad, mode="edge")
        a = sum(k[i] * np.take(p, range(i, i + a.shape[ax]), axis=ax) for i in range(2 * r + 1))
    return a

def binary_dilation(m, iterations=1):
    for _ in range(iterations):
        p = np.pad(m, 1); m = p[1:-1, 1:-1] | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
    return m

def binary_closing(m, iterations=1):
    n = ~binary_dilation(~np.pad(binary_dilation(m, iterations), 0), iterations)
    return n

def load():
    raw = subprocess.run(["convert", SRC + "[0]", "-depth", "8", "-alpha", "off", "rgb:-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(2048, 4096, 3).astype(np.float64) / 255

def coat_mask():
    """(skin R, skin or hoof R|B): the white socks sit partly in the hoof-bone triangles"""
    d = open(os.path.join(ROOT, "models/foal/coatMask.dds"), "rb").read()
    M = bc3.bc3(d[128:128 + (1024 // 4) ** 2 * 16], 1024)
    return M[..., 0] > 0.5, (M[..., 0] > 0.5) | (M[..., 2] > 0.5)

def clean(T, skin, body):
    L = T @ LUM
    mx, mn = T.max(-1), T.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1e-3)
    cen = np.zeros_like(body); cen[200:400, 250:800] = True; cen &= skin
    lb, sb = np.median(L[cen]), np.median(sat[cen])
    region = np.zeros_like(body); region[FACE] = True; region[LEGS] = True
    white = body & region & (L > lb + 0.18) & (sat < sb * 0.6)
    white = binary_closing(white, iterations=3)
    white = binary_dilation(white, iterations=4) & body
    keep = (skin & ~white).astype(np.float64)
    sig = 45
    num = np.stack([gaussian_filter(T[..., c] * keep, sig) for c in range(3)], -1)
    den = gaussian_filter(keep, sig)[..., None]
    fill = num / np.maximum(den, 1e-4)
    far = den[..., 0] < 2e-3                         # nothing to borrow from: use the body median
    fill[far] = np.median(T[cen], axis=0)
    Lf = fill @ LUM
    detail = L - gaussian_filter(L, 5)
    new = fill * (1 + np.clip(detail, -0.15, 0.15)[..., None] / np.maximum(Lf, 0.08)[..., None] * 0.8)
    # white fur in the hoof-bone triangles (the pastern next to the hoof) becomes dark horn, like the hoof wall beside it: a hoof is dark all the way down and the coat's tint and markings do not reach it
    if True:
        horn = np.array([0.20, 0.15, 0.11])           # dark brown horn (the hoof wall's own colour is olive from the edge fur)
        hw = white & ~skin
        new[hw] = (horn * (1 + np.clip(detail, -0.15, 0.15)[..., None] / max(horn @ LUM, 0.08) * 0.8))[hw]
    soft = gaussian_filter(white.astype(np.float64), 2)[..., None]
    out = T * (1 - soft) + np.clip(new, 0, 1) * soft
    return out, white

def main():
    A = load(); skin, body = coat_mask(); painted = np.zeros_like(body)
    for tu, tv in TILES:
        sl = (slice(tv * 1024, (tv + 1) * 1024), slice(tu * 1024, (tu + 1) * 1024))
        new, white = clean(A[sl], skin, body)
        print("tile", (tu, tv), "painted %.2f%% of the coat, %.0f%% of it outside the skin mask" % (100 * white.sum() / skin.sum(), 100 * (white & ~skin).sum() / max(white.sum(), 1)))
        A[sl] = new; painted |= white & skin
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "dev/foal/horseCoats_diffuse.png")
    raw = (A * 255 + 0.5).astype(np.uint8).tobytes()
    subprocess.run(["convert", "-size", "4096x2048", "-depth", "8", "rgb:-", out], input=raw, check=True)
    print("wrote", out)
    # the painted texels join the coat skin (make_coat_mask.py reads this): the tint and our markings reach them
    subprocess.run(["convert", "-size", "1024x1024", "-depth", "8", "gray:-", os.path.join(ROOT, "dev/foal/paintedWhite.png")], input=(painted * 255).astype(np.uint8).tobytes(), check=True)

if __name__ == "__main__":
    main()
