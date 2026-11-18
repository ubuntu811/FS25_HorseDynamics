#!/usr/bin/env python3
"""Re-places the shop pictures of the animal gear tab: the tile only shows the lower ~65 % of a 512 picture (the top spills out above it), so the object (shadow included) is centred at CY and at most MAXH tall.
  python3 tools/place_store_icons.py [file.dds ...]   (default: the five shop pictures of the tab; the originals stay in git)"""
import os, subprocess, sys, tempfile, shutil
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.join(here, "..")
sys.path.insert(0, here)
import make_horse_ball_mice as M
ICON, CY, MAXH = 512, 345, 330
FILES = ["store/ball_v2.dds", "store/mouseBall.dds", "vehicles/horseHarness/store_horseHarness_v2.dds", "vehicles/horseSaddle/store_horseSaddle.dds",
         "vehicles/horseJumps/store_jumpCross_v2.dds", "vehicles/horseJumps/store_jumpStandards_v2.dds"]
def run(cmd): return subprocess.run(cmd, shell=True, capture_output=True, text=True, check=True).stdout.strip()
def place(rel):
    src = os.path.join(root, rel); work = tempfile.mkdtemp(prefix="place_icon_", dir=os.environ.get("TMPDIR", "/tmp")); base = os.path.basename(rel)[:-4]
    png = os.path.join(work, base + ".png"); run('convert "%s" -define png:color-type=6 "%s"' % (src, png))
    w, h, x, y = [int(v) for v in run('convert "%s" -alpha extract -threshold 1%% -trim -format "%%w %%h %%X %%Y" info:' % png).replace("+", " ").replace("x", " ").split()[:4]]
    s = min(1.0, MAXH / h); nw, nh = max(1, round(w * s)), max(1, round(h * s))
    cx = x + w / 2; ox, oy = round(cx - nw / 2), round(CY - nh / 2)
    out = os.path.join(work, base + "_new.png")
    run('convert "%s" -crop %dx%d+%d+%d +repage -resize %dx%d "%s/c.png" && convert -size %dx%d xc:none "%s/c.png" -geometry +%d+%d -composite -define png:color-type=6 "%s"' % (png, w, h, x, y, nw, nh, work, ICON, ICON, work, ox, oy, out))
    final = os.path.join(work, base + ".png"); os.replace(out, final)
    shutil.copyfile(M.tool_dds(final, gui=True), src)
    print("%s: %dx%d at (%d,%d) -> %dx%d at (%d,%d)" % (rel, w, h, x, y, nw, nh, ox, oy))
if __name__ == "__main__":
    for f in (sys.argv[1:] or FILES): place(f)
