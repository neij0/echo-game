class_name ShardDoor
extends RockGate
## The sealed doorway of a boss arena: rock like any wall (collision, light,
## pulse), with a faint golden seam along its top and one socket per Echo
## Shard. Each collected shard lights a socket (StageManager calls
## set_shard_progress); when all are lit, open() lets the rock sink into the
## floor and the arena can be entered. The LevelBuilder places it on the
## arena's only doorway (the shape of a seal) and rebakes the creatures'
## navigation once it is open.

signal opened

@export_group("Seam")
@export var seam_color: Color = Color(1.0, 0.8, 0.35)
@export var seam_energy: float = 1.2
@export_range(0.0, 1.0) var seam_alpha: float = 0.1
## World units.
@export var seam_width: float = 0.04
## The glow shows when a player is this close (it is a glowing part, but it
## must not give the arena away from across the level).
@export var show_distance: float = 10.4

@export_group("Sockets")
@export var socket_color: Color = Color(0.55, 0.95, 1.0)
@export var socket_radius: float = 0.13
@export var socket_spacing: float = 0.68
@export_range(0.0, 1.0) var empty_socket_alpha: float = 0.25

@export_group("Opening")
## Seconds for the rock to sink away.
@export var open_time: float = 1.2
@export var open_sound: String = "world_barrier_open"

var shards_needed: int = 0
var shards_have: int = 0
var is_open: bool = false
var _marks: GlowLines


func _ready() -> void:
	sink_time = open_time
	super()
	add_to_group("level_exit")
	set_solid(true)
	snap()
	_marks = GlowLines.new()
	_marks.energy = seam_energy
	add_child(_marks)


func _process(delta: float) -> void:
	animate(delta)
	_draw_marks()


## Called by the StageManager whenever a shard is collected.
func set_shard_progress(have: int, needed: int) -> void:
	shards_have = have
	shards_needed = needed


## The rock sinks away: no collision any more (bodies, the pulse, sight).
func open() -> void:
	if is_open:
		return
	is_open = true
	set_solid(false)
	remove_from_group("level_exit")
	var audio: AudioDirector = AudioDirector.find(get_tree())
	if audio and open_sound != "":
		audio.play(open_sound, global_position + center)
	opened.emit()


## The seam and the sockets, on top of the rock, near a player only.
func _draw_marks() -> void:
	_marks.clear()
	var player: Player = Players.nearest(get_tree(), global_position + center)
	if player and raised > 0.0:
		var distance: float = Creature._flat_distance(player.global_position, global_position + center)
		var near: float = clampf(1.0 - distance / show_distance, 0.0, 1.0)
		var alpha: float = minf(near * 2.0, 1.0) * raised
		if alpha > 0.0:
			var top: float = height * raised * raised * (3.0 - 2.0 * raised) + 0.02
			var middle: Vector3 = global_position + center
			# Brighter while it opens.
			var seam := Color(seam_color, minf(seam_alpha * alpha * (1.0 + (1.0 - raised) * 2.0), 1.0))
			_marks.add_polyline(PackedVector3Array([middle - along * half_length, middle + along * half_length]), seam_width, seam, top)
			var first: float = -socket_spacing * (shards_needed - 1) * 0.5
			for i: int in shards_needed:
				var at: Vector3 = middle + along * (first + socket_spacing * i)
				if i < shards_have or is_open:
					_marks.add_disc(at, socket_radius * 1.4, Color(socket_color, alpha), top)
				else:
					_marks.add_ring(at, socket_radius, seam_width, Color(socket_color, empty_socket_alpha * alpha), top)
	_marks.commit()
