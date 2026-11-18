"""Mip chains for the coat masks, made by us. ImageMagick made them by resizing the RGBA image, which weights the colour channels by the alpha channel: where alpha is 0 (most of the body: the sock field, the pinto
pattern) the other channels were crushed (2026-11-12: the spot density 0.478 -> 0.040 and the blanket 0.238 -> 0.025 at the first smaller level, the coat mask R 0.591 -> 0.170), so every marking and the tint faded to
almost nothing at a distance of a few metres and came back, weaker, further away. Here every channel is a plain 2 x 2 average, or the maximum (thin marks: the face, the socks)."""
import os, subprocess, itertools
import numpy as np

def levels(rgba, maxch=()):
    out = [rgba.astype(np.uint8)]
    cur = rgba.astype(np.float32)
    while cur.shape[0] > 1:
        a, b, c, d = cur[0::2, 0::2], cur[0::2, 1::2], cur[1::2, 0::2], cur[1::2, 1::2]
        nxt = (a + b + c + d) / 4
        for ch in maxch:
            nxt[..., ch] = np.maximum(np.maximum(a[..., ch], b[..., ch]), np.maximum(c[..., ch], d[..., ch]))
        cur = nxt
        out.append(np.clip(cur + 0.5, 0, 255).astype(np.uint8))
    return out

def dxt5_chain(path, rgba, maxch=(), tmpdir="."):
    """Rewrites a DXT5 dds written by ImageMagick (header and level count are kept) with levels compressed from OUR chain."""
    data = open(path, "rb").read()
    header = bytearray(data[:128])
    payload = bytearray()
    for i, lv in enumerate(levels(rgba, maxch)):
        n = lv.shape[0]
        if n < 4:                                           # a block is 4 x 4: the small levels are blocks of the same colour
            lv = np.repeat(np.repeat(lv, 4 // n if n else 4, 0), 4 // n if n else 4, 1)[:4, :4]
            n = 4
        raw = os.path.join(tmpdir, "_lv.rgba"); one = os.path.join(tmpdir, "_lv.dds")
        np.ascontiguousarray(lv).tofile(raw)
        subprocess.run(["convert", "-size", "%dx%d" % (n, n), "-depth", "8", "rgba:" + raw, "-define", "dds:compression=dxt5", "-define", "dds:mipmaps=0", one], check=True)
        payload += open(one, "rb").read()[128:]
        os.remove(raw); os.remove(one)
    assert len(header) + len(payload) == len(data), "level sizes differ from ImageMagick's file: %d vs %d" % (len(header) + len(payload), len(data))
    open(path, "wb").write(bytes(header) + bytes(payload))
