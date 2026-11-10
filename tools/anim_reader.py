"""Reads an FS25 .i3d.anim (plain binary, no cipher): [u32 version=10][u32 sets] per set: [string name] [u32 clips] per clip: [string name][f32 duration ms][u32 tracks] per track: [u32 nodeId][u32 keys] per key: [f32 time ms][u32 flag=3][3 x f32 translation][3 x f32 rotation, radians].
Strings are u32 length + bytes, padded to 4. Returns { clip name: (duration ms, { nodeId: [(ms, (tx, ty, tz), (rx, ry, rz))] }) } (verified: the horse's 3143180 bytes are read to the last one)."""
import struct

def read_anim(path):
    d = open(path, "rb").read()
    u = lambda o: struct.unpack_from("<I", d, o)[0]
    f = lambda o: struct.unpack_from("<f", d, o)[0]
    def string(o):
        n = u(o)
        return d[o + 4:o + 4 + n].decode(), o + 4 + ((n + 3) // 4) * 4
    if u(0) != 10:
        raise ValueError("unknown .anim version %d" % u(0))
    _, o = string(8)
    clips = {}
    n = u(o); o += 4
    for _ in range(n):
        name, o = string(o)
        duration, tracks = f(o), u(o + 4); o += 8
        data = {}
        for _ in range(tracks):
            node, count = u(o), u(o + 4); o += 8
            keys = []
            for _ in range(count):
                v = struct.unpack_from("<6f", d, o + 8)
                keys.append((f(o), v[0:3], v[3:6])); o += 32
            data[node] = keys
        clips[name] = (duration, data)
    if o != len(d):
        raise ValueError("anim file not read to the end (%d of %d)" % (o, len(d)))
    return clips
