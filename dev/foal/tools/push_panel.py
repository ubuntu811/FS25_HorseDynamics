#!/usr/bin/env python3
"""The panel stands out of the game's saddle at the knee roll (up to 22 mm, the pocket in the flap): its vertices that are too close to the leather are moved towards the barrel axis, the move spread over the neighbours (the same function as the loose saddle's, make_saddle_item.push_panel_back).
Run after lift_flaps / thicken_flaps (the leather it measures against is the saddle as it is then); once per shapes file (a state file remembers the hash).
  python3 push_panel.py models/horse/horseAdult [--force]   (--force: again over a shapes file this script has pushed already, e.g. after a new margin)"""
import sys, os, json, hashlib
import numpy as np
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here); sys.path.insert(0, os.path.join(here, "..", "..", "..", "tools"))
import shift_saddle as SS
import make_saddle_item as M

def main(base):
    shapes_path = base + ".i3d.shapes"
    state_path = os.path.join(here, "..", "blanket_old", os.path.basename(base) + "_pushed.json")
    digest = hashlib.sha1(open(shapes_path, "rb").read()).hexdigest()
    force = "--force" in sys.argv
    if not force and os.path.exists(state_path) and json.load(open(state_path)).get("hash") == digest:
        print("panel already pushed back by this script:", base); return
    raw, sf = SS.S.read(shapes_path)
    _, seat = SS.load(sf, "saddleShape"); A = SS.arrays(seat)
    kp, panel = SS.load(sf, "panelShape"); PA = SS.arrays(panel)
    comp = M.components(A["P"], A["T"]); ids, c = np.unique(comp, return_counts=True); mid = ids[np.argmax(c)]
    Tb = np.array([t for t in A["T"] if comp[t[0]] == mid])
    before = M.panel_clearance(PA["P"], A["P"], Tb)
    print("before: %d panel vertices poke through the leather" % int((before < 0).sum()))
    P0 = PA["P"].copy()
    PA["P"] = M.push_panel_back(PA["P"], PA["T"], A["P"], Tb)
    flip = 0
    for a, b, c in PA["T"]:
        n0 = np.cross(P0[b] - P0[a], P0[c] - P0[a]); n1 = np.cross(PA["P"][b] - PA["P"][a], PA["P"][c] - PA["P"][a])
        if n0 @ n1 < 0: flip += 1
    print("triangles turned over by the push: %d" % flip)
    after = M.panel_clearance(PA["P"], A["P"], Tb)
    print("after: %d poke, closest clearance %.1f mm" % (int((after < 0).sum()), 1000 * np.nanmin(after)))
    SS.write(sf, kp, panel, PA); SS.S.write(shapes_path, sf)
    digest = hashlib.sha1(open(shapes_path, "rb").read()).hexdigest()
    os.makedirs(os.path.dirname(state_path), exist_ok=True)
    json.dump({"hash": digest}, open(state_path, "w"))

if __name__ == "__main__":
    main(sys.argv[1])
