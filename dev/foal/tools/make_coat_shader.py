#!/usr/bin/env python3
"""Makes shaders/foalCoatShader.xml: a copy of the game's horse skin shader (data/shaders/tileAndMirrorShader.xml, GIANTS Software) with our additions, and points the foal model at it (or back).
Settings of our own, per animal from Lua (I3DUtil.setShaderParameterRec(node, name, a, b, c, d)):
  coatTint r g b 1        a colour that multiplies the COAT (not eyes, mouth, hooves: the mask models/foal/coatMask.dds, tools/make_coat_mask.py)
  coatShade bright sat 0 eyeGloss   brightness and saturation of the coat; eyeGloss 0..1 makes the eyeballs glossy
  patternA r g b strength  a pattern layer (the mask's alpha channel: the Pinto patches so far) of that colour over the coat, strength 0 = off
  markWhite r g b 1       the colour of the white markings below
  marks face socks blanket spotKeep   face 0..1 (0.33 star, 0.67 blaze, 1 blaze + snip), sock height 0..1, blanket extent 0..1 (1 = leopard), spotKeep 0..1 = dark spots inside the blanket
  flecks strength minPx 1 raw   white flecks (w = 1: raw, none of the distance helpers) (snowflake) 0..1; the least radius of a spot on the screen in pixels (default 2; TAA averages away anything under 3 px across)
  spots density size seed cell   the spots (flecks, and the dark spots of the blanket) are made in the shader from the undeformed body position: density 0..1 of cells with a spot (times the mask's R: none on the muzzle and lids), size 0..1, a seed per animal, the cell size in metres
  (the second mask models/foal/coatMask2.dds, tools/make_coat_mask2.py: R spot density, G blanket gradient, B face levels, A sock gradient)
The body material uses the variation coatDirt (with the mask), the mane keeps dirtEnabled (coatTint on all of it).
Usage: make_coat_shader.py <game data dir (the folder with shaders/)> [--revert]      (writes ../../shaders/foalCoatShader.xml and patches ../../models/foal/horseFoal.i3d)
--revert: the foal model points at the game's own shader again (the shader file is kept)."""
import sys, os, re
here = os.path.dirname(os.path.abspath(__file__)); mod = os.path.normpath(os.path.join(here, "..", "..", ".."))
data = sys.argv[1]
GAME = "$data/shaders/tileAndMirrorShader.xml"; OURS = "../../shaders/foalCoatShader.xml"
# the foal and the adult clone (models/horse/horseAdult.i3d, baked with the "adult preset") use the same shader and the same two masks (the clone reaches into models/foal/)
MODELS = [(os.path.join(mod, "models", "foal", "horseFoal.i3d"), ""), (os.path.join(mod, "models", "horse", "horseAdult.i3d"), "../foal/")]

def spot_cells():
    out = []
    for i in range(8):
        ox, oy, oz = i % 2, (i // 2) % 2, i // 4
        out.append("""            {   // cell %d
                float3 spotS%d = spotBase + float3(%d.0, %d.0, %d.0) + object.spots.z * 7.31;
                float spotH0 = frac(sin(dot(spotS%d, float3(12.9898, 78.233, 37.719))) * 43758.5453);
                float spotH1 = frac(sin(dot(spotS%d, float3(39.346, 11.135, 83.155))) * 24634.6345);
                float spotH2 = frac(sin(dot(spotS%d, float3(73.156, 52.235, 9.151))) * 31415.9265);
                float spotH3 = frac(sin(dot(spotS%d, float3(27.623, 63.451, 21.917))) * 17453.2925);
                float spotH4 = frac(sin(dot(spotS%d, float3(51.771, 17.337, 66.209))) * 28571.4285);
                float spotH5 = frac(sin(dot(spotS%d, float3(18.231, 44.917, 73.403))) * 36542.7311);
                float3 spotPt = spotBase + float3(%d.5, %d.5, %d.5) + (float3(spotH0, spotH1, spotH2) - 0.5) * 0.4;
                float spotRad = (0.10 + 0.18 * spotH3) * object.spots.y;
                float spotRadE = (object.flecks.w > 0.5) ? spotRad : max(spotRad, object.flecks.y * spotPixel);   // never smaller than flecks.y pixels in radius (default 2: TAA averages away anything under about 3 px across): far away a spot is a small dot, not nothing ...
                float spotKeep = (object.flecks.w > 0.5) ? 1.0 : step(spotH5, max((spotRad * spotRad) / (spotRadE * spotRadE), 0.45));   // ... and fewer are kept as they grow (the white's total stays the same) but never fewer than 45 percent: a sparse pattern must still read at a distance (overstated on purpose)
                float spotD = length(spotQ + 0.5 - spotPt);
                spotCov = max(spotCov, step(spotH4, object.spots.x * m2.r) * spotKeep * saturate((spotRadE - spotD) / ((object.flecks.w > 0.5) ? 0.35 * spotRadE : max(0.35 * spotRadE, 0.5 * spotPixel))));
            }""" % (i, i, ox, oy, oz, i, i, i, i, i, i, ox, oy, oz))
    return "\n".join(out)

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
        '        <Parameter name="markWhite" target="markWhite" type="float4" group="base" defaultValue="0.56 0.58 0.58 1" minValue="0 0 0 0" maxValue="1 1 1 1" description="rgb colour of the white markings, a how much fur of the base coat shows through them (0 = flat)"/>\n'
        '        <Parameter name="marks" target="marks" type="float4" group="base" defaultValue="0 0 0 0" minValue="0 0 0 0" maxValue="1 1 1 1" description="x face, y socks, z blanket extent, w dark spots in the blanket"/>\n'
        '        <Parameter name="flecks" target="flecks" type="float4" group="base" defaultValue="0 2 1 0" minValue="0 0 0 0" maxValue="1 1 1 1" description="x white fleck strength, y the least radius of a spot in pixels, z 1 = procedural spots, w 1 = raw: none of the distance helpers"/>\n'
        '        <Parameter name="spots" target="spots" type="float4" group="base" defaultValue="0.7 0.8 0 0.08" minValue="0 0 0 0.01" maxValue="1 1 1000 1" description="procedural spots: x density, y size, z seed, w cell size in metres"/>\n'
        '        <Parameter name="dirt" ', "parameters")
    s = must('<Texture name="alphaMap" group="alphaMap" defaultColorProfile="linearRGB"/>', '<Texture name="alphaMap" group="alphaMap" defaultColorProfile="linearRGB"/>\n        <Texture name="coatMask" group="coat" defaultColorProfile="linearRGB"/>\n        <Texture name="coatMask2" group="coat" defaultColorProfile="linearRGB"/>', "texture")
    s = must('<Variation name="dirtEnabled" groups="base dirt">', '<Variation name="coatDirt" groups="base dirt coat">\n<![CDATA[\n    /* the body of our foal: dirtEnabled plus the coat mask (R coat, G eyeball, B hoof, A pattern A) */\n    #define DIRT_ENABLED\n]]>\n        </Variation>\n        <Variation name="dirtEnabled" groups="base dirt">', "variation")
    s = must("    float2 glossmapTexCoords : TEXCOORDn;\n", "    float2 glossmapTexCoords : TEXCOORDn;\n    float3 coatObjPos : TEXCOORDn; // our addition: the undeformed body position, for spots made in the shader\n", "vs output")
    s = must("    Out.glossmapTexCoords = newUV;\n", "    Out.glossmapTexCoords = newUV;\n    Out.coatObjPos = In.position.xyz;\n", "vs position")
    s = must("float4 atlasInvSizeAndOffsetUV;\n", "float4 atlasInvSizeAndOffsetUV;\n/* our additions: coatTint rgb multiplies the coat; coatShade x brightness y saturation w eye gloss; patternA rgb colour a strength */\nfloat4 coatTint;\nfloat4 coatShade;\nfloat4 patternA;\nfloat4 markWhite;\nfloat4 marks;\nfloat4 flecks;\nfloat4 spots;\n", "object parameters")
    s = must("    float4 gGloss;\n", "    float4 gGloss;\n    float4 gCoatMask; // R coat, G eyeball, B hoof, A pattern A (1 0 0 0 without the mask)\n    float4 gCoatMask2; // R spot field, G blanket gradient, B face levels, A sock gradient\n", "globals")
    s = must("globals.gGloss = float4(0.0,1.0,0.0,0.0);\n", "globals.gGloss = float4(0.0,1.0,0.0,0.0);\n#if defined( COAT_MASK )\n    globals.gCoatMask = tex2DSample( coatMask, standardMaterialSampler, In.vs.glossmapTexCoords ).rgba;\n    globals.gCoatMask2 = tex2DSample( coatMask2, standardMaterialSampler, In.vs.glossmapTexCoords ).rgba;\n#else\n    globals.gCoatMask = float4(1.0,0.0,0.0,0.0);\n    globals.gCoatMask2 = float4(0.0,0.0,0.0,0.0);\n#endif\n", "start fs")
    old = '<CodeInjection position="POST_DIFFUSE_COLOR_FS">\n<![CDATA[\n'
    s = must(old, old + """    {   // our additions: the coat colour of this animal, then its pattern
        // the fur of the base coat (each texel's brightness against the coarse average round it) is carried into the white of the markings and the pinto patches: a flat white looked like spray paint
        float furDetail = 1.0;
#if defined( COAT_MASK )
        {
            float3 furCoarse = tex2DSampleLod( baseMap, standardMaterialSampler, In.vs.glossmapTexCoords, 4.0 ).rgb;
            float furRatio = dot(diffuseColor, float3(0.299, 0.587, 0.114)) / max(dot(furCoarse, float3(0.299, 0.587, 0.114)), 0.02);
            furDetail = lerp(1.0, clamp(furRatio, 0.55, 1.5), object.markWhite.a);   // markWhite.a: how much of the base coat's fur shows through the white (0 = flat white, the default; hdCoat fur 0..1)
        }
#endif
        float3 shaded = diffuseColor * object.coatTint.rgb;
        float shadeLum = dot(shaded, float3(0.299, 0.587, 0.114));
        shaded = lerp(float3(shadeLum, shadeLum, shadeLum), shaded, object.coatShade.y) * object.coatShade.x;
        diffuseColor = lerp(diffuseColor, shaded, globals.gCoatMask.r);
        diffuseColor = lerp(diffuseColor, object.patternA.rgb * furDetail, globals.gCoatMask.a * object.patternA.a);
        // markings (coatMask2): blanket with dark spots, white flecks, face marking, socks
        float4 m2 = globals.gCoatMask2;
        float blanketT = lerp(1.02, -0.05, object.marks.z);
        float blanket = smoothstep(blanketT - 0.03, blanketT + 0.03, m2.g) * step(0.001, object.marks.z);
        float dots = 0.0;
        if (object.flecks.x > 0.001 || object.marks.w > 0.001)
        {   // spots made in the shader (no texture detail to lose at a distance): jittered points in a 3D grid of object.spots.w metres, 2x2x2 cells around the pixel, a disc of random size at each; the mask's R says where
            // they may be (density: none on the muzzle and lids). A spot is never smaller than a pixel (spotPixel, in cells) and only as many are kept as keep the total white the same: far away they are single pixels, not vanished.
            float3 spotQ = In.vs.coatObjPos / object.spots.w - 0.5;
            float3 spotBase = floor(spotQ);
            float spotCov = 0.0;
            float spotPixel = max(length(ddx(In.vs.coatObjPos)), length(ddy(In.vs.coatObjPos))) / object.spots.w;
@@UNROLL@@
            dots = spotCov;
        }
        float whiteBlanket = blanket * (1.0 - dots * object.marks.w);
        float whiteFlecks = dots * object.flecks.x * (1.0 - blanket);
        float faceT = 1.1 - 0.7 * object.marks.x;
        float face = smoothstep(faceT - 0.05, faceT + 0.05, m2.b) * step(0.001, object.marks.x);
        float sockT = 1.0 - object.marks.y;
        float sock = smoothstep(sockT - 0.04, sockT + 0.04, m2.a) * smoothstep(0.0, 0.04, m2.a) * step(0.001, object.marks.y);   // (the second factor: no sock where the field is 0, else socks 1 whitens everything that is not a leg)
        float whiteAmount = max(max(whiteBlanket, whiteFlecks), max(face, sock)) * globals.gCoatMask.r;
        diffuseColor = lerp(diffuseColor, object.markWhite.rgb * furDetail, whiteAmount);
    }
""", "post diffuse")
    old = "        bakedAO = globals.gGloss.g;\n    #endif\n#endif\n"
    s = must(old, old + "#if defined( COAT_MASK )\n    roughness = lerp(roughness, 0.04, globals.gCoatMask.g * object.coatShade.w); // our addition: glossy eyeballs\n#endif\n", "post gloss")
    # a sun glint on the eyeballs (coatShade.w): a sharp highlight of the sun on the eye's surface, so the eyes shine even where there is nothing bright to reflect
    i = s.index('<CodeInjection position="POST_GET_LIGHTING_FS">')
    j = s.index("]]>", i)
    s = s[:j] + """#if defined( COAT_MASK )
    {   // our addition: the sun's glint on the eyeballs (viewDir and lightDir point away from the surface, as in the scattering above)
        float3 glintHalf = normalize(lightDir + viewDir);
        float glint = pow(saturate(dot(normal, glintHalf)), 500.0) * globals.gCoatMask.g * object.coatShade.w * 30.0;
        lighting.xyz += lightColor * glint * lightAtten;
    }
#endif
""" + s[j:]
    s = s.replace("@@UNROLL@@", spot_cells())
    # the mane (variation dirtEnabled) runs the same injections but has no coat textures: a use of coatMask / coatMask2 outside #if defined( COAT_MASK ) does not compile there and the mane is gone
    depth_coat, stack = 0, []
    for no, line in enumerate(s.splitlines(), 1):
        st = line.strip()
        if st.startswith("#if"):
            stack.append("COAT_MASK" in st and "!" not in st and "#ifndef" not in st)
        elif st.startswith("#endif") and stack:
            stack.pop()
        elif re.search(r"\bcoatMask2?\b", line.split("//")[0]) and "<Texture" not in line and "Custommap" not in line and "group=" not in line and not any(stack):
            raise AssertionError("shader line %d uses a coat texture outside #if defined( COAT_MASK ): %s" % (no, st[:90]))
    out = os.path.join(mod, "shaders", "foalCoatShader.xml")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "w", encoding="utf-8").write(s)
    print("wrote", out)

def point(to):
    for i3d, prefix in MODELS:
        if os.path.exists(i3d):
            point_one(i3d, prefix, to)

def point_one(i3d, prefix, to):
    t = open(i3d, encoding="utf-8").read()
    ours = to == OURS
    t = t.replace('filename="%s"' % (GAME if ours else OURS), 'filename="%s"' % to)
    horse = re.search(r'<Material name="horse_mat".*?</Material>', t, re.S).group(0)
    h = horse
    # the mask file and the custom map of the body material
    t = re.sub(r'\n\s*<File fileId="1[12]" filename="[./a-z]*coatMask2?.dds" />', "", t)
    h = re.sub(r'\n\s*<Custommap name="coatMask2?" fileId="1[12]" />', "", h)
    h = re.sub(r'\n\s*<CustomParameter name="coat[A-Za-z]*" value="[^"]*" />', "", h)
    if ours:
        t = t.replace('<File fileId="10" ', '<File fileId="11" filename="%scoatMask.dds" />\n    <File fileId="12" filename="%scoatMask2.dds" />\n    <File fileId="10" ' % (prefix, prefix), 1)
        h = h.replace('customShaderVariation="dirtEnabled"', 'customShaderVariation="coatDirt"').replace("<Glossmap fileId=\"3\" />", "<Glossmap fileId=\"3\" />\n      <Custommap name=\"coatMask\" fileId=\"11\" />\n      <Custommap name=\"coatMask2\" fileId=\"12\" />")
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
    print("%s now uses %s" % (os.path.basename(i3d), to))

if "--revert" in sys.argv:
    point(GAME)
else:
    make(); point(OURS)
