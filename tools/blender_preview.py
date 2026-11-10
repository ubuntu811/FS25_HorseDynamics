# Renders the hitching post (import through the i3d add-on = a real parser reads the written .shapes) as a 512x512 transparent PNG: the store picture.
# Run: blender.exe --background --python blender_preview.py -- <hitchingPost.i3d> <out.png>   (Windows paths)
import sys, os, math, bpy
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view
model, out = sys.argv[sys.argv.index("--") + 1:][:2]
for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)
before = set(bpy.data.objects)
bpy.ops.import_scene.fs25_i3d(filepath=model)
objs = [o for o in bpy.data.objects if o not in before]
meshes = [o for o in objs if o.type == "MESH" and not (o.name.endswith(":col") or "main_component1" in o.name)]
for o in objs:
    if o.type == "MESH" and (o.name.endswith(":col") or "main_component1" in o.name): o.hide_render = True; o.hide_set(True)
    if o.type in ("CAMERA", "LIGHT"): o.hide_render = True
print("meshes", [(o.name, len(o.data.vertices), [m.name if m else None for m in o.data.materials]) for o in meshes])
import re as _re
xml_text = open(model, encoding="iso-8859-1").read()
cols = {m.group(1): tuple(float(x) for x in m.group(2).split()) for m in _re.finditer(r'<Material name="([^"]+)"[^>]*diffuseColor="([^"]+)"', xml_text)}
for o in meshes:
    for m in o.data.materials:
        if m is None: continue
        m.use_nodes = True
        bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        key = next((k for k in cols if k in m.name), None)
        if key is None: continue
        c = cols[key]
        bsdf.inputs["Base Color"].default_value = (c[0], c[1], c[2], 1)
        steel = "steel" in key
        bsdf.inputs["Roughness"].default_value = 0.3 if steel else 0.7
        bsdf.inputs["Metallic"].default_value = 0.9 if steel else 0.0
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
pts = []
for o in meshes:
    ev = o.evaluated_get(dg); me = ev.to_mesh(); pts += [ev.matrix_world @ v.co for v in me.vertices]; ev.to_mesh_clear()
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))); hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
centre = (lo + hi) / 2; print("bbox", tuple(lo), tuple(hi))
sc = bpy.context.scene
sc.render.engine = "CYCLES"; sc.cycles.device = "CPU"; sc.cycles.samples = 48; sc.cycles.use_denoising = False
sc.render.film_transparent = True; sc.render.resolution_x = sc.render.resolution_y = 512
sc.render.image_settings.file_format = "PNG"; sc.render.image_settings.color_mode = "RGBA"; sc.view_settings.view_transform = "Standard"
bpy.ops.mesh.primitive_plane_add(size=40, location=(centre.x, centre.y, lo.z)); bpy.context.object.is_shadow_catcher = True
sun = bpy.data.lights.new("sun", "SUN"); sun.energy = 3.2; sun.angle = math.radians(12)
so = bpy.data.objects.new("sun", sun); sc.collection.objects.link(so); so.rotation_euler = (math.radians(50), 0, math.radians(100))
w = bpy.data.worlds.new("w"); w.use_nodes = True; sc.world = w
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.75, 0.78, 0.85, 1); w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
cd = bpy.data.cameras.new("cam"); cd.lens = 50
cam = bpy.data.objects.new("cam", cd); sc.collection.objects.link(cam); sc.camera = cam
size = hi - lo
def place(dist):
    # the importer is z-up with the post's front along -y or +y: look from the front-left, 18 degrees up
    a = math.radians(-60); e = math.radians(18)
    d = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
    cam.location = centre + d * dist
    cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler(); bpy.context.view_layer.update()
dist = max(size) * 2.5
for _ in range(14):
    place(dist)
    cs = [world_to_camera_view(sc, cam, Vector((x, y, z))) for x in (lo.x, hi.x) for y in (lo.y, hi.y) for z in (lo.z, hi.z)]
    span = max(max(c.x for c in cs) - min(c.x for c in cs), max(c.y for c in cs) - min(c.y for c in cs)); dist *= span / 0.78
place(dist)
cs = [world_to_camera_view(sc, cam, Vector((x, y, z))) for x in (lo.x, hi.x) for y in (lo.y, hi.y) for z in (lo.z, hi.z)]
cd.shift_x = (max(c.x for c in cs) + min(c.x for c in cs)) / 2 - 0.5; cd.shift_y = (max(c.y for c in cs) + min(c.y for c in cs)) / 2 - 0.5
sc.render.filepath = out; bpy.ops.render.render(write_still=True); print("done")
