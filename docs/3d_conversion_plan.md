# Echo — 2D to 3D conversion plan

Status: **approved; Phase A has started.** Section 1 records the decisions as approved.

The 3D isometric prototype (`proto3d/`) was judged a success: lighting, darkness, the
character lights and creature movement feel much better than in 2D. The game is being
converted to 3D on Godot 4.7, Forward+. This plan says how, in what order, and what we
check first.

## 1. Decisions (all approved)

These choices shape everything below.

| # | Decision | Approved | Why |
|---|---|---|---|
| 1 | Camera | **Chosen by playing: yaw 45°, pitch 45°, speed compensation 100 %, keys follow the walls.** These are the defaults of `SharedCamera` (all still `@export`) | Tested against yaw 0°, pitch 55°, less compensation and exact-direction keys on real rooms; see section 5.1 |
| 2 | Rooms: redesign in 3D, or build the 3D rooms in code from the 11 existing floor plans | **From the existing floor plans** | All 9 Ocean levels, the validator and `check_levels` stay valid; no level design is redone |
| 3 | Units | **50 px = 1 world unit**, as in the prototype | Lights, fog, physics and imported models all expect metre-sized numbers |
| 4 | Art rule | **Changed** (see `CLAUDE.md`): CC0 models (Quaternius, KayKit, Kenney) and Mixamo animations are allowed, each with its licence file in the repo; still no AI-generated art or audio | The old rule ("vector shapes built in Godot only") cannot produce 3D characters |
| 5 | Convert in place or build beside the 2D code | **In place on branch `3d`**, same class and file names | One code base at the end; `main` is the working 2D game the whole time |
| 6 | Performance target | **60 FPS at 1080p on a mid-range GPU from about 2018** | Sets the budget for shadowed lights, fog quality and the edge pass |

## 2. Branch strategy

- `main` keeps the 2D game and stays shippable until the 3D version has caught up.
- `3d` was created from `main` and already contains the prototype commit (`proto3d/`).
  All conversion work is committed there.
- **2D gameplay code on `main` is frozen.** Only text and data changes go to `main`
  (for example roadmap step 6, the story text). After each one, `main` is merged into
  `3d`. Text and data merge cleanly; script changes would conflict with converted files.
- `proto3d/` stays as a reference during Phase A and is deleted at the end of it, once
  the real classes replace it.
- Switch-over: when `3d` passes every test in section 6 and a full Ocean play-through,
  tag `main` as `last-2d`, then merge `3d` into `main`.
- `CLAUDE.md` and `docs/roadmap.md` are updated at the end of every phase, on `3d`, so
  they always describe what the branch really contains.

## 3. The basic approach

The game is played on a flat plane in both versions. That is what makes the conversion
tractable:

- **Rules stay, nodes change.** State machines, timers, damage, offers, saves and stage
  flow are kept. What changes is the node type (`Node2D` -> `Node3D`,
  `CharacterBody2D` -> `CharacterBody3D`), positions (`Vector2` -> `Vector3` on the XZ
  plane, y up) and everything that draws.
- **Lengths are converted once per system**, when that system is ported: its exported
  defaults and the `.tres` / `.tscn` values that override them are divided by 50
  (speeds and accelerations too; times and ratios are untouched). A small helper tool
  does the division for a list of properties and files, so nothing is retyped by hand.
- **Room floor plans stay in pixels.** The 11 room scenes remain 2D polygon data and are
  scaled by the builder (`WorldConfig`, one `units_per_pixel` value).
- **All the 2D-only rendering work is deleted, not ported**: rock faces, ground shadows,
  the raised "top" lights, the top falloff material, occluded outlines, drop shadows,
  the sonar line builder. Real 3D lighting and depth replace them. This is about
  1,800 lines that simply go away.

Size of the job, for scale: 318 scripts, about 27,600 lines. About 133 scripts touch 2D
nodes or positions, 29 are UI and about 11 are pure data resources.

## 4. System by system

**Keep** = works unchanged or with a signature change only. **Adapt** = same logic, new
node types and units. **Rebuild** = written again for 3D.

| System | Verdict | How |
|---|---|---|
| **Sonar** (`SonarOverlay`, `PulseRing`, `get_sonar_lines`) | Rebuild | The prototype is the base: a ring of rays per pulse stored in a texture, a full-screen edge pass, a world-space surface shader. Added for the real game: 4 pulse slots with their own radius and speed (Echo pulse, distress pulse, Lure decoy), `pulse_radius_mult` and the world's pulse modifiers, the `sonar_targets` contract (corals wake, shards show, Sentinel ring, mines revealed, cyan orbs pop) |
| **Darkness and lights** (`Darkness`, `PlayerLight`, `TopLightFalloff`, `LightShafts`, `MarineSnow`, `AreaAccent`) | Rebuild | `WorldEnvironment` ambient per `StageDefinition` (same fields, new meaning), `OmniLight3D` per player, volumetric fog, GPU marine snow. Brightness option scales ambient and player lights as now. `set_extra_darkness` (Angler phase 3) stays as an API. Shadow budget: the Echo's light plus the N nearest lights cast shadows |
| **Players** (`Player`, visuals) | Adapt + rebuild visuals | Movement, leash, device binding and `uses_gamepad` are kept (`ProtoPlayer` already proves it). `EchoVisual` / `GuardianVisual` are rebuilt as models in Phase C; capsules until then |
| **Camera** (`SharedCamera`) | Rebuild | From `ProtoCamera`: orthographic, follows the midpoint, widens its view, `shake_with` through the same group. Adds the rock cut-away (section 5.2) |
| **Health** (`PlayerHealth`, `HealthSegments`, `HurtVignette`) | Keep | Logic and UI unchanged; `take_hit` takes a `Vector3` |
| **Oxygen** (`PlayerPressure`, stations, `BubbleVent`) | Keep / adapt | The meter is pure logic. Stations and vents become 3D nodes with the same radius checks |
| **Mending, revive, downed** (`PartnerMending`, `ReviveHelper`, `DistressPulse`, `CloseSense`) | Adapt | Same rules on flat distances. The mending link and revive ring are redrawn in 3D. The distress pulse becomes a sonar slot |
| **Skills** (`SkillDefinition`, `PlayerSkills`, `SkillOffer`, `SkillLoadout`, catalog, choice screen) | Keep | Data and UI unchanged. Length values in the skill `.tres` files are converted |
| **Active skills + aiming** (`LurePulseSkill`, `ShieldSkill`, `DashSkill`, twin-stick) | Adapt | `ActiveSkill` becomes a `Node3D`. Aim directions go through one camera mapping (section 5.1). Aim line, shield arc and dash trail are redrawn on the ground plane |
| **Sword** (`SwordAbility`) | Adapt | Timings and combo kept (`ProtoSword` already matches). Adds back deflecting, noise, hit-stop sound and the Exposed kill burst |
| **Creatures and AI** (`Creature`, `CreatureEyes`, `CreatureStuckWatch`, `CreatureVoice`) | Adapt + rebuild visuals | The state machine, chase ratios, lunge, alerting, search, frenzy and coral avoidance are kept. Visibility zones stay game rules (section 5.3). Bodies are primitives until Phase C |
| **Sentinels** (`Sentinel`) | Adapt | Small script on top of `Creature`; guard ring drawn on the floor |
| **Navigation** | Rebuild the bake, keep the use | `NavigationServer3D`, two meshes baked per agent size as now (26 px and 52 px become 0.52 and 1.04 units). Baked from the floor plan polygons, not from meshes, so it stays fast. Rebakes on lockdown, arena door and broken pillars stay |
| **Room grid** (`RoomGrid`, `LevelDefinition`, `RoomPlacement`, `LevelGenerator`) | Keep | Pure data and grid logic |
| **Validator** (`LayoutValidator`, `check_levels`) | Keep | It already works on the wall polygons before anything enters the world. The lighting checks are rewritten |
| **Rooms and builder** (`LevelChunk`, `LevelBuilder`, `RockWall`, `RockFace`) | Rebuild the meshing, adapt the builder | A new rock mesher pulls each floor-plan polygon up to its height (range per room as now, 32-72 px = 0.64-1.44 units), with the soft bumps and seals. `LevelBuilder` keeps placement, quarter turns, seals, seeded spawns and doorway clear zones. `RockWall` (889 lines) and `RockFace` shrink to a small mesher plus a shader |
| **Shards, exit, door** (`EchoShard`, `AncientLight`, `ShardDoor`, `GoalEcho`) | Adapt | Logic kept, nodes and looks in 3D. The Echo's arrow is drawn on the floor |
| **Lockdown** (`LockdownRoom`, `LockdownBarrier`) | Adapt | Trigger, waves, drain scale and reward kept. Barriers become rock that rises out of the floor |
| **Collapse escape** (`EscapeEvent`) | Adapt | Timer, frenzy and arrow kept. Falling rock and dust become 3D particles |
| **Boss framework** (`Boss`, `BossAttack`, `BossHealthBar`, `BossTitle`) | Adapt | Phases, armour, Exposed, attack states and hooks kept. Bar and title are UI and stay |
| **The Angler** (`AnglerBoss`, `AnglerBody`, `AnglerVisual`, `AnglerGlow`, orbs, mines, pillars) | Adapt logic, rebuild body | See Phase D. The side-profile drawing (about 1,650 lines) is replaced by a 3D model; hurtbox and attack zones become shapes on the ground plane |
| **Placeholder boss** | Adapt | Small; follows the framework |
| **Audio** (`AudioDirector`, `MusicDirector`, `AmbiencePlayer`, `UiAudio`, `generate_sounds.py`) | Keep, one change | Buses, music states, catalog and all sound files unchanged. Positional sounds move to `AudioStreamPlayer3D` (16 uses). The listener sits at the camera's focus point, not at the camera, which is 40 units away |
| **Menus, Journey, story, options, pause, end screens** | Keep | All 2D UI; it draws over a 3D world as it is. The Journey islands stay 2D |
| **HUD** (`Hud`, `PlayerStatus`, meters) | Keep, re-check glow | UI unchanged. The bloom on HUD text comes from a 2D glow environment today; over a 3D world that needs a test (risk 4) |
| **In-world prompts** (revive prompt, aim lines) | Adapt | Positioned with the camera's projection |
| **Landmarks** (8 kinds), **harmless life**, floor scatter, depth layers | Rebuild | Phase C and E, from models. Placement data (`LandmarkPlacement`, `AmbientLifeSpawn`) is kept |
| **Save** (`SaveData`, settings) | Keep | It stores world, stage, mode and skills only, no positions. No version change |
| **Debug views** (F1 lines, F2 hitboxes, F3 navigation) | F1 keep, F2 / F3 rebuild | Drawn as 3D lines on the floor |
| **Tests** | See section 6 | |

## 5. Fixes for what the prototype showed

### 5.1 Moving "up" looks about 30% slower

Cause: the camera looks down at 45°, so ground distance away from the camera is squashed
on screen by sin(45°) = 0.71.

Fix, in three parts:
1. **Uniform on-screen speed.** A mover's speed limit depends on its direction: it is
   divided by how much that direction is squashed on screen. Swimming looks equally fast
   every way. One shared helper does this for players, creatures, bosses and
   projectiles, so chase ratios stay fair in every direction.
2. **Direction mapping per device.** A stick maps to the exact screen direction it
   points at. Keyboard keys map to world directions, so that two keys held together
   follow a wall instead of drifting across the corridor.
3. **Ranges stay round in the world.** Sword arcs, pulse radius and light radii are not
   stretched; they look like ellipses on screen, which is what the prototype already
   shows and reads correctly.

A steeper camera (50-55°) shrinks the problem before any compensation and also helps
5.2; it is tried in the same test. If full compensation feels wrong (dodging in depth
becomes too easy), the fallback is half compensation.

### 5.2 Tall rocks hide the floor and the players

1. **Rock heights go back to the 2D values** (0.64-1.44 units). The prototype used 2.6
   and 3.2, about twice the game's tallest rock. A rock hides a strip of floor about as
   deep as it is tall, so this alone halves the problem. Taller rock is kept for the
   outer wall on the far side and for landmarks.
2. **Cut-away.** The rock shader dissolves rock inside a soft screen circle around each
   player wherever the rock is between the camera and that player, with a faint glowing
   rim on the cut. It works for any rock shape and needs no per-rock logic. The same
   cut-away applies to a short list of "must be seen" points: a downed partner, a shard
   being picked up, a creature in its lunge.
3. **See-through outlines stay** (already in the prototype) as the cheap fallback for
   everything else.
4. **Doorways stay clear**, using the existing `doorway_clear_distance` rule.

**Found while building it (Phase A):** at the 2D heights and pitch 45° a rock can only
hide a character's feet or lower body, and only right beside the rock: a 1.16-unit rock
never covers the middle of the Echo unless she is within about 0.6 units of it. So the
hole opens only when at least half of the body is covered (`ViewCutaway.min_covered_share`);
below that the see-through outline is enough. Full cover, and so the cut-away, will
mostly happen at taller rock: the boss arena (up to 1.44 units), landmarks, outer walls.

**Decided after the Phase A play-test:** the short 2D heights stay the default for all
rock. Tall walls are placed only where they mean something (the boss arena's entrance,
ancient gates and similar set pieces), on purpose and by hand, never as a general room
setting; the cut-away handles them. The `T` key of `tools/core_test.tscn` (every rock
x2.6) stays as the way to check the cut-away at its worst.

### 5.3 Unrevealed creatures fully hidden behind rocks

Rule: **the camera never hides what the 2D game would show.** Visibility stays a game
rule, decided by the existing zones (the Echo's reveal radius, the silhouette zone, the
Guardian's close sense, pulse reveals, whether rock blocks the Echo's light). The
renderer then honours it:

- close-range eyes and the lunge flare are always drawn through rock;
- a creature in the silhouette zone is drawn as a dim silhouette through rock;
- a fully revealed or Exposed creature gets its outline through rock, as in the prototype;
- a creature the rules say is hidden stays hidden. The darkness stays unknown.

## 6. Phases

Each phase ends with something playable and its tests passing. Estimates are working
days of the two of us (I write, you play and decide), and they are rough: expect
plus or minus half.

### Phase A — 3D core (6-9 days)
- Days 1-2, spikes on the open questions: camera yaw and pitch with keyboard movement
  (5.1), the cut-away shader (5.2) on two real floor plans (`room_kelp_maze`,
  `room_tunnel_bend`) pulled up into 3D, HUD glow over 3D.
- Then: `Player`, `SharedCamera`, darkness and lights, the full sonar, `SwordAbility`,
  `PlayerHealth`, `PlayerPressure`, downed / revive / mending / distress pulse / close
  sense, one `Creature` type on `NavigationRegion3D`, 3D physics interpolation.
- **Playable:** a test stage of two real rooms where both players explore, pulse,
  fight, get hurt, go down and revive each other.
- **Tested:** the core half of `test_creatures` (chase speeds, lunge, alert, search,
  downed, revive) ported and passing; `test_save` unchanged; FPS benchmark recorded.
- `proto3d/` is deleted at the end.

### Phase B — room grid and level flow (8-12 days)
- The rock mesher and the 3D `LevelBuilder`; all 11 room types; seals, outer rock,
  doorway rules; navigation bake for both agent sizes.
- Corals, stations, shards, the locked exit, the arena door, Sentinels, lockdown, the
  collapse escape, the Echo's arrow.
- `StageManager` and level fades, skills (stats, the three active skills, aiming), the
  HUD connected (it is UI, so this is wiring, not design).
- **Playable:** the whole Ocean, stages 1-3, start to finish from the main menu, with
  placeholder bodies and the placeholder boss in every boss arena.
- **Tested:** `check_levels`, `test_creatures`, `test_skills`, `test_stuck` all passing.

### Phase C — asset pipeline and characters (8-12 days)
- `tools/blender/`: Blender 5.2 run headless with Python (it is installed) to import a
  source model, clean it, apply the shared dark material, and export `.glb`.
- Sources: CC0 packs (Quaternius, KayKit, Kenney); Mixamo for the Guardian's rig and
  animations. **Every asset gets a licence file** beside it (source URL, author,
  licence, date, what was changed) plus one index, `assets/models/LICENSES.md`.
- One shared look: every model uses the same dark body + glowing rim shader, so packs
  with different styles still read as one world of silhouettes.
- The Echo, the Guardian (cloak and antlers as separate spring-driven parts), the
  creature types, the Sentinel, the 8 landmarks, harmless life.
- **Playable:** the Ocean with real characters, creatures and landmarks.
- **Tested:** previous tests still pass; landmark and life checks in `check_levels` and
  `test_creatures` ported; a capture tool saves a picture of every model for review.
- Your part: Mixamo needs your Adobe sign-in and a manual download; it cannot be scripted.

### Phase D — the Angler in 3D (6-9 days)
- Boss framework ported first, checked with the placeholder boss.
- The Angler's body as a model that really turns, with the lure, jaw, fins and glow;
  hurtbox, bite, sweep and charge zones as shapes on the ground plane.
- Pillars (crack, break, rebake), vents, orbs, mines, summons, the darker phase 3.
- **Playable:** stage 1 including the full Angler fight, both modes.
- **Tested:** `test_boss` passing; `sim_boss_fight` back inside its time targets
  (Calm 2:30-3:45, Challenge 3-4 min). Expect a balance pass here.

### Phase E — screens, audio, polish (7-10 days)
- Every screen checked over the 3D game in English and Arabic (`ui_capture`), pause
  menu, end screens, boss bar and title.
- 3D positional audio with the listener at the camera focus; `test_audio` passing.
- **Real recordings replace the procedural sounds** (decided after the Phase A play-test:
  the generated bells and resonant pings sound generic). Sources: the Sonniss GDC free
  bundles, Freesound CC0, and your own phone recordings. Each one is processed into
  something of our own (pitch, filters, layering, the underwater reverb) by a script in
  `tools/` (Python, run from the command line like `generate_sounds.py`), so the processing
  can be repeated and changed. **Every sound has its licence file** beside it (source URL
  or "own recording", author, licence, date, the processing applied), listed in
  `assets/audio/LICENSES.md`. Still no AI-generated audio. Sounds are found by file name
  (unchanged), so a recording replaces a generated sound without code changes, and the
  approval step stays: new sounds go to `assets/audio/preview/` first and are heard in the
  Sound Test beside the current ones. Order: the sounds heard most first (pulse ping, sonar
  tick, sword, hurt, creature voices), then the rest.
- Floor detail, area accents, depth layers, light shafts in stage 1, hit and kill
  effects, F2 / F3 debug views.
- Options: a graphics setting (fog quality, shadow count) if the benchmark needs it.
- **Playable:** the complete game, ready to replace `main`.
- **Tested:** every tool in the Folders list of `CLAUDE.md` passing, then the switch-over
  in section 2.

**Total: about 35-52 working days, 7 to 10 weeks.**

### Tests through the conversion

| Tool | Lines | What happens |
|---|---|---|
| `check_levels.gd` | 428 | Kept; lighting checks rewritten in Phase B |
| `test_save.gd` | 126 | Kept unchanged |
| `test_creatures` | 983 | Ported in two halves (A and B) |
| `test_skills` | 1,015 | Ported in Phase B |
| `test_stuck` | 244 | Ported in Phase B |
| `test_boss` | 1,046 | Ported in Phase D |
| `sim_boss_fight` | 689 | Ported in Phase D |
| `test_audio` | 412 | Ported in Phase E |
| `ui_capture` | 281 | Adjusted in Phase E |
| New: FPS benchmark | | From Phase A, run at the end of every phase on the largest level |
| New: view capture | | Screenshots of fixed poses (behind rock, in a tunnel, mid-pulse) for review |

A system counts as converted only when its test file passes again. The existing
assertions are the specification of how the game behaves.

## 7. Risks, and what we test first

In the order they are checked. The first four are the Phase A spikes: if one fails, we
stop and decide before building further.

1. **Camera angle with keyboard movement.** At 45° yaw, corridors are diagonal and a
   keyboard has 8 directions. Test: walk a real tunnel room with keys at yaw 45° and
   yaw 0°, pitch 45° and 55°. If neither device mapping in 5.1 feels right at 45°,
   yaw 0° is the fallback.
2. **Readability in tight rooms.** The prototype room was open. Test the cut-away in
   the kelp maze and the tunnel bend, with a creature chasing.
3. **Performance at level scale.** The prototype's 1,760 FPS was one small room on an
   RX 7800 XT at 1280x720. A level is 9 to 16 rooms with many lights. Test: the largest
   level with every light, at 1080p and 4K. The target is 60 FPS at 1080p on a
   mid-range card from about 2018; the development machine is far faster, so the
   benchmark's numbers are scaled down, not taken as they are.
   Levers if it is slow: fewer shadowed lights, lower fog quality, a half-resolution
   edge pass.
4. **HUD glow.** HUD and menu text bloom through a 2D glow environment today. Over a
   3D world that may stop working. Fallbacks: draw the 3D world in a sub-viewport under
   the 2D screen, or accept a drawn glow on the HUD.
5. **Sonar at level scale.** Reveal leaking over the top of a blocking rock onto a
   taller rock behind it (seen in the prototype), thin rock between ray directions at
   long range, four pulses at once.
6. **Characters and the edge pass.** The prototype keeps characters out of the sonar
   edge pass by drawing them as transparent. With many creatures, particles and
   effects that can cause draw-order errors. Checked in Phase A with ten creatures.
7. **Navigation bake time.** Level builds and mid-level rebakes must stay hidden behind
   the existing fades and camera shakes. Measure on the largest level.
8. **Cost of porting the tests.** About 4,400 lines of scene tests are full of
   positions. This is inside the estimates but is the part most likely to run over.
9. **Assets.** Mixing three packs; a cloaked, antlered Guardian is awkward for Mixamo's
   auto-rigger (plan: rig the body only). Mixamo is free to use in games but is not
   CC0 and its files may not be redistributed on their own, so its licence note differs
   from the CC0 ones. There may be no suitable CC0 anglerfish; the fallback is building
   it with Blender Python.
10. **The Angler's design assumed a side profile.** Its hurtbox, bite zone and "flips
    left / right" are 2D ideas. The fight needs retuning, not just porting.
11. **Two versions drifting apart.** Handled by freezing 2D gameplay code on `main`.

## 8. What this plan leaves out

- The other four worlds, the unique bosses for stages 2-3 and roadmap step 7. They
  resume after the switch-over, on the 3D version.
- Roadmap step 6 (story text) can go ahead on `main` at any time; it is text only.

## 9. Progress

Updated with every step, so a new session knows where the conversion stands.

### Phase A — 3D core
- [x] Camera test on real rooms; camera chosen (decision 1).
- [x] Rock cut-away (`ViewCutaway`, `shaders/cutaway.gdshaderinc`).
- [x] `Player` and its scenes, `PlayerHealth`, `PlayerPressure`, `ReviveHelper`,
  `PlayerSkills`, `ActiveSkill` (base only), `PlayerLight`, `PlayerAudio`.
- [x] `SharedCamera`, `ViewMotion`.
- [x] `Sonar` (4 pulse slots, per-pulse reach and speed, `on_sonar_hit`), `PulseAbility`,
  `ReadyCue`, `SonarAudio`.
- [x] `Darkness`, `MarineSnow`, `AudioDirector` (3D positional; moved forward from Phase E
  because the ported classes call it).
- [x] `RockMesher`; play-test stage `tools/core_test.tscn`.
- [x] `SwordAbility` (placeholder blade, slash arc, kill burst, aim tick on the floor).
- [x] `Creature` on `NavigationServer3D` (`NavigationBaker`: baked from the floor plans in
  0.04 s for three rooms), `CreatureBody` (placeholder look), `CreatureEyes`,
  `CreatureStuckWatch`, `CreatureVoice`, `CreatureHeartbeat`, `ExposedMark`.
- [x] `PartnerMending`, `DistressPulse`, `CloseSense`, `PlayerOverlay` (downed and revive
  rings), `GoalEcho`; `GlowLines` draws all of them.
- [x] 3D physics interpolation (on; `I` in the core test switches it to compare).
- [x] `tools/test_core.tscn`: the core half of `test_creatures`, rebuilt for 3D (40 checks).
- [x] FPS benchmark (core test, RX 7800 XT, three rooms, four creatures, a pulse every
  1.6 s): 1920x1080 about 360 FPS, GPU 1.2 ms and render CPU 0.36 ms per frame; no frame
  over 16.7 ms (worst 13-17 ms); a pulse's 1024 rays take up to 3-4 ms. For the 2018 target
  (about a quarter of this GPU) that is roughly 5 ms of GPU per frame. Still to measure
  at level scale (Phase B), where most of the cost will be.
- [x] `proto3d/` deleted.
- [ ] HUD glow over the 3D world (risk 4): moved to Phase B, where the HUD is ported.

### Left for Phase B, noted while porting
- **Scenes that inherit `scenes/creature.tscn`** (light hunter, sentinel, the placeholder
  boss, the Angler, `tools/large_creature.tscn`) still override 2D nodes (`EchoLayer/Echo`,
  `Shadow`...): redo them when their scripts come back. Their sonar echo colour is now
  `Creature.type_color` (was `CreatureEcho.color`).
- **Skill values in pixels**: `close_sense_add`, and any other length in the skill `.tres`
  files, must be divided by 50 when the skill catalog comes back.
- `Coral` (and every "corals" user) is read by duck typing; port it and type it again.
- The F2 hitbox view (`HitShapes`, `get_debug_shapes`) is not on the 3D creature or sword
  yet, and the F3 path view (`NavDebugDraw`) is in `legacy2d/`: Phase E.
- `DropShadow` is in `legacy2d/`: real lights and shadows do its job for now; a soft contact
  shadow under bodies may come back with the models (Phase C).
- The pulse's occlusion rays (1024 per pulse, up to ~4 ms on the pulse frame) are the
  biggest single cost: check them on a full level; fewer rays or rays spread over two
  physics frames if needed.
- `Darkness`: the darkening with depth through a stage needs the `LevelBuilder`
  (`stage_progress_at`); only the stage's ambient colour is applied for now.
- The `Game` autoload has no worlds and no skill catalog (they load every unported
  scene); put both back in `scenes/game_state.tscn` once the levels build in 3D.
- `WorldConfig`: only `pulse_radius` and the marine snow values are in world units so far;
  the room sizes and everything else are still pixels.
- Rock tops are flat and every rock has one height; the 2D rise and fall along a rock
  (`height_wave`) comes back with the real `LevelBuilder`.
