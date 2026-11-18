// rope.scad: a twisted rope segment for the game's rope shader (ForestryRope).
//
// The shader (data/shaders/ropeShader.xml) multiplies x and y of every vertex by the rope size and z by the rope length, so the mesh is one unit long along +z
// (z = 0 .. 1) with a diameter of 1 (x and y in -0.5 .. 0.5). The cross section is `strands` circles lying tangent on a circle (the sketch: circles round a circle, the red one
// is the rope's outline), plus a core so the middle is not hollow; it is extruded with a twist, which makes the strands run round the rope as in a laid rope.
//
// The twist is per mesh, and the shader stretches the mesh to the length of a piece: a piece of 0.5 m has `turns` turns in 0.5 m, a piece of 1 m the same number in 1 m (looser).
// Pieces of about the same length look alike; the normal map's tiling, which follows the length, is the thing that stays constant.

strands = 3;            // strands round the circle (3: a classic laid rope)
turns = 6;              // full turns over the unit length
sides = 10;             // sides of one strand's circle (the polygon count of the section)
slices_per_turn = 8;    // rings along the length per turn
overlap = 1.04;         // the strands overlap a little: one solid, no gaps
core = true;            // a core in the middle
aspect = 1;             // 1 for the mesh to export; for a PREVIEW at the proportion the shader makes of it (a piece of 0.5 m with a 1.5 cm rope: about 33) use  -D aspect=33

half = sin(180 / strands);
Rc = 0.5 / (1 + half);          // radius of the circle the strand centres lie on
rs = Rc * half;                 // radius of a strand: neighbours touch

module section() {
    for (i = [0 : strands - 1])
        rotate(i * 360 / strands) translate([Rc, 0]) circle(r = rs * overlap, $fn = sides);
    if (core) circle(r = max(Rc - rs * 0.5, 0.01), $fn = sides * 2);
}

scale([1, 1, aspect])
    linear_extrude(height = 1, twist = -360 * turns, slices = turns * slices_per_turn, convexity = 10) section();
