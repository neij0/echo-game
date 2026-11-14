class_name LookdevRoom
extends LevelTest
## Phase C look-dev room (run with F6): the level test, started in the world's
## natural look (WorldConfig.look: real sand and rock textures, walls dressed
## with the rock kit, ripples, sparkle, strata, cracks, moss, barnacles, depth
## tint, silt haze) with the creatures frozen and the oxygen drain off, so one
## room can be looked at calmly and tuned. Every look value is a parameter of
## the two materials in worlds/ocean_look.tres or an export of WorldLook.
## Keys: K = classic / natural look, H = silt haze on / off, plus every key
## of the level test (N / P level, R again, L world ambient, B brightness,
## C cut-away, T trails, F creatures...).
## "-- look <folder> [level number] [pictures]" saves before / after pictures
## (with and without a pulse) and measures the frame rate in both looks
## (LookdevShots; "pictures" = no benchmark).

## Start in the natural look (K switches).
@export var start_natural: bool = true
## Freeze the creatures and stop the oxygen drain at the start.
@export var calm_start: bool = true

var _haze_density: float = 0.0


func _ready() -> void:
	super._ready()
	if world.look:
		_haze_density = world.look.haze_density
	builder.set_natural_look(start_natural)
	if calm_start:
		set_creatures_frozen(true)
		oxygen_drain = false
		for player: Player in [echo, guardian]:
			player.pressure.drain_scale = 0.0
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() >= 2 and arguments[0] == "look":
		var shots := LookdevShots.new()
		shots.test = self
		shots.folder = arguments[1]
		if arguments.size() >= 3 and arguments[2].is_valid_int():
			shots.level_number = int(arguments[2]) - 1
		shots.benchmark = not arguments.has("pictures")
		add_child(shots)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		if key.physical_keycode == KEY_K:
			builder.set_natural_look(not builder.natural_look)
			return
		if key.physical_keycode == KEY_H:
			set_haze(world.look.haze_density <= 0.0)
			return
	super._unhandled_input(event)


## The silt haze of the natural look on / off.
func set_haze(on: bool) -> void:
	if world.look == null:
		return
	world.look.haze_density = _haze_density if on else 0.0
	builder.set_natural_look(builder.natural_look)


func _info_text() -> String:
	return "%s\nK look: %s (%d kit pieces)   H silt haze: %s" % [super._info_text(),
		"NATURAL" if builder.natural_look else "classic", builder.get_dressing_piece_count() if builder.natural_look else 0,
		"on" if world.look and world.look.haze_density > 0.0 else "off"]
