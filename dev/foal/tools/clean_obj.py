#!/usr/bin/env python3
"""Strips the Editor's helper shapes (the shadow box, the collision proxy, the dust emitters, the physics root) and the lower LODs from an OBJ exported from a horse scene, and numbers the models in it.
Keeps body, maneTail, saddle and reins of each model (a model = every occurrence of the name, in file order).
Usage: clean_obj.py <in.obj> <out.obj>"""
import sys
KEEP = ("body", "maneTail", "saddle", "reins")

def main(src, dst):
    v, vt, vn = [], [], []
    blocks = []                                   # [name, [face lines]]
    for line in open(src, errors="ignore"):
        if line.startswith("v "): v.append(line)
        elif line.startswith("vt "): vt.append(line)
        elif line.startswith("vn "): vn.append(line)
        elif line.startswith(("o ", "g ")): blocks.append([line.split(None, 1)[1].strip(), []])
        elif line.startswith("f ") and blocks: blocks[-1][1].append(line)
    seen = {}
    kept = []
    for name, faces in blocks:
        if name in KEEP and faces:
            n = seen.get(name, 0); seen[name] = n + 1
            kept.append(("model%d_%s" % (n + 1, name), faces))
    out = {"v": {}, "vt": {}, "vn": {}}
    lists = {"v": v, "vt": vt, "vn": vn}
    def remap(kind, i):
        i = int(i)
        i = i - 1 if i > 0 else len(lists[kind]) + i
        if i not in out[kind]: out[kind][i] = len(out[kind]) + 1
        return out[kind][i]
    body = []
    for name, faces in kept:
        body.append("o %s\n" % name)
        for f in faces:
            toks = []
            for t in f.split()[1:]:
                p = t.split("/")
                a = [str(remap("v", p[0]))]
                if len(p) > 1 and p[1]: a.append(str(remap("vt", p[1])))
                elif len(p) > 2: a.append("")
                if len(p) > 2 and p[2]: a.append(str(remap("vn", p[2])))
                toks.append("/".join(a))
            body.append("f " + " ".join(toks) + "\n")
    with open(dst, "w") as f:
        for kind in ("v", "vt", "vn"):
            for i in sorted(out[kind], key=out[kind].get): f.write(lists[kind][i])
        f.writelines(body)
    print("kept %d objects, %d vertices -> %s" % (len(kept), len(out["v"]), dst))
    for name, faces in kept: print("  %-18s %6d faces" % (name, len(faces)))

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
