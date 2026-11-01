#!/bin/bash
# Builds the rope meshes: OpenSCAD (Windows exe, run from WSL) -> STL -> OBJ with UVs.
#   lead    the long pieces of the lead (about 0.3 to 0.8 m): a lay of about 4 rope diameters needs many turns
#   halter  the short pieces of the halter and the loop in the hand (about 0.05 to 0.15 m): few turns, a coarser section
cd "$(dirname "$0")"
W="$(wslpath -w "$PWD")"
build() { # name, openscad -D options...
    local name="$1"; shift
    ( cd "/mnt/c/Program Files/OpenSCAD" && ./openscad.exe -o "$W\\$name.stl" "$@" "$W\\rope.scad" 2>&1 | grep -i facets )
    python3 -I stl_to_obj.py "$name.stl" "$name.obj"
}
build rope_lead   -D strands=3 -D sides=8 -D turns=8 -D slices_per_turn=6
build rope_halter -D strands=3 -D sides=8 -D turns=2 -D slices_per_turn=6
