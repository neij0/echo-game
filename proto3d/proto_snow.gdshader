shader_type spatial;
// Marine snow: tiny camera-facing dots, almost invisible in the dark, brighter
// inside a player's light and flashing as the sonar wave passes through them.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://proto3d/proto_sonar.gdshaderinc"

uniform vec3 tint : source_color = vec3(0.6, 0.8, 1.0);
uniform float base_glow = 0.02;
uniform vec3 light_pos[2];
uniform float light_range[2];
uniform float light_gain[2];
uniform float sonar_gain = 1.2;
uniform vec3 sonar_color : source_color = vec3(0.3, 0.9, 1.0);

varying float glow;
varying float flash;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	glow = base_glow;
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
