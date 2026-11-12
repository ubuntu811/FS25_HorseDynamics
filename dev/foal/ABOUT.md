# Foals in HorseDynamics

Foals for Farming Simulator 25: a baked, animated foal model for every horse coat, shop pictures, foals that are led and not ridden. The logic is `scripts/HorseFoal.lua` (xml/horseFoal.xml is the foal vehicle, xml/foalAnimals.xml the animal config); the foal itself is `models/foal/`.

## How we got to the model: `dev/foal/`

The workshop is part of this repo, with its history (`git log -- dev`): a browser app with sliders (`dev/foal/app`), the Blender scripts and the bake tools (`dev/foal/tools`). The recipe, in short:

1. `dev/foal/app` (foal-scale): shape the foal by sliders and presets (Favorite 1..6), look at it in the walk and idle poses beside the adult.
2. `dev/foal/tools/bake_foal.py`: turn that look into `horseFoal.i3d`, `.shapes` and `.anim` (bone scales, vertex edits, every clip converted); `check_bake.py` compares the result with the app.
3. `dev/foal/tools/blender_icon.py`: the shop pictures, one per coat.
4. Copy the result into `models/foal/` and `store/foal/`, then `bash build/deploy.sh`.

What is not in git (it comes from the game's own horse): `dev/foal/app/horse_app.json`, `dev/obj/`, `dev/out/`, `dev/foal/app/vendor/` (three.js). They are left out of git because they are the game's data; the foal model itself (`models/foal`) is in the repo with credit, see the README's Credits section.

The build (`build/build.sh`) packs only `store/ models/foal/ xml/ scripts/ ...` (HorseDynamics' build): `dev/foal/` never goes into the mod.

## Coat shader experiment (2026-11-12)

The foal's body is drawn by `shaders/foalCoatShader.xml`, a copy of the game's horse skin shader with our additions (variation `coatDirt` for the body; the mane keeps `dirtEnabled` and only gets the tint):

* `python3 dev/foal/tools/make_coat_mask.py <HorseModel dir> models/foal` makes `models/foal/coatMask.dds` from the game's mesh: R coat skin, G eyeballs, B hooves, A pattern A (the white patches of the game's Pinto tile). Check it by overlaying it on a tile (it lines up with the eye discs, hoof shapes and the Pinto patches).
* `python3 dev/foal/tools/make_coat_shader.py <game data dir>` writes the shader and points `models/foal/horseFoal.i3d` at it (variation, mask, parameters). Run it again after every bake (the bake writes the game's shader path back). `--revert` points the foal model at the game's own shader again.
* In the game, on a foal that has been led out of its pasture: `hdCoat tint 1.2 0.9 0.8` (colour of the coat only), `hdCoat shade 0.8 1.1` (brightness, saturation), `hdCoat gloss 0.8` (glossy eyes), `hdCoat pattern 1` (the Pinto patches in white), `hdCoat pattern 1 0.9 0.6 0.3` (in another colour), `hdCoat reset`, `all` at the end for every foal. If the foal looks pink, black or invisible the shader did not load: run `make_coat_shader.py --revert`, deploy, and read the log for the shader error.
