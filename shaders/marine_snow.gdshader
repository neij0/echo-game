shader_type spatial;
// Marine snow: tiny camera-facing dots, almost invisible in the dark, brighter
// inside a player's light and flashing as the sonar wave passes through them.
// Each one sways and twinkles on its own (from its particle index).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://shaders/sonar.gdshaderinc"

uniform vec3 tint : source_color = vec3(0.7, 0.9, 1.0);
// Brightness range in the dark (each particle twinkles between the two).
uniform float glow_min = 0.01;
uniform float glow_max = 0.05;
uniform float twinkle_speed = 0.25;
// Side-to-side sway in world units, and its cycles per second.
uniform float sway_amount = 0.24;
uniform float sway_speed = 0.12;
uniform vec3 light_pos[2];
uniform float light_range[2];
uniform float light_gain[2];
uniform float sonar_gain = 1.2;
uniform vec3 sonar_color : source_color = vec3(0.3, 0.9, 1.0);

varying float glow;
varying float flash;

void vertex() {
	float seed = fract(float(INSTANCE_ID) * 0.61803398875);
	vec3 center = MODEL_MATRIX[3].xyz;
	center.x += sin((TIME * sway_speed + seed) * TAU) * sway_amount;
	center.z += cos((TIME * sway_speed * 0.8 + seed * 3.7) * TAU) * sway_amount * 0.6;
	mat4 facing = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(center, 1.0));
	// Keeps the particle's own size (its scale) while it faces the camera.
	float size = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * facing * mat4(vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0), vec4(0.0, 0.0, 0.0, 1.0));

	float twinkle = 0.5 + 0.5 * sin((TIME * twinkle_speed + seed * 5.3) * TAU);
	glow = mix(glow_min, glow_max, twinkle);
	for (int i = 0; i < 2; i++) {
		float reach = max(1.0 - distance(center, light_pos[i]) / max(light_range[i], 0.001), 0.0);
		glow += light_gain[i] * reach * reach;
	}
	flash = sonar_at(center, vec3(0.0, 1.0, 0.0)).x * sonar_gain;
}

void fragment() {
	float dot_shape = 1.0 - smoothstep(0.1, 0.5, distance(UV, vec2(0.5)));
	ALBEDO = tint * glow + sonar_color * flash;
	ALPHA = dot_shape;
}
