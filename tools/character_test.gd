class_name CharacterTest
extends CoreTest
## Phase C silhouette test (run with F6): the core test stage (three real
## Ocean rooms, the real game camera, darkness, the pulse) with the players
## wearing the BLOCKOUT character models instead of the capsules, to choose a
## silhouette for the Echo and the Guardian. Blockouts are placeholders, not
## final art (tools/blender/make_character_blockouts.py).
## Both start in their final blockout (the variants merged after the first
## review), with the basic animations (idle, swim / walk, pulse pose, sword
## swing). Keys: E = the hand-made final Echo (characters/final/echo.glb,
## static: no rig yet), 7 = the Echo's final blockout, 1 / 2 / 3 = her first
## variants (Leaf, Comet, Bell); 9 = the final Echo's size (final_scales, the
## model only: her collision stays); 8 = the Guardian's final blockout, 4 / 5 / 6 = his first variants
## (Stag, Spire, Bulwark); 0 = the capsules again, L = studio light
## (to look at the shapes), Z = close view / game distance, plus the keys of
## the core test (F creatures, C cut-away, R restart...). The creatures start
## frozen and hidden.
## "-- pictures <folder>" saves pictures of every variant (CharacterTestShots);
## "-- pictures <folder> final" only those of the hand-made final Echo.

const ECHO_BLOCKOUT: PackedScene = preload("res://scenes/characters/echo_blockout.tscn")
const GUARDIAN_BLOCKOUT: PackedScene = preload("res://scenes/characters/guardian_blockout.tscn")
const ECHO_FINAL: PackedScene = preload("res://scenes/characters/echo_final.tscn")
const MODEL_PATH: String = "res://assets/models/characters/blockout/%s%s.glb"
## Variants 0-2 = the first three, FINAL = the merged blockout.
const FILES: Array[String] = ["_blockout_a", "_blockout_b", "_blockout_c", "_blockout"]
const VARIANTS: Array[String] = ["a", "b", "c", "final"]
const ECHO_NAMES: Array[String] = ["Leaf", "Comet", "Bell", "blockout"]
const GUARDIAN_NAMES: Array[String] = ["Stag", "Spire", "Bulwark", "blockout"]
const FINAL: int = 3
## The Echo only: the hand-made final model.
const HAND: int = 4

## The variant each player starts in (0-2, FINAL, the Echo also HAND; -1 =
## the capsule).
@export_range(-1, 4) var echo_variant: int = 3
@export_range(-1, 3) var guardian_variant: int = 3
## Key 9: the sizes tried for the hand-made final Echo (1 = as modelled).
@export var final_scales: Array[float] = [1.0, 1.15, 1.3]
## Freeze and hide the creatures at the start.
@export var calm_start: bool = true

@export_group("Studio")
## Key L: the ambient light and the sun used to look at the shapes.
@export var studio_ambient: float = 0.55
@export var studio_sun: float = 1.1
## Key Z: the camera's view height (units) in the close view.
@export var close_size: float = 6.0

var echo_model: CharacterModel
var echo_final_model: CharacterModel
var final_scale_index: int = 0
var guardian_model: CharacterModel
var darkness: Darkness
var studio_light: bool = false
var close_view: bool = false
var _sun: DirectionalLight3D
var _ambient_before: float = 0.0
var _fog_before: bool = false
var _min_size: float = 0.0
var _max_size: float = 0.0


func _ready() -> void:
	super._ready()
	darkness = get_node("Darkness") as Darkness
	_min_size = camera.min_size
	_max_size = camera.max_size
	if calm_start:
		set_creatures_frozen(true)
	echo_model = _wear(echo, ECHO_BLOCKOUT)
	echo_final_model = _wear(echo, ECHO_FINAL)
	guardian_model = _wear(guardian, GUARDIAN_BLOCKOUT)
	set_variants(echo_variant, guardian_variant)
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() >= 2 and arguments[0] == "pictures":
		var shots := CharacterTestShots.new()
		shots.test = self
		shots.folder = arguments[1]
		shots.with_variants = arguments.has("variants")
		shots.final_only = arguments.has("final")
		add_child(shots)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		match key.physical_keycode:
			KEY_1, KEY_2, KEY_3:
				set_variants(key.physical_keycode - KEY_1, guardian_variant)
				return
			KEY_4, KEY_5, KEY_6:
				set_variants(echo_variant, key.physical_keycode - KEY_4)
				return
			KEY_7:
				set_variants(FINAL, guardian_variant)
				return
			KEY_E:
				set_variants(HAND, guardian_variant)
				return
			KEY_9:
				set_final_scale((final_scale_index + 1) % final_scales.size())
				return
			KEY_8:
				set_variants(echo_variant, FINAL)
				return
			KEY_0:
				set_variants(-1, -1)
				return
			KEY_L:
				set_studio_light(not studio_light)
				return
			KEY_Z:
				set_close_view(not close_view)
				return
	super._unhandled_input(event)


func _process(delta: float) -> void:
	super._process(delta)
	_info.text += "\nBLOCKOUTS (placeholders)   [E / 7 / 1-3] Echo: %s   [9] final Echo size: %.2f   [8 / 4-6] Guardian: %s   [0] capsules   [L] studio light: %s   [Z] view: %s" % [
		_variant_name(echo_variant, ECHO_NAMES), echo_final_model.model_scale, _variant_name(guardian_variant, GUARDIAN_NAMES),
		"ON" if studio_light else "off", "CLOSE" if close_view else "game"]


## The model scene of a character's variant ("echo" / "guardian", 0-2).
static func model_of(character: String, variant: int) -> PackedScene:
	return load(MODEL_PATH % [character, FILES[variant]]) as PackedScene



## The hand-made final Echo's size: final_scales[index].
func set_final_scale(index: int) -> void:
	final_scale_index = index
	echo_final_model.model_scale = final_scales[index]


## The variant each player wears (0-2; -1 = the capsule of the game).
func set_variants(echo_index: int, guardian_index: int) -> void:
	echo_variant = echo_index
	guardian_variant = guardian_index
	_show(echo, echo_model, "echo", -1 if echo_index == HAND else echo_index)
	echo_final_model.visible = echo_index == HAND
	if echo_index == HAND:
		(echo.get_node("Body") as Node3D).visible = false
	_show(guardian, guardian_model, "guardian", guardian_index)
	# The model carries its own sword: the sword ability's stand-in blade is
	# hidden (its slash arc and hits stay).
	var blade := guardian.get_node_or_null("Sword/BladeHolder") as Node3D
	if blade:
		blade.visible = guardian_index < 0


## Lights up (to judge the shapes) or the game's darkness.
func set_studio_light(on: bool) -> void:
	if on == studio_light:
		return
	studio_light = on
	if on:
		_ambient_before = darkness.ambient_energy
		_fog_before = darkness.environment.volumetric_fog_enabled
		darkness.ambient_energy = studio_ambient
		darkness.environment.volumetric_fog_enabled = false
		_sun = DirectionalLight3D.new()
		_sun.rotation_degrees = Vector3(-52.0, 25.0, 0.0)
		_sun.light_energy = studio_sun
		_sun.shadow_enabled = true
		add_child(_sun)
	else:
		darkness.ambient_energy = _ambient_before
		darkness.environment.volumetric_fog_enabled = _fog_before
		_sun.queue_free()
		_sun = null


## The camera close to the players, or at the game's distance. size: the
## view height of the close view (0 = close_size).
func set_close_view(on: bool, size: float = 0.0) -> void:
	close_view = on
	var view: float = size if size > 0.0 else close_size
	camera.min_size = view if on else _min_size
	camera.max_size = view if on else _max_size
	camera.size = camera.min_size


func _wear(player: Player, scene: PackedScene) -> CharacterModel:
	var model := scene.instantiate() as CharacterModel
	model.player = player
	player.add_child(model)
	return model


func _show(player: Player, model: CharacterModel, character: String, variant: int) -> void:
	(player.get_node("Body") as Node3D).visible = variant < 0
	model.visible = variant >= 0
	if variant >= 0:
		model.set_model(model_of(character, variant))


func _variant_name(variant: int, names: Array[String]) -> String:
	if variant == HAND:
		return "FINAL (hand-made)"
	return "capsule" if variant < 0 else "%s (%s)" % [VARIANTS[variant].to_upper(), names[variant]]
