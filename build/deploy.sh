#!/usr/bin/env bash

# Exit immediately if any command fails
set -e

# Define source archive and destination folder name
MOD_NAME="FS25_HorseDynamics"
SOURCE_ZIP="build/${MOD_NAME}.zip"
TARGET_DIR_NAME="$HOME/fs25/mods/${MOD_NAME}"

echo "=== Starting FS25 Hot-Reload Deployment Pipeline ==="

# 0. A script that does not parse must never reach a game that is running: every Lua file is syntax checked, modDesc and the xml of the mod must be well formed. Nothing is built or copied when one fails.
BAD=0
for f in scripts/*.lua; do
    if ! lua -e "assert(loadfile('$f'))" >/tmp/hd_lua_check.txt 2>&1; then
        echo "!!! $f does not parse:"; head -2 /tmp/hd_lua_check.txt; BAD=1
    fi
done
for f in modDesc.xml xml/*.xml vehicles/*/*.xml; do
    if ! python3 -c "import sys,xml.dom.minidom as m; m.parse(sys.argv[1])" "$f" 2>/tmp/hd_xml_check.txt; then
        echo "!!! $f is not well formed:"; tail -1 /tmp/hd_xml_check.txt; BAD=1
    fi
done
for pair in "xml/horseAdult.xml models/horse/horseAdult.i3d" "xml/horseFoal.xml models/foal/horseFoal.i3d"; do
    set -- $pair
    if [ -f "$HOME/fs25_resources/HorseModel/horse.i3d" ] && ! python3 dev/foal/tools/check_mappings.py "$1" "$2" >/tmp/hd_map_check.txt 2>&1; then
        echo "!!! $1 has i3dMappings that do not find the same nodes in $2 as in the game's horse (an added node shifted an index):"; head -6 /tmp/hd_map_check.txt; BAD=1
    fi
done
if ! python3 dev/foal/tools/check_shader.py >/tmp/hd_shader_check.txt 2>&1; then
    echo "!!! shaders/foalCoatShader.xml uses a coat texture where the mane's variation has none (the manes would disappear):"; head -4 /tmp/hd_shader_check.txt; BAD=1
fi
for f in tests/*.lua; do
    if ! lua "$f" >/tmp/hd_test_out.txt 2>&1; then
        echo "!!! $f FAILS:"; grep -v "passed$" /tmp/hd_test_out.txt | head -6; BAD=1
    fi
done
if [ "$BAD" != "0" ]; then
    echo "!!! NOT deployed: fix the file(s) above first."; exit 1
fi

# 1. Always rebuild first - real bug found live tonight: the old
# "only build if the zip is missing" version silently deployed a stale
# zip from before a source edit whenever one already happened to exist,
# same class of bug already caught once tonight on the map mods'
# deploy.sh. Unconditional now, matching that fix - build.sh's own cost
# is small, there's no real reason to skip it.
if [ -f "build/build.sh" ]; then
    bash build/build.sh
fi

# 3. Deploy to a LIVE game: the game is always running and reads models, textures and xml when it needs them, so the folder is never emptied and a file is never half written: unzip into a staging
# folder, then rsync only the files that really changed (checksums; each is written as a temp file and renamed). What changed says what it takes to see it.
STAGE="build/.deploy_stage"
rm -rf "$STAGE"
mkdir -p "$STAGE" "$TARGET_DIR_NAME"
unzip -q "$SOURCE_ZIP" -d "$STAGE"
# rsync --delete removes what is not in the stage: never with an empty or wrong stage, never outside this mod's own folder, never more than a few files at once.
if [ ! -f "$STAGE/modDesc.xml" ]; then
    echo "!!! the staged package has no modDesc.xml: the target is NOT touched"; rm -rf "$STAGE"; exit 1
fi
case "$TARGET_DIR_NAME" in
    */mods/${MOD_NAME}) ;;
    *) echo "!!! the target is not .../mods/${MOD_NAME}: nothing deleted or written"; rm -rf "$STAGE"; exit 1 ;;
esac
CHANGES=$(rsync -rt --checksum --delete --max-delete=30 --itemize-changes "$STAGE"/ "$TARGET_DIR_NAME"/ | grep -v '^\.d' | grep -E '^(>f|\*deleting)' || true)
rm -rf "$STAGE"
if [ -z "$CHANGES" ]; then
    echo "--> Nothing changed in the deployed mod."
else
    echo "--> Changed files:"
    echo "$CHANGES" | sed 's/^[^ ]* /    /'
    if echo "$CHANGES" | grep -qE ' (scripts/|modDesc.xml|shaders/)|\.dds'; then
        echo "--> RESTART the game: Lua, modDesc, a shader or a texture (.dds) changed (those are read at start: hdReload does not drop the texture cache)."
    fi
    if echo "$CHANGES" | grep -qE ' (models/|vehicles/|xml/|store/|textures/)'; then
        echo "--> In game: hdReload (drops the cached models and reloads the vehicles near you; hdReload store also re-reads the store items); a pasture horse has to be led out first."
    fi
fi

echo "================================================="
echo " SUCCESS: Mod deployed as a loose unzipped folder!"
echo " Path: ${TARGET_DIR_NAME}"
echo "================================================="

