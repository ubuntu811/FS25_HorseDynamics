# Headless Blender: import an i3d with the user's installed FS25 i3d importer and write a plain-text description of what came in (objects, parents, modifiers, vertex groups, armatures).
# Run: blender.exe --background --python blender_dump.py -- <model.i3d> <game folder> <out.txt>   (Windows paths)
import sys, bpy
args = sys.argv[sys.argv.index("--") + 1:]
model, game, out = args[0], args[1], args[2]
MOD = "bl_ext.user_default.blender_i3d_importer"
print("addons enabled:", [a for a in bpy.context.preferences.addons.keys() if "i3d" in a])
bpy.context.preferences.addons[MOD].preferences.fs25_data_base = game
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
result = bpy.ops.import_scene.fs25_i3d(filepath=model)
lines = ["import result: %s" % (result,)]
kinds = {}
for o in bpy.data.objects:
    kinds[o.type] = kinds.get(o.type, 0) + 1
lines.append("objects by type: %s" % kinds)
for o in bpy.data.objects:
    if o.type in ("MESH", "ARMATURE") or o.parent is None:
        parent = o.parent.name if o.parent else "-"
        mods = ["%s(%s)" % (m.type, getattr(getattr(m, "object", None), "name", "")) for m in o.modifiers]
        cons = ["%s>%s" % (c.type, getattr(getattr(c, "target", None), "name", "")) for c in o.constraints]
        vg = [g.name for g in o.vertex_groups]
        extra = ""
        if o.type == "MESH":
            extra = " verts %d" % len(o.data.vertices)
        if o.type == "ARMATURE":
            extra = " bones %d: %s" % (len(o.data.bones), ", ".join(b.name for b in list(o.data.bones)[:12]))
        lines.append("%-9s %-34s parent %-30s mods %s cons %s vgroups %d %s%s" % (o.type, o.name[:34], parent[:30], mods, cons, len(vg), (vg[:6] if vg else ""), extra))
sample = [o for o in bpy.data.objects if o.type == "EMPTY"][:6]
for o in sample:
    lines.append("empty %s parent %s display %s size %.3f loc %s rot %s scale %s" % (o.name, o.parent.name if o.parent else "-", o.empty_display_type, o.empty_display_size, tuple(round(x, 3) for x in o.location), tuple(round(x, 3) for x in o.rotation_euler), tuple(round(x, 3) for x in o.scale)))
open(out, "w").write("\n".join(lines) + "\n")
