#!/usr/bin/env python3
"""Horse -> foal: a copy of horse.i3d whose bones carry the goat kid's proportions (scale per bone, hooves back on the ground).
Usage: make_foal.py <HorseModel dir> <out dir> [age 0..1]  (age 0 = kid proportions, 1 = adult)."""
import sys, math, shutil, os
import xml.etree.ElementTree as ET
ET.register_namespace("xsi", "http://www.w3.org/2001/XMLSchema-instance")

# World scale of a bone = the goat kid / adult length ratio of the segment that leaves it (measured from the game's goat i3d files).
SCALE = {
    "Root_M": 0.70, "RootPart1_M": 0.70, "Spine1_M": 0.70, "Chest_M": 0.64,
    "Neck_M": 0.51, "Neck2_M": 0.51, "Neck4_M": 0.51, "Head_M": 0.68,
    "frontRump": 0.78, "frontHip": 0.56, "frontKnee": 0.59, "frontAnkle": 0.89, "frontFoot": 0.96, "frontToes": 0.96, "hoofFront": 0.96,
    "backHip": 0.69, "backKnee": 0.61, "backAnkle": 0.84, "backFoot": 1.0, "backToes": 1.0, "hoofBack": 1.0,
    "Tail0_M": 0.79, "Tail2_M": 0.94, "Tail4_M": 0.94, "Tail6_M": 0.94,
}
def target(name):
    for key, v in SCALE.items():
        if name == key or (not key.endswith("_M") and name.startswith(key)):
            return v
    return None

def mat(rot, order):
    def r(ax, a):
        c, s = math.cos(a), math.sin(a)
        return {"x": [[1,0,0],[0,c,-s],[0,s,c]], "y": [[c,0,s],[0,1,0],[-s,0,c]], "z": [[c,-s,0],[s,c,0],[0,0,1]]}[ax]
    def mul(a, b): return [[sum(a[i][k]*b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    m = [[1,0,0],[0,1,0],[0,0,1]]
    for ax in order:
        m = mul(m, r(ax, math.radians(rot["xyz".index(ax)])))
    return m

def fk(root, order):
    """world height of every hoof, with scale attributes"""
    out = {}
    def walk(n, pm, pp, ps):
        for c in n:
            if c.tag != "TransformGroup": continue
            t = [float(x) for x in c.get("translation", "0 0 0").split()]
            ro = [float(x) for x in c.get("rotation", "0 0 0").split()]
            sc = float(c.get("scale", "1 1 1").split()[0])
            R = mat(ro, order)
            pos = [pp[i] + ps * sum(pm[i][j] * t[j] for j in range(3)) for i in range(3)]
            M = [[sum(pm[i][k]*R[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
            if c.get("name", "").startswith("hoof"): out[c.get("name")] = pos[1]
            walk(c, M, pos, ps * sc)
    walk(root, [[1,0,0],[0,1,0],[0,0,1]], [0,0,0], 1.0)
    return out

def main(src, dst, age=0.0):
    tree = ET.parse(os.path.join(src, "horse.i3d")); root = tree.getroot()
    sk = [g for g in root.iter("TransformGroup") if g.get("name") == "skeleton"][0]
    best = None
    for order in ("zyx", "xyz", "xzy", "yxz", "yzx", "zxy"):
        h = fk(sk, order); v = list(h.values())
        spread = max(v) - min(v)
        if best is None or spread < best[0]: best = (spread, order, h)
    spread, order, h0 = best
    print("rotation order %s: adult hoof heights %s (spread %.3f)" % (order, {k: round(x, 2) for k, x in h0.items()}, spread))
    def apply(node, parentS):
        for c in node:
            if c.tag != "TransformGroup": continue
            nm = c.get("name"); tv = target(nm)
            S = parentS
            if tv is not None:
                S = 1.0 + (tv - 1.0) * (1.0 - age)
                local = S / parentS
                if abs(local - 1) > 1e-6: c.set("scale", "%.5f %.5f %.5f" % (local, local, local))
            apply(c, S)
    apply(sk, 1.0)
    h1 = fk(sk, order)
    drop = (sum(h1.values()) - sum(h0.values())) / len(h0)
    rm = [g for g in sk.iter("TransformGroup") if g.get("name") == "Root_M"][0]
    t = [float(x) for x in rm.get("translation").split()]
    t[1] -= drop                                    # (the skeleton node itself is not rotated or scaled)
    rm.set("translation", "%.5f %.5f %.5f" % tuple(t))
    h2 = fk(sk, order)
    print("foal hoof heights after lowering the root by %.3f m: %s" % (drop, {k: round(x, 2) for k, x in h2.items()}))
    root.set("name", "horseFoal")
    os.makedirs(dst, exist_ok=True)
    tree.write(os.path.join(dst, "horseFoal.i3d"), encoding="iso-8859-1", xml_declaration=True)
    for ext in (".shapes", ".anim"):
        shutil.copy(os.path.join(src, "horse.i3d" + ext), os.path.join(dst, "horseFoal.i3d" + ext))
    x = open(os.path.join(dst, "horseFoal.i3d"), encoding="iso-8859-1").read().replace('externalAnimFile="horse.i3d.anim"', 'externalAnimFile="horseFoal.i3d.anim"')
    open(os.path.join(dst, "horseFoal.i3d"), "w", encoding="iso-8859-1").write(x)

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 0.0)
