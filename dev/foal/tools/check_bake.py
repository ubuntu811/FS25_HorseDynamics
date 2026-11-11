#!/usr/bin/env python3
"""Check a baked foal: skin the baked body shape with the baked skeleton and a baked walk key, compare to the app's own posed mesh (bake.json 'check').
Usage: check_bake.py <bake.json> <baked dir>"""
import sys, os, json, math, struct
import numpy as np
import xml.etree.ElementTree as ET
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here)
import shapes_io as S, anim_reader as AR
def Rx(a): c, s = math.cos(a), math.sin(a); return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
def Ry(a): c, s = math.cos(a), math.sin(a); return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
def Rz(a): c, s = math.cos(a), math.sin(a); return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
bk = json.load(open(sys.argv[1])); dst = sys.argv[2]
root = ET.parse(os.path.join(dst, "horseFoal.i3d")).getroot()
sk = [g for g in root.iter("TransformGroup") if g.get("name") == "skeleton"][0]
els = []
def col(el, par):
    for c in el:
        if c.tag != "TransformGroup": continue
        els.append((c, par)); col(c, len(els) - 1)
col(sk, -1)
ids = [int(c.get("nodeId")) for c, _ in els]
rest = []
for c, p in els:
    t = np.array([float(x) for x in c.get("translation").split()]); r = [math.radians(float(x)) for x in c.get("rotation").split()]
    rest.append((t, r))
def world(local):
    W = []
    for i, (c, p) in enumerate(els):
        M = np.eye(4); t, r = local[i]; M[:3, :3] = Rz(r[2]) @ Ry(r[1]) @ Rx(r[0]); M[:3, 3] = t
        W.append(W[p] @ M if p >= 0 else M)
    return W
Wr = world(rest); Binv = [np.linalg.inv(w) for w in Wr]
raw, sf = S.read(os.path.join(dst, "horseFoal.i3d.shapes"))
sh = [S.M.parse_shape_entity(e, sf.header.version) for e in sf.entities if e.entity_type.name == "SHAPE"]
body = [s for s in sh if s.name == "bodyShape"][0]
bind = [int(x) for x in [s for s in root.iter("Shape") if s.get("name") == "body"][0].get("skinBindNodeIds").split()]
P = np.array([[v.x, v.y, v.z] for v in body.positions]); Wt = np.array(body.blend_weights); Ix = np.array(body.blend_indices)
byid = {n: i for i, n in enumerate(ids)}
anim = AR.read_anim(os.path.join(dst, "horseFoal.i3d.anim"))
dur, tracks = anim["walkLeftSource"]
def pose(k):
    loc = list(rest)
    for nid, keys in tracks.items():
        if nid in byid:
            kk = keys[min(k, len(keys) - 1)]; loc[byid[nid]] = (np.array(kk[1]), list(kk[2]))
    return world(loc)
def skin(Wp):
    out = np.zeros_like(P)
    for j in range(4):
        for v in range(len(P)):
            pass
    M = np.zeros((len(bind), 4, 4)); 
    for bi, nid in enumerate(bind): M[bi] = Wp[byid[nid]] @ Binv[byid[nid]]
    Ph = np.concatenate([P, np.ones((len(P), 1))], 1)
    for j in range(4):
        out += Wt[:, j:j + 1] * np.einsum('vij,vj->vi', M[Ix[:, j]], Ph)[:, :3]
    return out
print("rest: max change of skinned vertex vs stored vertex %.6f" % np.abs(skin(Wr) - P).max())
for k in (0, 9, 18, 27):
    Q = skin(pose(k)); app = np.array(bk["check"]["walk%d" % k]).reshape(-1, 3)
    Qa = np.stack([Q[:, 0], -Q[:, 2], Q[:, 1]], 1)           # file -> app frame
    d = Qa - app; dz = np.median(d[:, 2]); d[:, 2] -= dz
    print("walk key %2d: vertical offset %+.3f m, then per-vertex difference to the app: median %.4f m, 99%% %.4f m, max %.4f m" % (k, dz, np.median(np.linalg.norm(d, axis=1)), np.percentile(np.linalg.norm(d, axis=1), 99), np.linalg.norm(d, axis=1).max()))
