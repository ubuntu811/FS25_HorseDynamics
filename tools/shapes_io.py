"""Read and write FS25 .i3d.shapes: entities in, entities out (same cipher call structure as the game's reader, so an untouched file round-trips byte for byte).
Uses the Blender i3d importer add-on's reader for the cipher (path below)."""
import sys, struct
ADDON = "/mnt/c/Users/Startklar/AppData/Roaming/Blender Foundation/Blender/5.1/extensions/user_default/blender_i3d_importer"
sys.path.insert(0, ADDON)
import i3d_shapes_reader as R
import i3d_shapes_models as M

def read(path):
    raw = open(path, "rb").read()
    sf = R.parse_shapes_bytes(raw)
    return raw, sf

def write(path, sf, trailer=b""):
    """sf: ShapesFile (header + entities with .type, .data); the cipher stream is one call per int / entity blob."""
    cipher = R.I3DCipher(sf.header.seed)
    out = bytearray(raw_header(sf.header))
    off = 0
    def put(b):
        nonlocal off
        buf = bytearray(b); off = cipher.process(buf, off); out.extend(buf)
    put(struct.pack("<i", len(sf.entities)))
    for e in sf.entities:
        put(struct.pack("<i", e.type)); put(struct.pack("<i", len(e.data))); put(bytes(e.data))
    out.extend(trailer)
    open(path, "wb").write(bytes(out))
    return bytes(out)

def raw_header(h):
    return bytes([h.version, 0, h.seed, 0]) if h.version >= 4 else bytes([0, h.seed, 0, h.version])
