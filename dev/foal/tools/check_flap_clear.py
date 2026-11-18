#!/usr/bin/env python3
"""Does the panel poke through the flap BETWEEN the flap's vertices? A ray from the barrel's axis (x = 0, y = 1.38) through every top vertex of the panel is intersected with the flap's outward triangles; the flap's radius there minus the panel's radius is the clearance (negative = poking through).
  python3 check_flap_clear.py models/horse/horseAdult"""
import sys, os
import numpy as np
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here); sys.path.insert(0, os.path.join(here, "..", "..", "..", "tools"))
import shift_saddle as SS
import lift_flaps as LF

def main(base):
    raw, sf = SS.S.read(base + ".i3d.shapes")
    A = SS.arrays(SS.load(sf, "saddleShape")[1]); P, N, T = A["P"], A["N"], A["T"]
    PA = SS.arrays(SS.load(sf, "panelShape")[1]); Q, QN = PA["P"], PA["N"]
    top = ((QN[:, 0] * Q[:, 0] + QN[:, 1] * (Q[:, 1] - 1.38)) > 0) & (np.arctan2(np.abs(Q[:, 0]), Q[:, 1] - 1.38) > 0.55)
    phi, r = LF.polar(P)
    reg = (phi > 0.55) & (phi < 2.8) & (P[:, 2] > 0.0) & (P[:, 2] < 0.46) & (r > 0.25) & (r < 0.5) & (P[:, 1] > 1.2)
    tri = [t for t in T if reg[t].all() and (np.cross(P[t[1]] - P[t[0]], P[t[2]] - P[t[0]]) @ np.array([P[t[0]][0], P[t[0]][1] - 1.38, 0.0])) > 0]
    tri = np.array(tri); print("flap triangles:", len(tri))
    out = []
    for q in Q[top]:
        # work in the plane z = const: the ray goes from (0, 1.38) along (x, y - 1.38), z fixed, so intersect each triangle's section in that z plane
        d2 = np.array([q[0], q[1] - 1.38]); dn = np.linalg.norm(d2); d2 = d2 / dn
        best = None
        for t in tri:
            a, b, c = P[t]
            if min(a[2], b[2], c[2]) > q[2] + 1e-9 or max(a[2], b[2], c[2]) < q[2] - 1e-9: continue
            pts = []
            for u, v in ((a, b), (b, c), (c, a)):
                if (u[2] - q[2]) * (v[2] - q[2]) <= 0 and abs(u[2] - v[2]) > 1e-12:
                    s = (q[2] - u[2]) / (v[2] - u[2]); pts.append(u + s * (v - u))
            if len(pts) < 2: continue
            p0, p1 = pts[0], pts[1]
            e = np.array([p1[0] - p0[0], p1[1] - p0[1]]); w = np.array([p0[0], p0[1] - 1.38])
            M = np.array([[d2[0], -e[0]], [d2[1], -e[1]]])
            if abs(np.linalg.det(M)) < 1e-12: continue
            tt, ss = np.linalg.solve(M, -w)
            if 0 <= ss <= 1 and tt > 0:
                best = tt if best is None else max(best, tt)
        if best is not None: out.append((best - dn, q))
    c = np.array([o[0] for o in out])
    print("panel top vertices with a flap above them: %d of %d" % (len(c), int(top.sum())))
    print("clearance mm: min %.1f  p5 %.1f  median %.1f" % (1000 * c.min(), 1000 * np.percentile(c, 5), 1000 * np.median(c)))
    bad = [(1000 * o[0], o[1]) for o in out if o[0] < 0]
    print("poking through (clearance below 0): %d" % len(bad))
    if bad:
        pts = np.array([b[1] for b in bad]); print("   at z %.2f..%.2f  y %.2f..%.2f" % (pts[:, 2].min(), pts[:, 2].max(), pts[:, 1].min(), pts[:, 1].max()))

if __name__ == "__main__":
    main(sys.argv[1])
