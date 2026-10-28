class_name TopLightFalloff
extends Node
## Keeps far rock tops dark: the lighter top of a tall rock (RockWall.top_lift)
## and the outer rock around the level would otherwise show the whole room
## layout even far from every light. Their material (material()) fades their
## colour from full near a light to far_brightness beyond it, so near the
## players the tops read as raised rock and far away only the pulse shows the
## layout. Every PointLight2D in the "falloff_lights" group counts (the
## players' lights, lit corals, the ancient light, stations, shards, landmark
## glows), with its own radius (texture size x texture_scale), while its
## energy is above min_energy.
## Created by the LevelBuilder; without one (tools) the tops keep full colour.

const MAX_LIGHTS: int = 32

const SHADER_CODE: String = """
shader_type canvas_item;

uniform int light_count = 0;
// xy = global position, z = radius (pixels).
uniform vec4 lights[32];
uniform float inner_share = 0.85;
uniform float outer_share = 1.3;
uniform float far_brightness = 0.25;

varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float near = light_count == 0 ? 1.0 : 0.0;
	for (int i = 0; i < light_count; i++) {
		float d = distance(world_position, lights[i].xy);
		near = max(near, 1.0 - smoothstep(lights[i].z * inner_share, lights[i].z * outer_share, d));
	}
	COLOR.rgb *= mix(far_brightness, 1.0, near);
}
"""

## Full colour up to this share of a light's radius...
@export var inner_share: float = 0.85
## ...fading to far_brightness at this share of it.
@export var outer_share: float = 1.3
## Colour multiplier far from every light (about the floor's brightness, so a
## far top no longer stands out from the floor).
@export_range(0.0, 1.0) var far_brightness: float = 0.25
## Lights dimmer than this are ignored (an unlit coral, a dark shard).
@export var min_energy: float = 0.05

static var _material: ShaderMaterial


## The shared material of every rock top piece and the outer rock.
static func material() -> ShaderMaterial:
	if _material == null:
		var shader := Shader.new()
		shader.code = SHADER_CODE
		_material = ShaderMaterial.new()
		_material.shader = shader
	return _material


func _ready() -> void:
	_push_settings()


func _exit_tree() -> void:
	# Back to full colour (tools that build rocks without a falloff node).
	material().set_shader_parameter("light_count", 0)


func _process(_delta: float) -> void:
	var points := PackedVector4Array()
	for node: Node in get_tree().get_nodes_in_group("falloff_lights"):
		var light := node as PointLight2D
		if light == null or not light.is_visible_in_tree() or not light.enabled or light.energy < min_energy or light.texture == null:
			continue
		var radius: float = light.texture.get_width() * 0.5 * light.texture_scale
		var at: Vector2 = light.global_position
		points.append(Vector4(at.x, at.y, radius, 0.0))
		if points.size() >= MAX_LIGHTS:
			break
	# A level always has the players' lights: none at all = nothing to fade by.
	var count: int = points.size()
	points.resize(MAX_LIGHTS)
	material().set_shader_parameter("lights", points)
	material().set_shader_parameter("light_count", count)


func _push_settings() -> void:
	material().set_shader_parameter("inner_share", inner_share)
	material().set_shader_parameter("outer_share", outer_share)
	material().set_shader_parameter("far_brightness", far_brightness)
