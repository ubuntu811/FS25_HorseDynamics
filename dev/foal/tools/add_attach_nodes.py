#!/usr/bin/env python3
"""Adds the attach nodes of the tack to a baked horse model (the nodes the scripts tie ropes to, so they do not have to create and place them): so far `bridleRing`, a child of the head bone at the bridle's bit ring.
  python3 add_attach_nodes.py models/horse/horseAdult          (folder + model name without extension; after bake_foal.py, make_coat_shader.py and split_tack.py)
The position is worked out from the model's OWN bridle (a foal's head is elsewhere): the bit ring is the small connected piece of the game's bridle mesh (163 vertices, near the mouth), found by vertex number in the
baked mesh, its centre taken to the head bone's space by the model's skeleton (the i3d's bone transforms: rotations apply as Rz * Ry * Rx, no scale). The side is the one the script's HorseRope.ring uses (z > 0 in the bone's space)."""
import sys, os, re, math
import numpy as np
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here)
import shapes_io as S
import split_tack as ST

def rot(rx, ry, rz):
    rx, ry, rz = map(math.radians, (rx, ry, rz))
    Rx = np.array([[1, 0, 0], [0, math.cos(rx), -math.sin(rx)], [0, math.sin(rx), math.cos(rx)]])
    Ry = np.array([[math.cos(ry), 0, math.sin(ry)], [0, 1, 0], [-math.sin(ry), 0, math.cos(ry)]])
    Rz = np.array([[math.cos(rz), -math.sin(rz), 0], [math.sin(rz), math.cos(rz), 0], [0, 0, 1]])
    return Rz @ Ry @ Rx

def bone_world(xml, name):
    """World matrix of the named bone: the chain of the i3d's TransformGroups from the root to it (translation, rotation in degrees; the baked skeleton has no scale)."""
    import xml.etree.ElementTree as ET
    root = ET.fromstring(xml.encode("latin-1"))
    def walk(el, M):
        for c in el:
            if c.tag not in ("TransformGroup", "Shape", "Light"): continue
            t = [float(v) for v in c.get("translation", "0 0 0").split()]
            r = [float(v) for v in c.get("rotation", "0 0 0").split()]
            m = np.eye(4); m[:3, :3] = rot(*r); m[:3, 3] = t
            W = M @ m
            if c.get("name") == name: return W
            found = walk(c, W)
            if found is not None: return found
        return None
    scene = root.find("Scene")
    return walk(scene, np.eye(4))

def main(base):
    shapes_path, i3d_path = base + ".i3d.shapes", base + ".i3d"
    xml = open(i3d_path, "rb").read().decode("latin-1")
    # a node added in the MIDDLE of a bone's children shifts the child indices after it, and the vehicle xml addresses nodes by index path ("0>0|0|2|..."): new nodes go LAST. A bridleRing from an earlier
    # run that sits first (the first version did, and the reins were not found) is taken out and put at the end.
    xml = re.sub(r'\n[ \t]*<TransformGroup name="bridleRing"[^>]*/>', "", xml)
    raw, sf = S.read(shapes_path)
    bsh = None
    for e in sf.entities:
        if e.entity_type.name == "SHAPE":
            sh = S.M.parse_shape_entity(e, sf.header.version)
            if sh.name == "bridleShape": bsh = sh
    assert bsh is not None, "run split_tack.py first (no bridleShape)"
    # the bit rings: pieces of 163 vertices of the game's own saddle mesh near the mouth; the baked bridle shape has its own vertex numbering (a subset), so find them on the game's mesh and map by position order
    graw, gsf = S.read(ST.GAME_SHAPES)
    gsh = [s for s in (S.M.parse_shape_entity(e, gsf.header.version) for e in gsf.entities if e.entity_type.name == "SHAPE") if s.name == "saddleShape"][0]
    GP = np.array([[p.x, p.y, p.z] for p in gsh.positions]); gtri = np.array([[t.p1 - 1, t.p2 - 1, t.p3 - 1] for t in gsh.triangles])
    comp = ST.components(GP, gtri)
    # the same partition as split_tack: the bridle vertices in original order
    bridle = np.zeros(len(GP), bool)
    for cid in np.unique(comp):
        m = comp == cid
        if GP[m][:, 2].mean() > ST.BRIDLE_FROM_Z: bridle |= m
    order = np.nonzero(bridle)[0]                      # original vertex numbers of the bridle shape's vertices, in the shape's own order
    BP = np.array([[p.x, p.y, p.z] for p in bsh.positions]); assert len(order) == len(BP)
    rings = []
    for cid in np.unique(comp):
        m = comp == cid
        if m.sum() == 163 and GP[m][:, 2].mean() > 1.4:
            sel = np.isin(order, np.nonzero(m)[0]); rings.append(BP[sel].mean(0))
    assert len(rings) == 2, "expected two bit rings, found %d" % len(rings)
    Wh = bone_world(xml, "Head_M"); assert Wh is not None, "no Head_M in the i3d"
    inv = np.linalg.inv(Wh)
    local = [(inv @ np.append(r, 1.0))[:3] for r in rings]
    pick = max(local, key=lambda v: v[2])               # z > 0: the side HorseRope.ring uses
    print("%s: bit ring in Head_M space (%.4f %.4f %.4f); the script's constant is (-0.0983 0.4425 0.0700)" % (os.path.basename(base), pick[0], pick[1], pick[2]))
    m = re.search(r'(\n[ \t]*)<TransformGroup name="Head_M"[^>]*?(?<!/)>', xml)
    assert m is not None, "Head_M is not an open element"
    depth, pos, close = 1, m.end(), None
    for tag in re.finditer(r'<TransformGroup\b[^>]*?(/?)>|</TransformGroup>', xml[m.end():]):
        if tag.group(0).startswith("</"): depth -= 1
        elif tag.group(1) != "/": depth += 1
        if depth == 0:
            close = m.end() + tag.start(); break
    assert close is not None, "no end of Head_M"
    node_id = max(int(x) for x in re.findall(r'nodeId="(\d+)"', xml)) + 1
    indent = m.group(1) + "  "
    line_start = xml.rfind("\n", 0, close)                                  # the closing tag's own line
    new = '%s<TransformGroup name="bridleRing" translation="%.5f %.5f %.5f" nodeId="%d" />' % (indent, pick[0], pick[1], pick[2], node_id)
    xml = xml[:line_start] + new + xml[line_start:]
    open(i3d_path, "wb").write(xml.encode("latin-1"))

if __name__ == "__main__":
    main(sys.argv[1])
