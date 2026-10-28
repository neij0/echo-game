class_name WorldConfig
extends Resource
## Everything that makes one world (Ocean, Caves, Forest, Desert, Snow) look
## and play differently. One .tres per world in worlds/. Scripts read these
## values (via the "world_listeners" group, see StageManager) instead of
## hard-coding anything world-specific.
## Structure: World -> 3 stages (StageDefinition) -> 3 levels each (LevelDefinition).

## Must match an entry of the Game autoload's world_ids (used by the save file,
## the World Map and the story file names).
@export var world_id: String = "ocean"
@export var world_name: String = "Ocean"

@export_group("Stages")
## The world's stages, in order. Each one lists its levels.
@export var stages: Array[StageDefinition] = []
@export var coral_scene: PackedScene
@export var station_scene: PackedScene
@export var goal_scene: PackedScene
## One Echo Shard (EchoShard), placed on the level's planned shard spots.
@export var shard_scene: PackedScene
## The sealed doorway of a boss arena (ShardDoor), opened by the shards.
@export var shard_door_scene: PackedScene
## The Sentinel that guards some of the shards (LevelDefinition.sentinels).
@export var sentinel_scene: PackedScene
## The creature type of the lockdown wave.
@export var lockdown_creature_scene: PackedScene
## The lockdown event (LockdownRoom), placed in each level's lockdown room.
@export var lockdown_room_scene: PackedScene

@export_group("Rooms")
## Size of every room chunk (a square, in pixels). All rooms of a world share it.
@export var room_size: float = 1600.0
## Rock band along each room's edges (pixels).
@export var room_wall_band: float = 100.0
## Width of a doorway, centred on a room side (pixels).
@export var room_door_width: float = 360.0
## How deep into the room a seal reaches (from the room edge, pixels): it must
## cover the doorway passage through the band.
@export var room_seal_depth: float = 190.0
## Room chunks (LevelChunk) the level generator tool (tools/propose_level.gd)
## picks from. The game itself only uses the rooms listed in each LevelDefinition.
@export var room_chunks: Array[PackedScene] = []
## Boss arena rooms for proposed boss levels.
@export var boss_arena_rooms: Array[PackedScene] = []

@export_group("Depth")
## Depth shown in the HUD at the top of the world's first level.
@export var surface_depth_m: float = 200.0
@export var meters_per_pixel: float = 0.1
## Extra depth added for every level (each level starts deeper).
@export var level_depth_step_m: float = 400.0

@export_group("Palette")
## The base darkness (ambient colour) is set per stage, in each StageDefinition.
@export var floor_color_shallow: Color = Color(0.2, 0.3, 0.36)
@export var floor_color_deep: Color = Color(0.15, 0.23, 0.29)
## Rock fill = the floor colour lightened by this much (0-1). Kept small, so
## walls only read as faint silhouettes near the players and not from a
## distance. The glowing sonar edges only come with a pulse.
@export_range(0.0, 1.0) var rock_fill_lift: float = 0.09
## Sonar colours (wave front and revealed edges).
@export var ring_color: Color = Color(0.4, 0.9, 1.0, 0.9)
@export var edge_color: Color = Color(0.45, 0.95, 1.0)

## Muted colour accents on the floor, one per room (AreaAccent; picked by the
## room's cell, alpha = strength), so rooms feel different while the palette
## stays dark. A landmark's own accent (e.g. amber near a vent) wins.
@export var area_accents: Array[Color] = []
@export var area_accent_radius: float = 760.0

@export_group("Ambient Life")
## Harmless life scattered over every level (fish schools, jellyfish, crabs,
## sea plants). Never creature-like; creatures and the music ignore it.
@export var ambient_life: Array[AmbientLifeSpawn] = []

@export_group("Marine Snow")
## Tiny glowing particles drifting across the whole level (around the camera).
@export var snow_count: int = 140
@export var snow_color: Color = Color(0.7, 0.9, 1.0)
## Opacity range of one particle (each one twinkles between the two).
@export_range(0.0, 1.0) var snow_alpha_min: float = 0.08
@export_range(0.0, 1.0) var snow_alpha_max: float = 0.35
@export var snow_size_min: float = 0.8
@export var snow_size_max: float = 2.2
## Slow downward drift in pixels per second (random per particle up to this).
@export var snow_fall_speed: float = 9.0
## Side-to-side sway in pixels, and its cycles per second.
@export var snow_sway_amount: float = 12.0
@export var snow_sway_speed: float = 0.12
## Twinkle cycles per second.
@export var snow_twinkle_speed: float = 0.25

@export_group("Light Shafts")
## Faint light from the surface. How strong they are is set per stage
## (StageDefinition.light_shaft_strength; only the first stage has them).
@export var shaft_color: Color = Color(0.55, 0.8, 0.95)
## Opacity of a shaft at full strength (they are added on top, so keep it low).
@export_range(0.0, 1.0) var shaft_alpha: float = 0.025
@export var shaft_count: int = 5
@export var shaft_width_min: float = 60.0
@export var shaft_width_max: float = 170.0
## Tilt of the shafts in degrees (0 = straight down the screen).
@export var shaft_angle_degrees: float = 18.0
## Slow sideways sway of each shaft in pixels, and its cycles per second.
@export var shaft_sway_amount: float = 40.0
@export var shaft_sway_speed: float = 0.05
## How much the shafts slide when the camera moves sideways (0 = fixed on
## screen, 1 = fixed in the world). Small values feel far away.
@export var shaft_parallax: float = 0.15
## 0-1: how much the shafts fade from the top of the stage to its bottom.
@export_range(0.0, 1.0) var shaft_depth_fade: float = 0.7

@export_group("Pressure")
## What the world's survival pressure is called in the HUD (Oxygen, Cold, Heat...).
@export var pressure_name: String = "Oxygen"
## Seconds a full meter lasts without using abilities.
@export var pressure_drain_seconds: float = 180.0
## 0-1: below this the low warning (HUD + alarm) is on.
@export_range(0.0, 1.0) var pressure_low_threshold: float = 0.25
## 0-1: share of a full meter added to each player at the start of every level
## after the first one of a stage (the meter carries over between levels).
@export_range(0.0, 1.0) var pressure_level_refill: float = 0.4
@export var pressure_color: Color = Color(0.35, 0.8, 1.0)

@export_group("Audio")
## The world's "air": a low-pass and a reverb on the SFX and Ambience buses
## (AudioDirector). Underwater = muffled highs and a big soft space.
@export var audio_lowpass_hz: float = 5200.0
@export_range(0.0, 1.0) var audio_reverb_room_size: float = 0.75
@export_range(0.0, 1.0) var audio_reverb_damping: float = 0.65
@export_range(0.0, 1.0) var audio_reverb_wet: float = 0.22
@export_range(0.0, 1.0) var audio_reverb_dry: float = 1.0
## The ambience bed loop (AmbiencePlayer) and its random one-shots: sound names
## of the AudioDirector's catalog (variants _1, _2... are picked at random).
@export var ambience_bed: AudioStream
@export var ambience_bed_volume_db: float = -6.0
@export var ambience_small_one_shot: String = "amb_bubbles"
@export var ambience_small_interval_min: float = 2.0
@export var ambience_small_interval_max: float = 6.0
@export var ambience_small_volume_min_db: float = -16.0
@export var ambience_small_volume_max_db: float = -8.0
## Rare, distant one-shot (whale groans in the Ocean).
@export var ambience_rare_one_shot: String = "amb_whale"
@export var ambience_rare_interval_min: float = 45.0
@export var ambience_rare_interval_max: float = 100.0
@export var ambience_rare_volume_min_db: float = -10.0
@export var ambience_rare_volume_max_db: float = -4.0

@export_group("Pulse")
## Echo pulse in this world.
@export var pulse_radius: float = 650.0
## Seconds for the pulse front to reach pulse_radius (lower = faster).
@export var pulse_expand_time: float = 0.8
## 0-1: share of a full pressure meter each pulse costs.
@export_range(0.0, 1.0) var pulse_cost_ratio: float = 0.03


func get_stage_count() -> int:
	return stages.size()


## The stage (0-based). Uses the last entry if there are fewer.
func get_stage(stage_index: int) -> StageDefinition:
	return stages[clampi(stage_index, 0, stages.size() - 1)]


func get_level_count(stage_index: int) -> int:
	return get_stage(stage_index).get_level_count()


func get_level(stage_index: int, level_index: int) -> LevelDefinition:
	var stage: StageDefinition = get_stage(stage_index)
	return stage.levels[clampi(level_index, 0, stage.levels.size() - 1)]


## Index of a level counted from the world's very first level (for depth).
func get_global_level_index(stage_index: int, level_index: int) -> int:
	var total: int = 0
	for i: int in clampi(stage_index, 0, stages.size()):
		total += stages[i].get_level_count()
	return total + level_index
