#!/usr/bin/env python3
"""Bake the foal-scale web app's result into a game-ready horse model (.i3d + .i3d.shapes + .i3d.anim).

Usage: bake_foal.py <bake.json> <HorseModel dir> <out dir>
  bake.json: the page's ?bake=1 dump (foal-scale.html?<params>&bake=1, headless Edge --dump-dom).

What it does
  skeleton  every bone gets a new local translation / rotation (no scale) so that, at rest, the joints sit where the app's skinned foal has them, standing on the ground.
  meshes    body / mane+tail / saddle / reins get the app's rest-pose vertices (bind pose = this skeleton at rest); the LODs get the nearest LOD0 vertices' displacement.
            Normals and tangents are rotated by the change of the (welded) smooth normal, so creases stay.
  anim      every key's rotation is the app's modified local rotation; translations are the rest translation plus the key's change times the parent's scale.
"""
import sys, os, json, math, struct, shutil
import numpy as np
import xml.etree.ElementTree as ET
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
import shapes_io as S
import anim_reader as AR
ET.register_namespace("xsi", "http://www.w3.org/2001/XMLSchema-instance")

def L4(rows):
    m = np.eye(4); m[:3, :] = np.array(rows).reshape(3, 4); return m

def euler(R):
    """R = Rz(c) Ry(b) Rx(a) -> (a, b, c)"""
    b = -math.asin(max(-1.0, min(1.0, R[2, 0])))
    if abs(R[2, 0]) < 0.99999:
        a = math.atan2(R[2, 1], R[2, 2]); c = math.atan2(R[1, 0], R[0, 0])
    else:
        a = math.atan2(-R[1, 2], R[1, 1]); c = 0.0
    return np.array([a, b, c])

def unwrap(prev, cur):
    return cur + 2 * math.pi * np.round((prev - cur) / (2 * math.pi))

def main(bake_path, src, dst):
    bk = json.load(open(bake_path))
    names = bk["names"]; NN = len(names); minZ = bk["minZ"]
    app = json.load(open(os.path.join(here, "..", "app", "horse_app.json")))
    nodes = app["nodes"]
    assert [n["name"] for n in nodes] == names
    par = [n["parent"] for n in nodes]
    S_loc = [np.diag(bk["sc"][i] + [1.0]) for i in range(NN)]
    Lrest = [L4(r) for r in bk["restL"]]
    Lrest0 = Lrest   # the modified rest local matrices (translation part = the key formula's rest value)

    # ---- foal rest world (the app's own FK: W = Wp * L * S) and the rigid frames of the new skeleton
    W = [None] * NN; A = [None] * NN; J = np.zeros((NN, 3))
    for i in range(NN):
        p = par[i]
        W[i] = (W[p] @ Lrest[i] @ S_loc[i]) if p >= 0 else (Lrest[i] @ S_loc[i])
        A[i] = (A[p] @ Lrest[i][:3, :3]) if p >= 0 else Lrest[i][:3, :3]
        J[i] = W[i][:3, 3]
    J[:, 1] -= minZ                                           # hooves on the ground (the app subtracts the lowest body vertex)
    tNew = np.zeros((NN, 3)); rNew = np.zeros((NN, 3))
    for i in range(NN):
        p = par[i]
        tNew[i] = A[p].T @ (J[i] - J[p]) if p >= 0 else J[i]
        rNew[i] = euler(Lrest[i][:3, :3])
    # world scale of each bone in its own frame (column norms), for the animation deltas
    Sd = [np.linalg.norm(W[i][:3, :3], axis=0) for i in range(NN)]

    # ---- i3d xml: new skeleton transforms
    tree = ET.parse(os.path.join(src, "horse.i3d")); root = tree.getroot()
    sk = [g for g in root.iter("TransformGroup") if g.get("name") == "skeleton"][0]
    order = []
    def collect(el):
        for c in el:
            if c.tag != "TransformGroup": continue
            order.append(c); collect(c)
    collect(sk)
    assert len(order) == NN
    for i, el in enumerate(order):
        assert el.get("name") == names[i]
        el.set("translation", "%.6f %.6f %.6f" % tuple(tNew[i]))
        el.set("rotation", "%.5f %.5f %.5f" % tuple(np.degrees(rNew[i])))
        if "scale" in el.attrib: del el.attrib["scale"]
    root.set("name", "horseFoal")
    os.makedirs(dst, exist_ok=True)
    out_i3d = os.path.join(dst, "horseFoal.i3d")
    tree.write(out_i3d, encoding="iso-8859-1", xml_declaration=True)
    x = open(out_i3d, encoding="iso-8859-1").read().replace('externalAnimFile="horse.i3d.anim"', 'externalAnimFile="horseFoal.i3d.anim"').replace('externalShapesFile="horse.i3d.shapes"', 'externalShapesFile="horseFoal.i3d.shapes"')
    open(out_i3d, "w", encoding="iso-8859-1").write(x)

    # check: the new chain reproduces the joints
    Wn = [None] * NN
    def R3(e): a, b, c = e; return Rz(c) @ Ry(b) @ Rx(a)
    for i in range(NN):
        M = np.eye(4); M[:3, :3] = R3(rNew[i]); M[:3, 3] = tNew[i]
        Wn[i] = Wn[par[i]] @ M if par[i] >= 0 else M
    err = max(np.linalg.norm(Wn[i][:3, 3] - J[i]) for i in range(NN))
    print("skeleton: joint positions off by at most %.6f m; root drop %.3f m" % (err, minZ))

    # ---- shapes
    raw, sf = S.read(os.path.join(src, "horse.i3d.shapes"))
    byname = {}
    for e in sf.entities:
        if e.entity_type.name == "SHAPE":
            sh = S.M.parse_shape_entity(e, sf.header.version); byname[sh.name] = (e, sh)
    def to_file(p):          # app (z up, nose -y) -> file (y up, nose +z)
        p = np.asarray(p, dtype=np.float64).reshape(-1, 3); return np.stack([p[:, 0], p[:, 2], -p[:, 1]], 1)
    def shape_arrays(sh):
        P = np.array([[v.x, v.y, v.z] for v in sh.positions])
        N = np.array([[v.x, v.y, v.z] for v in sh.normals]) if sh.normals else None
        T = np.array([[v.x, v.y, v.z, v.w] for v in sh.tangents]) if getattr(sh, "tangents", None) else None
        F = np.array([[t.p1 - 1, t.p2 - 1, t.p3 - 1] for t in sh.triangles])
        return P, N, T, F
    def welded_normals(P, F):
        key = {}; grp = np.zeros(len(P), dtype=np.int64)
        for i, p in enumerate(np.round(P * 1e4).astype(np.int64)):
            grp[i] = key.setdefault(tuple(p), len(key))
        fn = np.cross(P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]])
        acc = np.zeros((len(key), 3))
        for k in range(3): np.add.at(acc, grp[F[:, k]], fn)
        n = acc[grp]; l = np.linalg.norm(n, axis=1, keepdims=True); l[l == 0] = 1
        return n / l
    def rotate_to(v, a, b):   # rotate vectors v by the rotation taking unit a to unit b (per row)
        axis = np.cross(a, b); s = np.linalg.norm(axis, axis=1, keepdims=True); c = (a * b).sum(1, keepdims=True)
        ok = (s[:, 0] > 1e-9)
        k = np.where(s > 1e-9, axis / np.where(s > 1e-9, s, 1), 0)
        out = v * c + np.cross(k, v) * s + k * (k * v).sum(1, keepdims=True) * (1 - c)
        return np.where(ok[:, None], out, v)
    def patch(ename, newP):
        e, sh = byname[ename]
        P0, N0, T0, F = shape_arrays(sh)
        data = bytearray(e.data)
        def put(old, new):
            ob = struct.pack("<%df" % old.size, *old.reshape(-1)); nb = struct.pack("<%df" % new.size, *new.reshape(-1))
            assert data.count(ob) == 1, "block not unique in %s" % ename
            o = data.find(ob); data[o:o + len(ob)] = nb
        newP = np.asarray(newP, dtype=np.float64)
        if N0 is not None:
            a = welded_normals(P0, F); b = welded_normals(newP, F)
            N1 = rotate_to(N0, a, b)
            if T0 is not None:
                T1 = np.concatenate([rotate_to(T0[:, :3], a, b), T0[:, 3:]], 1)
        # replace blocks (normals/tangents first, they are located by their old bytes)
        if N0 is not None: put(N0.astype(np.float32).astype(np.float64), N1.astype(np.float32))
        if T0 is not None: put(T0.astype(np.float32).astype(np.float64), T1.astype(np.float32))
        put(P0.astype(np.float32).astype(np.float64), newP.astype(np.float32))
        e.data = bytes(data)
    # LOD0 meshes from the app
    app_names = {"body": "bodyShape", "maneTail": "maneTailShape", "saddle": "saddleShape", "reins": "reinsShape"}
    newPos = {}; oldPos = {}
    for k, sn in app_names.items():
        e, sh = byname[sn]
        P0 = np.array([[v.x, v.y, v.z] for v in sh.positions])
        P1 = to_file(bk["pos"][k])
        assert len(P1) == len(P0)
        # sanity: the adult app positions are the same vertices
        newPos[sn] = P1; oldPos[sn] = P0
    def lod_from(src_name, lod_name):
        e, sh = byname[lod_name]
        P0 = np.array([[v.x, v.y, v.z] for v in sh.positions])
        Q0, Q1 = oldPos[src_name], newPos[src_name]
        D = Q1 - Q0
        out = np.empty_like(P0)
        for s0 in range(0, len(P0), 512):
            d2 = ((P0[s0:s0 + 512, None, :] - Q0[None, :, :]) ** 2).sum(2)
            idx = np.argpartition(d2, 4, axis=1)[:, :4]
            dd = np.take_along_axis(d2, idx, 1); w = 1.0 / (np.sqrt(dd) + 1e-4); w /= w.sum(1, keepdims=True)
            out[s0:s0 + 512] = P0[s0:s0 + 512] + (D[idx] * w[:, :, None]).sum(1)
        return out
    jobs = dict(newPos)
    for lod, srcn in (("body_LOD1Shape", "bodyShape"), ("body_LOD2Shape", "bodyShape"), ("maneTail_LOD1Shape", "maneTailShape"), ("maneTail_LOD2Shape", "maneTailShape")):
        jobs[lod] = lod_from(srcn, lod)
    for name, P in jobs.items():
        patch(name, P)
    S.write(os.path.join(dst, "horseFoal.i3d.shapes"), sf)
    print("shapes patched:", ", ".join(sorted(jobs)))

    # ---- anim: patch the keys in place
    d = bytearray(open(os.path.join(src, "horse.i3d.anim"), "rb").read())
    u = lambda o: struct.unpack_from("<I", d, o)[0]
    def string(o):
        n = u(o); return o + 4 + ((n + 3) // 4) * 4
    byid = {n["id"]: i for i, n in enumerate(nodes)}
    o = string(8); nclips = u(o); o += 4
    changed = 0
    for _ in range(nclips):
        n = u(o); cname = bytes(d[o + 4:o + 4 + n]).decode(); o = string(o); o += 8
        ntr = struct.unpack_from("<I", d, o - 4)[0]
        for _ in range(ntr):
            nid, cnt = u(o), u(o + 4); o += 8
            i = byid.get(nid)
            prev = None
            for k in range(cnt):
                if i is not None:
                    v = struct.unpack_from("<6f", d, o + 8)
                    m = bk["mod"][i]
                    Rk = R3(v[3:6]); Rm = np.array(m["R"]).reshape(3, 3) @ Rk       # the app's rotation change is premultiplied
                    tk = m["a"] * np.array(v[0:3]) + np.array(m["b"])
                    p = par[i]
                    sd = Sd[p] if p >= 0 else Sd[i]
                    tnew = tNew[i] + sd * (tk - Lrest0[i][:3, 3])
                    rk = euler(Rm)
                    if prev is not None: rk = unwrap(prev, rk)
                    prev = rk
                    struct.pack_into("<6f", d, o + 8, *tnew, *rk); changed += 1
                o += 32
    assert o == len(d), (o, len(d))
    open(os.path.join(dst, "horseFoal.i3d.anim"), "wb").write(bytes(d))
    print("anim: %d keys rewritten" % changed)

def Rx(a): c, s = math.cos(a), math.sin(a); return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
def Ry(a): c, s = math.cos(a), math.sin(a); return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
def Rz(a): c, s = math.cos(a), math.sin(a); return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])

if __name__ == "__main__":
    main(*sys.argv[1:4])
