#!/usr/bin/env python3
"""Checks shaders/foalCoatShader.xml for the mistake that made the manes and tails disappear (2026-11-12): the mane (variation dirtEnabled) runs the same code injections as the body but has no coat textures, so a use
of coatMask / coatMask2 outside #if defined( COAT_MASK ) fails to compile there ("undeclared identifier") and the mane is not drawn. Exit 1 on a finding.   check_shader.py [shader file]"""
import sys, re, os
path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "shaders", "foalCoatShader.xml")
stack, bad = [], 0
for no, line in enumerate(open(path, encoding="utf-8").read().splitlines(), 1):
    st = line.strip()
    if st.startswith("#if"):
        stack.append("COAT_MASK" in st and "#ifndef" not in st and "!" not in st)
    elif st.startswith("#endif") and stack:
        stack.pop()
    elif re.search(r"\bcoatMask2?\b", line.split("//")[0]) and "<Texture" not in line and "Custommap" not in line and "group=" not in line and not any(stack):
        print("line %d uses a coat texture outside #if defined( COAT_MASK ): %s" % (no, st[:100])); bad = 1
sys.exit(bad)
