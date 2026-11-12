shader_type spatial;
// The flash at the Echo when she fires a pulse: a soft, over-bright disc that
// always faces the camera (it blooms), grown and faded by Sonar.
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 flash_color : source_color = vec3(0.75, 0.95, 1.0);
// 0-1 over the flash's life (Sonar animates it), times its brightness.
uniform float strength = 1.0;
uniform float energy = 6.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3])
		* mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float r = distance(UV, vec2(0.5)) * 2.0;
	// A hot core and a wide soft halo.
	float shape = exp(-r * r * 9.0) + 0.35 * exp(-r * r * 2.5);
	ALBEDO = flash_color * energy * strength * shape * (1.0 - smoothstep(0.85, 1.0, r));
}
