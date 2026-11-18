#!/usr/bin/env python3
"""A joint for each stirrup (called by rebuild_blanket.py): the stirrup iron and its leather (the game's own pieces, which stay exactly where the game has them = the RIDING pose) get a new bone `stirrupJoint_R/L` at the top of the leather
(under the saddle flap), a child of Spine1_M. Skin: the iron and the lower leather are 100 % on the new bone, fading to the leather's old bones at its top. HorseStirrup.lua swings the bone about the horse's lateral axis when nobody rides.
The bone is added last under Spine1_M (the vehicle xml's i3dMappings use index paths) and to the saddleSeat shape's skinBindNodeIds. Idempotent."""
import re, os, sys
import numpy as np
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here)
import add_attach_nodes as AN

FULL_BELOW = 0.25          # metres (adult) below the pivot from which the leather is 100 % on the new bone

def stirrup_sets(SAD, P_base, scale):
    """per side: (iron + keeper pieces B, leather pieces S) found like the girth details did: small islands relative to the girth band"""
    import girth_details as GD
    isl = GD.islands(SAD); out = {}
    for side in (1.0, -1.0):
        girth = None
        for idx in isl:
            q = P_base[idx]
            if len(idx) == 54 and side * q[:, 0].mean() > 0 and 0.20 <= SAD["U"][idx][:, 0].min() and SAD["U"][idx][:, 0].max() <= 0.31 and SAD["U"][idx][:, 1].max() < 0.41: girth = idx
        if girth is None: continue
        gz0 = (P_base[girth][:, 2].min() + P_base[girth][:, 2].max()) / 2; gy0 = P_base[girth][:, 1].min()
        B, S = [], []
        for idx in isl:
            q = P_base[idx]
            if len(idx) <= 60 and idx is not girth and side * q[:, 0].mean() > 0.1 * scale and gz0 - 0.22 * scale <= q[:, 2].mean() <= gz0 - 0.04 * scale and q[:, 1].min() > gy0 + 0.04 * scale and q[:, 1].max() < gy0 + 0.76 * scale:
                (S if q[:, 1].max() >= gy0 + 0.39 * scale else B).append(idx)
        if B and S: out[side] = (np.concatenate(B), np.concatenate(S))
    return out

def apply(SAD, P_base, sets, i3d_path, scale):
    xml = open(i3d_path, "rb").read().decode("latin-1")
    Ws = AN.bone_world(xml, "Spine1_M"); inv = np.linalg.inv(Ws)
    m = re.search(r'(\n[ \t]*)<TransformGroup name="Spine1_M"[^>]*?(?<!/)>', xml)
    nid = max(int(x) for x in re.findall(r'nodeId="(\d+)"', xml))
    ids = {}
    for side, tag in ((1.0, "L"), (-1.0, "R")):                      # (+x is the model's left: the bones are named by the horse's own sides)
        if side not in sets: continue
        B, S = sets[side]
        top = S[np.argmax(P_base[S][:, 1])]; pivot = P_base[top]
        local = (inv @ np.append(pivot, 1.0))[:3]
        name = "stirrupJoint_" + tag
        mm = re.search(r'<TransformGroup name="%s"[^>]*nodeId="(\d+)"' % name, xml)
        if mm: ids[side] = int(mm.group(1)); continue
        nid += 1; ids[side] = nid
        depth, close = 1, None
        for tag_ in re.finditer(r'<TransformGroup\b[^>]*?(/?)>|</TransformGroup>', xml[m.end():]):
            if tag_.group(0).startswith("</"): depth -= 1
            elif tag_.group(1) != "/": depth += 1
            if depth == 0: close = m.end() + tag_.start(); break
        ls = xml.rfind("\n", 0, close)
        xml = xml[:ls] + '%s<TransformGroup name="%s" translation="%.5f %.5f %.5f" nodeId="%d" />' % (m.group(1) + "  ", name, local[0], local[1], local[2], nid) + xml[ls:]
        m = re.search(r'(\n[ \t]*)<TransformGroup name="Spine1_M"[^>]*?(?<!/)>', xml)
    # the saddleSeat shape binds the new bones too (appended to its list: indices = their positions)
    sm = re.search(r'(<Shape name="saddleSeat" [^>]*?skinBindNodeIds=")([^"]*)(")', xml)
    lst = [int(v) for v in sm.group(2).split()]
    for side in (1.0, -1.0):
        if side in ids and ids[side] not in lst: lst.append(ids[side])
    xml = xml[:sm.start()] + sm.group(1) + " ".join(str(v) for v in lst) + sm.group(3) + xml[sm.end():]
    open(i3d_path, "wb").write(xml.encode("latin-1"))
    report = []
    for side in (1.0, -1.0):
        if side not in ids: continue
        B, S = sets[side]; bone = lst.index(ids[side]); allv = np.concatenate([B, S])
        top = S[np.argmax(P_base[S][:, 1])]; ypiv = P_base[top][1]
        t = np.clip((ypiv - P_base[allv][:, 1]) / (FULL_BELOW * scale), 0.0, 1.0); w = t * t * (3 - 2 * t)
        for v, wn in zip(allv, w):
            old = [(int(SAD["I"][v, k]), float(SAD["W"][v, k])) for k in range(4) if SAD["W"][v, k] > 0]
            old = sorted(old, key=lambda a: -a[1])[:3]
            tot = sum(x for _, x in old) or 1.0
            mix = [(i, (1 - wn) * x / tot) for i, x in old] + [(bone, wn)]
            mix = [a for a in mix if a[1] > 1e-5]; ts = sum(x for _, x in mix)
            SAD["W"][v] = 0; SAD["I"][v] = 0
            for k, (i, x) in enumerate(sorted(mix, key=lambda a: -a[1])): SAD["I"][v, k] = i; SAD["W"][v, k] = x / ts
        report.append("side %+d: bone %s (node %d, index %d) at the top of the leather y %.2f; %d vertices (%d iron, %d leather)" % (side, "stirrupJoint_" + ("L" if side > 0 else "R"), ids[side], bone, ypiv, len(allv), len(B), len(S)))
    return report


def quat_from_matrix(R):
    t = np.trace(R)
    if t > 0:
        sq = np.sqrt(t + 1.0) * 2; w = 0.25 * sq; x = (R[2, 1] - R[1, 2]) / sq; y = (R[0, 2] - R[2, 0]) / sq; z = (R[1, 0] - R[0, 1]) / sq
    elif R[0, 0] > R[1, 1] and R[0, 0] > R[2, 2]:
        sq = np.sqrt(1.0 + R[0, 0] - R[1, 1] - R[2, 2]) * 2; w = (R[2, 1] - R[1, 2]) / sq; x = 0.25 * sq; y = (R[0, 1] + R[1, 0]) / sq; z = (R[0, 2] + R[2, 0]) / sq
    elif R[1, 1] > R[2, 2]:
        sq = np.sqrt(1.0 + R[1, 1] - R[0, 0] - R[2, 2]) * 2; w = (R[0, 2] - R[2, 0]) / sq; x = (R[0, 1] + R[1, 0]) / sq; y = 0.25 * sq; z = (R[1, 2] + R[2, 1]) / sq
    else:
        sq = np.sqrt(1.0 + R[2, 2] - R[0, 0] - R[1, 1]) * 2; w = (R[1, 0] - R[0, 1]) / sq; x = (R[0, 2] + R[2, 0]) / sq; y = (R[1, 2] + R[2, 1]) / sq; z = 0.25 * sq
    q = np.array([x, y, z, w]); q /= np.linalg.norm(q)
    return q if q[3] >= 0 else -q

def lead_pose(P_base, P_moved, sets, i3d_path, scale):
    """The leading pose of each stirrup as a move of its bone: the rigid fit (Kabsch) of the iron's pieces from the game's position to where they were put when they hung at the girth, turned into the bone's parent space (Spine1_M) as a
    local rotation (quaternion x y z w) and a local translation. Returns {side: dict}."""
    xml = open(i3d_path, "rb").read().decode("latin-1")
    Wm = AN.bone_world(xml, "Spine1_M"); Rw = Wm[:3, :3]
    out = {}
    for side, (B, S) in sets.items():
        A = P_base[B]; C = P_moved[B]
        ca, cc = A.mean(0), C.mean(0)
        H = (A - ca).T @ (C - cc); U, _, Vt = np.linalg.svd(H); d = np.sign(np.linalg.det(Vt.T @ U.T))
        R = Vt.T @ np.diag([1, 1, d]) @ U.T
        t = cc - R @ ca
        top = S[np.argmax(P_base[S][:, 1])]; b = P_base[top]                  # the bone's pivot
        tau = t + R @ b - b                                                    # v' = R (v - b) + b + tau
        Rl = Rw.T @ R @ Rw; taul = Rw.T @ tau
        q = quat_from_matrix(Rl)
        resid = np.linalg.norm((A @ R.T + t) - C, axis=1).max()
        ang = np.degrees(2 * np.arccos(min(1.0, q[3])))
        cl = Rw.T @ (ca - b)                                                  # the iron's centre relative to the pivot, in the bone's parent space (the yaw turns about the iron's own vertical axis)
        out[side] = dict(q=[float(v) for v in q], t=[float(v) for v in taul], c=[float(v) for v in cl], info="turn %.1f deg, move %.1f cm (model space %s), fit residual %.1f mm" % (ang, 100 * np.linalg.norm(t), np.round(t * 100, 1).tolist(), 1000 * resid))
    return out


def ride_pose(P_base, sets, i3d_path, feet, sole):
    """The RIDING pose of each stirrup as a move of its bone: the game's iron hangs flat against the flank (the leading pose, left as it is), and the rider's boots are not in it. Here the iron's bottom bar middle is moved under the ball of the foot
    (the rider's ToeBase node, measured in the game with hdStirrup measure: x and z of the foot, y minus `sole`). Returned in the bone's parent space (Spine1_M) as a translation t and the iron's centre c relative to the pivot (the yaw turns about it).
    No feet data (the foal has no rider): the pose is nothing."""
    xml = open(i3d_path, "rb").read().decode("latin-1")
    Rw = AN.bone_world(xml, "Spine1_M")[:3, :3]
    out = {}
    for side, (B, S) in sets.items():
        Q = P_base[B]; top = S[np.argmax(P_base[S][:, 1])]; b = P_base[top]
        ymin = Q[:, 1].min(); mid = Q[Q[:, 1] < ymin + 0.012].mean(0); cen = Q.mean(0)
        foot = feet.get("L" if side > 0 else "R") if feet else None
        if foot is None:
            t = np.zeros(3)
        else:
            t = np.array([foot[0], foot[1] - sole, foot[2]]) - mid
        out[side] = dict(q=[0.0, 0.0, 0.0, 1.0], t=[float(v) for v in Rw.T @ t], c=[float(v) for v in Rw.T @ (cen - b)],
                         info="move (model space) %s cm to put the bar middle %s under the foot %s" % (np.round(t * 100, 1).tolist(), np.round(mid, 3).tolist(), foot))
    return out
