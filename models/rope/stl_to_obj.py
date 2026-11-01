"""stl_to_obj.py -- OpenSCAD 2021 writes STL (and OFF, AMF, 3MF) but no OBJ, and an STL has no UVs or smooth normals. This writes an OBJ for Blockbench / GIANTS Editor:
vertices welded, smooth vertex normals, and UVs for the rope shader: u = the angle round the z axis (0..1), v = z (0..1; the shader multiplies v by the length and the uv scale, so a texture tiles along the rope).

    python3 stl_to_obj.py rope_3strand.stl rope_3strand.obj
"""
import math, re, sys

src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
raw = [tuple(float(v) for v in m) for m in re.findall(r'vertex\s+(\S+)\s+(\S+)\s+(\S+)', text)]
if len(raw) % 3:
    sys.exit('not an ASCII STL of triangles')

index, verts = {}, []
def weld(p):
    key = (round(p[0], 6), round(p[1], 6), round(p[2], 6))
    if key not in index:
        index[key] = len(verts)
        verts.append(p)
    return index[key]

tris = []
for i in range(0, len(raw), 3):
    tri = [weld(raw[i]), weld(raw[i + 1]), weld(raw[i + 2])]
    if len(set(tri)) == 3:
        tris.append(tri)

# smooth normals: the area weighted average of the faces at a vertex
normals = [[0.0, 0.0, 0.0] for _ in verts]
for a, b, c in tris:
    pa, pb, pc = verts[a], verts[b], verts[c]
    u = [pb[k] - pa[k] for k in range(3)]; w = [pc[k] - pa[k] for k in range(3)]
    n = [u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0]]
    for v in (a, b, c):
        for k in range(3):
            normals[v][k] += n[k]
for n in normals:
    length = math.sqrt(sum(x * x for x in n)) or 1.0
    for k in range(3):
        n[k] /= length

def uv(v):
    x, y, z = verts[v]
    return (math.atan2(y, x) / (2 * math.pi) + 0.5, z)

out = ['# rope for the game rope shader: one unit long along +z, diameter 1', 'o rope']
out += ['v %.6f %.6f %.6f' % v for v in verts]
out += ['vn %.5f %.5f %.5f' % tuple(n) for n in normals]
vts, faces = [], []
for tri in tris:
    coords = [uv(v) for v in tri]
    us = [c[0] for c in coords]
    if max(us) - min(us) > 0.5:                      # a triangle across the seam: the small u values go to the other side
        coords = [(c[0] + 1.0 if c[0] < 0.5 else c[0], c[1]) for c in coords]
    corner = []
    for v, c in zip(tri, coords):
        vts.append(c)
        corner.append('%d/%d/%d' % (v + 1, len(vts), v + 1))
    faces.append('f ' + ' '.join(corner))
out += ['vt %.5f %.5f' % c for c in vts]
out += faces
open(dst, 'w').write('\n'.join(out) + '\n')
xs, ys, zs = [v[0] for v in verts], [v[1] for v in verts], [v[2] for v in verts]
print('%d vertices, %d triangles; x %.3f..%.3f  y %.3f..%.3f  z %.3f..%.3f' % (len(verts), len(tris), min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))
