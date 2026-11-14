# Mixamo downloads (the Guardian)

Files downloaded from mixamo.com go in this folder. Mixamo characters and animations
are made by people, free to use in a game (Adobe account needed), but **not CC0 and not
to be redistributed on their own**: the `.gitignore` here keeps the raw `.fbx` files out
of the repository, and the `.gdignore` keeps Godot from importing them. Only what the
Blender scripts make from them goes into the game.

## Option 2 of the Guardian: a Mixamo knight as the body

1. Open https://www.mixamo.com and sign in (a free Adobe account).
2. **Characters** tab, search `Paladin`, pick **"Paladin J Nordstrom"** (full plate
   armour, helmet; not the "WProp" one, which carries a sword and shield).
   Second choice if the look is wrong: **"Knight D Pelegrini"**.
3. **Download**: Format `FBX Binary (.fbx)`, Pose `T-pose`. Save it here as
   `paladin.fbx`.
4. Run (from the project folder):
   `"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" --background --python tools/blender/make_guardian_mixamo.py -- assets/models/characters/mixamo/paladin.fbx assets/models/characters/blockout/guardian_mixamo_blockout.glb`
5. Open the project in Godot once (it imports the new model), then run
   `tools/character_test.tscn` (F6) and press **9**: the Guardian on the Mixamo body,
   with our cape, antlers, gold and sword. `-- pictures <folder>` then also saves both
   Guardians side by side (`sheet_guardian`, `game_guardian_options`).

The script was only tried with a stand-in file (our own blockout body with Mixamo bone
names), never with a real Mixamo download: the fit of the helm and pauldrons on the
Paladin will need a look.

## The rig and animations for our own blockout Guardian

1. Mixamo, **Upload Character**: `assets/models/characters/blockout/mixamo_upload/guardian_blockout_body.fbx`
   (his bare body in T-pose: no cape, antlers or sword).
2. In the auto-rigger place the markers (chin, wrists, elbows, knees, groin), keep
   "Standard Skeleton (65)", finish.
3. Download the rigged character: `FBX Binary`, `T-pose` -> `guardian_rigged.fbx`.
4. Animations (search each, download as `FBX Binary`, **Without Skin**, 30 fps):
   - `Great Sword Idle` -> `guardian_idle.fbx`
   - `Great Sword Walk` (tick **In Place**) -> `guardian_walk.fbx`
   - `Great Sword Slash` -> `guardian_slash.fbx`

   Put them here. Using them in the game (retargeted to Godot's humanoid names, which
   the blockout rig already has) is the next step after the review; until then the game
   plays its own simple animations made in code (`GuardianMoves`).
