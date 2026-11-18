#!/usr/bin/env python3
"""Re-skins the stirrup leathers of a baked horse model so that they follow the horse's contour in the riding pose: the leather stays on its old bones (hangs flat against the flank, under the rider's thigh and knee) down to Y_TOP,
and moves onto the stirrup bone only in its lower part (Y_TOP to Y_FULL), so only the iron goes out under the boot and the leather bends outward at the bottom. Below Y_FULL (iron and keepers) it is the bone's, as stirrup_bones.py made it.
  python3 reskin_stirrup.py models/horse/horseAdult           (after rebuild_blanket.py; safe to run again: the weights follow from the vertex heights)
The leather's old bone weights are lost where the bone had all of it: they are taken from the nearest vertex that kept some (the leather's top)."""
import sys, os, re
import numpy as np
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here); sys.path.insert(0, os.path.join(here, "..", "..", "..", "tools"))
import shift_saddle as SS

Y_TOP, Y_FULL = 1.34, 1.15                      # model heights (adult): above Y_TOP the leather is not the bone's at all, below Y_FULL it is all the bone's

def main(base):
    xml = open(base + ".i3d", "rb").read().decode("latin-1")
    lst = [int(v) for v in re.search(r'<Shape name="saddleSeat" [^>]*?skinBindNodeIds="([^"]*)"', xml).group(1).split()]
    bones = [lst.index(int(re.search(r'name="stirrupJoint_%s"[^>]*nodeId="(\d+)"' % t, xml).group(1))) for t in "LR"]
    raw, sf = SS.S.read(base + ".i3d.shapes"); k, s = SS.load(sf, "saddleShape"); A = SS.arrays(s)
    P, W, I = A["P"], A["W"], A["I"]; n = 0
    for b in bones:
        wb = np.where(I == b, W, 0).sum(1); V = np.where(wb > 0)[0]
        donors = V[wb[V] < 0.99]                                                       # vertices that still have their old bones
        for v in V:
            y = P[v, 1]; t = min(1.0, max(0.0, (Y_TOP - y) / (Y_TOP - Y_FULL))); w = t * t * (3 - 2 * t)
            if y < Y_FULL - 1e-6: continue                                             # the iron: untouched
            old = [(int(I[v, j]), float(W[v, j])) for j in range(4) if W[v, j] > 0 and int(I[v, j]) != b]
            if sum(x for _, x in old) < 0.05:
                d = donors[np.argmin(((P[donors] - P[v]) ** 2).sum(1))]
                old = [(int(I[d, j]), float(W[d, j])) for j in range(4) if W[d, j] > 0 and int(I[d, j]) != b]
            old = sorted(old, key=lambda a: -a[1])[:3]; tot = sum(x for _, x in old) or 1.0
            mix = [(i, (1 - w) * x / tot) for i, x in old] + [(b, w)]
            mix = sorted([a for a in mix if a[1] > 1e-5], key=lambda a: -a[1]); ts = sum(x for _, x in mix)
            W[v] = 0; I[v] = 0
            for j, (i, x) in enumerate(mix): I[v, j] = i; W[v, j] = x / ts
            n += 1
    SS.write(sf, k, s, A); SS.S.write(base + ".i3d.shapes", sf)
    print("re-skinned %d leather vertices (bone weight 0 above y %.2f, 1 below %.2f)" % (n, Y_TOP, Y_FULL))

if __name__ == "__main__":
    main(sys.argv[1])
