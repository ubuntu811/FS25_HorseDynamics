#!/usr/bin/env python3
"""The mouse ball: the horse ball with a sheet of nine mouse stickers (dev/ballmice/mice_sheet.webp, 3 x 3) printed all over it.
  python3 tools/make_horse_ball_mice.py [--preview out dir]   -> vehicles/horseBall/horseBallMice_diffuse.dds, horseBallMice.i3d(.shapes), horseBallMice.xml
The texture is made by looking from every pixel of the sphere's own UV layout (u round, v pole to pole, image row 0 = v 1: the same as the coat masks) at which sticker covers that direction, so the mice are
the same size and upright everywhere, also at the poles (no stretching). The stickers sit on a Fibonacci spiral over the sphere (even spacing), each is multiplied onto white (the sheet's own white margin is the ball's white).
--preview: renders four views of the finished texture on a sphere (png) to see the mice without the game."""
import os, sys, math, re, subprocess, shutil
import numpy as np
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here)
import make_horse_ball as M

mod = os.path.normpath(os.path.join(here, ".."))
SHEET = os.path.join(mod, "dev", "ballmice", "mice_sheet.webp")
OUT = os.path.join(mod, "vehicles", "horseBall")
W, H = 2048, 1024
RADIUS = 0.45                 # the main ball's radius: stickers are sized against it (the small and large ball would scale them)
STICKER_M = 0.30              # one sticker's side on the ball, m (the nearest two centres are 0.356 m apart: no sticker touches another)
COUNT = 16

def run(cmd): subprocess.run(cmd, shell=True, check=True)

TOOL = os.path.expanduser("~/fs25_resources/texture_tool/textureTool_9.0.1_win64/textureTool.exe")      # GIANTS Texture Tool: the engine wants its BC1 / BC7 files (ImageMagick's DXT5 came out scrambled in the game: the engine skips top mip levels of big textures and wants the tool's chain)
WORK = os.path.join(mod, "dev", "ballmice", "out")

def tool_dds(png, gui=False):
    """Converts a png with the GIANTS Texture Tool (a .gim next to it says 'no mipmaps' for a GUI picture); returns the dds next to it."""
    base = png[:-4]
    if gui:
        open(base + ".gim", "w").write('<?xml version="1.0" encoding="utf-8" standalone="no" ?>\n<metadata>\n\t<numMipmaps>0</numMipmaps>\n</metadata>\n')
    elif os.path.exists(base + ".gim"):
        os.remove(base + ".gim")
    win = subprocess.run(["wslpath", "-w", png], capture_output=True, text=True, check=True).stdout.strip()
    r = subprocess.run([TOOL, "-ignoreTimestamp", "-overwriteNonGenerated", "-inputs", win], cwd=os.path.dirname(TOOL), capture_output=True, text=True, timeout=600)
    print(r.stdout[-400:].strip())
    assert os.path.exists(base + ".dds") and r.returncode == 0, "the texture tool did not make %s.dds: %s" % (os.path.basename(base), r.stderr[-300:])
    return base + ".dds"

def read_ppm(path):
    with open(path, "rb") as f:
        assert f.readline().strip() == b"P6"
        w, h = map(int, f.readline().split()); f.readline()
        return np.frombuffer(f.read(), np.uint8).reshape(h, w, 3).astype(np.float64) / 255.0

def write_ppm(path, a):
    with open(path, "wb") as f:
        f.write(b"P6 %d %d 255\n" % (a.shape[1], a.shape[0])); f.write((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8).tobytes())

def read_pgm(path):
    with open(path, "rb") as f:
        assert f.readline().strip() == b"P5"
        w, h = map(int, f.readline().split()); f.readline()
        return np.frombuffer(f.read(), np.uint8).reshape(h, w).astype(np.float64) / 255.0

def label(mask):
    """Connected components (4-neighbour) of a boolean mask: (labels, count). Plain Python breadth first search, the masks are small."""
    h, w = mask.shape; lab = np.zeros((h, w), np.int32); n = 0
    for y0 in range(h):
        for x0 in np.nonzero(mask[y0] & (lab[y0] == 0))[0]:
            if lab[y0, x0]: continue
            n += 1; lab[y0, x0] = n; stack = [(y0, int(x0))]
            while stack:
                y, x = stack.pop()
                for yy, xx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                    if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and not lab[yy, xx]:
                        lab[yy, xx] = n; stack.append((yy, xx))
    return lab, n

def grow(mask, r):
    """The mask grown by r pixels (a disc), without wrapping round the edges."""
    pad = np.pad(mask, r); out = pad.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dy * dy + dx * dx <= r * r: out |= np.roll(np.roll(pad, dy, 0), dx, 1)
    return out[r:-r, r:-r]

def cells(tmp, size):
    """The nine stickers, each cut out along its own outline (the sheet's alpha: the stickers do not sit on an even grid, a fixed cell cut off a hat, an ear), at one common scale, centred in a white square of
    size x size px. Scraps that belong to a sticker (the sparkles, the zzz) stay with it; the scraps of the neighbours are white."""
    run('convert "%s" -background white -alpha remove -alpha off -colorspace sRGB -type TrueColor "%s/sheet.ppm"' % (SHEET, tmp))    # (the sheet is transparent between the stickers: onto white)
    run('convert "%s" -alpha extract -depth 8 "%s/alpha.pgm"' % (SHEET, tmp))
    rgb = read_ppm(tmp + "/sheet.ppm"); alpha_f = read_pgm(tmp + "/alpha.pgm"); alpha = alpha_f > 0.04
    lab, n = label(grow(alpha[::2, ::2], 3))                # (half size, the outlines grown a little so a sticker and its bits are one piece)
    area = np.bincount(lab.ravel(), minlength=n + 1); area[0] = 0
    big = [i for i in np.argsort(-area)[:9]]
    assert len(big) == 9 and area[big[-1]] > 3000, "expected nine stickers, found areas %s" % sorted(area)[-12:]
    cen = {}
    for i in range(1, n + 1):
        ys, xs = np.nonzero(lab == i); cen[i] = (ys.mean(), xs.mean(), len(ys))
    group = {i: i for i in big}
    for i in range(1, n + 1):                               # (the little pieces go with the nearest sticker)
        if i in group or cen[i][2] < 12: continue
        d = [(math.hypot(cen[i][0] - cen[b][0], cen[i][1] - cen[b][1]), b) for b in big]
        dist, b = min(d)
        if dist < 260: group[i] = b
    order = sorted(big, key=lambda b: (round(cen[b][0] / 200), cen[b][1]))      # (rows of the sheet, then left to right)
    crops = []; acrops = []
    for b in order:
        m = np.isin(lab, [i for i, g in group.items() if g == b])
        m = np.kron(grow(m, 2), np.ones((2, 2), bool))[:alpha.shape[0], :alpha.shape[1]] & grow(alpha, 3)
        ys, xs = np.nonzero(m); y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        piece = np.where(m[y0:y1, x0:x1, None], rgb[y0:y1, x0:x1], 1.0)
        crops.append(piece); acrops.append(np.where(m[y0:y1, x0:x1], alpha_f[y0:y1, x0:x1], 0.0))
    side = int(max(max(c.shape[:2]) for c in crops) * 1.04)
    out = []
    for k, c in enumerate(crops):
        sq = np.ones((side, side, 3)); sa = np.zeros((side, side)); oy = (side - c.shape[0]) // 2; ox = (side - c.shape[1]) // 2
        sq[oy:oy + c.shape[0], ox:ox + c.shape[1]] = c; sa[oy:oy + c.shape[0], ox:ox + c.shape[1]] = acrops[k]
        write_ppm("%s/c%d.ppm" % (tmp, k), sq); write_ppm("%s/a%d.ppm" % (tmp, k), np.repeat(sa[..., None], 3, 2))
        for name in ("c", "a"):
            run('convert "%s/%s%d.ppm" -filter Lanczos -resize %dx%d! "%s/%s%d.ppm"' % (tmp, name, k, size, size, tmp, name, k))
        out.append((read_ppm("%s/c%d.ppm" % (tmp, k)), read_ppm("%s/a%d.ppm" % (tmp, k))[..., 0]))
    return out

def bilinear(img, x, y):
    h, w = img.shape[:2]
    x = np.clip(x, 0, w - 1.001); y = np.clip(y, 0, h - 1.001)
    x0 = x.astype(int); y0 = y.astype(int); fx = (x - x0)[..., None]; fy = (y - y0)[..., None]
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x0 + 1] * fx * (1 - fy) + img[y0 + 1, x0] * (1 - fx) * fy + img[y0 + 1, x0 + 1] * fx * fy)

def directions():
    c, r = np.meshgrid(np.arange(W) + 0.5, np.arange(H) + 0.5)
    u = c / W; v = 1 - r / H                                # image row 0 is v = 1
    a = math.pi * v; b = 2 * math.pi * u
    return np.stack([np.sin(a) * np.cos(b), np.cos(a), np.sin(a) * np.sin(b)], -1)

def spots():
    """Fibonacci spiral over the sphere: (direction, sticker index)."""
    golden = math.pi * (3 - math.sqrt(5)); out = []
    for i in range(COUNT):
        y = 1 - 2 * (i + 0.5) / COUNT; rr = math.sqrt(1 - y * y); b = i * golden
        out.append((np.array([rr * math.cos(b), y, rr * math.sin(b)]), (i * 4) % 9))
    return out

def texture(tmp):
    """(rgb, alpha) of the sticker layer: the stickers on a transparent background (white where there is nothing, so the mip levels do not darken the edges)."""
    d = directions()
    half = (STICKER_M / 2) / RADIUS
    size = int(round(STICKER_M * W / (2 * math.pi * RADIUS)))
    stickers = cells(tmp, size)
    rgb = np.ones((H, W, 3)); alpha = np.zeros((H, W))
    for n, k in spots():
        right = np.cross([0, 1, 0], n); right /= np.linalg.norm(right)
        up = np.cross(n, right)
        dr, du, dn = d @ right, d @ up, d @ n
        m = (dn > 0.3) & (np.abs(dr) < half) & (np.abs(du) < half)
        sx = (dr[m] / (2 * half) + 0.5) * size; sy = (0.5 - du[m] / (2 * half)) * size
        s_rgb = bilinear(stickers[k][0], sx, sy); s_a = bilinear(stickers[k][1][..., None], sx, sy)[..., 0]
        rgb[m] = rgb[m] * (1 - s_a[:, None]) + s_rgb * s_a[:, None]
        alpha[m] = 1 - (1 - alpha[m]) * (1 - s_a)
    return rgb, alpha

BASE_PREVIEW = (0.35, 0.65, 0.95)          # the base colour the preview and the shop picture show (the shop's own white is the default in the game)

def over_base(tex, base):
    rgb, alpha = tex
    return rgb * alpha[..., None] + np.array(base) * (1 - alpha[..., None])

def render_view(canvas, S, az_deg, up_v=(0, 1, 0)):
    """One orthographic view of the texture on the sphere from the direction az (round the y axis), lit from the camera side: (rgb, inside mask)."""
    yy, xx = np.meshgrid(np.arange(S) + 0.5, np.arange(S) + 0.5, indexing="ij")
    px = (xx - S / 2) / (S / 2); py = -(yy - S / 2) / (S / 2); rr = px * px + py * py; ok = rr < 1
    pz = np.sqrt(np.clip(1 - rr, 0, 1))
    n0 = np.array([math.cos(math.radians(az_deg)), 0, math.sin(math.radians(az_deg))]) if up_v == (0, 1, 0) else np.array([0, 1, 0])
    up = np.array(up_v, float); right = np.cross(up, n0); right /= np.linalg.norm(right); up = np.cross(n0, right)
    dd = px[..., None] * right + py[..., None] * up + pz[..., None] * n0
    al = np.arccos(np.clip(dd[..., 1], -1, 1)); be = np.mod(np.arctan2(dd[..., 2], dd[..., 0]), 2 * math.pi)
    col = be / (2 * math.pi) * W - 0.5
    row = H * (1 - al / math.pi) - 0.5                  # texture(): v = 1 - r / H and alpha = pi v, so r = H (1 - alpha / pi)
    img = bilinear(canvas, np.mod(col, W - 1.001), row)
    return img * (0.45 + 0.55 * pz)[..., None], ok

def preview(canvas, path, tmp):
    """Four views (from +x, +z, -x, above) as one png."""
    views = []
    for az, up_v in ((0, (0, 1, 0)), (90, (0, 1, 0)), (180, (0, 1, 0)), (0, (1, 0, 0))):
        img, ok = render_view(canvas, 520, az, up_v); views.append(np.where(ok[..., None], img, 1.0))
    write_ppm(path + ".ppm", np.concatenate(views, 1)); run('convert "%s.ppm" "%s"' % (path, path)); os.remove(path + ".ppm")

ICON = 512                    # shop pictures are 512 x 512 dxt5 with alpha; the plain ball's: 54 % of the width, centre at (0.53, 0.43) of the picture, a soft shadow to the lower left (store/ball.dds, measured)
ICON_BALL = 276

def store_icon(canvas, path, tmp):
    """The shop picture: the ball (2x supersampled) the size and place of the plain ball's picture, with a soft shadow, on a transparent background; converted by the texture tool as a GUI picture."""
    img, ok = render_view(canvas, ICON_BALL * 2, 25)
    write_ppm(tmp + "/icon.ppm", img); write_ppm(tmp + "/icon_a.ppm", np.repeat(ok[..., None], 3, 2).astype(float))
    run('convert "%s/icon.ppm" \\( "%s/icon_a.ppm" -colorspace Gray \\) -alpha off -compose CopyOpacity -composite -resize %dx%d "%s/ball.png"' % (tmp, tmp, ICON_BALL, ICON_BALL, tmp))
    ox, oy = int(0.527 * ICON - ICON_BALL / 2), int(0.43 * ICON - ICON_BALL / 2)
    os.makedirs(WORK, exist_ok=True)
    png = os.path.join(WORK, "mouseBall.png")
    run('convert -size %dx%d xc:none \\( -size %dx%d xc:none -fill black -draw "ellipse 232,398 190,58 0,360" -blur 0x22 -channel A -evaluate multiply 0.6 +channel \\) -composite "%s/ball.png" -geometry +%d+%d -composite -depth 8 "PNG32:%s"'
        % (ICON, ICON, ICON, ICON, tmp, ox, oy, png))
    shutil.copyfile(tool_dds(png, gui=True), path)

def xml_for(main_xml):
    x = main_xml.replace("vehicles/horseBall/horseBall.i3d", "vehicles/horseBall/horseBallMice.i3d")
    x = x.replace("<image>store/ball_v2.dds</image>", "<image>store/mouseBall.dds</image>")
    x = re.sub(r"    <designColor2Configurations.*?</designColor2Configurations>\n", "", x, flags=re.S)
    x = x.replace('title="Panel colour 1"', 'title="Base colour"').replace('defaultColorIndex="13"', 'defaultColorIndex="1"')
    x = re.sub(r"    <!-- the colours:.*?-->", "    <!-- the base colour under the stickers: the game's palette as a shop option (the material ball_mat; the stickers are a second, transparent shell: mice_mat); white by default -->", x, flags=re.S)
    x = x.replace("<en>Horse ball</en>", "<en>Mouse ball</en>").replace("<de>Pferdeball</de>", "<de>Mäuseball</de>")
    x = x.replace("A big red ball for the horses to kick around (FS25_HorseDynamics).", "A ball covered in mouse stickers for the horses to kick around (FS25_HorseDynamics).")
    x = x.replace("A big red ball for the horses to kick around: ride or lead a horse into it.", "A ball covered in little mice for the horses to kick around: ride or lead a horse into it.")
    return x

if __name__ == "__main__":
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        tex = texture(tmp)
        canvas = over_base(tex, BASE_PREVIEW if "--preview" in sys.argv else (1, 1, 1))
        if "--preview" in sys.argv:
            d = sys.argv[sys.argv.index("--preview") + 1]; os.makedirs(d, exist_ok=True)
            preview(canvas, os.path.join(d, "mice_preview.png"), tmp)
            write_ppm(os.path.join(tmp, "flat.ppm"), canvas); run('convert "%s/flat.ppm" -resize 1400x "%s"' % (tmp, os.path.join(d, "mice_flat.png")))
            print("preview written to", d)
        else:
            write_ppm(tmp + "/tex.ppm", tex[0]); write_ppm(tmp + "/tex_a.ppm", np.repeat(tex[1][..., None], 3, 2))
            os.makedirs(WORK, exist_ok=True)
            png = os.path.join(WORK, "horseBallMice_diffuse.png")
            run('convert "%s/tex.ppm" \\( "%s/tex_a.ppm" -colorspace Gray \\) -alpha off -compose CopyOpacity -composite -depth 8 "PNG32:%s"' % (tmp, tmp, png))
            shutil.copyfile(tool_dds(png), os.path.join(OUT, "horseBallMice_diffuse.dds"))
            store_icon(canvas, os.path.join(mod, "store", "mouseBall.dds"), tmp)
            M.build(OUT, RADIUS, "horseBallMice", mice=True)
            main = open(os.path.join(OUT, "horseBall.xml"), encoding="utf-8").read()
            open(os.path.join(OUT, "horseBallMice.xml"), "w", encoding="utf-8").write(xml_for(main))
            print("wrote the mouse ball")
