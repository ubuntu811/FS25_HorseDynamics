#!/usr/bin/env python3
"""Adds the UV coordinates of the game's horse (read from horse.i3d.shapes, same vertex order as the app's meshes: the positions match to 1e-5) to app/horse_app.json, for the app's texture view.
Usage: add_uvs.py <HorseModel dir> [app/horse_app.json]"""
import sys, os, json
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here)
import numpy as np
import shapes_io as S
d = sys.argv[1]; path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, "..", "app", "horse_app.json")
raw, sf = S.read(os.path.join(d, "horse.i3d.shapes"))
sh = [S.M.parse_shape_entity(e, sf.header.version) for e in sf.entities if e.entity_type.name == "SHAPE"]
data = json.load(open(path))
for name, m in data["meshes"].items():
    s = [x for x in sh if x.name == name + "Shape"][0]
    P = np.array([[v.x, v.y, v.z] for v in s.positions]); app = np.array(m["pos"]).reshape(-1, 3)
    assert len(P) == len(app) and np.abs(np.stack([P[:, 0], -P[:, 2], P[:, 1]], 1) - app).max() < 1e-3, name
    m["uv"] = [round(c, 5) for u in s.uv_sets[0] for c in (u.u, u.v)]
json.dump(data, open(path, "w"))
print("uv added to", list(data["meshes"]))
