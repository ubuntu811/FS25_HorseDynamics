# Headless Blender: one scene with the adult horse and the foal side by side, both playing one clip of the horse's .anim (baked as keyframes on the joint empties).
# The second horse is a second import of the same file; each one is posed through forward kinematics (see blender_anim.py) and shifted sideways by moving every joint empty, which the armature follows.
# Run: blender.exe --background --python blender_side.py -- <horse.i3d> <game folder> <out dir> <clip> [gap in metres]   (Windows paths)
import sys, re, os, math, bpy, importlib.util
import xml.etree.ElementTree as ET
from mathutils import Matrix
args = sys.argv[sys.argv.index("--") + 1:]
model, game, outdir, clipname = args[0], args[1], args[2], args[3]
gap = float(args[4]) if len(args) > 4 else 3.0
here = os.path.dirname(os.path.abspath(__file__))
def load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(here, name + ".py"))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
mf, ar = load("make_foal"), load("anim_reader")
MOD = "bl_ext.user_default.blender_i3d_importer"
bpy.context.preferences.addons[MOD].preferences.fs25_data_base = game
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
clips = ar.read_anim(model + ".anim")
duration, tracks = clips[clipname]
nkeys = len(next(iter(tracks.values())))
M = Matrix.Rotation(math.radians(90), 4, "X"); Mi = M.inverted()
def TR(t, r):
    return Matrix.Translation(t) @ (Matrix.Rotation(r[2], 4, "Z") @ Matrix.Rotation(r[1], 4, "Y") @ Matrix.Rotation(r[0], 4, "X"))
root = ET.parse(model).getroot()
sk = [g for g in root.iter("TransformGroup") if g.get("name") == "skeleton"][0]
nodes = {}
def collect(el, parent):
    for c in el:
        if c.tag != "TransformGroup": continue
        nid = int(c.get("nodeId"))
        nodes[nid] = (parent, c.get("name"), tuple(float(x) for x in c.get("translation", "0 0 0").split()), tuple(math.radians(float(x)) for x in c.get("rotation", "0 0 0").split()))
        collect(c, nid)
collect(sk, None)
order = list(nodes)
def foal_scales(age=0.0):
    out, cum = {}, {}
    for nid in order:
        parent, name, _, _ = nodes[nid]
        ps = cum.get(parent, 1.0); tv = mf.target(name); S = ps
        if tv is not None:
            S = 1.0 + (tv - 1.0) * (1.0 - age); out[nid] = S / ps
        cum[nid] = S
    return out
def fk(local_of):
    W = {}
    for nid in order:
        parent = nodes[nid][0]
        W[nid] = (W[parent] if parent in W else Matrix.Identity(4)) @ local_of(nid)
    return W
rest_local = lambda nid: TR(nodes[nid][2], nodes[nid][3])
W_rest = fk(rest_local)

class Horse:
    def __init__(self, tag, scales, dx):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.fs25_i3d(filepath=model)
        self.objs = [o for o in bpy.data.objects if o not in before]
        self.scales, self.dx, self.tag = scales, dx, tag
        self.empties = {}
        for o in self.objs:
            m = re.match(r"^\d+\.(\d+):", o.name)
            if o.type == "EMPTY" and m and int(m.group(1)) in nodes:
                self.empties[int(m.group(1))] = o; o.empty_display_size = 0.02
        bpy.context.view_layer.update()
        self.E_rest = {n: o.matrix_world.copy() for n, o in self.empties.items()}
        self.body = next(o for o in self.objs if o.type == "MESH" and re.sub(r"\.\d+$", "", o.name) == "body")
        self.drop = 0.0
        for o in self.objs:                       # the viewport shows only the horse itself
            base = re.sub(r"\.\d+$", "", o.name)
            if o.type == "MESH" and base not in ("body", "maneTail", "saddle", "reins"): o.hide_set(True)
            if o.type in ("CAMERA", "LIGHT"): o.hide_set(True)
        for o in self.empties.values(): o.hide_set(True)
    def pose(self, key):
        def local_of(nid):
            if nid in tracks:
                _, t, r = tracks[nid][min(key, len(tracks[nid]) - 1)]; L = TR(t, r)
            else: L = rest_local(nid)
            s = self.scales.get(nid, 1.0)
            return L @ Matrix.Diagonal((s, s, s, 1.0)) if s != 1.0 else L
        W = fk(local_of); target = {}
        shift = Matrix.Translation((self.dx, 0, -self.drop))
        for nid in self.empties:
            target[nid] = shift @ (M @ (W[nid] @ W_rest[nid].inverted()) @ Mi) @ self.E_rest[nid]
        by_obj = {v: k for k, v in self.empties.items()}
        for nid in order:
            o = self.empties.get(nid)
            if o is None: continue
            if o.parent is None: pw = Matrix.Identity(4)
            else: pw = target[by_obj[o.parent]] if o.parent in by_obj else o.parent.matrix_world
            o.matrix_basis = (pw @ o.matrix_parent_inverse).inverted() @ target[nid]
    def lowest(self):
        dg = bpy.context.evaluated_depsgraph_get(); dg.update()
        ev = self.body.evaluated_get(dg); me = ev.to_mesh()
        z = min((ev.matrix_world @ v.co).z for v in me.vertices); ev.to_mesh_clear(); return z
    def bake(self):
        scene = bpy.context.scene
        for k in range(nkeys):
            scene.frame_set(k + 1)
            self.pose(k)
            for o in self.empties.values():
                o.rotation_mode = "QUATERNION"
                loc, quat, sc = o.matrix_basis.decompose()
                o.location, o.rotation_quaternion, o.scale = loc, quat, sc
                for p in ("location", "rotation_quaternion", "scale"):
                    o.keyframe_insert(p, frame=k + 1)

adult = Horse("adult", {}, -gap / 2)
foal = Horse("foal", foal_scales(0.0), gap / 2)
for h in (adult, foal):
    low = None
    for k in range(0, nkeys, 3):
        h.pose(k); z = h.lowest(); low = z if low is None else min(low, z)
    h.drop = low
scene = bpy.context.scene
scene.frame_start, scene.frame_end = 1, nkeys
adult.bake(); foal.bake()
scene.frame_set(1)
os.makedirs(outdir, exist_ok=True)
# a check picture
scene.render.engine = "BLENDER_WORKBENCH"; scene.render.resolution_x, scene.render.resolution_y = 1000, 420
scene.display.shading.light = "STUDIO"; scene.display.shading.color_type = "SINGLE"; scene.display.shading.single_color = (0.8, 0.78, 0.74)
cd = bpy.data.cameras.new("cam"); cd.type = "ORTHO"; cd.ortho_scale = 6.5
cam = bpy.data.objects.new("cam", cd); scene.collection.objects.link(cam); scene.camera = cam
cam.location = (0, -10, 1.3); cam.rotation_euler = (1.5708, 0, 0)
for k in (1, 12):
    scene.frame_set(k)
    scene.render.filepath = os.path.join(outdir, "side_%02d.png" % k)
    bpy.ops.render.render(write_still=True)
scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(outdir, "horses_side_by_side_%s.blend" % clipname))
print("DONE adult drop %.3f foal drop %.3f" % (adult.drop, foal.drop))
