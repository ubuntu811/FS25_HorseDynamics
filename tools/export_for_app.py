# Headless Blender: export what the browser app needs: the horse's meshes (rest pose, triangles, top-4 skin weights per vertex), the skeleton (parent, rest translation / rotation, rest joint position), and two clips.
# Run: blender.exe --background --python export_for_app.py -- <horse.i3d> <game folder> <out.json>   (Windows paths)
import sys, re, json, math, os, importlib.util
import bpy
import xml.etree.ElementTree as ET
args = sys.argv[sys.argv.index("--") + 1:]
model, game, out = args
here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("anim_reader", os.path.join(here, "anim_reader.py"))
ar = importlib.util.module_from_spec(spec); spec.loader.exec_module(ar)
MOD = "bl_ext.user_default.blender_i3d_importer"
bpy.context.preferences.addons[MOD].preferences.fs25_data_base = game
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.fs25_i3d(filepath=model)
bpy.context.view_layer.update()
root = ET.parse(model).getroot()
sk = [g for g in root.iter("TransformGroup") if g.get("name") == "skeleton"][0]
nodes = []
def collect(el, parent):
    for c in el:
        if c.tag != "TransformGroup": continue
        idx = len(nodes)
        t = [float(x) for x in c.get("translation", "0 0 0").split()]
        r = [math.radians(float(x)) for x in c.get("rotation", "0 0 0").split()]
        nodes.append({"id": int(c.get("nodeId")), "name": c.get("name"), "parent": parent, "t": t, "r": r})
        collect(c, idx)
collect(sk, -1)
by_id = {n["id"]: i for i, n in enumerate(nodes)}
by_name = {n["name"]: i for i, n in enumerate(nodes)}
for o in bpy.data.objects:
    m = re.match(r"^\d+\.(\d+):", o.name)
    if o.type == "EMPTY" and m and int(m.group(1)) in by_id:
        nodes[by_id[int(m.group(1))]]["p"] = [round(x, 5) for x in o.matrix_world.translation]
def r5(x): return round(x, 5)
meshes = {}
for name in ("body", "maneTail", "saddle", "reins"):
    o = bpy.data.objects[name]
    me = o.data
    me.calc_loop_triangles()
    gnames = {g.index: g.name for g in o.vertex_groups}
    pos, jn, wt = [], [], []
    for v in me.vertices:
        p = o.matrix_world @ v.co
        pos += [r5(p.x), r5(p.y), r5(p.z)]
        infl = []
        for g in v.groups:
            n = re.sub(r"(\.\d+)?_skin$", "", gnames.get(g.group, ""))
            if n in by_name and g.weight > 1e-4: infl.append((by_name[n], g.weight))
        infl.sort(key=lambda x: -x[1]); infl = infl[:4]
        tot = sum(w for _, w in infl) or 1.0
        while len(infl) < 4: infl.append((0, 0.0))
        jn += [j for j, _ in infl]; wt += [round(w / tot, 4) for _, w in infl]
    idx = []
    for t in me.loop_triangles:
        idx += [t.vertices[0], t.vertices[1], t.vertices[2]]
    meshes[name] = {"pos": pos, "idx": idx, "jn": jn, "wt": wt}
clips = {}
allc = ar.read_anim(model + ".anim")
for cname, key in (("idle", "idle01Source"), ("walk", "walkLeftSource")):
    dur, tracks = allc[key]
    clips[cname] = {"duration": dur, "tracks": {str(by_id[nid]): [[r5(x) for x in (k[1] + k[2])] for k in keys] for nid, keys in tracks.items() if nid in by_id}}
json.dump({"nodes": nodes, "meshes": meshes, "clips": clips}, open(out, "w"), separators=(",", ":"))
print("EXPORT", len(nodes), "nodes;", {k: (len(v["pos"]) // 3, len(v["idx"]) // 3) for k, v in meshes.items()})
