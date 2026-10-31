# FS25_HorseDynamics

Makes the horses of a pasture follow you.

* **Right Ctrl + C**: calls the nearest horse (a horse of a pasture, or one that stands loose as a vehicle). Press again for each further horse.
* **Right Ctrl + V**: gives them all back.
* Console: `hdLead [start|stop|status]`.

A horse follows in bursts (a few seconds of walking, then it stands a while, then follows again); the gait grows with the distance (walk, canter, trot, gallop) and eases back as it closes in;
when something is in its way (a fence, a sprayer) it backs up and turns twice before it is given up on and released; it is given back by itself when it is at a stable and you are with it, so leading horses to a new stable is walking them there.

## Hand tools (in the shop, category "animals" hand tools: the one the game's horse brush is in)

* **Carrot** (15): a switch: the primary action calls every horse of the pasture you stand in (or the nearest horse pasture within 40 m) and also gathers the horse vehicles that stand loose within 80 m (released earlier, stuck somewhere); the same action again lets those horses go.
* **Leash** (25): the primary action takes the nearest horse (a pasture horse or one that stands loose) on the leash; the same action again lets the leashed horses go.

The shop images are `assets/shop_icons.png` split in two. In-hand models: the carrot is the base game's own carrot mesh (`effects/unload/particle/carrot`) in a small wrapper i3d (`handTools/carrot/carrot.i3d`, hand placement copied from the horse brush, to be tuned in the game); the leash has no model of its own any more (the base game's rope props, a coil of `rope01`/`rope02`, were tried and were too big): in the hand it shows a 20 cm end of rope hanging from the tool while no horse is on it (`HorseRope.syncStub`, the same winch rope), and with a horse on it the rope itself runs from the hand to the horse. Icons were made with the pipeline of
`FS25_whatAmILookingAt/docs/icon_pipeline.md` (ImageMagick for the crop and resize, GIANTS textureTool for the BC7 DDS): `store/carrot.dds`, `store/leash.dds`, `icon.dds`.

**Pinned horses (between bushes, in a collider):** a led horse backs up and turns twice, is then put 3 m towards you once (the game's own `setWorldPosition`, which moves the character controller too), and only then given up on. A horse you ride that stays halted for 2.5 s is put 3 m behind itself automatically; `hdLead free` does the same for the nearest horse on demand.

**Mounting a following horse:** press the enter key on it as on any horse. The virtual rider is only a flag; the game sees the horse as free (it reports "controlled" only inside the one game function that
holds an unridden horse still), so mounting works; the horse is then dropped from the string and the others keep following you (on the horse).

**The leash is a real rope** (`scripts/HorseRope.lua`, confirmed in the game: it draws, the horse follows it): each leashed horse gets a rope to its bridle, drawn by the game's own winch rope (`ForestryRope`, the shape the forestry winch uses: a straight rope that the shader stretches between a link node and a target node every frame; the path has to be resolved with `Utils.getFilename`, the engine does not know `$data`). The target is the horse's rein node. A `ForestryRope` is always straight, so the sag is made of 6 pieces with points between them, put every frame on a hanging curve (the slack makes the sag, at most 35 cm, never below the ground; `HorseRope.SEGMENTS`, `SAG_MAX_M`). The rope starts at the leash in your hand; put the leash away and it stays, hanging from your chest, and when you mount a horse it hangs from the saddle: the horses are still led, so the rope is too. Let the horses go and the ropes are deleted. 1.5 cm thick (`HorseRope.DIAMETER`). Following: a horse that stands (arrived, or in a pause) turns in place to face you (`RIDE_TURN_RATE_STILL`), and when you ride, the followers keep about 2.4 m behind your horse instead of 3.5 m (`RIDE_ARRIVE_MOUNTED_M`) and do not pause far behind (`RIDE_KEEP_UP_MOUNTED_M`).

## How it works

The game swaps a pasture animal for a Rideable vehicle when a player rides it (`PlaceableHusbandryAnimals:startRiding`). Called with no player, that gives a horse vehicle nobody rides. A per-instance
`getIsControlled` that says "yes" stops the server holding it still (`Rideable:onUpdateInterpolation`), and the script sets gait and steer itself each frame. A rideable near a pasture goes back into it
(`doHusbandryCheck`). The horse's heading (`currentTurnAngle`, the game's own field) is turned towards you at about 400 degrees a second while it moves (`RIDE_TURN_RATE`), because the game's own turning (45 degrees a second) draws a gentle arc straight into the wall next to a gate. Proven in the game with the AnimalLab prototype (`~/my_mods/FS25_AnimalLab`, which stays the lab for probing the engine's animal functions).

**Gates.** Near a fence gate (4.5 m to its door or its trigger) the leash click is for the gate (`scripts/HorseGate.lua`): with a horse on the rope it opens or closes the gate instead of letting the horse go, and with no horse to take it does the same. The game's own `setDirection` is used on every leaf of the gate (the same call as its key), the farm check of the game is respected. Both fence systems are covered (pasture fences and the older fence placeables). To let a horse go next to a gate, walk on a few metres and click again.

## Status

Offline: `lua5.1 tests/horsedynamics_test.lua` (35 checks, a fake engine). In the game: the lead logic is the prototype's (confirmed: a horse followed out of its pasture, through a gate); the keys, the stuck
check, the loose-horse takeover and the stable hand-over are new and not seen in the game yet. Single player only.

## Planned

A helper-list job (so the horses show as a worker that can be cancelled from the map), a carrot hand tool (all horses of the pasture come) and a leash (the closest one), and ambient behaviour (a horse
sometimes comes over when you enter its pasture, one may shy away when you walk up to it).
