#!/usr/bin/env python3
"""The girth's details (called by rebuild_blanket.py): the game's own two roller buckles (chrome frames with leather keepers) and its billet strap sit 13 cm behind the girth band, so nothing connects them. Here they are moved onto the girth's top end, the
billet is made two (one per buckle), everything lies on the blanket at its own height, shares the blanket's skin weights, and a keeper strap is added across the billets on the blanket (the loop the billets pass through).
Pure geometry on the saddle arrays: SAD = dict P N Tg U W I T (numpy)."""
import numpy as np, sys, os
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here); sys.path.insert(0, os.path.join(here, "..", "..", "..", "tools"))
import make_horse_sulky as K

LIFT_STRAP, LIFT_BUCKLE, LIFT_KEEPER = 0.014, 0.018, 0.0205       # metres (adult) above the blanket's top
STRAP_GAP = 0.030                                                    # the two billets: this far either side of the girth's middle (z)
KEEPER_HALF_LEN, KEEPER_HALF_W, KEEPER_HALF_T = 0.075, 0.0085, 0.0016
KEEPER_ABOVE_GIRTH = 0.115                                           # the keeper's height above the girth's top end
ZONE_Z, ZONE_Y = (0.12, 0.30), (0.90, 1.62)                          # where the game's buckle / billet pieces are (adult size)
LEATHER_UV_V = (0.46, 0.88)                                          # the billet's own leather strip in the saddle texture: u .42, v from..to

def islands(SAD):
    par = list(range(len(SAD["P"])))
    def f(a):
        while par[a] != a: par[a] = par[par[a]]; a = par[a]
        return a
    for a, b, c in SAD["T"]:
        ra, rb, rc = f(a), f(b), f(c); par[rb] = ra; par[rc] = ra
    isl = np.array([f(i) for i in range(len(SAD["P"]))])
    return [np.where(isl == r)[0] for r in np.unique(isl)]

def apply(SAD, P_base, NPo, NNt, Wm, Im, scale):
    isl = islands(SAD)
    report = []
    added_total = 0
    for side in (1.0, -1.0):
        padv = np.where(np.sign(NPo[:, 0]) == side)[0]
        PP, PN = NPo[padv], NNt[padv]
        def lay(pos, lift, group=None):
            """pos moved along the blanket's normals so that its height above the blanket top is `lift` (the mean over the group, bins of 1 cm in y if group is 'bins')"""
            d = ((pos[:, None, :] - PP[None, :, :]) ** 2).sum(2); jj = np.argmin(d, axis=1)
            h = ((pos - PP[jj]) * PN[jj]).sum(1)
            if group == "bins":
                key = np.round(pos[:, 1] / (0.01 * scale)).astype(int); delta = np.zeros(len(pos))
                for k in np.unique(key): delta[key == k] = lift - h[key == k].mean()
            else:
                delta = np.full(len(pos), lift - h.mean())
            return pos + PN[jj] * delta[:, None], padv[jj]
        girth, B, S = None, [], []
        for idx in isl:
            q = P_base[idx]
            if len(idx) == 54 and side * q[:, 0].mean() > 0 and 0.20 <= SAD["U"][idx][:, 0].min() and SAD["U"][idx][:, 0].max() <= 0.31 and SAD["U"][idx][:, 1].max() < 0.41:
                girth = idx
        if girth is not None:
            gz0 = (P_base[girth][:, 2].min() + P_base[girth][:, 2].max()) / 2; gy0 = P_base[girth][:, 1].min()       # (the zone is found relative to the girth band: a foal's model is scaled and shifted)
            for idx in isl:
                q = P_base[idx]
                if len(idx) <= 60 and idx is not girth and side * q[:, 0].mean() > 0.1 * scale and gz0 - 0.22 * scale <= q[:, 2].mean() <= gz0 - 0.04 * scale and q[:, 1].min() > gy0 + 0.04 * scale and q[:, 1].max() < gy0 + 0.76 * scale:
                    (S if q[:, 1].max() >= gy0 + 0.39 * scale else B).append(idx)
        if girth is None or not B or not S:
            report.append("side %+d: nothing found (girth %s, buckle pieces %d, strap pieces %d)" % (side, girth is not None, len(B), len(S))); continue
        zg = (P_base[girth][:, 2].min() + P_base[girth][:, 2].max()) / 2
        Bi = np.concatenate(B); Si = np.concatenate(S)
        dz = zg - P_base[Bi][:, 2].mean()
        # buckles: each frame on its own height above the blanket
        for idx in B:
            pos, j = lay(P_base[idx] + [0, 0, dz], LIFT_BUCKLE * scale)
            SAD["P"][idx] = pos; SAD["W"][idx] = Wm[j]; SAD["I"][idx] = Im[j]
        # the billet: one moved aside, a copy on the other side (each buckle gets its own strap)
        Ts = SAD["T"][np.isin(SAD["T"], Si).all(1)]
        remap = {int(v): len(SAD["P"]) + k for k, v in enumerate(Si)}
        for key in ("P", "N", "Tg", "U", "W", "I"): SAD[key] = np.vstack([SAD[key], SAD[key][Si]])
        SAD["T"] = np.vstack([SAD["T"], np.array([[remap[int(v)] for v in t] for t in Ts])])
        copyi = np.array([remap[int(v)] for v in Si])
        for ids, off in ((Si, -STRAP_GAP * scale), (copyi, STRAP_GAP * scale)):
            pos, j = lay(P_base[Si] + [0, 0, dz + off], LIFT_STRAP * scale, "bins")
            SAD["P"][ids] = pos; SAD["W"][ids] = Wm[j]; SAD["I"][ids] = Im[j]
        added_total += len(Si)
        # the keeper strap on the blanket, across the billets, a little above the girth's top
        ytop = P_base[girth][:, 1].max() + KEEPER_ABOVE_GIRTH * scale
        n = 9; zs = np.linspace(zg - KEEPER_HALF_LEN * scale, zg + KEEPER_HALF_LEN * scale, n)
        cen, nrm, wj = [], [], []
        for z in zs:
            j = padv[np.argmin((NPo[padv, 2] - z) ** 2 + (NPo[padv, 1] - ytop) ** 2)]
            cen.append(NPo[j] + NNt[j] * LIFT_KEEPER * scale); nrm.append(NNt[j]); wj.append(j)
        cen = np.array(cen); nrm = np.array(nrm)
        for _ in range(2): cen[1:-1] = (cen[:-2] + 2 * cen[1:-1] + cen[2:]) / 4
        hw, ht = KEEPER_HALF_W * scale, KEEPER_HALF_T * scale
        P_, N_, U_, W_, I_, T_ = [], [], [], [], [], []
        def vert(p, nn, uv, j):
            P_.append(p); N_.append(nn); U_.append(uv); W_.append(Wm[j]); I_.append(Im[j]); return len(P_) - 1
        faces = [(+1, 0), (-1, 0), (0, +1), (0, -1)]
        for fn, fw in faces:
            rows = []
            for k in range(n):
                t = cen[min(k + 1, n - 1)] - cen[max(k - 1, 0)]; t = np.array(K.norm(tuple(t)))
                nn = nrm[k] - t * (nrm[k] @ t); nn = np.array(K.norm(tuple(nn))); w = np.array(K.cross(tuple(t), tuple(nn)))
                nface = nn * fn + w * fw
                base = cen[k] + nn * ht * fn + w * hw * fw
                a, b = (base - w * hw, base + w * hw) if fn else (base - nn * ht, base + nn * ht)
                uv0 = 0.40 + 0.04 * k / (n - 1)
                rows.append((vert(a, nface, (uv0, LEATHER_UV_V[0] + 0.05), wj[k]), vert(b, nface, (uv0 + 0.01, LEATHER_UV_V[0] + 0.05), wj[k])))
            for k in range(n - 1):
                for tri in ((rows[k][0], rows[k][1], rows[k + 1][1]), (rows[k][0], rows[k + 1][1], rows[k + 1][0])):
                    nrm_t = np.cross(P_[tri[1]] - P_[tri[0]], P_[tri[2]] - P_[tri[0]])
                    T_.append(tri if nrm_t @ N_[tri[0]] >= 0 else (tri[0], tri[2], tri[1]))
        base_i = len(SAD["P"])
        SAD["P"] = np.vstack([SAD["P"], np.array(P_)]); SAD["N"] = np.vstack([SAD["N"], np.array(N_)])
        SAD["Tg"] = np.vstack([SAD["Tg"], np.array([list(K.frame_of(K.norm(tuple(x)))[0]) + [1.0] for x in N_])])
        SAD["U"] = np.vstack([SAD["U"], np.array(U_)]); SAD["W"] = np.vstack([SAD["W"], np.array(W_)]); SAD["I"] = np.vstack([SAD["I"], np.array(I_)])
        SAD["T"] = np.vstack([SAD["T"], np.array(T_) + base_i])
        report.append("side %+d: buckles %d pieces moved %.1f cm forward, billet %d verts x2, keeper %d verts at y %.2f" % (side, len(B), dz * 100, len(Si), len(P_), ytop))
    return report
