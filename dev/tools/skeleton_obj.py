#!/usr/bin/env python3
"""Writes the skeleton of an i3d as an OBJ: one vertex per joint (in centimetres, y up, like the Editor's OBJ export) and one line (l) per bone, parent to child, so it can be imported into Blender next to the mesh.
Usage: skeleton_obj.py <model.i3d> <out.obj> [x offset in cm, to stand next to a second model]"""
import sys, math
import xml.etree.ElementTree as ET
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from make_foal import mat

ORDER = "zyx"       # the rotation order make_foal.py found by checking that all four hooves come out at the same height

def main(path, out, dx=0.0):
    root = ET.parse(path).getroot()
    sk = [g for g in root.iter("TransformGroup") if g.get("name") == "skeleton"][0]
    names, points, lines = [], [], []
    def walk(n, pm, pp, ps, parent):
        for c in n:
            if c.tag != "TransformGroup":
                continue
            t = [float(x) for x in c.get("translation", "0 0 0").split()]
            ro = [float(x) for x in c.get("rotation", "0 0 0").split()]
            sc = float(c.get("scale", "1 1 1").split()[0])
            R = mat(ro, ORDER)
            pos = [pp[i] + ps * sum(pm[i][j] * t[j] for j in range(3)) for i in range(3)]
            M = [[sum(pm[i][k] * R[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
            names.append(c.get("name")); points.append(pos)
            index = len(points)
            if parent is not None:
                lines.append((parent, index))
            walk(c, M, pos, ps * sc, index)
    walk(sk, [[1, 0, 0], [0, 1, 0], [0, 0, 1]], [0, 0, 0], 1.0, None)
    with open(out, "w") as f:
        f.write("# skeleton of %s: %d joints, %d bones (cm)\n" % (path, len(points), len(lines)))
        for name, p in zip(names, points):
            f.write("# %s\n" % name)
            f.write("v %.3f %.3f %.3f\n" % (p[0] * 100 + dx, p[1] * 100, p[2] * 100))
        f.write("o skeleton\n")
        for a, b in lines:
            f.write("l %d %d\n" % (a, b))
    print("%d joints, %d bones -> %s" % (len(points), len(lines), out))
    for name in ("Head_M", "hoofBackRight", "hoofFrontRight", "Tail0_M"):
        if name in names:
            p = points[names.index(name)]
            print("  %-15s x %.1f  y %.1f  z %.1f cm" % (name, p[0] * 100, p[1] * 100, p[2] * 100))

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 0.0)
