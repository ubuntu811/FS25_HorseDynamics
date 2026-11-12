#!/usr/bin/env python3
"""Makes shaders/foalCoatShader.xml: a copy of the game's horse skin shader (data/shaders/tileAndMirrorShader.xml, GIANTS Software) with our additions, and points the foal model at it (or back).
Settings of our own, per animal from Lua (I3DUtil.setShaderParameterRec(node, name, a, b, c, d)):
  coatTint r g b 1        a colour that multiplies the COAT (not eyes, mouth, hooves: the mask models/foal/coatMask.dds, tools/make_coat_mask.py)
  coatShade bright sat 0 eyeGloss   brightness and saturation of the coat; eyeGloss 0..1 makes the eyeballs glossy
  patternA r g b strength  a pattern layer (the mask's alpha channel: the Pinto patches so far) of that colour over the coat, strength 0 = off
The body material uses the variation coatDirt (with the mask), the mane keeps dirtEnabled (coatTint on all of it).
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
    def must(old, new, what):
        assert old in s, what
        return s.replace(old, new, 1)
    s = must('<Group name="dirt" define="DIRT_ENABLED" />', '<Group name="dirt" define="DIRT_ENABLED" />\n        <Group name="coat" define="COAT_MASK" />', "groups")
    s = must('<Parameter name="dirt" ', '<Parameter name="coatTint" target="coatTint" type="float4" group="base" defaultValue="1 1 1 1" minValue="0 0 0 0" maxValue="4 4 4 4" description="colour that multiplies the coat"/>\n'
        '        <Parameter name="coatShade" target="coatShade" type="float4" group="base" defaultValue="1 1 0 0" minValue="0 0 0 0" maxValue="4 4 4 1" description="x brightness, y saturation, w eye gloss"/>\n'
        '        <Parameter name="patternA" target="patternA" type="float4" group="base" defaultValue="1 1 1 0" minValue="0 0 0 0" maxValue="1 1 1 1" description="rgb colour of pattern A, a its strength"/>\n'
        '        <Parameter name="dirt" ', "parameters")
    s = must('<Texture name="alphaMap" group="alphaMap" defaultColorProfile="linearRGB"/>', '<Texture name="alphaMap" group="alphaMap" defaultColorProfile="linearRGB"/>\n        <Texture name="coatMask" group="coat" defaultColorProfile="linearRGB"/>', "texture")
    s = must('<Variation name="dirtEnabled" groups="base dirt">', '<Variation name="coatDirt" groups="base dirt coat">\n<![CDATA[\n    /* the body of our foal: dirtEnabled plus the coat mask (R coat, G eyeball, B hoof, A pattern A) */\n    #define DIRT_ENABLED\n]]>\n        </Variation>\n        <Variation name="dirtEnabled" groups="base dirt">', "variation")
    s = must("float4 atlasInvSizeAndOffsetUV;\n", "float4 atlasInvSizeAndOffsetUV;\n/* our additions: coatTint rgb multiplies the coat; coatShade x brightness y saturation w eye gloss; patternA rgb colour a strength */\nfloat4 coatTint;\nfloat4 coatShade;\nfloat4 patternA;\n", "object parameters")
    s = must("    float4 gGloss;\n", "    float4 gGloss;\n    float4 gCoatMask; // R coat, G eyeball, B hoof, A pattern A (1 0 0 0 without the mask)\n", "globals")
    s = must("globals.gGloss = float4(0.0,1.0,0.0,0.0);\n", "globals.gGloss = float4(0.0,1.0,0.0,0.0);\n#if defined( COAT_MASK )\n    globals.gCoatMask = tex2DSample( coatMask, standardMaterialSampler, In.vs.glossmapTexCoords ).rgba;\n#else\n    globals.gCoatMask = float4(1.0,0.0,0.0,0.0);\n#endif\n", "start fs")
    old = '<CodeInjection position="POST_DIFFUSE_COLOR_FS">\n<![CDATA[\n'
    s = must(old, old + """    {   // our additions: the coat colour of this animal, then its pattern
        float3 shaded = diffuseColor * object.coatTint.rgb;
        float shadeLum = dot(shaded, float3(0.299, 0.587, 0.114));
        shaded = lerp(float3(shadeLum, shadeLum, shadeLum), shaded, object.coatShade.y) * object.coatShade.x;
        diffuseColor = lerp(diffuseColor, shaded, globals.gCoatMask.r);
        diffuseColor = lerp(diffuseColor, object.patternA.rgb, globals.gCoatMask.a * object.patternA.a);
    }
""", "post diffuse")
    old = "        bakedAO = globals.gGloss.g;\n    #endif\n#endif\n"
    s = must(old, old + "#if defined( COAT_MASK )\n    roughness = lerp(roughness, 0.04, globals.gCoatMask.g * object.coatShade.w); // our addition: glossy eyeballs\n#endif\n", "post gloss")
    out = os.path.join(mod, "shaders", "foalCoatShader.xml")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "w", encoding="utf-8").write(s)
    print("wrote", out)

def point(to):
    t = open(i3d, encoding="utf-8").read()
    ours = to == OURS
    t = t.replace('filename="%s"' % (GAME if ours else OURS), 'filename="%s"' % to)
    horse = re.search(r'<Material name="horse_mat".*?</Material>', t, re.S).group(0)
    h = horse
    # the mask file and the custom map of the body material
    t = re.sub(r'\n\s*<File fileId="11" filename="coatMask.dds" />', "", t)
    h = re.sub(r'\n\s*<Custommap name="coatMask" fileId="11" />', "", h)
    h = re.sub(r'\n\s*<CustomParameter name="coat[A-Za-z]*" value="[^"]*" />', "", h)
    if ours:
        t = t.replace('<File fileId="10" ', '<File fileId="11" filename="coatMask.dds" />\n    <File fileId="10" ', 1) if 'fileId="11"' not in t else t
        h = h.replace('customShaderVariation="dirtEnabled"', 'customShaderVariation="coatDirt"').replace("<Glossmap fileId=\"3\" />", "<Glossmap fileId=\"3\" />\n      <Custommap name=\"coatMask\" fileId=\"11\" />")
        h = h.replace('<CustomParameter name="mirrorScaleAndOffsetUV" value="1 1 0 0" />', '<CustomParameter name="mirrorScaleAndOffsetUV" value="1 1 0 0" />\n      <CustomParameter name="coatTint" value="1 1 1 1" />')
    else:
        h = h.replace('customShaderVariation="coatDirt"', 'customShaderVariation="dirtEnabled"')
    t = t.replace(horse, h, 1)
    # the mane keeps dirtEnabled with the tint only
    mane = re.search(r'<Material name="maneTailBraide_mat".*?</Material>', t, re.S).group(0)
    m = re.sub(r'\n\s*<CustomParameter name="coat[A-Za-z]*" value="[^"]*" />', "", mane)
    if ours:
        m = m.replace('<CustomParameter name="mirrorScaleAndOffsetUV" value="1 1 0 0" />', '<CustomParameter name="mirrorScaleAndOffsetUV" value="1 1 0 0" />\n      <CustomParameter name="coatTint" value="1 1 1 1" />')
    t = t.replace(mane, m, 1)
    open(i3d, "w", encoding="utf-8").write(t)
    print("the foal model now uses", to)

if "--revert" in sys.argv:
    point(GAME)
else:
    make(); point(OURS)
