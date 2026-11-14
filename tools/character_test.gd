class_name CharacterTest
extends CoreTest
## Phase C silhouette test (run with F6): the core test stage (three real
## Ocean rooms, the real game camera, darkness, the pulse) with the players
## wearing the BLOCKOUT character models instead of the capsules, to choose a
## silhouette for the Echo and the Guardian. Blockouts are placeholders, not
## final art (tools/blender/make_character_blockouts.py).
## Keys: 1 / 2 / 3 = the Echo's variant (Leaf, Comet, Bell), 4 / 5 / 6 = the
## Guardian's (Stag, Spire, Bulwark), 0 = the capsules again, L = studio light
## (to look at the shapes), Z = close view / game distance, plus the keys of
## the core test (F creatures, C cut-away, R restart...). The creatures start
## frozen and hidden.
## "-- pictures <folder>" saves pictures of every variant (CharacterTestShots).

const ECHO_BLOCKOUT: PackedScene = preload("res://scenes/characters/echo_blockout.tscn")
const GUARDIAN_BLOCKOUT: PackedScene = preload("res://scenes/characters/guardian_blockout.tscn")
const MODEL_PATH: String = "res://assets/models/characters/blockout/%s_blockout_%s.glb"
const VARIANTS: Array[String] = ["a", "b", "c"]
const ECHO_NAMES: Array[String] = ["Leaf", "Comet", "Bell"]
const GUARDIAN_NAMES: Array[String] = ["Stag", "Spire", "Bulwark"]

## The variant each player starts in (0-2; -1 = the capsule).
@export_range(-1, 2) var echo_variant: int = 0
@export_range(-1, 2) var guardian_variant: int = 0
## Freeze and hide the creatures at the start.
@export var calm_start: bool = true

@export_group("Studio")
## Key L: the ambient light and the sun used to look at the shapes.
@export var studio_ambient: float = 0.55
@export var studio_sun: float = 1.1
## Key Z: the camera's view height (units) in the close view.
@export var close_size: float = 6.0

var echo_model: CharacterModel
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
	guardian_model = _wear(guardian, GUARDIAN_BLOCKOUT)
	set_variants(echo_variant, guardian_variant)
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() >= 2 and arguments[0] == "pictures":
		var shots := CharacterTestShots.new()
		shots.test = self
		shots.folder = arguments[1]
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
	_info.text += "\nBLOCKOUTS (placeholders)   [1-3] Echo: %s   [4-6] Guardian: %s   [0] capsules   [L] studio light: %s   [Z] view: %s" % [
		_variant_name(echo_variant, ECHO_NAMES), _variant_name(guardian_variant, GUARDIAN_NAMES),
		"ON" if studio_light else "off", "CLOSE" if close_view else "game"]


## The model scene of a character's variant ("echo" / "guardian", 0-2).
static func model_of(character: String, variant: int) -> PackedScene:
	return load(MODEL_PATH % [character, VARIANTS[variant]]) as PackedScene


## The variant each player wears (0-2; -1 = the capsule of the game).
func set_variants(echo_index: int, guardian_index: int) -> void:
	echo_variant = echo_index
	guardian_variant = guardian_index
	_show(echo, echo_model, "echo", echo_index)
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
	return "capsule" if variant < 0 else "%s (%s)" % [VARIANTS[variant].to_upper(), names[variant]]
