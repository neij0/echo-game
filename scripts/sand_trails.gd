class_name SandTrails
extends Node3D
## Trails in the sand of the sea floor. Every SandTrailMaker (players,
## creatures, later fish) stamps a soft furrow along the way it moved this
## frame into one texture, and a short patch of stirred sand; the floor shader
## (shaders/floor_surface.gdshader + sand_trails.gdshaderinc) reads it. Things
## that move fast also throw a small puff of sand (lit particles, so a puff in
## the dark is not seen).
## The darkness rules hold: a furrow only changes how the sand takes light (a
## darker groove with sloping sides), so it is seen only where a light falls,
## or in the pulse's afterglow (a little brighter there, so the Echo can read
## a creature's track after a pulse).
## Cheap by design: the texture covers trail_window units and wraps over the
## world (a floor point uses its position modulo the window), so it never
## scrolls or copies. Only makers within active_radius of the camera's focus
## stamp (farther ones would land on wrapped texels the camera can see). The
## fade is a multiply over the whole texture fade_rate times per second
## (HDR half floats, so a slow fade never sticks).

const FADE_SHADER_CODE: String = """
shader_type canvas_item;
render_mode blend_mul, unshaded;
uniform vec2 decay = vec2(1.0, 1.0);
void fragment() {
	COLOR = vec4(decay, 1.0, 1.0);
}
"""

@export var enabled: bool = true:
	set(value):
		enabled = value
		if _viewport:
			_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED

@export_group("Texture")
## Texels per side of the trail texture.
@export var texture_size: int = 1024
## World units the texture covers before it wraps (keep it at least twice
## active_radius).
@export var trail_window: float = 64.0
## Makers farther than this from the camera's focus do not stamp (units).
@export var active_radius: float = 30.0

@export_group("Fading")
## Seconds until a furrow has faded to about 5 %. A trail is as long as its
## maker moves in this time.
@export var fade_time: float = 8.0
## Seconds until stirred sand has settled (to about 5 %).
@export var stir_fade_time: float = 1.2
## Fade steps per second (each step multiplies the whole texture once).
@export var fade_rate: float = 30.0

@export_group("Puffs")
@export var puffs_enabled: bool = true
## Puff emitters reused in turn (each throws puff_particles particles).
@export var puff_pool_size: int = 12
@export var puff_particles: int = 10
@export var puff_lifetime: float = 1.1
@export var puff_color: Color = Color(0.55, 0.58, 0.6, 0.55)
@export var puff_size: float = 0.22
@export var puff_spread_speed: float = 1.2
@export var puff_rise_speed: float = 0.5

var _viewport: SubViewport
var _fade: Node2D
var _fade_material: ShaderMaterial
var _stamps: Node2D
var _stamp_texture: Texture2D
var _fade_wait: float = 0.0
## Stamps to draw this frame: [texel position, radius in texels, strength rg].
var _pending: Array[Array] = []
var _materials: Array[ShaderMaterial] = []
var _puffs: Array[GPUParticles3D] = []
var _next_puff: int = 0
## Puffs thrown since the start (tests).
var puffs_thrown: int = 0
## Stamps drawn since the start (tests).
var stamps_drawn: int = 0


static func find(tree: SceneTree) -> SandTrails:
	return tree.get_first_node_in_group("sand_trails") as SandTrails if tree else null


func _ready() -> void:
	add_to_group("sand_trails")
	_viewport = SubViewport.new()
	_viewport.name = "TrailMap"
	_viewport.size = Vector2i(texture_size, texture_size)
	_viewport.use_hdr_2d = true
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	add_child(_viewport)

	_fade = Node2D.new()
	_fade.name = "Fade"
	_fade_material = ShaderMaterial.new()
	var fade_shader := Shader.new()
	fade_shader.code = FADE_SHADER_CODE
	_fade_material.shader = fade_shader
	_fade.material = _fade_material
	_fade.visible = false
	_fade.draw.connect(func() -> void: _fade.draw_rect(Rect2(Vector2.ZERO, Vector2.ONE * texture_size), Color.WHITE))
	_viewport.add_child(_fade)

	_stamps = Node2D.new()
	_stamps.name = "Stamps"
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_stamps.material = add
	_stamps.draw.connect(_draw_stamps)
	_viewport.add_child(_stamps)
	_stamp_texture = _make_stamp_texture()
	_build_puffs()


## A floor material reading the trails (floor_surface.gdshader).
func register_material(material: ShaderMaterial) -> void:
	_materials.append(material)
	material.set_shader_parameter("trail_map", _viewport.get_texture())
	material.set_shader_parameter("trail_window", trail_window)
	material.set_shader_parameter("trail_texel", trail_window / texture_size)


func _process(delta: float) -> void:
	if not enabled:
		return
	# The fade: a multiply over the whole texture, fade_rate times per second.
	_fade_wait += delta
	var step: float = 1.0 / maxf(fade_rate, 1.0)
	_fade.visible = _fade_wait >= step
	if _fade.visible:
		# exp(-3) is about 5 %: faded after fade_time.
		_fade_material.set_shader_parameter("decay", Vector2(
			exp(-3.0 * _fade_wait / maxf(fade_time, 0.01)), exp(-3.0 * _fade_wait / maxf(stir_fade_time, 0.01))))
		_fade_wait = 0.0
	var focus: Vector3 = _focus()
	for node: Node in get_tree().get_nodes_in_group("sand_trail_makers"):
		var maker := node as SandTrailMaker
		if maker and maker.is_visible_in_tree():
			_update_maker(maker, focus, delta)
	_stamps.queue_redraw()


func _update_maker(maker: SandTrailMaker, focus: Vector3, delta: float) -> void:
	var at: Vector3 = maker.get_floor_position()
	var last: Vector3 = maker.last_floor_position
	maker.last_floor_position = at
	if not maker.has_last:
		maker.has_last = true
		return
	var flat := Vector2(at.x - focus.x, at.z - focus.z)
	if flat.length() > active_radius or not maker.is_touching():
		return
	var moved: float = Vector2(at.x - last.x, at.z - last.z).length()
	# A jump (teleport, respawn): no furrow across the floor.
	if moved > maker.max_step:
		return
	var speed: float = moved / maxf(delta, 0.0001)
	if moved > 0.0001:
		_stamp_segment(last, at, maker)
	maker.puff_cooldown_left = maxf(maker.puff_cooldown_left - delta, 0.0)
	if puffs_enabled and maker.puff_speed > 0.0 and speed >= maker.puff_speed and maker.puff_cooldown_left <= 0.0:
		maker.puff_cooldown_left = maker.puff_interval
		throw_puff(at, maker.puff_scale)


## Soft stamps along the segment, spaced so the furrow is continuous.
func _stamp_segment(from: Vector3, to: Vector3, maker: SandTrailMaker) -> void:
	var texels_per_unit: float = texture_size / trail_window
	var radius: float = maker.radius * texels_per_unit
	var length: float = Vector2(to.x - from.x, to.z - from.z).length()
	var spacing: float = maxf(maker.radius * 0.5, 0.02)
	var count: int = maxi(1, ceili(length / spacing))
	# The furrow builds up over about one maker radius of travel.
	var strength: float = maker.depth * minf(length / count / maxf(maker.radius, 0.01), 1.0)
	for i: int in count:
		var p: Vector3 = from.lerp(to, float(i + 1) / count)
		_pending.append([_texel(p), radius, Vector2(strength, maker.stir * strength)])


func _texel(world: Vector3) -> Vector2:
	var uv := Vector2(fposmod(world.x / trail_window, 1.0), fposmod(world.z / trail_window, 1.0))
	return uv * texture_size


func _draw_stamps() -> void:
	for stamp: Array in _pending:
		var center: Vector2 = stamp[0]
		var radius: float = stamp[1]
		var strength: Vector2 = stamp[2]
		# Draw colours are turned from sRGB to linear in an HDR viewport: give
		# the sRGB value of the wanted strength.
		var color := Color(strength.x, strength.y, 0.0, 1.0).linear_to_srgb()
		var rect := Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
		_stamps.draw_texture_rect(_stamp_texture, rect, false, color)
		# Near an edge of the texture, again on the far side (it wraps).
		var size := float(texture_size)
		for shift: Vector2 in [Vector2(size, 0), Vector2(-size, 0), Vector2(0, size), Vector2(0, -size),
				Vector2(size, size), Vector2(-size, size), Vector2(size, -size), Vector2(-size, -size)]:
			var moved: Rect2 = Rect2(rect.position + shift, rect.size)
			if moved.intersects(Rect2(0, 0, size, size)):
				_stamps.draw_texture_rect(_stamp_texture, moved, false, color)
		stamps_drawn += 1
	_pending.clear()


## A small puff of stirred sand at a floor point (lunges, dashes, knockbacks).
func throw_puff(at: Vector3, scale_factor: float = 1.0) -> void:
	if _puffs.is_empty():
		return
	var puff: GPUParticles3D = _puffs[_next_puff]
	_next_puff = (_next_puff + 1) % _puffs.size()
	puff.global_position = Vector3(at.x, 0.05, at.z)
	puff.scale = Vector3.ONE * scale_factor
	puff.restart()
	puffs_thrown += 1


## The camera's focus on the floor (the players' midpoint), else the origin.
func _focus() -> Vector3:
	var camera: SharedCamera = SharedCamera.find(get_tree())
	if camera:
		return camera.get_focus()
	return Vector3.ZERO


## The trail value (r = furrow, g = stirred) at a world point, read back from
## the GPU (slow: tests only).
func sample(world: Vector3) -> Vector2:
	var image: Image = _viewport.get_texture().get_image()
	var texel: Vector2 = _texel(world)
	var color: Color = image.get_pixel(clampi(int(texel.x), 0, texture_size - 1), clampi(int(texel.y), 0, texture_size - 1))
	return Vector2(color.r, color.g)


## A soft round stamp: full in the middle, fading out to the rim.
func _make_stamp_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.45, Color(1.0, 1.0, 1.0, 0.75))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32
	return texture


func _build_puffs() -> void:
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 80.0
	process.initial_velocity_min = puff_spread_speed * 0.4
	process.initial_velocity_max = puff_spread_speed
	process.gravity = Vector3(0.0, -0.4, 0.0)
	process.damping_min = 1.5
	process.damping_max = 2.5
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.15
	process.scale_min = 0.6
	process.scale_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	fade.add_point(0.15, Color(1.0, 1.0, 1.0, 1.0))
	fade.set_color(fade.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.6))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	process.scale_curve = grow_texture

	var material := StandardMaterial3D.new()
	# Lit like the sand: a puff in the dark stays dark.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_color = puff_color
	material.albedo_texture = _stamp_texture
	material.roughness = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * puff_size
	quad.material = material
	for i: int in puff_pool_size:
		var puff := GPUParticles3D.new()
		puff.name = "Puff%d" % i
		puff.amount = puff_particles
		puff.lifetime = puff_lifetime
		puff.one_shot = true
		puff.explosiveness = 0.9
		puff.emitting = false
		puff.local_coords = false
		puff.process_material = process
		puff.draw_pass_1 = quad
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.visibility_aabb = AABB(Vector3(-2.0, -0.5, -2.0), Vector3(4.0, 3.0, 4.0))
		puff.top_level = true
		add_child(puff)
		_puffs.append(puff)
