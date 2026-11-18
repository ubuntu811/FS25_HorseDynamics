# Shop icons for the baked foal: the foal model textured with each coat's atlas tile, a transparent 512x512 PNG with a ground shadow, like the game's own store_horse*.dds.
# Run: blender.exe --background --python blender_icon.py -- <horseFoal.i3d> <dataS dir (the folder that holds character/)> <out dir> [azimuth_deg] [tiles e.g. 0:0,1:0 ...]   (Windows paths)
# Coat order (animals.xml entry -> atlas tile u:v): Gray 0:0, Pinto 1:0, Palomino 2:0, Chestnut 3:0, Bay 0:1, Black 1:1, SealBrown 2:1, Dun 3:1.
import sys, os, re, math, bpy
from mathutils import Vector, Matrix
from bpy_extras.object_utils import world_to_camera_view

args = sys.argv[sys.argv.index("--") + 1:]
model, datas, outdir = args[0], args[1], args[2]
azimuth = float(args[3]) if len(args) > 3 else 50.0
COATS = [("Gray", 0, 0), ("Pinto", 1, 0), ("Palomino", 2, 0), ("Chestnut", 3, 0), ("Bay", 0, 1), ("Black", 1, 1), ("SealBrown", 2, 1), ("Dun", 3, 1)]
if len(args) > 4:
    want = [tuple(int(x) for x in t.split(":")) for t in args[4].split(",")]
    COATS = [c for c in COATS if (c[1], c[2]) in want]
os.makedirs(outdir, exist_ok=True)

MOD = "bl_ext.user_default.blender_i3d_importer"
bpy.context.preferences.addons[MOD].preferences.fs25_data_base = os.path.dirname(datas.rstrip("\\/"))
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
before = set(bpy.data.objects)
bpy.ops.import_scene.fs25_i3d(filepath=model)
objs = [o for o in bpy.data.objects if o not in before]
meshes = {}
for o in objs:
    base = re.sub(r"\.\d+$", "", o.name)
    if o.type == "MESH" and base in ("body", "maneTail"):
        meshes[base] = o
    elif o.type == "MESH":
        o.hide_render = True; o.hide_set(True)
    elif o.type in ("CAMERA", "LIGHT"):
        o.hide_render = True; o.hide_set(True)
print("meshes", list(meshes))
# the rest pose has the mouth open: turn the jaw bone's empty (JAW_DEG degrees about its local JAW_AXIS) to close it
JAW_DEG = float(os.environ.get("JAW_DEG", "0")); JAW_AXIS = os.environ.get("JAW_AXIS", "Z")
for o in objs:
    if o.type == "EMPTY" and re.search(r":Jaw_M$", o.name):
        print("jaw empty", o.name, o.rotation_mode)
        if JAW_DEG:
            o.matrix_basis = o.matrix_basis @ Matrix.Rotation(math.radians(JAW_DEG), 4, JAW_AXIS)

horse_dir = os.path.join(datas, "character", "animals", "domesticated", "horse")
def image(name):
    return bpy.data.images.load(os.path.join(horse_dir, name), check_existing=True)

def make_mat(name, tex, tu, tv, alpha=False):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    uv = nt.nodes.new("ShaderNodeTexCoord"); mp = nt.nodes.new("ShaderNodeMapping"); im = nt.nodes.new("ShaderNodeTexImage")
    im.image = image(tex); im.interpolation = "Linear"
    mp.inputs["Scale"].default_value = (0.25, 0.5, 1)
    mp.inputs["Location"].default_value = (0.25 * tu, 0.5 * tv, 0)
    nt.links.new(uv.outputs["UV"], mp.inputs["Vector"]); nt.links.new(mp.outputs["Vector"], im.inputs["Vector"])
    nt.links.new(im.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.55
    if alpha:
        nt.links.new(im.outputs["Alpha"], bsdf.inputs["Alpha"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return m, mp

mats = {}
for key, tex in (("body", "horse_diffuse.dds"), ("maneTail", "maneTailBraide_diffuse.dds")):
    m, mp = make_mat("icon_" + key, tex, 0, 0, alpha=(key == "maneTail"))
    mats[key] = (m, mp)
    me = meshes[key]
    me.data.materials.clear(); me.data.materials.append(m)

bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get(); dg.update()
# bounding box of the visible shapes in world space (skinned mesh evaluated)
pts = []
for o in meshes.values():
    ev = o.evaluated_get(dg); me = ev.to_mesh()
    pts += [ev.matrix_world @ v.co for v in me.vertices]
    ev.to_mesh_clear()
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
centre = (lo + hi) / 2
size = hi - lo
print("bbox", tuple(lo), tuple(hi))

scene = bpy.context.scene
scene.render.engine = "CYCLES"; scene.cycles.device = "CPU"; scene.cycles.samples = 48; scene.cycles.use_denoising = False
scene.render.film_transparent = True
scene.render.resolution_x = scene.render.resolution_y = 512
scene.render.image_settings.file_format = "PNG"; scene.render.image_settings.color_mode = "RGBA"
scene.view_settings.view_transform = "Standard"

# ground (shadow catcher) at the lowest point
bpy.ops.mesh.primitive_plane_add(size=40, location=(centre.x, centre.y, lo.z))
ground = bpy.context.object; ground.is_shadow_catcher = True

# light: a sun from the upper left front, plus a soft sky
sun = bpy.data.lights.new("sun", "SUN"); sun.energy = 3.2; sun.angle = math.radians(12)
so = bpy.data.objects.new("sun", sun); scene.collection.objects.link(so)
so.rotation_euler = (math.radians(50), 0, math.radians(azimuth + 40))
world = bpy.data.worlds.new("w"); world.use_nodes = True; scene.world = world
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.75, 0.78, 0.85, 1); world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9

cd = bpy.data.cameras.new("cam"); cd.lens = 50
cam = bpy.data.objects.new("cam", cd); scene.collection.objects.link(cam); scene.camera = cam

# which way is the nose? the longer horizontal axis of the box; the head end is the higher end (the neck rises)
long_axis = 0 if size.x > size.y else 1
def height_at(side):
    sel = [p for p in pts if (p[long_axis] - centre[long_axis]) * side > size[long_axis] * 0.3]
    return sum(p.z for p in sel) / max(len(sel), 1)
nose_dir = Vector((0, 0, 0)); nose_dir[long_axis] = 1 if height_at(1) > height_at(-1) else -1
nose_az = math.atan2(nose_dir.y, nose_dir.x)

def place(az_deg, dist, elev_deg=15):
    # the camera is `az_deg` round from the nose direction (seen from above), looking at the box centre, `elev_deg` above the horizon
    a = nose_az + math.radians(az_deg); e = math.radians(elev_deg)
    d = Vector((math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e)))
    cam.location = centre + d * dist
    cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.view_layer.update()

def fit(az_deg):
    dist = max(size) * 2.5
    for _ in range(14):
        place(az_deg, dist)
        xs, ys = [], []
        for x in (lo.x, hi.x):
            for y in (lo.y, hi.y):
                for z in (lo.z, hi.z):
                    c = world_to_camera_view(scene, cam, Vector((x, y, z))); xs.append(c.x); ys.append(c.y)
        span = max(max(xs) - min(xs), max(ys) - min(ys))
        dist *= span / 0.80
    place(az_deg, dist)
    # centre the box's projection in the frame by shifting the camera shift
    xs, ys = [], []
    for x in (lo.x, hi.x):
        for y in (lo.y, hi.y):
            for z in (lo.z, hi.z):
                c = world_to_camera_view(scene, cam, Vector((x, y, z))); xs.append(c.x); ys.append(c.y)
    cd.shift_x = ((max(xs) + min(xs)) / 2 - 0.5) * 1.0; cd.shift_y = ((max(ys) + min(ys)) / 2 - 0.5) * 1.0

# the camera sits in front of the nose, turned `azimuth` degrees to one side: the game's icons show the horse facing left of the picture
fit(azimuth)
for name, tu, tv in COATS:
    for key in mats:
        m, mp = mats[key]
        mp.inputs["Location"].default_value = (0.25 * tu, 0.5 * tv, 0)
    scene.render.filepath = os.path.join(outdir, "store_foal%s.png" % name)
    bpy.ops.render.render(write_still=True)
print("done")
