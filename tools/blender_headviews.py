# THREE-QUARTER HEAD VIEWS of the candidates (to judge a head from the front, not only the side).
# (derived from blender_legs.py: LEG-THICKNESS round on the Q3 foal (bare), mid-walk stills.
# (derived from blender_final.py: FINAL foal (Z4, body 0.58, no saddle or reins) next to the adult, the walk baked, a GIF of the cycle.
# (derived from blender_heads7.py: head-shape variants of the foal next to the adult (head depth / length / width, jaw), standing stills, head close-ups, and the walk baked in the saved .blend.
# The head bone's local axes: x up/down, y forward (to the muzzle), z sideways.
# A variant sets ABSOLUTE scale factors per region (relative to the adult), as (length along the bone, thickness) where it matters; every node without a rule inherits its parent's; local = absolute / parent's absolute, per axis.
# Run: blender.exe --background --python blender_variants.py -- <horse.i3d> <game folder> <out dir>   (Windows paths)
import sys, re, os, math, bpy, importlib.util
import xml.etree.ElementTree as ET
from mathutils import Matrix
args = sys.argv[sys.argv.index("--") + 1:]
model, game, outdir = args[0], args[1], args[2]
here = os.path.dirname(os.path.abspath(__file__))
def load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(here, name + ".py"))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
ar = load("anim_reader")
MOD = "bl_ext.user_default.blender_i3d_importer"
bpy.context.preferences.addons[MOD].preferences.fs25_data_base = game
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
clips = ar.read_anim(model + ".anim")
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
def fk(local_of):
    W = {}
    for nid in order:
        parent = nodes[nid][0]
        W[nid] = (W[parent] if parent in W else Matrix.Identity(4)) @ local_of(nid)
    return W
rest_local = lambda nid: TR(nodes[nid][2], nodes[nid][3])
W_rest = fk(rest_local)

# ---- the variants: factors relative to a uniformly scaled adult (B), the rest of the table's regions
BASE = dict(B=1.0, torso=1.0, neck_len=1.0, neck_th=1.0, head=(1.0, 1.0, 1.0), jaw=(1.0, 1.0, 1.0), ear=1.0, eyes=1.0, leg_len=1.0, leg_th=1.0, hoof=1.0, tail=1.0)
A = dict(B=0.65, torso=0.93, neck_len=0.88, neck_th=0.88, ear=1.15, eyes=1.12, leg_len=1.30, leg_th=0.85, hoof=0.88, tail=0.85)
Bn = dict(B=0.60, torso=0.90, neck_len=0.85, neck_th=0.85, ear=1.2, eyes=1.18, leg_len=1.42, leg_th=0.80, hoof=0.85, tail=0.75)
def with_head(base, head, jaw=(1.0, 1.0, 1.0)):
    d = dict(base); d["head"] = head; d["jaw"] = jaw; return d
def mk(**kw):
    d = dict(A); d.update(kw); return d
H = (1.45, 1.2, 1.45)
Q = dict(A, head=(1.50, 1.25, 1.50), jaw=(1.0, 0.92, 1.0), ear=1.9, neck_th=0.98)
def q(**kw):
    d = dict(Q); d.update(kw); return d
FOAL = q(B=0.58, head=(1.40, 1.30, 0.95), neck_len=1.10, neck_th=0.78)
def adult_head(k):
    return dict(BASE, head=(k, k, k), eyes=1.0 + (k - 1) * 0.5, ear=1.0 + (k - 1) * 0.5)
Q3 = q(ear=1.7)
def l3(**kw):
    d = dict(Q3); d.update(kw); return d
VARIANTS = [
    ("adult (game)", dict(), False),
    ("adult head +15%", adult_head(1.15), False),
    ("Q3 + legs 1.25", l3(leg_th=1.25, hoof=1.2), True),
    ("N4 (Z4 head, long neck)", q(B=0.54, head=(1.40, 1.30, 0.95), neck_len=1.45, neck_th=0.82, leg_th=1.25, hoof=1.2), True),
]
def absolute_for(p):
    P = dict(BASE); P.update(p); B = P["B"]
    hd, hl, hw = P["head"]; jd, jl, jw = P["jaw"]
    def rule(name):
        if name == "Root_M": return (B, B, B)
        if name in ("RootPart1_M", "Spine1_M", "Chest_M", "Spine1Part1_M", "belly1_M"): return (B * P["torso"],) * 3
        if name == "Neck_M": return (B * P["neck_len"], B * P["neck_th"], B * P["neck_th"])
        if name == "Head_M": return (B * hd, B * hl, B * hw)                     # (depth, length toward the muzzle, width)
        if name.startswith("ear"): return (B * P["ear"],) * 3
        if name == "Jaw_M": return (B * hd * jd, B * hl * jl, B * hw * jw)
        if name.startswith("Eye_") or name.startswith("lid"): return (B * P["eyes"],) * 3
        if name in ("frontHip_R", "frontHip_L", "backHip_R", "backHip_L"): return (B * P["leg_len"], B * P["leg_th"], B * P["leg_th"])
        if "Toes" in name or name.startswith("hoof"): return (B * P["hoof"],) * 3
        if name == "Tail0_M": return (B * P["tail"],) * 3
        return None
    out, cum = {}, {}
    for nid in order:
        parent, name, _, _ = nodes[nid]
        ps = cum.get(parent, (1.0, 1.0, 1.0)); S = rule(name) or ps
        out[nid] = tuple(S[i] / ps[i] for i in range(3)); cum[nid] = S
    return out

class Horse:
    def __init__(self, label, scales, y, bare=False):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.fs25_i3d(filepath=model)
        self.objs = [o for o in bpy.data.objects if o not in before]
        self.label, self.scales, self.y = label, scales, y
        self.empties = {}
        for o in self.objs:
            m = re.match(r"^\d+\.(\d+):", o.name)
            if o.type == "EMPTY" and m and int(m.group(1)) in nodes:
                self.empties[int(m.group(1))] = o; o.empty_display_size = 0.02
        bpy.context.view_layer.update()
        self.E_rest = {n: o.matrix_world.copy() for n, o in self.empties.items()}
        self.body = next(o for o in self.objs if o.type == "MESH" and re.sub(r"\.\d+$", "", o.name) == "body")
        self.drop = 0.0
        if bare:                                  # no saddle, no reins
            gone = [o for o in self.objs if o.type == 'MESH' and re.sub(r'\.\d+$', '', o.name) in ('saddle', 'reins')]
            self.objs = [o for o in self.objs if o not in gone]
            for o in gone:
                bpy.data.objects.remove(o, do_unlink=True)
        for o in self.objs:
            base = re.sub(r"\.\d+$", "", o.name)
            if o.type == "MESH" and base not in ("body", "maneTail", "saddle", "reins"): o.hide_set(True); o.hide_render = True
            if o.type in ("CAMERA", "LIGHT"): o.hide_set(True)
        for o in self.empties.values(): o.hide_set(True)
    def pose(self, tracks, key):
        def local_of(nid):
            if nid in tracks:
                _, t, r = tracks[nid][min(key, len(tracks[nid]) - 1)]; L = TR(t, r)
            else: L = rest_local(nid)
            s = self.scales.get(nid, (1.0, 1.0, 1.0))
            return L @ Matrix.Diagonal((s[0], s[1], s[2], 1.0))
        W = fk(local_of); target = {}
        shift = Matrix.Translation((0, self.y, -self.drop))
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
    def height(self):
        dg = bpy.context.evaluated_depsgraph_get(); dg.update()
        ev = self.body.evaluated_get(dg); me = ev.to_mesh()
        z = max((ev.matrix_world @ v.co).z for v in me.vertices); ev.to_mesh_clear(); return z
    def bake(self, tracks, n):
        scene = bpy.context.scene
        for k in range(n):
            scene.frame_set(k + 1)
            self.pose(tracks, k)
            for o in self.empties.values():
                o.rotation_mode = "QUATERNION"
                loc, quat, sc = o.matrix_basis.decompose()
                o.location, o.rotation_quaternion, o.scale = loc, quat, sc
                for p in ("location", "rotation_quaternion", "scale"):
                    o.keyframe_insert(p, frame=k + 1)

SPACING = 3.4
horses = []
for i, (label, params, bare) in enumerate(VARIANTS):
    h = Horse(label, absolute_for(params), (i - (len(VARIANTS) - 1) / 2) * SPACING, bare)
    horses.append(h)
idle = {n: k for n, k in clips["idle01Source"][1].items()}
walk = clips["walkLeftSource"][1]
for h in horses:
    h.pose(idle, 0); h.drop = h.lowest()
scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"; scene.display.shading.color_type = "SINGLE"; scene.display.shading.single_color = (0.8, 0.78, 0.74)
cd = bpy.data.cameras.new("cam"); cd.type = "ORTHO"; cd.ortho_scale = 20.5
cam = bpy.data.objects.new("cam", cd); scene.collection.objects.link(cam); scene.camera = cam
cam.location = (20, 0, 1.15); cam.rotation_euler = (1.5708, 0, 1.5708)
os.makedirs(outdir, exist_ok=True)
# the walk, baked on every horse
n = len(next(iter(walk.values())))
for h in horses:
    low = None
    for k in range(0, n, 4):
        h.pose(walk, k); z = h.lowest(); low = z if low is None else min(low, z)
    h.drop = low
scene.frame_start, scene.frame_end = 1, n
for h in horses:
    h.bake(walk, n)
scene.frame_set(1)
scene.render.resolution_x, scene.render.resolution_y = 2400, 560
import mathutils
scene.render.resolution_x, scene.render.resolution_y = 700, 700
cd.type = "PERSP"; cd.lens = 85
for h in horses:
    h.pose(idle, 0)
for i, h in enumerate(horses):
    bpy.context.view_layer.update()
    head = next(o for nid, o in h.empties.items() if nodes[nid][1] == "Head_M")
    c = head.matrix_world.translation
    for tag, off in (("three", (2.4, -4.2, 0.35)), ("front", (0.0, -5.2, 0.35))):
        cam.location = c + mathutils.Vector(off)
        cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(outdir, "view_%s_%d.png" % (tag, i))
        bpy.ops.render.render(write_still=True)
scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(outdir, "head_views.blend"))
print("DONE", [(h.label, round(h.drop, 3)) for h in horses])
