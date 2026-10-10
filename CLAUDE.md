# Echo — Project Rules

2D top-down co-op roguelite set in the deep ocean. Target: PC (Steam), local co-op with gamepads later.

## Core idea
The players are deep-sea divers in heavy suits with weighted boots, walking on the ocean
floor. The world is almost completely dark. The diver's helmet carries a small light and
emits a sonar pulse that reveals the surroundings for a few seconds and wakes up sparse
bioluminescent corals (safe spots). Every pulse raises the "Depth Awareness" meter
(0-100), which makes the hidden creatures more aggressive.

A run is one descent: start at the top, walk down through 3 ever deeper and darker zones
while oxygen drains (oxygen stations off the main path refill it), and activate the
ancient light at the bottom. Death (creature or oxygen) restarts the run from the top.

## Rules
- **Godot 4 + GDScript only.** No C#, no GDExtension, no third-party addons unless agreed first.
- **Typed GDScript everywhere**: typed variables, parameters and return types
  (`var speed: float = 100.0`, `func foo(x: int) -> void:`). The project warns on untyped declarations.
- **Small, focused scripts**: one responsibility per script. Prefer signals over tight coupling.
- **File names in snake_case** (`player.gd`, `pulse_ring.tscn`). Class names in PascalCase via `class_name`.
- **All tunable values are `@export` variables** (speeds, durations, radii, colors, amounts). No magic numbers in logic.
- **No final art yet**: grey-box only (Polygon2D, `_draw()` shapes, generated light textures).

## Folders
- `scenes/` — `.tscn` scenes
- `scripts/` — `.gd` scripts
- `assets/` — future art/audio (empty during grey-box)

## Collision layers
1 = walls, 2 = player, 3 = creatures

## Git
- **Never run `git push`.** The GitHub sign-in window opens hidden and the push hangs.
  Commit as usual, then end the reply by telling the user to run `git push` themselves.
