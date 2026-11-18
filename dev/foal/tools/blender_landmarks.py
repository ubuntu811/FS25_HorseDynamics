# LANDMARK round: ear base / eye / nose tip and the two profile points (forehead stop, cheek-jaw angle) measured on the mesh in the rest pose, drawn as dots.
# (derived from blender_eyes.py / blender_cheeks.py: CHEEK round: smaller cheek/jaw, shorter muzzle, wider nose, eyes forward and out, ears smaller and closer.
# (derived from blender_ears.py: EAR-TILT round: both ear bones rotated forward (up) about the head's sideways axis, on top of the clip.
# (derived from blender_shorthead.py: SHORT-HEAD round: three-quarter / side / front head views, one horse at a time.
# (derived from blender_headviews.py: THREE-QUARTER HEAD VIEWS of the candidates (to judge a head from the front, not only the side).
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
BASE = dict(B=1.0, torso=1.0, neck_len=1.0, neck_th=1.0, head=(1.0, 1.0, 1.0), jaw=(1.0, 1.0, 1.0), ear=1.0, eyes=1.0, leg_len=1.0, leg_th=1.0, hoof=1.0, tail=1.0, lipw=1.0)
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
def adult_head(k):
    return dict(BASE, head=(k, k, k), eyes=1.0 + (k - 1) * 0.5, ear=1.0 + (k - 1) * 0.5)
NOW = q(ear=1.8, jaw=(1.0, 1.0, 1.0), neck_len=1.2, neck_th=0.95, leg_th=1.25, hoof=1.2, head=(1.25, 0.90, 1.15))
NOW["ear_tilt"] = -30
def ck(head, jaw, ear, ear_in, eye_off, eyes, lipw):
    d = dict(NOW); d.update(head=head, jaw=jaw, ear=ear, ear_in=ear_in, eye_off=eye_off, eyes=eyes, lipw=lipw); return d
def uni(k, eyes, pitch=0, ear=1.12, jaw=1.0):      # the adult's head scaled uniformly, eyeballs a bit bigger, ears 3/4 of the C2 size and a little forward, optional nose-forward pitch
    d = dict(NOW); d.update(head=(k, k, k), jaw=(jaw, jaw, jaw), eyes=eyes, ear=ear, ear_fwd=0.02, ear_in=0.0, lipw=1.0, head_pitch=pitch); return d
VARIANTS = [
    ("adult (game)", dict(), False),
    ("adult head +15%", adult_head(1.15), False),
    ("U1 pitch 0", uni(1.2, 1.3, 0), True),
    ("U1 pitch 10", uni(1.2, 1.3, 10), True),
    ("U1 pitch 20", uni(1.2, 1.3, 20), True),
    ("U1 pitch 30", uni(1.2, 1.3, 30), True),
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
        if name.startswith("lipMid") or name.startswith("lipCorner"): return (B * hd, B * hl, B * hw * P.get("lipw", 1.0))
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
            if getattr(self, 'pitch', 0) and nodes[nid][1] == 'Head_M':             # nose forward / up: a rotation about the head's z (sideways) axis at the poll
                Tm = Matrix.Translation(L.to_translation())
                L = Tm @ Matrix.Rotation(-math.radians(self.pitch), 4, 'Z') @ (Tm.inverted() @ L)
            if (getattr(self, 'tilt', 0) or getattr(self, 'pitch', 0)) and nodes[nid][1].startswith('ear'):       # ears forward / up: a rotation about the head's z (sideways) axis, before the ear's own rotation
                Tm = Matrix.Translation(L.to_translation())
                L = Tm @ Matrix.Rotation(math.radians(self.tilt + getattr(self, 'pitch', 0)), 4, 'Z') @ (Tm.inverted() @ L)
            nm = nodes[nid][1]
            if getattr(self, 'ear_fwd', 0) and nm.startswith('ear'):
                L = Matrix.Translation((0, self.ear_fwd, 0)) @ L
            if getattr(self, 'ear_in', 0) and nm.startswith('ear'):                  # ears closer together: toward the head's middle plane (z)
                L = Matrix.Translation((0, 0, self.ear_in if nm.endswith('_R') else -self.ear_in)) @ L
            if getattr(self, 'eye_off', None) and (nm.startswith('Eye_') or nm.startswith('lid')):   # eyes forward (y) and outward (z)
                fy, oz = self.eye_off
                L = Matrix.Translation((0, fy, -oz if nm.endswith('_R') else oz)) @ L
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
    h.tilt = params.get('ear_tilt', 0)
    h.ear_in = params.get('ear_in', 0)
    h.ear_fwd = params.get('ear_fwd', 0)
    h.pitch = params.get('head_pitch', 0)
    h.eye_off = params.get('eye_off', None)
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
# (no walk baking here: keyframes would override the rest pose at render time)
scene.render.resolution_x, scene.render.resolution_y = 2400, 560
import mathutils
from mathutils import Vector
def wp(h, name):
    return next(o for nid, o in h.empties.items() if nodes[nid][1] == name).matrix_world.translation.copy()
def smooth(vals, w):
    out = []
    for i in range(len(vals)):
        lo, hi = max(0, i - w), min(len(vals), i + w + 1)
        seg = [v for v in vals[lo:hi] if v is not None]
        out.append(sum(seg) / len(seg) if seg else None)
    return out
scene.render.resolution_x, scene.render.resolution_y = 600, 600
scene.display.shading.color_type = "OBJECT"
for o in bpy.data.objects:
    if o.type == "MESH": o.color = (0.8, 0.78, 0.74, 1)
def dot(p, color, r):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=p + Vector((0.14, 0, 0)))
    o = bpy.context.active_object; o.color = color; return o
cd.type = "ORTHO"; cd.ortho_scale = 1.3
report = []
dots = {}
for h in horses:
    h.pose({}, 0); h.drop = 0.0; h.pose({}, 0)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get(); dg.update()
    ev = h.body.evaluated_get(dg); me = ev.to_mesh(); mw = ev.matrix_world
    names = {g.index: g.name for g in h.body.vertex_groups}
    pts = []
    orig = h.body.data.vertices                            # (the weights live on the original mesh; the evaluated one has the same vertex order)
    for i, v in enumerate(me.vertices):
        w = sum(g.weight for g in orig[i].groups if re.match(r"^(Head_M|Jaw_M)(\.\d+)?_skin$", names.get(g.group, "")))
        if w > 0.2: pts.append(mw @ v.co)
    ev.to_mesh_clear()
    print("HEADPTS", h.label, len(pts), "groups:", [n for n in names.values() if n.startswith(("Head", "Jaw"))])
    E = (wp(h, "ear1_R") + wp(h, "ear1_L")) / 2
    Y = (wp(h, "Eye_R") + wp(h, "Eye_L")) / 2
    N = min(pts, key=lambda p: p.y)                       # the horse faces -y: the nose tip is the most forward vertex of the head
    x0 = E.x
    en = Vector((0, N.y - E.y, N.z - E.z)); L = en.length; u = en.normalized()
    v = Vector((0, -u.z, u.y))
    if v.z < 0: v = -v
    side = [p for p in pts if abs(p.x - x0) < 0.035 * (L / 0.6)]
    def st(p):
        d = p - E
        return d.dot(u), d.dot(v)
    sp = [st(p) for p in side]
    nb = 40
    top = [None] * nb; bot = [None] * nb
    for s_, t_ in sp:
        i = int(max(0, min(nb - 1, s_ / L * nb)))
        top[i] = t_ if top[i] is None else max(top[i], t_)
        bot[i] = t_ if bot[i] is None else min(bot[i], t_)
    def ang_change(prof, lo, hi):                         # the bin with the biggest change of slope between the stretch before and after it
        best, bi = 0, None
        ps = smooth(prof, 1)
        for i in range(max(lo, 3), min(hi, nb - 3)):
            a = [ps[j] for j in range(i - 3, i + 1)]; b = [ps[j] for j in range(i, i + 4)]
            if None in a or None in b: continue
            sa = (a[-1] - a[0]) / 3; sb = (b[-1] - b[0]) / 3
            ch = abs(math.atan(sb * nb / L) - math.atan(sa * nb / L))
            if ch > best: best, bi = ch, i
        return bi
    fi = ang_change(top, int(0.35 * nb), int(0.85 * nb))   # forehead / nose-bridge angle
    ji = ang_change(bot, int(0.15 * nb), int(0.65 * nb))   # cheek / jaw angle
    topS, botS = smooth(top, 1), smooth(bot, 1)
    def pt(i, prof): return E + u * ((i + 0.5) / nb * L) + v * prof[i]
    F = pt(fi, topS) if fi is not None and topS[fi] is not None else None
    J = pt(ji, botS) if ji is not None and botS[ji] is not None else None
    def ang(a, b, c):                                      # angle at b in degrees
        x, y = (a - b).normalized(), (c - b).normalized()
        return math.degrees(math.acos(max(-1, min(1, x.dot(y)))))
    line = "-"
    if F is not None and J is not None:
        d1 = (F - N).normalized(); d2 = (J - N).normalized()
        line = "%.1f deg" % math.degrees(math.acos(max(-1, min(1, d1.dot(d2)))))
    report.append("%-24s ear-nose %.3f m | eye-nose/ear-nose %.2f | ear-eye/ear-nose %.2f | angle at eye (ear-eye-nose) %.0f deg | nose->forehead vs nose->jaw %s" % (h.label, L, (Y - N).length / L, (Y - E).length / L, ang(E, Y, N), line))
    dots[h.label] = (N, E, Y, F, J)
    made = []
    if F is not None: made.append(dot(F, (0.1, 0.8, 0.2, 1), 0.012))
    if J is not None: made.append(dot(J, (0.1, 0.8, 0.2, 1), 0.012))
    made.append(dot(N, (0.9, 0.2, 0.2, 1), 0.01))
    made.append(dot(E, (0.2, 0.3, 0.9, 1), 0.01))
    made.append(dot(Y, (0.9, 0.9, 0.2, 1), 0.01))
    for o2 in bpy.data.objects:
        if o2.type == "MESH" and o2 not in made: o2.hide_render = True
    for o2 in h.objs:
        if o2.type == "MESH" and re.sub(r"\.\d+$", "", o2.name) in ("body", "maneTail"): o2.hide_render = False
    c = (N + E) / 2
    cam.location = (20, c.y, c.z); cam.rotation_euler = (1.5708, 0, 1.5708)
    scene.render.filepath = os.path.join(outdir, "lm_%d.png" % horses.index(h))
    bpy.ops.render.render(write_still=True)
    for o in made: bpy.data.objects.remove(o, do_unlink=True)
    for o2 in bpy.data.objects:
        if o2.type == "MESH": o2.hide_render = False
open(os.path.join(outdir, "landmarks.txt"), "w").write("\n".join(report) + "\n")
print("\n".join(report))
scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(outdir, "landmarks.blend"))
print("DONE", [(h.label, round(h.drop, 3)) for h in horses])
