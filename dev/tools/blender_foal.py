# Headless Blender: import horse.i3d with the FS25 i3d importer, give the joint empties the foal's proportions (the same per-joint scale table as make_foal.py) and measure what the skinned mesh does.
# Run: blender.exe --background --python blender_foal.py -- <horse.i3d> <game folder> <out dir> [age 0..1]   (Windows paths)
import sys, re, os, bpy, importlib.util
args = sys.argv[sys.argv.index("--") + 1:]
model, game, outdir = args[0], args[1], args[2]
age = float(args[3]) if len(args) > 3 else 0.0
here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("make_foal", os.path.join(here, "make_foal.py"))
mf = importlib.util.module_from_spec(spec); spec.loader.exec_module(mf)
MOD = "bl_ext.user_default.blender_i3d_importer"
bpy.context.preferences.addons[MOD].preferences.fs25_data_base = game
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.fs25_i3d(filepath=model)
log = []
def clean(n): return re.sub(r"^\d+\.\d+:", "", n)
empties = {o.name: o for o in bpy.data.objects if o.type == "EMPTY"}
for e in empties.values():
    e.empty_display_size = 0.03
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
pb = arm.pose.bones
log.append("armature %s: %d pose bones" % (arm.name, len(pb)))
for b in list(pb)[:4]:
    log.append("  bone %s constraints: %s" % (b.name, [(c.type, getattr(c.target, "name", None), getattr(c, "subtarget", "")) for c in b.constraints]))
body = bpy.data.objects["body"]
def measure(label):
    dg = bpy.context.evaluated_depsgraph_get(); dg.update()
    ev = body.evaluated_get(dg)
    me = ev.to_mesh()
    mw = ev.matrix_world
    pts = [mw @ v.co for v in me.vertices]
    mn = [min(p[i] for p in pts) for i in range(3)]; mx = [max(p[i] for p in pts) for i in range(3)]
    ev.to_mesh_clear()
    log.append("%s: body bbox size x %.3f y %.3f z %.3f  min %s max %s" % (label, mx[0]-mn[0], mx[1]-mn[1], mx[2]-mn[2], tuple(round(v, 3) for v in mn), tuple(round(v, 3) for v in mx)))
SHOW = ("body", "maneTail", "saddle", "reins")
for o in bpy.data.objects:
    o.hide_render = o.name not in SHOW
scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.render.resolution_x, scene.render.resolution_y = 900, 600
scene.display.shading.light = "STUDIO"; scene.display.shading.color_type = "SINGLE"; scene.display.shading.single_color = (0.8, 0.78, 0.74)
cam_data = bpy.data.cameras.new("cam"); cam_data.type = "ORTHO"; cam_data.ortho_scale = 3.4
cam = bpy.data.objects.new("cam", cam_data); scene.collection.objects.link(cam); scene.camera = cam
cam.location = (10, -0.4, 1.1); cam.rotation_euler = (1.5708, 0, 1.5708)
def shot(name):
    scene.render.filepath = os.path.join(outdir, name)
    bpy.ops.render.render(write_still=True)
os.makedirs(outdir, exist_ok=True)
measure("adult")
shot("adult.png")
# per-joint local scale (the same walk as make_foal.apply)
def walk(o, parentS):
    for c in o.children:
        if c.type != "EMPTY": continue
        tv = mf.target(clean(c.name)); S = parentS
        if tv is not None:
            S = 1.0 + (tv - 1.0) * (1.0 - age)
            local = S / parentS
            c.scale = (local, local, local)
        walk(c, S)
roots = [o for o in empties.values() if o.parent is None or o.parent.type != "EMPTY"]
skeleton = [o for o in empties.values() if clean(o.name) == "skeleton"]
log.append("skeleton nodes: %s" % [o.name for o in skeleton])
for s in skeleton:
    walk(s, 1.0)
measure("foal (empties scaled)")
# hooves back on the ground: lower the skeleton by the foal's lowest point
dg = bpy.context.evaluated_depsgraph_get(); dg.update()
ev = body.evaluated_get(dg); me = ev.to_mesh()
lowest = min((ev.matrix_world @ v.co).z for v in me.vertices); ev.to_mesh_clear()
for sk in skeleton:
    sk.location.z -= lowest
measure("foal (lowered by %.3f)" % lowest)
shot("foal.png")
os.makedirs(outdir, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(outdir, "horse_foal_test.blend"))
open(os.path.join(outdir, "foal_log.txt"), "w").write("\n".join(log) + "\n")
