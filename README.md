# FS25_HorseFoalMod

Foals for Farming Simulator 25: a baked, animated foal model for every horse coat, shop pictures, foals that are led and not ridden. The logic is `scripts/HorseFoal.lua`; the foal itself is `model/`.

## How we got to the model: `dev/`

The workshop is part of this repo, with its history (`git log -- dev`): a browser app with sliders (`dev/app`), the Blender scripts and the bake tools (`dev/tools`). The recipe, in short:

1. `dev/app` (foal-scale): shape the foal by sliders and presets (Favorite 1..6), look at it in the walk and idle poses beside the adult.
2. `dev/tools/bake_foal.py`: turn that look into `horseFoal.i3d`, `.shapes` and `.anim` (bone scales, vertex edits, every clip converted); `check_bake.py` compares the result with the app.
3. `dev/tools/blender_icon.py`: the shop pictures, one per coat.
4. Copy the result into `model/` and `icons/`, then `bash build/deploy.sh`.

What is not in git (it comes from the game's own horse): `dev/app/horse_app.json`, `dev/obj/`, `dev/out/`, `dev/app/vendor/` (three.js). Keep this repo private or keep those out of it.

The build (`build/build.sh`) packs only `scripts/ model/ icons/ horseFoal.xml animals.xml modDesc.xml icon.dds`: `dev/` never goes into the mod.
