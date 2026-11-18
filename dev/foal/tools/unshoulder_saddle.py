#!/usr/bin/env python3
"""The saddle and its panels hang partly on the horse's shoulder bones (frontRump_*, frontHip_*, weights up to 0.64 at the front flaps): when the leg swings the leather is dragged along. Those weights are dropped and the rest renormalised (the spine bones carry the leather; a vertex with nothing left takes Chest_M).
  python3 unshoulder_saddle.py models/horse/horseAdult      (safe to run again)"""
import sys, os, re
import numpy as np
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here); sys.path.insert(0, os.path.join(here, "..", "..", "..", "tools"))
import shift_saddle as SS
LEG = re.compile(r"^(front|fr[A-Z]|jnts_for)")

def main(base):
    xml = open(base + ".i3d", "rb").read().decode("latin-1")
    lst = [int(v) for v in re.search(r'<Shape name="saddleSeat" [^>]*?skinBindNodeIds="([^"]*)"', xml).group(1).split()]
    names = {int(m.group(2)): m.group(1) for m in re.finditer(r'name="([^"]+)"[^>]*nodeId="(\d+)"', xml)}
    bones = [names.get(i, "?") for i in lst]; leg = np.array([bool(LEG.match(b)) for b in bones]); chest = bones.index("Chest_M")
    print("leg bones in the bind list:", [b for b, l in zip(bones, leg) if l])
    raw, sf = SS.S.read(base + ".i3d.shapes")
    for name in ("saddleShape", "panelShape"):
        k, s = SS.load(sf, name); A = SS.arrays(s); W, I = A["W"].copy(), A["I"]
        drop = leg[I] & (W > 0); moved = np.where(drop.any(1))[0]
        W[drop] = 0.0; tot = W.sum(1)
        for v in moved:
            if tot[v] < 1e-3: W[v] = 0.0; W[v, 0] = 1.0; I[v, 0] = chest
            else: W[v] = W[v] / tot[v]
        print("%s: %d of %d vertices lost shoulder weight" % (name, len(moved), len(W)))
        A["W"] = W; SS.write(sf, k, s, A)
    SS.S.write(base + ".i3d.shapes", sf)

if __name__ == "__main__":
    main(sys.argv[1])
