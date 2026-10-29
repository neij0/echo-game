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
- **Level** = a small, hand-designed **grid of rooms** (`LevelDefinition`, 3x3 to 4x4 cells,
  not all filled) with branches, at least one loop and dead ends, in any direction: start and
  exit can be anywhere (the exit may be close to the start). Explore while each player's
  survival pressure drains (Oxygen in the Ocean; stations in rooms refill it), collect the
  Echo Shards (`EchoShard`, in different rooms, hidden until a player is close or a pulse
  passes over them) and activate the ancient light in the exit room. The exit stays locked
  (empty sockets) until every shard is collected. Shortly after each pulse, the Echo alone
  gets a faint arrow (`GoalEcho`) to the nearest shard (cyan), then to the exit (gold).
  The pressure meter carries over between the levels of a stage with a partial refill.
- **Boss level** (last level of a stage): its exit room is a boss arena, sealed by a
  `ShardDoor` (rock with one socket per shard) until every shard is collected; beating the
  boss completes the stage. The boss is a placeholder for now (`scenes/boss_placeholder.tscn`: a
  bigger creature with much more health; real bosses come later).
- **Every attempt** (retries included) reshuffles creature, coral, station and shard spawn
  points with a new seed, so a retry never plays exactly the same.
- **Room grid rules** (`LevelBuilder`, `RoomGrid`): every room is a square of
  `WorldConfig.room_size`; a room declares its doorways (N/E/S/W, `LevelChunk.openings`) and
  can be turned in quarter turns. Two neighbouring rooms connect when both have a doorway on
  the shared side; every other doorway is sealed with rock. One room per level is the
  **lockdown room** (`lockdown_cell`, on or near the way to the exit).
- **Sentinels** (`Sentinel`, `scenes/sentinel.tscn`, `LevelDefinition.sentinels`, 1-2 per
  level): posted next to some shards (picked by the seed). Wander / investigate only inside
  `guard_radius` of the post, chase only while the player is inside `leash_radius`, then
  swim back; more health (Calm 12 / Challenge 16). Spine crest + pale eyes; a pulse shows a
  faint dashed ring of the area it guards. Answers: pulse + finisher together, sneak, lure.
- **Lockdown** (`LockdownRoom` + `LockdownBarrier`, built by the `LevelBuilder`): when every
  player is deep inside the lockdown room (`trigger_inset`), its connected doorways close
  with rock (rumble, slam, shake) and a wave wakes on its Creature markers
  (`lockdown_wave_calm` / `_challenge`). Once every wave creature is dead the doorways open
  (chord + warm light in each doorway). While locked the passive oxygen drain is scaled
  (`calm_drain_scale` 0 = paused, `challenge_drain_scale` 0.5; pulses cost as usual); clearing
  the wave gives both players `clear_pressure_ratio` (25 %) back (refill sound + ring).
  Once per attempt; downed / revive, distress pulse and
  close sense work inside; both downed = the normal restart rules.
- **Navigation rebake**: lockdown barriers and the arena door rebake the mesh one frame after
  the event, while its camera shake (`"shared_camera"` group, `shake_with`) hides the hitch.
- **Collapse escape** (`EscapeEvent`, `LevelDefinition.escape_event`, level 2 of every
  stage): the last shard starts it: falling rock + dust, rumble, shakes, every creature in
  frenzy (`Creature.set_frenzy`: hunts the nearest standing player, never loses track; the
  lockdown breaks open), the Echo's arrow points to the exit and stays on, and a HUD timer
  (`escape_time_calm` / `_challenge`). Timer at 0 = every player downed (`Cause.COLLAPSE`).
  `check_levels` requires each timer >= 1.6x the longest shard -> exit walk at 230 px/s.
- **Creatures** (`Creature`): WANDER / INVESTIGATE (pulses, sword noise, alerts) / CHASE /
  SEARCH. They path with a navigation mesh the `LevelBuilder` bakes from every rock (doorways,
  corners; the closed arena door is an obstacle until it opens). Chase speed = the chased
  player's `max_speed` x a ratio per mode (Calm 0.82-0.88, Challenge 0.95-1.0, the higher end
  at full Depth Awareness), so they are never clearly faster. Danger comes from the lunge
  (within ~120 px: 0.3 s telegraphed wind-up with flaring eyes + sound, burst, recovery).
  Losing sight: go where the player was heading and SEARCH there a few seconds. Entering
  CHASE alerts creatures within `alert_radius` (they INVESTIGATE towards it).
  **Navigation per size**: the normal mesh is baked for 26 px; creatures with
  `body_radius + navigation_margin` above that (the boss) path on a second map baked for
  52 px (`LevelBuilder.navigation_map_for`). Godot 4.7 logs harmless "edge error(s)" warnings
  for that second map on some levels. Near a lit coral, creatures slide around its safe zone
  (never steer into it; a wall flips the side) and a target inside the zone counts as reached.
  **Stuck watch** (`CreatureStuckWatch` on every creature): < 10 px in 0.75 s while it should
  move = stuck (logged when `log_enabled`); 2 windows = repath, 3 = nudge off the wall / onto
  the mesh. **F3** (`NavDebugDraw`) draws every creature's path, next point, target, state
  and a red ring while stuck.
- **Health** (`PlayerHealth`, in segments; `segment_count` per character, default 4): a
  creature touch costs `calm_hit_damage` (1.0) / `challenge_hit_damage` (1.5) segments, with
  knockback and a short invulnerability. A partly damaged segment refills on its own after
  ~4 s without damage; fully lost segments only come back through **partner mending**
  (`PartnerMending`: both within 150 px, nobody downed, no creature chasing either; one
  segment per 6 s Calm / 10 s Challenge, with a glowing link between them), an **Echo Shard**
  (+1 segment to every player not downed) or a revive (1 segment). Health carries over
  between the levels of a stage. HUD: `HealthSegments` per player; at 1 segment or less a
  heartbeat + red edge pulse (`HurtVignette`). At zero the player is downed.
- **Downed**: creatures ignore a downed player (no spotting, chase ends, no damage). A caught
  player can be revived by the partner; interrupted revive progress pauses
  (`decay_delay`, 1 s) then decays (20 %/s) instead of resetting (`ReviveHelper`). A downed
  Echo can send a **distress pulse** (`DistressPulse`: action button, 200 px, 4 s cooldown,
  no oxygen / awareness; reveals + Exposes creatures it reaches; its noise draws creatures within
  `noise_radius` to INVESTIGATE: Calm 0, Challenge 200 px). The Guardian's **close sense** (`CloseSense`, 90 px): creatures that close
  always show as a silhouette with clearly glowing eyes and are hittable with normal sword
  damage (only an Echo pulse makes them Exposed for the instant kill; the lunge flare is
  always visible). Per-mode values reach these via the `mode_listeners` group. If both are
  downed at the same time, it depends on the mode (main menu, changeable later):
  **Calm** = restart the current level (and the meter drains slower);
  **Challenge** = restart the current stage from level 1.
- **Save** (`user://save.json`, `SaveData`, version 2): current world, current stage, unlocked
  worlds, mode, the skills (`SkillLoadout` as owned at the end of the last completed stage).
  Settings (`user://settings.json`): language (English/Arabic), mode, brightness, one volume
  per audio bus (Options sliders).
- **Screens**: main menu (Continue if a save exists, New Game, Mode, Language, Options, Quit) →
  stage (`game.tscn`) → stage summary → next stage, or story screen → World Map.
- **Skills** (see "Skills" below): after every completed level both players pick at the same
  time (`SkillChoiceScreen`), then the next level starts.
- **Pause menu** (`PauseMenu`, `pause` action: Esc / Start on any gamepad, only while a level is
  played: `StageManager.can_pause`): pauses the whole tree (players, creatures, oxygen, the
  escape timer, stage time). Resume, Options (`OptionsPanel`, shared with the main menu),
  Restart level (`StageManager.restart_level`; Calm: the level again with the meters, health
  and skills of its start; Challenge: shown as "Restart stage", the whole stage from level 1
  like both downed, with its own confirmation text),
  Quit to World Map, Quit to Main Menu (the last three with a confirmation; quitting loses the
  stage's progress since the last save). Shows the mode and both players' skills (read-only).
  Navigated with the `ui_*` actions (keyboard + every gamepad).
- **Testing one stage**: run `game.tscn` on its own (F6). The `StageManager` then uses its
  `world`, `test_stage_index`, `test_mode` and `test_skills` (`"far_echo:2"`, `"shield"`...)
  exports and never writes the save.

## Skills
Data-driven: every skill is a `SkillDefinition` (.tres in `skills/<echo|guardian|shared>/`,
listed in `skills/skill_catalog.tres`, set on the `Game` autoload). Fields: `id` (saved, never
rename), `owner` (Echo / Guardian / Shared: each character owns their own copy), `category`
(core / pressure / world), `kind` (passive / active), `max_rank` (1-2), `values` (key -> one
value per rank), name / description / co-op tip in EN + AR, `available_from_world` (index in
`Game.world_ids`), `offer_weight`, icon (`SkillIcon.Shape` + colour, drawn in code).
- **Passive = stats.** Every `values` key is a stat the systems read through `PlayerSkills`
  (the `Skills` node on every player): `*_mult` keys multiply (product over owned skills),
  others add (`get_bonus`); creatures use `PlayerSkills.team_bonus`. Stats so far:
  `pulse_radius_mult` (PulseAbility), `pulse_cost_mult` / `pressure_drain_mult`
  (PlayerPressure), `exposed_time_add` / `mark_time_add` (Creature: Exposed longer, Echo Mark
  outline `EchoMarkOutline`; Exposed always counts as revealed), `sword_arc_mult`
  (SwordAbility), `close_sense_add` (CloseSense), `revive_time_mult` (the reviver's
  ReviveHelper), `mend_rate_mult` (own rate) / `mend_distance_mult` (best of both,
  PartnerMending), `shard_heal_add` (StageManager).
- **Active = a node.** `active_scene` (an `ActiveSkill`: `scenes/skills/`) is added to the
  player's UnlitLayer while owned; its numbers are `value(key)` from the definition, its look
  and sounds are its own exports. One active slot per character. Ocean: `LurePulseSkill`
  (decoy echo, creatures within `noise_radius` investigate, costs oxygen), `ShieldSkill`
  (hold; `hit_blockers` group: `PlayerHealth.take_hit` asks `blocks_hit`; repels the creature,
  slows him, no sword; protects the Echo behind him), `DashSkill` (burst + short
  invulnerability). Skill button: `p1_skill` (Left Shift / gamepad 1 X), `p2_skill`
  (Right Ctrl / gamepad 2 X): `Player.try_skill_pressed` / `is_skill_held`.
- **Aiming (twin-stick)**: `p1_aim_*` / `p2_aim_*` = the right stick of the player's own gamepad
  (device 0 / 1 only). `Player.uses_gamepad` follows the player's own last input (their gamepad
  device, or their own keys; never the partner's), `get_stick_aim()` (deadzone `aim_deadzone`),
  `get_aim_direction()` (stick, else move direction, else facing), `get_attack_direction()`
  (stick, else facing). Lure: gamepad = the button throws along the stick (she keeps moving);
  keyboard = hold to aim (`Player.move_locked`: she stops, the move keys aim), release to throw;
  dotted line + target circle while aiming. Shield: `shield_direction` set from the aim when
  raised, then locked; the right stick turns it at once, keyboard keys turn it at
  `keyboard_turn_speed` (240°/s) while he strafes slowly. Sword: each hit along
  `get_attack_direction()`, a faint tick while the stick aims; keyboard = facing.
- **Cooldown readability**: `SkillIcon.set_state` (also the Echo's pulse in the HUD,
  `setup_custom`): recharging = dimmed + desaturated, a dark radial fill, a thin progress ring;
  ready = full colour, glowing edge; becoming ready = a short flash. In the world a `ReadyCue`
  (ring out of the character + the soft `skill_ready` chime) plays once when an active skill or
  the pulse (`PulseAbility.ready_cue`, quieter) is ready again (`became_ready`). A hold skill
  without a cooldown (Shield) only lights up while held.
- **Offers** (`SkillOffer`, no UI): own + shared pool, available in this world, below max rank
  (higher ranks come back), weighted, no repeats; once an active is owned no active is
  offered, and one offer never holds two new actives; empty places get a fallback
  (`SkillCatalog.fallbacks`, e.g. `deep_breath` = full oxygen, applied once, not kept).
  Cards / picks per stage in `StageDefinition` (`skill_offer_count`, `skill_pick_count`,
  `boss_skill_*`; Ocean: stage 1 = 1 of 2, stages 2-3 = 1 of 3, 2 of 3 after a boss); none
  after the world's final level.
- **Screen** (`SkillChoiceScreen`): Echo left / Guardian right (not mirrored in Arabic, the text
  inside is), each with their own move up / down + action; both ready -> the picks + tips for
  `summary_time` (2 s).
- **Lifetime**: `StageManager.loadout` (a `SkillLoadout`: character -> {id: rank}); a Calm retry
  restores the skills of the level start, a Challenge retry those of the stage start; saved
  with every completed stage (`Game.complete_stage(loadout)`); cleared when the next world
  starts. HUD (`PlayerStatus`): the Echo's pulse and the active skill with their cooldown and
  button, small icons for the passives (rank dots).

### Adding a new skill
1. Only existing stats (e.g. another drain or radius bonus): duplicate a `.tres` in `skills/`,
   give it a new `id`, owner, ranks, `values`, texts (EN + AR), icon, `available_from_world`,
   and add it to `skills/skill_catalog.tres`. No code.
2. A new stat: read it where it matters with `PlayerSkills.of(player).get_multiplier("x_mult")`
   (or `get_bonus("x_add")`), list it in the `PlayerSkills` header, then step 1.
3. A new active skill: a script extending `ActiveSkill` (override `_update`, maybe
   `is_in_use`, `blocks_actions`, `_draw`), a scene in `scenes/skills/`, then step 1 with
   `kind` = active and `active_scene` set.
4. A world skill (only in one world): `category` = world, `available_from_world` = that world's
   index. A pressure skill that should read differently in a world (cold instead of oxygen):
   add a `SkillTextOverride` (skill id + texts) to that `WorldConfig.skill_text_overrides`.
5. Add checks to `tools/test_skills.gd` and run it.

The game will have 5 worlds, each with its own chunks, colours, creatures, survival pressure
and pulse behaviour. Only the Ocean exists so far.

Controls: P1 Echo = WASD + Space (pulse) + Left Shift (skill) or gamepad 1 (left stick, A, X,
right stick aims). P2 Guardian = arrow keys + Enter (attack) + Right Ctrl (skill) or gamepad 2
(left stick, A, X, right stick aims skills and sword). Holding the action button next to a downed
partner revives them. Esc / Start = pause.

## Audio
Everything is procedural (`tools/generate_sounds.py`, the `preview` section; no AI tools).
Sounds are found **by file name**, so a better recording with the same name (or an extra
numbered variant) replaces one without code changes.
- **Buses** (`default_bus_layout.tres`): Master, Music (a "Duck" amplify), SFX and Ambience
  (a "Gate" amplify + the world's underwater low-pass + reverb), UI. Volumes: `Game.volumes`
  (Options sliders, saved).
- **`AudioDirector`** (game.tscn): catalog of every .wav in `assets/audio/sfx|music|ambience`
  (`name_2.wav` = a variant of `name`), `play(name, position)` with random pitch / volume
  (`sound_settings` per sound), positional with a position (the `SharedCamera` has the
  `AudioListener2D`), bus from the prefix (sting/music -> Music, amb -> Ambience, else SFX),
  `make_loop_player`, `duck()`, `play_after_silence()` (the finisher's hit-stop silence), and
  `apply_world` (WorldConfig `audio_lowpass_hz`, `audio_reverb_*`).
- **`MusicDirector`**: layers looping in sync at 120 bpm (`music_tension/chase/intense/boss`),
  2 s crossfades, states CALM (ambience bed only) < TENSION (a creature investigating /
  searching / a light hunter stalking within 800 px) < CHASE < INTENSE (lockdown, collapse) <
  BOSS (door open and the boss awake or near); calmer only after `release_time` (3.5 s).
  Stingers: spotted, shard, lockdown, doors open, level complete (`StageManager.level_won`),
  player downed.
- **`AmbiencePlayer`**: the WorldConfig's bed loop + small one-shots (bubbles, around the
  camera, every 2-6 s) + a rare distant one (whales, 45-100 s).
- **`CreatureVoice`** (on every creature): idle clicks near players, investigate voice (basic =
  chitter, light hunter = call while stalking, Sentinel = creak, boss = its three layered
  voices), screech on a chase (one per 0.25 s for all creatures), hiss on the lunge, death.
  **`PlayerAudio`**: swishes while swimming, hurt, downed, revive. Also: sword whoosh per combo
  hit + impact (heavier on the finisher), pulse ping with echoes, distress ping, shard hum loop
  + chime, mending hum, low oxygen beep, low-health heartbeat, barrier close / open, collapse
  rumble + falling rocks, `skill_ready` (soft two-note chime: pulse / active skill ready).
- Loops carry a WAV "smpl" loop chunk (Godot: "Detect From WAV").
- Tools: `tools/sound_test.tscn` (every sound, the music crossfades, ambience),
  `tools/test_audio.tscn` (headless checks).

## Lighting (layers)
The pulse is the main way to read the layout from a distance; nothing else may make far
walls and corridors readable. Everything near is seen through **real lights**, never a mask.
1. **Ambient** (`Darkness`, a CanvasModulate): near-black deep blue, per stage in each
   `StageDefinition` (stage 1 brightest, stage 3 darkest; a little darker down a stage).
2. **Real lights** (with shadows: every rock has a LightOccluder2D):
   - The Echo's `PlayerLight` is the main light: warm, soft, ~280 px.
   - The Guardian's `PlayerLight` is tiny and faint (~70 px): he is almost blind and has to
     stay near the Echo to see.
   - Corals (when woken by the pulse) and the ancient light are local lights too.
   - Each `PlayerLight` has a raised copy (`top_light_raise`, `top_light_share`, no shadows)
     that only lights the rock tops (light layer `top_light_layer`): a top is drawn higher
     than its base, so without it the top gets less light than the floor in front of it and
     the rock reads as a pit.
   - Light textures are float (`use_hdr`) and debanding is on, so soft fades show no rings.
3. **Rock fill**: the floor colour lightened by `rock_fill_lift`; rock tops are clearly
   lighter (`RockWall.top_lift`) with grain, so floor and rock never look alike. The floor
   only gets subtle, low-contrast sand ripples and pebbles (`LevelBuilder` "Floor Detail",
   `SurfaceTextures.floor_detail`). Around the whole level the `LevelBuilder` draws solid
   "outer rock" (lighter by `outer_rock_lift`, like the tops; no collision/shadow/sonar), so
   the level edge fades into darkness instead of a hard black strip. The glowing sonar
   edges only come with a pulse.
   **Top falloff** (`TopLightFalloff`, created by the `LevelBuilder`): the rock tops, the
   outer rock and the landmark parts share one material that keeps their colour within
   `inner_share` of a light's radius and fades it to `far_brightness` at `outer_share`, so
   far rock never shows the layout. Lights count when in the `falloff_lights` group (player
   lights, lit corals, ancient light, stations, shards, landmark glows).
4. **Environment light**: marine snow (`MarineSnow`) everywhere; very faint light shafts
   (`LightShafts`, one smooth gradient each) where `StageDefinition.light_shaft_strength` > 0
   (first stage only).
5. **Area accents** (`AreaAccent`, over the floor at z -3, lit like the floor): one muted
   soft disc per room from `WorldConfig.area_accents` (teal / violet / blue, picked by cell
   and level), or the accent of a landmark in the room (amber at a vent, violet at the clam
   and anemones, teal at the coral tree).
6. **Brightness** (Options, 70-130 %): scales the ambient and the players' lights a little;
   the narrow range keeps far areas unreadable. The pulse and sonar are never affected.
7. **Creature visibility zones** (all outside them stay invisible, except the close-range
   eyes and pulse reveals):
   - within the Echo's `light_reveal_radius` (115 px): full body, hittable, can be Exposed;
   - from there to the edge of her light (~280 px): only a dark moving silhouette with faint
     eyes, fading in as it gets closer; no outline, not hittable, not Exposed; hidden when a
     rock blocks her light (`Creature` "Silhouette" group, `CreatureEyes.silhouette_eye_share`).
## Characters (procedural, silhouette + glow)
- **Echo** (`EchoVisual` on her `Body`): small dark body, long ears, Line2D antennae with
  glowing tips (springs), verlet tail with a faint gold particle trail, glowing gold core.
  Floats (bob, lean). Pulse: core flare, antennae lift, squash-stretch. Downed: core dims and
  flickers, body sinks.
- **Guardian** (`GuardianVisual`): tall dark cloak (spring hem), large branching antlers,
  faint cold blue rim, two faint eyes. Downed: kneels, antlers lower, eyes dim.
  `SwordAbility` draws the dark blade (gold edge only inside the Echo's light), the trailing
  slash arc, and gives a visual lunge per hit (`get_lunge_offset`); the finisher pulls back
  first and has a wider, brighter arc.
  Rest pose: the Guardian faces right or left (flips only when the horizontal input changes
  sign; straight up/down keeps it) and the sword hangs `rest_angle_degrees` (45) below
  horizontal on that side, blending over `rest_transition_time` (0.12 s) after a flip or a
  combo. Attacks still aim along `player.facing`.
- **Creatures** (`Creature.draw_shape`): fully revealed = dark body with a glowing outline in
  the type colour (= its sonar echo colour) plus tendrils / fins / spikes with procedural
  motion; the same shape is used for the silhouette zone and the pulse echo.
- Shared helpers: `SpringPoint`, `VerletChain`. Springs run relative to the player so
  movement only bends them by their drag term.

- **Hit flash** (`HurtVignette`): thin red band on the screen edges only, low opacity, 0.4 s.
Note: 2D renders in HDR (linear). Screenshots taken with `get_viewport().get_texture()` are
linear float data and look much darker than the screen; convert each pixel with
`Color.linear_to_srgb()` before saving (8-bit linear PNGs lose the dark detail).

## Landmarks and harmless life
- **Landmarks** (`Landmark` + one script per kind, scenes in `scenes/landmarks/<world>/`,
  placed by hand in `LevelDefinition.landmarks` as `LandmarkPlacement`s: cell + offset in
  the room, same spot every attempt, 1-3 per level, each level its own mix). Ocean: wreck,
  statue (orb = Ancient Light hint), whale skeleton, coral tree, vent, anemone field, broken
  arch, giant clam. Solid parts are `RockWall` bases (`get_footprints()` works before the
  tree, so validation, navigation and the ground shadows include them); decor parts
  (`add_part`) are y-sorted on their own base point; extra sonar lines (`add_sonar_line`,
  group `sonar_shapes`, the line of sight may pass through the landmark's own walls).
  Glow stays small and dim (optional weak light, dots on the level's `GlowLayer`).
  Never rotated as a node. `check_levels` checks count, unique mix, no kind twice in a
  stage, no two placements of a kind in the same room type + turn within 400 px, and the
  distance to rock / markers / doorways.
- **Variation per placement** (`LandmarkPlacement`: `mirrored`, `size_scale`,
  `floor_turn_degrees`, `damage`, `variant`, `accent_color`; `Landmark.configure`): mirror and
  size apply to everything (`variation()`); the floor turn, damage and variant are read by
  each kind (`rand(key)` mixes in the variant). Wreck: bow half tilted out of the sand
  (`RockWall.height_slope`), gap with frames, stern piece (gone when wrecked), bowsprit,
  fallen mast, barrels, cabin fragment, planks. Whale: big skull, bending spine, rib pairs
  arching out and curving back in (3D curves projected with `Landmark.project`), some
  broken / fallen, loose vertebrae, jaw. Columns (`LandmarkColumn`, statue + arch): fluted,
  chipped, cracked, leaning, capital or jagged broken top, fallen drums (collision only:
  `RockWall.draw_flat` false).
- **Harmless life** (`AmbientLife`: `FishSchool`, `Jellyfish`, `Crab`, `SeaPlant` kelp /
  anemone, scenes in `scenes/life/<world>/`, `WorldConfig.ambient_life` = `AmbientLifeSpawn`
  per kind and room, on open floor from the validator flood, with the seed). Fish scatter
  from players and pulses, crabs scuttle sideways, plants / anemones shrink on a pulse
  (`sonar_targets`), jellyfish flare. Never creature-like: no eyes, cool soft colours, no
  sounds, no collision, not in `creatures`; creatures ignore it and the music stays calm.
- **Room variation between levels** (`LevelBuilder`, picked by level + cell, the same on
  every attempt of a level): floor texture seed / ripple period, rock heights (another pick
  per rock and a room scale, `room_height_jitter`), the accent, and a `FloorScatter`
  (pebbles, stone clusters, shell fragments, dead coral bits on open floor).
- **Cost**: far from the camera they skip updates (`GlowLayer.near_camera`); slow motion
  redraws at `redraw_rate` (30/s); every moving shape goes through `ShapeBatch` (one
  `canvas_item_add_triangle_array` per draw, no per-shape triangulation or anti-aliasing:
  `draw_circle` / AA `draw_polyline` per frame cost far too much).

## 3/4 view (every Ocean room)
The world is tilted to match the characters, still 2D:
- **Rock height** (classic 3/4): each room has a range (`LevelChunk.rock_height_min` /
  `_max`, e.g. 32-72 px; both 0 = flat). The `LevelBuilder` gives each rock a middle
  `RockWall.height` in it (picked by the rock's position, `rock_middle_low` / `_high`) and a
  `height_spread` (`rock_height_spread` of the range): `RockWall.height_at(p)` rises and falls
  along the rock (`height_wave`), so long walls are no flat extrusion. Seals get the middle of
  their room's range. The polygon is the rock's **base**: collision, navigation and the
  occluder stay there, so players stop at the foot of the rock like at a wall.
  `build_faces` (called by the `LevelBuilder`, in global space so turned rooms stand upright)
  splits the base into short edges (`face_piece_length`) and draws the rock standing on it as
  `RockFace` pieces: the top (each base point raised by its height and drawn in by
  `top_inset`, except where the rock touches other rock, so the base is a little wider;
  lighter: `top_lift`; cut into vertical strips and cells with light patches
  (`top_variation`), plus scattered cracks, moss patches and barnacle clusters (`detail_*`,
  `moss_*`, `barnacle_*`) and a front face over every base edge that faces down at all
  (`face_min_facing`; darker towards the base, colour patches, broken strata, a few cracks,
  an irregular bottom edge, a rim light on top and a contact shadow on the floor). Tops and
  faces get a procedural rock grain with faint strata streaks (`grain_*`,
  `SurfaceTextures.rock_grain`, continuous across pieces). The base polygon is not drawn.
- **Ground shadow**: a soft dark band on the floor around every base (`ground_shadow_*`,
  wider and darker below the front face: `front_shadow_*`, z `ground_shadow_z_index`), so
  rocks sit on the floor; not where the rock touches other rock.
- **Doorways stay clear**: within `doorway_clear_distance` of every connected doorway corridor
  (`LevelBuilder`, `RockWall.clear_zones`) the rock drops to `doorway_rock_height`, so no top
  hides the opening or a player walking through it.
- **Occluder of a tall rock**: culled (`tall_occluder_culled`) so only the far edges cast a
  shadow and a light in front of the rock lights its top and face; open lines that skip base
  edges touching another rock (`occluder_join_margin`), so a seal and a wall light as one.
- **Sonar** outlines what the eye sees (`get_sonar_lines`): the outer silhouette of the drawn
  rock (top and faces merged: top outline, face sides, front base edge) plus the rim where a
  face meets the top, unless a face in front hides it. Never lines inside the shape (a
  concave rock's hidden edges), never the details on the top, and never within
  `sonar_side_margin` of other rock (another rock's base, the room's edge). Points every
  `sonar_point_spacing`; line of sight is checked on the base straight below each point
  (`get_sonar_sights`); except on the front base edge the ray may pass through the rock
  itself (seen from above). Sparks are small round glints. Flat rocks keep the base outline.
- **Draw order**: `Game`, `LevelBuilder`, `Level` and the chunks are y-sorted. z: floors /
  outer rock -4, `DropShadow` and the rocks' ground shadows -2, flat rocks -1, players,
  creatures, shards, corals and the `RockFace` pieces 0 (y-sorted). Each piece sits on the base
  under it, so whatever stands north of (behind) the rock is covered. Glow layers are drawn
  above the world, so the Echo's / Guardian's glow and creature eyes fade there
  (`RockFace.is_covered(point, sort_y)`, `behind_rock_hide`; the lunge flare always shows).
  `RockFace` keeps a lookup grid (`GRID_CELL`), so these tests only look at nearby pieces.
- **Occluded players** (`OccludedOutline` under each player's visual, players only): the
  parts of the outline a rock covers are drawn through it, soft and semi-transparent (Echo
  cyan, Guardian gold), from the visual's `get_outline_lines()`.
- **Rock outlines**: natural, irregular shapes with soft bumps (no spikes, no perfect
  circles); points on the room edge stay where they are. The bumps only cut into the rock
  (walls 0 to -9 px), so no corridor or spawn point got less room than in the original
  design. Seals get soft bumps on their room side
  (`LevelBuilder.seal_bump`). Lockdown barriers and the arena door stay flat (they fade).
- **Depth layers** (`RoomDepthLayers` in the room): dark swaying kelp / coral tips at its
  `Kelp*` / `Coral*` markers on an unlit CanvasLayer, bigger and faster than the world
  (`foreground_scale`). No background layer: dim ridges on the floor read as fake rocks.
- **Drop shadows** (`DropShadow` on every player and creature, all rooms): a soft ellipse a
  little below the body; a creature's follows `get_body_visibility()`.

## Rules
- **Godot 4 + GDScript only.** No C#, no GDExtension, no third-party addons unless agreed first.
- **Typed GDScript everywhere**: typed variables, parameters and return types
  (`var speed: float = 100.0`, `func foo(x: int) -> void:`). The project warns on untyped declarations.
- **Small, focused scripts**: one responsibility per script. Prefer signals over tight coupling.
- **File names in snake_case** (`player.gd`, `pulse_ring.tscn`). Class names in PascalCase via `class_name`.
- **All tunable values are `@export` variables** (speeds, durations, radii, colors, amounts). No magic numbers in logic.
- **Art style: "silhouette + glow".** In the dark world players only see dark silhouettes and
  glowing parts. There is no artist and no budget: every character / creature visual is built
  from vector shapes in Godot (Polygon2D, Line2D, `_draw()`, particles, lights) with procedural
  animation (springs, verlet chains, sine motion). **No AI-generated art in the game.**
  `assets/concepts/` is for mood reference only (never traced). Dark silhouettes are drawn in
  the world (lit by lights); glowing parts on a CanvasLayer with `follow_viewport_enabled`
  using HDR colours (energy > 1 blooms).
- **Terminology**: World > Stage > Level, everywhere (classes, files, signals, UI text).
  "Run" is not used any more.
- **All menu / screen text is bilingual** (English + Arabic): add new strings to
  `scripts/ui_text.gd` and read them with `Game.text(key)`. Arabic screens are laid out
  right-to-left (`Game.apply_direction`). The UI font is Tajawal (`assets/fonts/`, OFL),
  set as the project's custom font so Arabic renders everywhere.

## Folders
- `scenes/` — `.tscn` scenes (`main_menu`, `game`, `story_screen`, `world_map`, and
  `game_state.tscn` = the `Game` autoload)
- `scenes/chunks/<world>/` — the hand-made room chunks of each world (`room_*.tscn`)
- `scenes/landmarks/<world>/` — landmark set-pieces; `scenes/life/<world>/` — harmless life
- `scripts/` — `.gd` scripts
- `worlds/` — one `WorldConfig` resource (`.tres`) per world
- `worlds/<world>/` — the world's `LevelDefinition`s (`level_<stage>_<level>.tres`)
- `story/` — story text per world and language (`<world>_end_en.txt`, `<world>_end_ar.txt`;
  one line per line, empty lines skipped). Not a Godot resource: when exporting, add `*.txt`
  to the export preset's "non-resource files" filter.
- `assets/audio/` — procedural sounds (generated by `tools/generate_sounds.py`): `sfx/`,
  `music/` (layers + stingers), `ambience/`; older files directly in `assets/audio/`
  (all still used: sonar tick, station refill, ancient light, lockdown rumble, creature heartbeat)
- `assets/fonts/` — UI font (Tajawal, with its OFL licence)
- `assets/concepts/` — concept art references (not imported by Godot: has a `.gdignore`)
- `tools/` — helper scripts outside the game:
  - `generate_sounds.py` (Python)
  - `check_levels.gd`: checks every room alone (markers reachable, doorways open), every
    level's room graph (branches, loop, dead ends, lockdown position), validates every level
    (BFS) with many spawn seeds, reports the walking path start -> all shards -> exit, the
    balance (Sentinels, lockdown wave per mode, escape timer vs path), the landmarks and
    the harmless life, and checks the
    structure, lighting and the generator:
    `godot --headless --path . -s res://tools/check_levels.gd`
  - `test_save.gd`: save/load test (uses its own test files in `user://`), with the skills
    (round trip, old version 1 files, saved per stage, reset on a new world):
    `godot --headless --path . -s res://tools/test_save.gd`
  - `test_skills.tscn`: skills and pause, run as a scene: offer sizes per stage, offer rules
    (pools, ranks, active slot, worlds, fallback), a data-only skill, every Ocean skill's
    effect value, the choice flow, retries keeping the level / stage start skills, the pause
    menu freezing creatures / oxygen / escape timer and its Restart level (Calm / Challenge),
    aiming (device binding, Lure / Shield / sword with gamepad and keyboard) and the cooldown
    states (icon looks, ready flash, ReadyCue + chime, the pulse in the HUD):
    `godot --headless --path . --fixed-fps 60 res://tools/test_skills.tscn`
  - `test_creatures.tscn`: creature + shard test, run as a scene (needs the `Game` autoload):
    chase speeds per mode/awareness, lunge, alerting, search, downed Echo (ignored, distress
    pulse, close sense, revive decay), Sentinels, lockdown, collapse escape, pathing on every
    level (with and without navigation), shards, locked exit and arena door, landmarks
    (solid base, navigation around it) and harmless life (ignored, calm music, reactions):
    `godot --headless --path . --fixed-fps 60 res://tools/test_creatures.tscn`
  - `test_stuck.tscn`: creatures (normal + boss size) chase hopping players through every
    level, plus a normal-AI pass with pulses and lit corals; fails on any stuck >= 1.5 s
    (`-- log` prints every stuck window, `-- norecover` turns the safety net off):
    `godot --headless --path . --fixed-fps 60 res://tools/test_stuck.tscn`
  - `test_audio.tscn`: buses, volume settings, underwater filter, the sound catalog, hit-stop
    + ducking, music states and stingers, every creature type's voice, player / world /
    ambience sounds: `godot --headless --path . --fixed-fps 60 res://tools/test_audio.tscn`
  - `sound_test.tscn`: listen to every sound and the music crossfades (run it with F6)
  - `propose_level.gd`: **editor tool** (open it in the Script editor, File > Run) that
    proposes a new random room-grid `LevelDefinition` from the world's room pool, validates it
    and saves it as `worlds/<world>/proposed_<seed>.tres` to edit by hand.
  - Note: `-s` tools run without autoloads, so they must not load scripts that use `Game`.
- `skills/` — `SkillDefinition`s (`echo/`, `guardian/`, `shared/`, `fallback/`) and
  `skill_catalog.tres`; `scenes/skills/` — the active skill scenes
- `docs/` — design notes (e.g. `skills.md`: more skill ideas for later)

## Adding a new world
All world-specific values live in its `WorldConfig` (`scripts/world_config.gd`); scripts get
them through the `world_listeners` group (`apply_world(world)`), never hard-coded.
1. Build its rooms in `scenes/chunks/<world>/` (root script `LevelChunk`, see the contract at
   the top of `scripts/level_chunk.gd`): square rooms of `room_size` with a rock band
   (`room_wall_band`) and a centred doorway (`room_door_width`) on every side listed in
   `openings`. Give rooms clearly different shapes (open caverns, pillar fields, twisting
   tunnels, mazes, arenas, alcoves behind narrow gaps, dead ends with hidden spots) and a mix
   of doorway patterns (1 / 2 opposite / 2 corner / 3 / 4) so every grid shape can be built
   with quarter turns. Markers ("Spawns"): Player1/Player2 and Goal in every room, Shard* in
   interesting spots (dead ends, alcoves, niches), Creature*, Coral*, Station*. Boss arena
   rooms: `is_boss_arena`, one doorway, a Boss marker.
2. Design its 9 levels as room grids (`LevelDefinition` in `worlds/<world>/`, or start from
   `tools/propose_level.gd`): `RoomPlacement`s (cell, room, quarter turns), start / exit /
   lockdown cells, shard count (default 3, boss levels 2), creature types and counts, corals,
   stations, sentinels, the lockdown wave per mode, on each stage's level 2 the collapse escape
   (`escape_event` + timers), and on each stage's last level the boss (exit = a boss arena)
   and its health, and 1-3 landmarks (a mix no other level has). The lockdown room needs
   Creature markers (the wave wakes there).
   Every level needs branches, at least one loop and dead ends; shards go to different rooms
   (never the start or exit room), spread over the branches.
3. Duplicate `worlds/ocean.tres` as `worlds/<world>.tres` and set: `world_id` (must match
   `Game.world_ids`), 3 `StageDefinition`s with their 3 levels each and their lighting, the
   room pool and sizes (for the builder and the generator), `sentinel_scene`,
   `lockdown_creature_scene`, `lockdown_room_scene`, the audio (low-pass, reverb, ambience
   bed and one-shots), the palette and area accents, the ambient life, the pressure (name,
   drain, low warning, level refill, colour) and the pulse modifiers (radius, speed, cost).
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
