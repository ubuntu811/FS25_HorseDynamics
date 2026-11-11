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
