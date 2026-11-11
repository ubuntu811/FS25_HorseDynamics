#!/usr/bin/env python3
"""Makes shaders/foalCoatShader.xml: a copy of the game's horse skin shader (data/shaders/tileAndMirrorShader.xml, GIANTS Software) with our additions, and points the foal model at it (or back).
Experiment 1: one new setting, coatTint (a colour that multiplies the coat), settable per animal from Lua (I3DUtil.setShaderParameterRec(node, "coatTint", r, g, b, 1)).
Usage: make_coat_shader.py <game data dir (the folder with shaders/)> [--revert]      (writes ../../shaders/foalCoatShader.xml and patches ../../models/foal/horseFoal.i3d)
--revert: the foal model points at the game's own shader again (the shader file is kept)."""
import sys, os, re
here = os.path.dirname(os.path.abspath(__file__)); mod = os.path.normpath(os.path.join(here, "..", "..", ".."))
data = sys.argv[1]
GAME = "$data/shaders/tileAndMirrorShader.xml"; OURS = "../../shaders/foalCoatShader.xml"
i3d = os.path.join(mod, "models", "foal", "horseFoal.i3d")

def make():
    s = open(os.path.join(data, "shaders", "tileAndMirrorShader.xml"), encoding="utf-8-sig").read()
    s = s.replace('defaultFilename="../shared/characterDirt_normal.png"', 'defaultFilename="$data/shared/characterDirt_normal.png"')   # (the copy is not in the game's shaders folder any more)
    # the setting
    s = s.replace('<Parameter name="dirt" ', '<Parameter name="coatTint" target="coatTint" type="float4" group="base" defaultValue="1 1 1 1" minValue="0 0 0 0" maxValue="4 4 4 4" description="colour that multiplies the coat (foal coat shader)"/>\n        <Parameter name="dirt" ', 1)
    assert 'name="coatTint"' in s
    s = s.replace("float4 atlasInvSizeAndOffsetUV;\n", "float4 atlasInvSizeAndOffsetUV;\n/* the coat is multiplied by this colour (our addition) */\nfloat4 coatTint;\n", 1)
    assert "float4 coatTint;" in s
    old = '<CodeInjection position="POST_DIFFUSE_COLOR_FS">\n<![CDATA[\n'
    assert old in s
    s = s.replace(old, old + "    diffuseColor = diffuseColor * object.coatTint.rgb;   // our addition: the coat colour of this animal\n", 1)
    out = os.path.join(mod, "shaders", "foalCoatShader.xml")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "w", encoding="utf-8").write(s)
    print("wrote", out)

def point(to):
    t = open(i3d, encoding="utf-8").read()
    frm = GAME if to == OURS else OURS
    t = t.replace('filename="%s"' % frm, 'filename="%s"' % to)
    if to == OURS:
        t = re.sub(r'(<CustomParameter name="mirrorScaleAndOffsetUV" value="[^"]*" />)(?!\s*<CustomParameter name="coatTint")', r'\1\n      <CustomParameter name="coatTint" value="1 1 1 1" />', t)
    else:
        t = re.sub(r'\n\s*<CustomParameter name="coatTint" value="[^"]*" />', "", t)
    open(i3d, "w", encoding="utf-8").write(t)
    print("the foal model now uses", to)

if "--revert" in sys.argv:
    point(GAME)
else:
    make(); point(OURS)
