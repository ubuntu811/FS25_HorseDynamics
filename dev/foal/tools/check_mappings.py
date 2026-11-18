#!/usr/bin/env python3
"""Checks that every i3dMapping path of a vehicle xml (index paths: "0>0|0|2|0") finds the SAME node, by name, in a baked model as in the game's own horse.i3d. An added node in the middle of a bone's children
shifts the indices after it: the game then says "Failed to find child ... Index not found" and the horse does not load.
  python3 check_mappings.py xml/horseAdult.xml models/horse/horseAdult.i3d        (exit 1 on a mismatch)"""
import sys, re, os
import xml.etree.ElementTree as ET
GAME_I3D = os.path.expanduser("~/fs25_resources/HorseModel/horse.i3d")

def scene_nodes(path):
    root = ET.fromstring(open(path, "rb").read().decode("latin-1").encode("latin-1"))
    scene = root.find("Scene")
    return list(scene)

def resolve(top, path):
    """'0>0|0|2' -> the element: the part before > is the index of the scene's top node, then child indices."""
    first, _, rest = path.partition(">")
    el = top[int(first)]
    for seg in [s for s in rest.split("|") if s != ""]:
        kids = [c for c in el if c.tag in ("TransformGroup", "Shape", "Light", "Camera", "Audio", "AudioSource", "Emitter")]
        i = int(seg)
        if i >= len(kids): return None
        el = kids[i]
    return el

def main(xml_path, i3d_path):
    game, model = scene_nodes(GAME_I3D), scene_nodes(i3d_path)
    maps = re.findall(r'<i3dMapping id="([^"]+)" node="([^"]+)"', open(xml_path, encoding="utf-8-sig").read())
    bad = 0
    for mid, node in maps:
        g, m = resolve(game, node), resolve(model, node)
        gname = g.get("name") if g is not None else None
        mname = m.get("name") if m is not None else None
        if gname is not None and mname != gname:
            print("MISMATCH %-28s %-34s game: %-18s model: %s" % (mid, node, gname, mname)); bad += 1
    print("%s: %d mappings checked, %d mismatches" % (os.path.basename(xml_path), len(maps), bad))
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
