#!/usr/bin/env python3
"""The shop picture of the loose saddle: Blender renders the real i3d (tools/blender_preview.py, no texture in the preview: tinted leather brown here), ImageMagick sizes it to the object tile (about 54 % of the width, centred at 0.53 / 0.45), the GIANTS Texture Tool makes the dds (a GUI picture: no mipmaps).
  python3 dev/foal/tools/make_saddle_icon.py      -> vehicles/horseSaddle/store_horseSaddle.dds"""
import os, subprocess, sys, shutil, tempfile
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.join(here, "..", "..", "..")
sys.path.insert(0, os.path.join(root, "tools"))
import make_horse_ball_mice as M
BLENDER = "/mnt/c/Program Files/Blender Foundation/Blender 5.1/blender.exe"
ICON, WIDTH = 512, 0.54
def win(p): return subprocess.run(["wslpath", "-w", os.path.abspath(p)], capture_output=True, text=True, check=True).stdout.strip()
out = os.path.join(root, "vehicles", "horseSaddle"); work = tempfile.mkdtemp(prefix="saddle_icon_", dir=os.environ.get("TMPDIR", "/tmp"))
_w = subprocess.run(["cmd.exe", "/c", "echo %TEMP%"], capture_output=True, text=True, cwd="/mnt/c").stdout.strip()      # (the Windows temp folder, asked of Windows)
shared = os.path.join(subprocess.run(["wslpath", "-u", _w], capture_output=True, text=True).stdout.strip(), "saddle_item"); os.makedirs(shared, exist_ok=True)
win_shared = _w + "\\saddle_item"
subprocess.run(["convert", os.path.expanduser("~/fs25_resources/HorseModel/saddle_diffuse.dds"), shared + "/leather.png"], check=True)
subprocess.run([BLENDER, "--background", "--python", win(os.path.join(root, "tools", "blender_preview.py")), "--", win(os.path.join(out, "horseSaddle.i3d")), win_shared + "\\raw.png", win_shared + "\\leather.png"], capture_output=True)
shutil.copyfile(shared + "/raw.png", os.path.join(work, "raw.png"))
w = int(ICON * WIDTH); ox, oy = int(0.53 * ICON), int(0.45 * ICON); png = os.path.join(work, "store_horseSaddle.png")
subprocess.run('cd "%s" && convert raw.png -trim +repage -resize %dx raw_t.png && convert -size %dx%d xc:none raw_t.png -gravity center -geometry +%d+%d -composite "%s"' % (work, w, ICON, ICON, ox - ICON // 2, oy - ICON // 2, png), shell=True, check=True)
shutil.copyfile(M.tool_dds(png, gui=True), os.path.join(out, "store_horseSaddle.dds"))
print("wrote", os.path.join(out, "store_horseSaddle.dds"))
