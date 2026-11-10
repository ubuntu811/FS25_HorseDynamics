#!/usr/bin/env python3
"""Builds the single-file foal-scale app: app/index.template.html + app/style.css + app/app.js + three.js + the exported horse JSON -> out/foal-scale.html
Usage: build_app.py [horse_app.json]   (default app/horse_app.json, made by tools/export_for_app.py)"""
import sys, os, json
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.dirname(here)
app = os.path.join(root, "app")
data = open(sys.argv[1] if len(sys.argv) > 1 else os.path.join(app, "horse_app.json")).read()
html = open(os.path.join(app, "index.template.html")).read()
for key, path in (("/*STYLE*/", "style.css"), ("/*THREE*/", "vendor/three.min.js"), ("/*APP*/", "app.js")):
    html = html.replace(key, open(os.path.join(app, path)).read())
html = html.replace("/*DATA*/", data)
out = os.path.join(root, "out", "foal-scale.html")
os.makedirs(os.path.dirname(out), exist_ok=True)
open(out, "w").write(html)
print("wrote %s (%.1f MB)" % (out, len(html) / 1e6))
