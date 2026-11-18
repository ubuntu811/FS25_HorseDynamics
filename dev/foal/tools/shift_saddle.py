#!/usr/bin/env python3
"""Moves the saddle assembly (saddle, panel, pad and the two stirrup joints) BACK along the horse, off the shoulder blade: the saddle tree's front lies at z 0.44 and the scapula's rear edge at about z 0.38 to 0.40 (bones of the rest pose),
so it rests on the back of the shoulder blade. The pad and the panel keep their distance to the body (their height follows the body's back where they move to: it falls away behind the withers), the saddle moves as one piece by the mean
of that change, the stirrup joints (bones under Spine1_M) by the same in the parent's frame (and scripts/HorseStirrupPose.lua's riding pose by the opposite: the rider's feet do not move).
  python3 shift_saddle.py models/horse/horseAdult [metres back, default 0.04]      (the last step of the chain: split_tack, add_halter, rebuild_blanket, add_panel, shift_saddle, lift_flaps, thicken_flaps, reskin_stirrup)
Safe to run again: dev/foal/blanket_old/<model>_shift.json holds the hash of the shapes file this script wrote; a file with another hash is a fresh one (a bake or a redraw of the pad or the panel), shifted from where it is."""
import sys, os, re, json, hashlib, copy, math
import numpy as np
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here); sys.path.insert(0, os.path.join(here, "..", "..", "..", "tools"))
import shapes_io as S
import make_hitching_post as H
import add_attach_nodes as AN

def load(sf, name):
    for k, e in enumerate(sf.entities):
        if e.entity_type.name == "SHAPE":
            s = S.M.parse_shape_entity(e, sf.header.version)
            if s.name == name: return k, s
    raise SystemExit("no shape " + name)

def arrays(s):
    return dict(P=np.array([[p.x, p.y, p.z] for p in s.positions]), N=np.array([[p.x, p.y, p.z] for p in s.normals]), Tg=np.array([[p.x, p.y, p.z, p.w] for p in s.tangents]),
                U=np.array([[u.u, u.v] for u in s.uv_sets[0]]), W=np.array(s.blend_weights), I=np.array(s.blend_indices), T=np.array([[t.p1 - 1, t.p2 - 1, t.p3 - 1] for t in s.triangles]))

def write(sf, k, s, A):
    s0 = s.subsets[0]
    sf.entities[k].data = H.shape_entity(s.name, s.id, [tuple(p) for p in A["P"]], [tuple(n) for n in A["N"]], [tuple(u) for u in A["U"]], A["T"].reshape(-1).tolist(),
                                         [(0, len(A["P"]), 0, A["T"].size, s0.uv_density1)], s.material_slot_names, tangents=[tuple(t) for t in A["Tg"]], skin=([tuple(w) for w in A["W"]], [tuple(i) for i in A["I"]]))

AXIS_Y = 1.38                                   # the barrel's axis the pad's radial offset is measured round (add_panel.py)

def radius_field(P, N):
    """r of the body's surface round the barrel axis at (angle, z), from the body's outward vertices of the trunk (not the legs): inverse distance weighting"""
    rel = np.stack([P[:, 0], P[:, 1] - AXIS_Y], 1); r = np.linalg.norm(rel, axis=1)
    out = ((N[:, 0] * rel[:, 0] + N[:, 1] * rel[:, 1]) / np.maximum(r, 1e-9) > 0.3) & (P[:, 1] > 1.0) & (P[:, 2] > -0.45) & (P[:, 2] < 0.7)
    phi = np.arctan2(rel[:, 0], rel[:, 1])
    pts = np.stack([phi[out] * 0.4, P[out, 2]], 1); rr = r[out]
    def r_at(ph, z):
        d = (pts[:, 0] - ph * 0.4) ** 2 + (pts[:, 1] - z) ** 2
        k = np.argpartition(d, 24)[:24]; w = np.exp(-d[k] / (2 * 0.04 ** 2)) + 1e-9           # (a smooth Gaussian average: neighbouring points get nearly the same offset)
        return float((rr[k] * w).sum() / w.sum())
    return r_at

def hug(P, shift, r_at, weight=None):
    """P moved back by `shift`, its distance to the body's surface (radially round the barrel axis) kept: where the body's surface is further out at the new place, the point goes out with it"""
    Q = P.copy()
    for i in range(len(P)):
        x, y, z = P[i]; rel_y = y - AXIS_Y; r = math.hypot(x, rel_y)
        w = 1.0 if weight is None else weight(y)
        if r < 1e-6 or w <= 0:
            Q[i] = (x, y, z - shift); continue
        ph = math.atan2(x, rel_y)
        dr = (r_at(ph, z - shift) - r_at(ph, z)) * w
        Q[i] = ((r + dr) * math.sin(ph), AXIS_Y + (r + dr) * math.cos(ph), z - shift)
    return Q

def main(base, shift):
    shapes_path, i3d_path = base + ".i3d.shapes", base + ".i3d"
    state_path = os.path.join(here, "..", "blanket_old", os.path.basename(base) + "_shift.json")
    digest = hashlib.sha1(open(shapes_path, "rb").read() + open(i3d_path, "rb").read()).hexdigest()
    if os.path.exists(state_path) and json.load(open(state_path)).get("hash") == digest:
        print("already shifted by this script (the files are the ones it wrote):", base); return
    xml = open(i3d_path, "rb").read().decode("latin-1")
    raw, sf = S.read(shapes_path)
    kb, body = load(sf, "bodyShape"); BA = arrays(body)
    r_at = radius_field(BA["P"], BA["N"])
    out = {}
    pm = {}
    for name in ("blanketShape", "panelShape"):
        k, s = load(sf, name); A = arrays(s)
        P0 = A["P"]; A["P"] = hug(P0, shift, r_at); write(sf, k, s, A); out[name] = len(P0)
        if name == "panelShape": pm = (P0, A["P"])
    dy_seat = float(np.mean(pm[1][:, 1] - pm[0][:, 1]))
    k, s = load(sf, "saddleShape"); A = arrays(s)
    # rigid on top, hugging where it hangs down the flank (the billets and the girth band lie on the body): the pull to the body fades in below y 1.40
    low = lambda y: min(1.0, max(0.0, (1.40 - y) / 0.10))
    rigid = A["P"] + np.array([0.0, dy_seat, -shift]); hugged = hug(A["P"], shift, r_at, weight=low)
    t = np.array([low(p[1]) for p in A["P"]])[:, None]
    A["P"] = rigid * (1 - t) + hugged * t; write(sf, k, s, A); out["saddleShape"] = len(A["P"])
    # the stirrup joints (bones under Spine1_M): the same world move, in the parent's frame
    R = AN.bone_world(xml, "Spine1_M")[:3, :3]
    local = R.T @ np.array([0.0, dy_seat, -shift])
    for tag in ("L", "R"):
        m = re.search(r'(<TransformGroup name="stirrupJoint_%s" translation=")([^"]+)(")' % tag, xml)
        t = np.array([float(v) for v in m.group(2).split()]) + local
        xml = xml.replace(m.group(0), m.group(1) + "%.5f %.5f %.5f" % tuple(t) + m.group(3), 1)
    open(i3d_path, "wb").write(xml.encode("latin-1"))
    pose_path = os.path.join(os.path.dirname(os.path.abspath(i3d_path)), "..", "..", "scripts", "HorseStirrupPose.lua")      # the riding pose is a move from the rest pose to the rider's feet, which stay put: it shrinks by what the rest pose moved
    lua = open(pose_path).read(); m = re.search(r"(%s = \{\n)(.*?)(\n    \},)" % os.path.basename(base), lua, re.S)
    if m:
        body = re.sub(r"t = \{ ([^}]+) \}", lambda g: "t = { %.6f, %.6f, %.6f }" % tuple(np.array([float(v) for v in g.group(1).replace(",", " ").split()]) - local), m.group(2))
        open(pose_path, "w").write(lua.replace(m.group(0), m.group(1) + body + m.group(3), 1))
    S.write(shapes_path, sf)
    digest = hashlib.sha1(open(shapes_path, "rb").read() + open(i3d_path, "rb").read()).hexdigest()
    os.makedirs(os.path.dirname(state_path), exist_ok=True)
    json.dump({"hash": digest, "shift": shift, "dy_seat": dy_seat}, open(state_path, "w"))
    print("shifted %.3f m back (seat height %+.4f m): %s; stirrup joints by %s in their parent's frame" % (shift, dy_seat, out, np.round(local, 4)))

if __name__ == "__main__":
    main(sys.argv[1], float(sys.argv[2]) if len(sys.argv) > 2 else 0.04)
