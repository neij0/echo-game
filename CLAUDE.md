# Echo — Project Rules

2D top-down co-op roguelite set in the deep ocean, for exactly 2 players (local co-op).
Target: PC (Steam).

## Core idea
The two playable characters are deep-sea creatures:
- **The Echo** (P1, female): small and glowing. Sees with sonar pulses that reveal the
  surroundings for a few seconds and wake up sparse bioluminescent corals (safe spots).
  Her pulse costs her oxygen. She cannot fight.
- **The Guardian** (P2, male): tall, dark and almost blind (only a very faint light).
  Fights with a sword (3-hit combo), but can only hurt creatures the Echo reveals.

Pillars:
1. **One sees, one fights.**
2. **Everything has a cost:** every pulse and every sword hit attracts danger (raises the
   "Depth Awareness" meter and alerts hostile creatures).
3. **Levels are hand-designed, but the darkness stays unknown:** creatures, corals and
   stations move to different spots on every attempt.

## Game structure
```
World (5, in this order: Ocean, Caves, Forest, Desert, Snow)
 └─ 3 Stages per world          (progress is saved after each completed stage)
     └─ 3 Levels per stage      (the last level of each stage ends in a boss arena)
After the 3rd stage of a world: a story text screen, then the World Map.
```
- **Level** = one descent: a fixed, hand-designed list of chunks (`LevelDefinition`). Go down
  while each player's survival pressure drains (Oxygen in the Ocean; stations in side pockets
  refill it) and activate the ancient light at the bottom to clear the level. The pressure
  meter carries over between the levels of a stage with a partial refill.
- **Boss level** (last level of a stage): ends in a boss arena chunk; beating the boss
  completes the stage. The boss is a placeholder for now (`scenes/boss_placeholder.tscn`: a
  bigger creature with much more health; real bosses come later).
- **Every attempt** (retries included) reshuffles creature, coral and station spawn points
  with a new seed, so a retry never plays exactly the same.
- **Downed**: a caught player can be revived by the partner. If both are downed at the same
  time, it depends on the mode (main menu, changeable later):
  **Calm** = restart the current level (and the meter drains slower);
  **Challenge** = restart the current stage from level 1.
- **Save** (`user://save.json`, `SaveData`): current world, current stage, unlocked worlds,
  mode, chosen skills. Settings (`user://settings.json`): language (English/Arabic), mode.
- **Screens**: main menu (Continue if a save exists, New Game, Mode, Language, Quit) →
  stage (`game.tscn`) → stage summary → next stage, or story screen → World Map.
- **Skill choice hook**: `StageManager._between_levels()` runs between two levels (paused);
  the skill choice screen goes there and stores the picks in `Game.save.skills`.
- **Testing one stage**: run `game.tscn` on its own (F6). The `StageManager` then uses its
  `world`, `test_stage_index` and `test_mode` exports and never writes the save.

The game will have 5 worlds, each with its own chunks, colours, creatures, survival pressure
and pulse behaviour. Only the Ocean exists so far.

Controls: P1 Echo = WASD + Space (pulse) or gamepad 1. P2 Guardian = arrow keys + Enter
(attack) or gamepad 2. Holding the action button next to a downed partner revives them.

## Lighting (layers)
1. **Ambient** (`Darkness`, a CanvasModulate): deep blue/teal, set per stage in each
   `StageDefinition` (stage 1 brightest, stage 3 darkest; fades a little darker down a stage).
   Rocks and floor read as faint silhouettes (~10-20%). Creatures stay hidden: their body is
   only drawn inside the Echo's light. The Brightness setting (Options) scales this layer only.
2. **Rock fill**: `rock_color` slightly lighter than the floor colours (WorldConfig Palette).
   The glowing sonar edges still only come with a pulse.
3. **Environment light**: marine snow (`MarineSnow`) everywhere, light shafts (`LightShafts`)
   where `StageDefinition.light_shaft_strength` > 0 (first stage only). Look values live in
   the WorldConfig groups "Marine Snow" and "Light Shafts".
4. **Gameplay reveals** (Echo light, pulse, sonar edges, creature echoes) are unchanged and
   never affected by Brightness.
Note: 2D renders in HDR (linear). Screenshots taken with `get_viewport().get_texture()` are
linear and look much darker than the screen; convert them to sRGB before judging.

## Rules
- **Godot 4 + GDScript only.** No C#, no GDExtension, no third-party addons unless agreed first.
- **Typed GDScript everywhere**: typed variables, parameters and return types
  (`var speed: float = 100.0`, `func foo(x: int) -> void:`). The project warns on untyped declarations.
- **Small, focused scripts**: one responsibility per script. Prefer signals over tight coupling.
- **File names in snake_case** (`player.gd`, `pulse_ring.tscn`). Class names in PascalCase via `class_name`.
- **All tunable values are `@export` variables** (speeds, durations, radii, colors, amounts). No magic numbers in logic.
- **No final art yet**: grey-box only (Polygon2D, `_draw()` shapes, generated light textures).
- **Terminology**: World > Stage > Level, everywhere (classes, files, signals, UI text).
  "Run" is not used any more.
- **All menu / screen text is bilingual** (English + Arabic): add new strings to
  `scripts/ui_text.gd` and read them with `Game.text(key)`. Arabic screens are laid out
  right-to-left (`Game.apply_direction`). The UI font is Tajawal (`assets/fonts/`, OFL),
  set as the project's custom font so Arabic renders everywhere.

## Folders
- `scenes/` — `.tscn` scenes (`main_menu`, `game`, `story_screen`, `world_map`, and
  `game_state.tscn` = the `Game` autoload)
- `scenes/chunks/<world>/` — the hand-made level chunks of each world
- `scripts/` — `.gd` scripts
- `worlds/` — one `WorldConfig` resource (`.tres`) per world
- `worlds/<world>/` — the world's `LevelDefinition`s (`level_<stage>_<level>.tres`)
- `story/` — story text per world and language (`<world>_end_en.txt`, `<world>_end_ar.txt`;
  one line per line, empty lines skipped). Not a Godot resource: when exporting, add `*.txt`
  to the export preset's "non-resource files" filter.
- `assets/audio/` — procedural placeholder sounds (generated by `tools/generate_sounds.py`)
- `assets/fonts/` — UI font (Tajawal, with its OFL licence)
- `assets/concepts/` — concept art references (not imported by Godot: has a `.gdignore`)
- `tools/` — helper scripts outside the game:
  - `generate_sounds.py` (Python)
  - `check_levels.gd`: loads every level of a world and validates it (BFS) with many spawn
    seeds, plus the structure and the generator:
    `godot --headless --path . -s res://tools/check_levels.gd`
  - `test_save.gd`: save/load test (uses its own test files in `user://`):
    `godot --headless --path . -s res://tools/test_save.gd`
  - `propose_level.gd`: **editor tool** (open it in the Script editor, File > Run) that
    proposes a new random `LevelDefinition` from the world's chunk pools, validates it and
    saves it as `worlds/<world>/proposed_<seed>.tres` to edit by hand.
  - Note: `-s` tools run without autoloads, so they must not load scripts that use `Game`.
- `docs/` — design notes (e.g. `skills.md`: skill ideas for later, not implemented)

## Adding a new world
All world-specific values live in its `WorldConfig` (`scripts/world_config.gd`); scripts get
them through the `world_listeners` group (`apply_world(world)`), never hard-coded.
1. Build its chunks in `scenes/chunks/<world>/` (root script `LevelChunk`, see the contract at
   the top of `scripts/level_chunk.gd`): start chunks (Player1/Player2 markers, top cap), middle
   chunks (corridor, cave, narrow; Creature/Coral markers, optional SideLeft/SideRight openings),
   pocket chunks (Station markers), goal chunks (Goal marker, bottom cap) and boss arena chunks
   (Boss marker, bottom cap).
2. Design its 9 levels as `LevelDefinition`s in `worlds/<world>/` (or start from
   `tools/propose_level.gd`): the ordered chunks (start, middles, goal or boss arena), one
   pocket per side opening, creature types and counts, corals, stations, station distance,
   and on each stage's last level the boss scene and its health.
3. Duplicate `worlds/ocean.tres` as `worlds/<world>.tres` and set: `world_id` (must match
   `Game.world_ids`), 3 `StageDefinition`s with their 3 levels each, the chunk pools (for
   the generator), the palette, the pressure (name, drain, low warning, level refill, colour)
   and the pulse modifiers (radius, speed, cost).
4. New creature types: a scene inheriting `scenes/creature.tscn` (or a script extending
   `Creature`), then add it to the levels' `creatures` lists.
5. Add the `.tres` to the `worlds` list of `scenes/game_state.tscn` (the `Game` autoload),
   and write `story/<world>_end_en.txt` and `story/<world>_end_ar.txt`.
6. Run `tools/check_levels.gd` with the new world path to confirm every level is valid.
A pressure that works differently from a draining meter (e.g. heat that rises near fire)
gets its own logic next to `PlayerPressure`, but its numbers still go in the `WorldConfig`.

## Collision layers
1 = walls, 2 = player, 3 = creatures

## Git
- **Never run `git push`.** The GitHub sign-in window opens hidden and the push hangs.
  Commit as usual, then end the reply by telling the user to run `git push` themselves.
