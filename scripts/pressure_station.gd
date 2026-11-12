class_name PressureStation
extends Node3D
## A refill station for the world's pressure meter (an old oxygen tank in the
## Ocean). A player touching it gets a full meter, then it is used up. A slow
## blinking beacon makes it findable in the dark.

signal used(player: Player)

## A player this close (units) uses it.
@export var touch_radius: float = 0.68
@export_flags_3d_physics var player_mask: int = 2
@export var refill_stream: AudioStream
@export var refill_volume_db: float = -4.0

@export_group("Beacon")
@export var beacon_color: Color = Color(1.0, 0.85, 0.35)
@export var beacon_energy: float = 1.4
## Reach of the beacon's light (units).
@export var beacon_radius: float = 2.2
## Blinks per second.
@export var beacon_speed: float = 0.6
## 0-1: brightness at the dark point of the blink.
@export_range(0.0, 1.0) var beacon_min: float = 0.25

@export_group("Look")
## The tank: radius and height (units).
@export var tank_radius: float = 0.26
@export var tank_height: float = 0.8
@export var full_color: Color = Color(0.55, 0.48, 0.25)
@export var empty_color: Color = Color(0.2, 0.2, 0.2)
## HDR energy of the small lamp on top (above 1 = it blooms).
@export var lamp_energy: float = 4.0
@export var lamp_radius: float = 0.08

var is_used: bool = false
var _time: float = 0.0
var _beacon: OmniLight3D
var _tank_material: StandardMaterial3D
var _lamp: MeshInstance3D
var _audio: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("pressure_stations")
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = player_mask
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = touch_radius
	cylinder.height = 2.0
	shape.shape = cylinder
	shape.position.y = 1.0
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)

	var tank_mesh := CylinderMesh.new()
	tank_mesh.top_radius = tank_radius * 0.8
	tank_mesh.bottom_radius = tank_radius
	tank_mesh.height = tank_height
	tank_mesh.radial_segments = 12
	_tank_material = StandardMaterial3D.new()
	_tank_material.albedo_color = full_color
	_tank_material.roughness = 0.6
	_tank_material.metallic = 0.3
	var tank := MeshInstance3D.new()
	tank.mesh = tank_mesh
	tank.material_override = _tank_material
	tank.position.y = tank_height * 0.5
	add_child(tank)

	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = lamp_radius
	lamp_mesh.height = lamp_radius * 2.0
	var lamp_material := StandardMaterial3D.new()
	lamp_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_material.albedo_color = Color(beacon_color.r * lamp_energy, beacon_color.g * lamp_energy, beacon_color.b * lamp_energy)
	_lamp = MeshInstance3D.new()
	_lamp.mesh = lamp_mesh
	_lamp.material_override = lamp_material
	_lamp.position.y = tank_height + lamp_radius
	add_child(_lamp)

	_beacon = OmniLight3D.new()
	_beacon.light_color = beacon_color
	_beacon.light_energy = beacon_energy
	_beacon.omni_range = beacon_radius
	_beacon.position.y = tank_height + 0.3
	add_child(_beacon)

	_audio = AudioStreamPlayer3D.new()
	_audio.stream = refill_stream
	_audio.bus = &"SFX"
	_audio.volume_db = refill_volume_db
	add_child(_audio)


func _process(delta: float) -> void:
	if is_used:
		return
	_time += delta
	var blink: float = 0.5 + 0.5 * sin(_time * TAU * beacon_speed)
	_beacon.light_energy = beacon_energy * lerpf(beacon_min, 1.0, blink)


func _on_body_entered(body: Node3D) -> void:
	var player := body as Player
	if is_used or player == null or player.health.is_downed:
		return
	use(player)


## Refills the player's meter and uses the station up.
func use(player: Player) -> void:
	is_used = true
	player.pressure.refill()
	_beacon.visible = false
	_lamp.visible = false
	_tank_material.albedo_color = empty_color
	if refill_stream:
		_audio.play()
	used.emit(player)
