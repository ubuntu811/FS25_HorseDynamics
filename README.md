# HorseFoal

Experiment: what does a horse look like with the goat kid's proportions?

`tools/make_foal.py <HorseModel dir> <out dir> [age 0..1]` copies `horse.i3d` (+ `.shapes`, `.anim`) to `horseFoal.i3d` and puts a **scale on each bone** of the skeleton: the ratio of the goat kid's bone length to the goat adult's, measured from the game's own `goat.i3d` / `goatKid.i3d` (legs and neck shrink most, 0.5 to 0.6; hooves and feet stay large, 0.8 to 1.0; the body 0.64 to 0.7). Scaling bones (not moving them) keeps the mesh in proportion and survives the animation clips, which only drive translation and rotation. Then the root is lowered so the four hooves stand on the ground again (checked by forward kinematics: the horse's rotations are Z-Y-X Euler; all adult hooves come out at 0.000 m, the foal's within 1 cm).

Result (skeleton positions, not yet looked at in the editor or the game): withers 1.46 m -> 1.08 m, head 2.06 m -> 1.39 m, head to tail 2.60 m -> 1.88 m. `age` 0 is the kid, 1 the adult; in between is a growing foal.

Open: look at it in the GIANTS Editor; the collision proxy, camera nodes and the rideable vehicle XML are not changed; stride and speed need a locomotion file of their own (the goat kid has one); how the game would show it (a new animal entry with a model of its own) is not worked out.
