# Headless Blender: import horse.i3d, play one clip of its .anim on the skeleton (adult, and the foal with the per-joint scale of make_foal.py) and render it frame by frame.
# The clip is applied through the game's own space: forward kinematics over the i3d's skeleton gives every joint's pose; each joint empty is moved by (pose x rest^-1) in Blender's world (M = +90 about X, the axis fix the importer bakes into the mesh)
# on top of where the importer left it, and the armature bones follow their empties (Child-Of constraints).
# Run: blender.exe --background --python blender_anim.py -- <horse.i3d> <game folder> <out dir> <clip> [first,last,step] [bake 0|1]   (Windows paths)
import sys, re, os, math, bpy, importlib.util
import xml.etree.ElementTree as ET
from mathutils import Matrix
args = sys.argv[sys.argv.index("--") + 1:]
model, game, outdir, clipname = args[0], args[1], args[2], args[3]
first, last, step = [int(x) for x in args[4].split(",")] if len(args) > 4 else (1, 36, 1)
bake = len(args) > 5 and args[5] == "1"
here = os.path.dirname(os.path.abspath(__file__))
def load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(here, name + ".py"))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
mf, ar = load("make_foal"), load("anim_reader")
MOD = "bl_ext.user_default.blender_i3d_importer"
bpy.context.preferences.addons[MOD].preferences.fs25_data_base = game
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.fs25_i3d(filepath=model)
log = []
clips = ar.read_anim(model + ".anim")
duration, tracks = clips[clipname]
nkeys = len(next(iter(tracks.values())))
M = Matrix.Rotation(math.radians(90), 4, "X"); Mi = M.inverted()
def TR(t, r):                                    # translation, then Rz * Ry * Rx (radians)
    return Matrix.Translation(t) @ (Matrix.Rotation(r[2], 4, "Z") @ Matrix.Rotation(r[1], 4, "Y") @ Matrix.Rotation(r[0], 4, "X"))
# --- the i3d skeleton: nodeId -> (parent, name, rest translation, rest rotation in radians)
root = ET.parse(model).getroot()
sk = [g for g in root.iter("TransformGroup") if g.get("name") == "skeleton"][0]
nodes = {}
def collect(el, parent):
    for c in el:
        if c.tag != "TransformGroup": continue
        nid = int(c.get("nodeId"))
        t = tuple(float(x) for x in c.get("translation", "0 0 0").split())
        r = tuple(math.radians(float(x)) for x in c.get("rotation", "0 0 0").split())
        nodes[nid] = (parent, c.get("name"), t, r)
        collect(c, nid)
collect(sk, None)
order = list(nodes)                              # parents before children (document order)
# --- the foal's uniform local scale per node (same walk as make_foal.apply)
def foal_scales(age=0.0):
    out, cum = {}, {}
    for nid in order:
        parent, name, _, _ = nodes[nid]
        ps = cum.get(parent, 1.0)
        tv = mf.target(name); S = ps
        if tv is not None:
            S = 1.0 + (tv - 1.0) * (1.0 - age)
            out[nid] = S / ps
        cum[nid] = S
    return out
# --- empties by nodeId, their rest world matrices as imported
empties = {}
for o in bpy.data.objects:
    m = re.match(r"^\d+\.(\d+):", o.name)
    if o.type == "EMPTY" and m and int(m.group(1)) in nodes:
        empties[int(m.group(1))] = o
        o.empty_display_size = 0.03
bpy.context.view_layer.update()
E_rest = {nid: o.matrix_world.copy() for nid, o in empties.items()}
def fk(local_of):
    W = {}
    for nid in order:
        parent = nodes[nid][0]
        W[nid] = (W[parent] if parent in W else Matrix.Identity(4)) @ local_of(nid)
    return W
rest_local = lambda nid: TR(nodes[nid][2], nodes[nid][3])
W_rest = fk(rest_local)
log.append("clip %s: %.0f ms, %d keys, %d tracks; %d skeleton nodes, %d empties" % (clipname, duration, nkeys, len(tracks), len(nodes), len(empties)))
def pose(key, scales, drop):
    """Set every joint empty for key index `key`. scales: nodeId -> local uniform scale (or {}); drop: metres the whole skeleton is lowered."""
    def local_of(nid):
        if nid in tracks:
            _, t, r = tracks[nid][min(key, len(tracks[nid]) - 1)]
            L = TR(t, r)
        else:
            L = rest_local(nid)
        s = scales.get(nid, 1.0)
        return L @ Matrix.Diagonal((s, s, s, 1.0)) if s != 1.0 else L
    W = fk(local_of)
    target = {}
    low = Matrix.Translation((0, 0, -drop))
    for nid, o in empties.items():
        D = W[nid] @ W_rest[nid].inverted()
        target[nid] = low @ (M @ D @ Mi) @ E_rest[nid]
    for nid in order:
        o = empties.get(nid)
        if o is None: continue
        if o.parent is None: parent_world = Matrix.Identity(4)
        else:
            pid = next((k for k, v in empties.items() if v == o.parent), None)
            parent_world = target[pid] if pid is not None else o.parent.matrix_world
        o.matrix_basis = (parent_world @ o.matrix_parent_inverse).inverted() @ target[nid]
body = bpy.data.objects["body"]
def body_low():
    dg = bpy.context.evaluated_depsgraph_get(); dg.update()
    ev = body.evaluated_get(dg); me = ev.to_mesh()
    z = min((ev.matrix_world @ v.co).z for v in me.vertices); ev.to_mesh_clear(); return z
scene = bpy.context.scene
SHOW = ("body", "maneTail", "saddle", "reins")
for o in bpy.data.objects:
    o.hide_render = o.name not in SHOW
scene.render.engine = "BLENDER_WORKBENCH"
scene.render.resolution_x, scene.render.resolution_y = 600, 420
scene.display.shading.light = "STUDIO"; scene.display.shading.color_type = "SINGLE"; scene.display.shading.single_color = (0.8, 0.78, 0.74)
cd = bpy.data.cameras.new("cam"); cd.type = "ORTHO"; cd.ortho_scale = 4.2
cam = bpy.data.objects.new("cam", cd); scene.collection.objects.link(cam); scene.camera = cam
cam.location = (10, -0.5, 1.2); cam.rotation_euler = (1.5708, 0, 1.5708)
os.makedirs(outdir, exist_ok=True)
keys = list(range(first - 1, min(last, nkeys), step))
def ground(scales):
    low = None
    for k in keys:
        pose(k, scales, 0.0); z = body_low()
        low = z if low is None else min(low, z)
    return low
def shoot(prefix, scales, drop, keyframes=False):
    for k in keys:
        scene.frame_set(k + 1)                   # (first the frame, then the pose: moving the frame re-evaluates the keyframes made so far and would overwrite the pose)
        pose(k, scales, drop)
        if keyframes:
            for o in empties.values():
                o.rotation_mode = "QUATERNION"
                loc, quat, sc = o.matrix_basis.decompose()
                o.location, o.rotation_quaternion, o.scale = loc, quat, sc
                for p in ("location", "rotation_quaternion", "scale"):
                    o.keyframe_insert(p, frame=k + 1)
        scene.render.filepath = os.path.join(outdir, "%s_%03d.png" % (prefix, k + 1))
        bpy.ops.render.render(write_still=True)
adult_ground = ground({})
log.append("adult: lowest point over the cycle %.3f m" % adult_ground)
shoot("adult", {}, adult_ground)
foal = foal_scales(0.0)
foal_ground = ground(foal)
log.append("foal: lowest point over the cycle %.3f m" % foal_ground)
shoot("foal", foal, foal_ground, keyframes=bake)
scene.frame_start, scene.frame_end = first, min(last, nkeys)
if bake:
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(outdir, "horse_foal_%s.blend" % clipname))
open(os.path.join(outdir, "anim_log.txt"), "w").write("\n".join(log) + "\n")
