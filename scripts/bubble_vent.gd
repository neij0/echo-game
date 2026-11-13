class_name BubbleVent
extends Node3D
## A crack in the arena floor that breathes out a column of bubbles: a player
## standing within radius gets oxygen back (refill_per_second of a full meter),
## so a boss fight is never lost to the meter. A soft light, a faint ring on
## the floor and the rising bubbles make it findable in the dark; the bubbles
## swell while someone breathes there. Bosses may punish standing here
## (AnglerBoss: vent prey). Placed by the LevelBuilder on the boss arena's
## "Vent*" markers.

## World units (the 2D game's 70 px).
@export var radius: float = 1.4
## Share of a full meter per second while a player stands in it.
@export var refill_per_second: float = 0.22

@export_group("Look")
@export var crack_color: Color = Color(0.02, 0.03, 0.04)
@export var crack_radius: float = 0.34
@export var glow_color: Color = Color(0.45, 0.95, 1.0)
@export var glow_energy: float = 1.4
@export_range(0.0, 1.0) var ring_alpha: float = 0.035
@export var ring_width: float = 0.03
@export var light_radius: float = 2.6
@export var light_energy: float = 1.2
@export var light_height: float = 0.5
@export var bubble_color: Color = Color(0.7, 0.95, 1.0, 0.6)
@export var bubble_amount: int = 26
@export var bubble_size: float = 0.07
## How high the bubbles rise before they fade (units, about).
@export var bubble_rise: float = 2.4

@export_group("Sound")
@export var breathe_sound: String = "world_vent_breathe"
## Seconds between breathe sounds while someone refills.
@export var breathe_interval: float = 1.4

var _time: float = 0.0
var _busy: bool = false
var _breathe_left: float = 0.0
var _bubbles: GPUParticles3D
var _marks: GlowLines
var _light: OmniLight3D


func _ready() -> void:
	add_to_group("bubble_vents")
	_add_crack()
	_add_bubbles()
	_light = OmniLight3D.new()
	_light.light_color = glow_color
	_light.light_energy = light_energy
	_light.omni_range = light_radius
	_light.shadow_enabled = false
	_light.position.y = light_height
	add_child(_light)
	_marks = GlowLines.new()
	_marks.energy = glow_energy
	_marks.through_rock = false
	add_child(_marks)


func _physics_process(delta: float) -> void:
	_time += delta
	_busy = false
	for player: Player in Players.all(get_tree()):
		if is_player_at(player):
			player.pressure.add_ratio(refill_per_second * delta)
			_busy = true
	_bubbles.speed_scale = 1.8 if _busy else 1.0
	_light.light_energy = light_energy * (1.6 if _busy else 1.0) * (0.85 + 0.15 * sin(_time * 2.1))
	_breathe_left -= delta
	if _busy and _breathe_left <= 0.0:
		_breathe_left = breathe_interval
		var audio: AudioDirector = AudioDirector.find(get_tree())
		if audio:
			audio.play(breathe_sound, global_position)


func _process(_delta: float) -> void:
	var pulse: float = 0.75 + 0.25 * sin(_time * 2.1)
	_marks.clear()
	_marks.add_disc(global_position, 0.16, Color(glow_color, 0.5 * pulse), 0.01)
	# Where it reaches (brighter while someone breathes there).
	_marks.add_ring(global_position, radius, ring_width, Color(glow_color, ring_alpha * (2.0 if _busy else 1.0) * pulse))
	_marks.commit()


func is_player_at(player: Player) -> bool:
	return not player.health.is_downed and Creature._flat_distance(player.global_position, global_position) <= radius


## True while a player breathes here (tests).
func is_busy() -> bool:
	return _busy


## The crack in the floor: a dark, slightly uneven patch.
func _add_crack() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	var points := PackedVector3Array()
	for i: int in 9:
		var angle: float = TAU * float(i) / 9.0
		var reach: float = crack_radius * (0.75 + 0.25 * sin(float(i) * 2.7))
		points.append(Vector3(cos(angle) * reach, 0.012, sin(angle) * reach * 0.6))
	for i: int in points.size():
		# Clockwise seen from above: Godot's front face.
		tool.add_vertex(Vector3(0.0, 0.012, 0.0))
		tool.add_vertex(points[(i + 1) % points.size()])
		tool.add_vertex(points[i])
	var material := StandardMaterial3D.new()
	material.albedo_color = crack_color
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var crack := MeshInstance3D.new()
	crack.name = "Crack"
	crack.mesh = tool.commit()
	crack.material_override = material
	crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(crack)


func _add_bubbles() -> void:
	var lifetime: float = 2.2
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 12.0
	process.initial_velocity_min = bubble_rise / lifetime * 0.6
	process.initial_velocity_max = bubble_rise / lifetime * 1.3
	process.gravity = Vector3(0.0, 0.3, 0.0)
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = crack_radius * 0.6
	process.scale_min = 0.5
	process.scale_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.9))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_color = bubble_color
	material.albedo_texture = LightTextures.radial(32, 0.5)
	material.roughness = 0.3
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * bubble_size
	quad.material = material
	_bubbles = GPUParticles3D.new()
	_bubbles.name = "Bubbles"
	_bubbles.amount = bubble_amount
	_bubbles.lifetime = lifetime
	_bubbles.process_material = process
	_bubbles.draw_pass_1 = quad
	_bubbles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bubbles.visibility_aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3.0, bubble_rise + 2.0, 3.0))
	add_child(_bubbles)
