class_name LevelTest
extends Node3D
## Phase B play-test stage (run with F6): the real Ocean levels built in 3D by
## the LevelBuilder, with the real players, creatures (basic, unkillable,
## light hunter, Sentinel), corals, oxygen stations, Echo Shards and the
## ancient light, the HUD's player blocks (health + oxygen), the sand trails,
## the sonar, the darkness and the audio. The level flow is a stand-in for
## the StageManager (next step): collect every shard, wake the ancient light,
## the next level starts; both players down = the level again (new seed).
## Oxygen drains as in the game (stations refill it; a new level tops it up to
## the world's level refill). Health and oxygen carry over between levels.
## Not yet: lockdown, collapse escape, bosses (a boss level ends at an ancient
## light in its arena), skills, harmless life, landmarks' looks.
## Keys: N / P = next / previous level, 1-9 = level 1-9 of the world,
## R = this level again (new seed), M = Calm / Challenge, F = freeze and hide
## every creature, T = sand trails on / off, C = cut-away on / off,
## I = physics interpolation on / off, O = oxygen drain on / off,
## L = the near ambient (faint deep-blue fill round the players) on / off,
## B = Brightness option 70 / 100 / 130 %.
## "-- shots <folder> [level number] [pictures]" saves pictures and runs the
## FPS benchmark on the largest level (LevelTestShots; "pictures" = no
## benchmark).

const ECHO_SCENE: PackedScene = preload("res://scenes/echo.tscn")
const GUARDIAN_SCENE: PackedScene = preload("res://scenes/guardian.tscn")
const PING_STREAM: AudioStream = preload("res://assets/audio/sfx/pulse_ping.wav")
const TICK_STREAM: AudioStream = preload("res://assets/audio/sonar_tick.wav")
## The groups a frozen creature leaves (key F).
const FROZEN_GROUPS: Array[String] = ["creatures", "sonar_targets", "cutaway_targets"]

## Loaded when the scene starts (not preloaded: the world still references
## scenes whose scripts are in legacy2d/, which print load errors).
@export var world: WorldConfig
@export_file("*.tres") var world_path: String = "res://worlds/ocean.tres"
## Where F6 starts (0-based).
@export var stage_index: int = 0
@export var level_index: int = 0
@export var challenge_mode: bool = false
## -1 = a new spawn seed on every build.
@export var forced_seed: int = -1
## Seconds after the ancient light wakes before the next level starts.
@export var next_level_delay: float = 2.5
## Seconds after both players are down before the level starts again.
@export var retry_delay: float = 2.0

var sonar: Sonar
var camera: SharedCamera
var cutaway: ViewCutaway
var awareness: DepthAwareness
var mending: PartnerMending
var trails: SandTrails
var darkness: Darkness
var builder: LevelBuilder
var echo: Player
var guardian: Player
var shards_collected: int = 0
var shards_total: int = 0
var creatures_frozen: bool = false
var oxygen_drain: bool = true
var levels_built: int = 0
var _frozen: Array[Creature] = []
var _cut_radius: float = 0.0
var _info: Label
var _hud: Control
var _pending: String = ""
var _pending_left: float = 0.0
## Health and oxygen at the start of the level (a retry restores them).
var _start_state: Array[Vector2] = []


func _ready() -> void:
	if world == null:
		world = load(world_path) as WorldConfig
	darkness = _add(Darkness.new(), "Darkness") as Darkness
	_add(AudioDirector.new(), "AudioDirector")
	awareness = _add(DepthAwareness.new(), "DepthAwareness") as DepthAwareness
	sonar = _add(Sonar.new(), "Sonar") as Sonar
	var sonar_audio := SonarAudio.new()
	sonar_audio.sonar = sonar
	sonar_audio.ping_stream = PING_STREAM
	sonar_audio.tick_stream = TICK_STREAM
	_add(sonar_audio, "SonarAudio")
	camera = _add(SharedCamera.new(), "SharedCamera") as SharedCamera
	cutaway = _add(ViewCutaway.new(), "ViewCutaway") as ViewCutaway
	_cut_radius = cutaway.radius
	_add(MarineSnow.new(), "MarineSnow")
	trails = _add(SandTrails.new(), "SandTrails") as SandTrails
	mending = _add(PartnerMending.new(), "PartnerMending") as PartnerMending
	builder = LevelBuilder.new()
	builder.world = world
	builder.forced_seed = forced_seed
	_add(builder, "LevelBuilder")
	_build_players()
	_build_hud()
	_build_info()
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() >= 2 and arguments[0] == "shots":
		var shots := LevelTestShots.new()
		shots.test = self
		shots.folder = arguments[1]
		if arguments.size() >= 3:
			shots.bench_level = int(arguments[2]) - 1
		shots.benchmark = not arguments.has("pictures")
		add_child(shots)
		return
	start_level(stage_index, level_index)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_N:
			_step_level(1)
		KEY_P:
			_step_level(-1)
		KEY_R:
			retry_level()
		KEY_M:
			set_challenge_mode(not challenge_mode)
		KEY_F:
			set_creatures_frozen(not creatures_frozen)
		KEY_T:
			trails.enabled = not trails.enabled
		KEY_C:
			cutaway.radius = _cut_radius if cutaway.radius <= 0.0 else 0.0
		KEY_I:
			get_tree().physics_interpolation = not get_tree().physics_interpolation
		KEY_L:
			darkness.near_enabled = not darkness.near_enabled
		KEY_B:
			_cycle_brightness()
		KEY_O:
			oxygen_drain = not oxygen_drain
			for player: Player in [echo, guardian]:
				player.pressure.drain_scale = 1.0 if oxygen_drain else 0.0
		_:
			var number: int = key.physical_keycode - KEY_1
			if number >= 0 and number < 9:
				start_level(number / 3, number % 3)


## The Brightness option: 70 % -> 100 % -> 130 % -> 70 %.
func _cycle_brightness() -> void:
	var game := get_node_or_null("/root/Game") as GameState
	if game == null:
		return
	var steps: Array[float] = [game.min_brightness, 1.0, game.max_brightness]
	var next: int = 0
	for i: int in steps.size():
		if absf(game.brightness - steps[i]) < 0.01:
			next = (i + 1) % steps.size()
	game.set_brightness(steps[next])


## Builds a level of the world and puts the players on its start.
func start_level(stage: int, level: int, is_retry: bool = false) -> bool:
	stage = clampi(stage, 0, world.get_stage_count() - 1)
	level = clampi(level, 0, world.get_level_count(stage) - 1)
	var definition: LevelDefinition = world.get_level(stage, level)
	if definition == null:
		return false
	stage_index = stage
	level_index = level
	_pending = ""
	var frozen: bool = creatures_frozen
	set_creatures_frozen(false)
	if not builder.build_level(definition, level, world.get_level_count(stage), world.get_global_level_index(stage, level)):
		return false
	levels_built += 1
	darkness.apply_stage(world.get_stage(stage))
	get_tree().call_group("world_listeners", "apply_world", world)
	awareness.reset()
	for player: Player in [echo, guardian]:
		var spawn: Vector3 = builder.get_spawn_position(player.player_number)
		player.global_position = spawn
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
		if player.health.is_downed:
			player.health.revive()
		player.pressure.drain_scale = 1.0 if oxygen_drain else 0.0
	if is_retry and _start_state.size() == 2:
		for i: int in 2:
			var player: Player = [echo, guardian][i]
			player.health.set_segments(_start_state[i].x)
			player.pressure.value = _start_state[i].y
	else:
		for player: Player in [echo, guardian]:
			player.pressure.ensure_ratio(world.pressure_level_refill)
	_start_state = [Vector2(echo.health.value, echo.pressure.value), Vector2(guardian.health.value, guardian.pressure.value)]
	camera.snap_to_players()
	shards_collected = 0
	shards_total = builder.get_shards().size()
	for shard: EchoShard in builder.get_shards():
		shard.collected.connect(_on_shard_collected)
	var goal: AncientLight = builder.get_goal()
	if goal:
		goal.set_shard_progress(0, shards_total)
		goal.activated.connect(_on_goal_activated)
	set_challenge_mode(challenge_mode)
	if frozen:
		set_creatures_frozen.call_deferred(true)
	return true


func retry_level() -> void:
	start_level(stage_index, level_index, true)


func _step_level(step: int) -> void:
	var number: int = world.get_global_level_index(stage_index, level_index) + step
	var count: int = 0
	for stage: int in world.get_stage_count():
		count += world.get_level_count(stage)
	number = posmod(number, count)
	start_level(number / 3, number % 3)


func set_challenge_mode(enabled: bool) -> void:
	challenge_mode = enabled
	get_tree().call_group("mode_listeners", "set_challenge_mode", enabled)
	get_tree().call_group("creatures", "set_challenge_mode", enabled)
	for player: Player in [echo, guardian]:
		player.health.set_challenge_mode(enabled)


## Freezes and hides every creature (it forgets the players and leaves its
## groups, so mending, the sonar and the music ignore it), or brings them back.
func set_creatures_frozen(frozen: bool) -> void:
	creatures_frozen = frozen
	if frozen:
		for node: Node in get_tree().get_nodes_in_group("creatures"):
			_freeze(node as Creature)
		return
	for creature: Creature in _frozen:
		if not is_instance_valid(creature):
			continue
		for group: String in FROZEN_GROUPS:
			creature.add_to_group(group)
		creature.visible = true
		creature.process_mode = Node.PROCESS_MODE_INHERIT
		creature.reset_physics_interpolation()
	_frozen.clear()


func _freeze(creature: Creature) -> void:
	if creature == null:
		return
	creature.forget_players()
	creature.velocity = Vector3.ZERO
	for group: String in FROZEN_GROUPS:
		creature.remove_from_group(group)
	creature.visible = false
	creature.process_mode = Node.PROCESS_MODE_DISABLED
	for child: Node in creature.find_children("*", "AudioStreamPlayer3D", true, false):
		(child as AudioStreamPlayer3D).stream_paused = true
	_frozen.append(creature)


func _on_shard_collected(_shard: EchoShard) -> void:
	shards_collected += 1
	# A shard heals every player who is not downed by one segment (the game's rule).
	for player: Player in [echo, guardian]:
		if not player.health.is_downed:
			player.health.heal(1.0)
	var goal: AncientLight = builder.get_goal()
	if goal:
		goal.set_shard_progress(shards_collected, shards_total)


func _on_goal_activated() -> void:
	_pending = "next"
	_pending_left = next_level_delay


func _process(delta: float) -> void:
	if _pending != "":
		_pending_left -= delta
		if _pending_left <= 0.0:
			var what: String = _pending
			_pending = ""
			if what == "next":
				_step_level(1)
			else:
				retry_level()
	elif echo.health.is_downed and guardian.health.is_downed:
		_pending = "retry"
		_pending_left = retry_delay
	_info.text = _info_text()


func _on_pulse_emitted(origin: Vector3, player: Player) -> void:
	awareness.add_pulse()
	get_tree().call_group("creatures", "hear_pulse", origin, player)


func _info_text() -> String:
	var states: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("creatures"):
		var creature := node as Creature
		if creature:
			var state_name: String = Creature.State.keys()[creature.state].to_lower()
			states[state_name] = int(states.get(state_name, 0)) + 1
	var state_text := PackedStringArray()
	for state_name: String in states:
		state_text.append("%s %d" % [state_name, states[state_name]])
	var lines := PackedStringArray()
	lines.append("LEVEL TEST   %d FPS   stage %d level %d (world level %d)%s   %s   seed %d   build %.2f s (navigation %.2f s)" % [
		Engine.get_frames_per_second(), stage_index + 1, level_index + 1, world.get_global_level_index(stage_index, level_index) + 1,
		"  boss level: ends at a light in the arena" if world.get_level(stage_index, level_index).is_boss_level() else "",
		"Challenge" if challenge_mode else "Calm", builder.spawn_seed, builder.build_seconds, builder.bake_seconds])
	lines.append("shards %d / %d   awareness %d%%   creatures: %s%s" % [shards_collected, shards_total,
		roundi(awareness.get_ratio() * 100.0), "frozen" if creatures_frozen else ", ".join(state_text),
		"   MENDING" if mending.is_mending else ""])
	lines.append("[N/P] level  [1-9] jump  [R] again  [M] mode  [F] creatures %s  [T] trails %s  [C] cut-away %s  [I] interpolation %s  [O] oxygen drain %s" % [
		"FROZEN" if creatures_frozen else "on", "on" if trails.enabled else "OFF", "on" if cutaway.radius > 0.0 else "OFF",
		"on" if get_tree().physics_interpolation else "OFF", "on" if oxygen_drain else "OFF"])
	var game := get_node_or_null("/root/Game") as GameState
	lines.append("[L] near ambient %s  [B] brightness %d%%" % ["on" if darkness.near_enabled else "OFF",
		roundi((game.brightness if game else 1.0) * 100.0)])
	return "\n".join(lines)


func _build_players() -> void:
	echo = ECHO_SCENE.instantiate() as Player
	add_child(echo)
	guardian = GUARDIAN_SCENE.instantiate() as Player
	add_child(guardian)
	for player: Player in [echo, guardian]:
		player.pulse_emitted.connect(_on_pulse_emitted.bind(player))


## The HUD's player blocks (health + oxygen; the full Hud comes with the
## StageManager): the Echo top left, the Guardian top right.
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Hud"
	add_child(layer)
	_hud = MarginContainer.new()
	_hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hud.theme = Game.ui_theme
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		_hud.add_theme_constant_override("margin_" + side, 28)
	_hud.add_theme_constant_override("margin_top", 20)
	layer.add_child(_hud)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(row)
	for player: Player in [echo, guardian]:
		var status := PlayerStatus.new()
		status.setup(player, builder, world)
		row.add_child(status)
		if player == echo:
			var spacer := Control.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(spacer)


func _build_info() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Info"
	add_child(layer)
	_info = Label.new()
	_info.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_info.position = Vector2(16.0, -12.0)
	_info.add_theme_font_size_override("font_size", 13)
	_info.modulate = Color(0.6, 0.8, 0.9, 0.7)
	layer.add_child(_info)


func _add(node: Node, node_name: String) -> Node:
	node.name = node_name
	add_child(node)
	return node
