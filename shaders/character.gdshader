shader_type spatial;
// Players and creatures: a dark body with a glowing rim, and for a model's
// glowing parts (core, tips, trims, blade) a glow of their own. Writing ALPHA
// puts them in the transparent pass, so the sonar edge pass (which only reads
// the opaque depth buffer) never outlines them.
render_mode depth_draw_always, cull_back;

uniform vec3 body_color : source_color = vec3(0.02, 0.03, 0.04);
uniform vec3 rim_color : source_color = vec3(0.3, 0.9, 1.0);
uniform float rim_energy = 1.0;
uniform float rim_power = 2.5;
// A part that glows all over (0 = none).
uniform vec3 glow_color : source_color = vec3(0.0);
uniform float glow_energy = 0.0;

void fragment() {
	ALBEDO = body_color;
	ROUGHNESS = 0.9;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = rim_color * rim * rim_energy + glow_color * glow_energy;
	ALPHA = 1.0;
}
