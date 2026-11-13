# legacy2d — the 2D scripts and tools not ported to 3D yet

Branch `3d` only. Every file here is the 2D version of a script or tool, moved out of
Godot's scan (this folder has a `.gdignore`) so the editor opens without parse errors while
the conversion is in progress. The paths inside mirror the project: `legacy2d/scripts/x.gd`
was `scripts/x.gd`, `legacy2d/tools/x.gd` was `tools/x.gd`.

When a script is ported, move it back with `git mv` (history follows) and port it in place:

    git mv legacy2d/scripts/hud.gd scripts/hud.gd
    git mv legacy2d/scripts/hud.gd.uid scripts/hud.gd.uid

Scenes that use these scripts (e.g. `scenes/game.tscn`) stay where they are and do not load
until their scripts are back. `tools/check_scripts.tscn` lists every script outside this
folder that does not parse; it must stay at zero. Still here after Phase B step 2: the
boss framework and the bosses (Phase D), harmless life, light shafts, the debug draws,
the drop shadows, the level generator, the old tests and tools. Which phase ports what:
`docs/3d_conversion_plan.md`, sections 6 and 9. The folder is deleted when it is empty.
