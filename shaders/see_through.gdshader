shader_type spatial;
// Second pass on a character: drawn only where a rock covers it, as a soft
// outline through the rock (like OccludedOutline in the 2D game).
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_back, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 outline_color : source_color = vec3(0.3, 0.9, 1.0);
uniform float energy = 1.3;
uniform float rim_power = 3.0;
// Brightness of the inside of the shape (the rim is always 1).
uniform float fill = 0.05;
// 0 = never shown (a creature nobody revealed).
uniform float visibility = 1.0;
// How far behind the rock's surface the character must be (world units).
uniform float depth_margin = 0.12;

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = scene.z / scene.w;
	float covered = step(VERTEX.z + depth_margin, scene_z);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	ALBEDO = outline_color * energy * (fill + rim);
	ALPHA = covered * visibility;
}
