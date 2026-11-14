shader_type spatial;
// The sea floor of the natural look (WorldLook): real sand (a CC0 PBR
// texture, two layers of it at different sizes and turns so it never shows
// its tile), long sand ripples in patches, tiny glints that sparkle in a
// light and in the pulse, darker with depth, plus everything the classic
// floor has: the sand trails (a darker groove, albedo only), the world's
// faint ambient and the pulse's wave of light. Ripples and grain tilt the
// normal, so a light near the floor rakes across them.

#include "res://shaders/sonar.gdshaderinc"
#include "res://shaders/sand_trails.gdshaderinc"
#include "res://shaders/world_ambient.gdshaderinc"
#include "res://shaders/surface_detail.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.15, 0.19, 0.25);
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : filter_linear_mipmap_anisotropic, repeat_enable;
// r = ambient occlusion, g = roughness.
uniform sampler2D sand_arm : filter_linear_mipmap, repeat_enable;
// World units one tile of the texture covers.
uniform float texture_size = 3.4;
// The texture's average colour (linear): the texture only adds detail round
// base_color, so the darkness tuned for the classic look is kept.
uniform vec3 texture_mean = vec3(0.3, 0.25, 0.18);
// 0 = only the texture's light and dark, 1 = its own hue too.
uniform float texture_tint : hint_range(0.0, 1.0) = 0.3;
uniform float texture_contrast = 1.0;
uniform float normal_strength = 0.9;
uniform float occlusion_strength : hint_range(0.0, 1.0) = 0.6;
// Large soft patches of lighter and darker sand.
uniform float patch_scale = 0.12;
uniform float patch_strength = 0.14;

group_uniforms ripples;
// World units between crests, the direction they run across, how far a slow
// noise bends them, their depth (units) and how much darker a trough is.
uniform float ripple_spacing = 0.5;
uniform vec2 ripple_direction = vec2(0.8, 0.6);
uniform float ripple_bend = 4.5;
uniform float ripple_depth = 0.026;
uniform float ripple_shade = 0.16;
// Ripples come in patches: their share where the sand is smooth.
uniform float ripple_floor : hint_range(0.0, 1.0) = 0.12;

group_uniforms sparkle;
// Size of a glint (world units), the share of grains that glint, how far a
// glint's facet leans, its polish and strength, and how much brighter it is
// in the pulse's light.
uniform float sparkle_size = 0.045;
uniform float sparkle_density : hint_range(0.0, 0.3) = 0.05;
uniform float sparkle_tilt = 0.9;
uniform float sparkle_roughness : hint_range(0.05, 1.0) = 0.28;
uniform float sparkle_specular : hint_range(0.0, 1.0) = 1.0;
uniform float sparkle_pulse = 1.2;

group_uniforms trails;
uniform float furrow_darken = 0.6;
uniform float stirred_lighten = 0.35;

group_uniforms pulse;
// How much of the ripples and grain the pulse's light shades (0 = flat sand).
uniform float pulse_relief : hint_range(0.0, 1.0) = 0.7;

float ripple_height(vec2 p) {
	// Bent by a slow and a quicker noise, so crests wander, fork and fade.
	float bend = noise2(p * 0.17) * ripple_bend + noise2(p * 0.9 + 3.0) * ripple_bend * 0.12;
	float phase = (dot(p, normalize(ripple_direction)) + bend) / ripple_spacing * TAU;
	float wave = 0.5 + 0.5 * sin(phase + 0.9 * sin(phase * 0.31 + p.y * 0.7));
	float patches = smoothstep(0.3, 0.65, noise2(p * 0.13 + 11.0));
	return pow(wave, 1.5) * mix(ripple_floor, 1.0, patches);
}

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = world_pos.xz;

	// Two layers of the texture, the second larger and turned, mixed by a
	// slow noise.
	mat2 turn = mat2(vec2(0.819, 0.574), vec2(-0.574, 0.819));
	vec2 uv_a = p / texture_size;
	vec2 uv_b = (turn * p) / (texture_size * 1.61) + vec2(0.37, 0.11);
	float layer = smoothstep(0.3, 0.7, noise2(p * 0.21 + 5.0));
	vec3 texel = mix(texture(sand_albedo, uv_a).rgb, texture(sand_albedo, uv_b).rgb, layer);
	vec2 lean_a = texture(sand_normal, uv_a).xy * 2.0 - 1.0;
	vec2 lean_b = texture(sand_normal, uv_b).xy * 2.0 - 1.0;
	// A normal map's green points up the image: -z on the floor.
	lean_a = vec2(lean_a.x, -lean_a.y);
	lean_b = transpose(turn) * vec2(lean_b.x, -lean_b.y);
	vec2 lean = mix(lean_a, lean_b, layer) * normal_strength;
	vec2 arm = mix(texture(sand_arm, uv_a).rg, texture(sand_arm, uv_b).rg, layer);

	// Ripples: the slope of their height tilts the normal.
	float height = ripple_height(p);
	float step_size = 0.04;
	vec2 slope = vec2(ripple_height(p + vec2(step_size, 0.0)) - height,
		ripple_height(p + vec2(0.0, step_size)) - height) / step_size * ripple_depth;
	lean -= slope;

	vec3 detail = texel / max(texture_mean, vec3(0.001));
	float light_dark = dot(detail, vec3(0.3333));
	detail = mix(vec3(light_dark), detail, texture_tint);
	detail = max(mix(vec3(1.0), detail, texture_contrast), vec3(0.0));
	float patches = 1.0 + (noise2(p * patch_scale + 23.0) - 0.5) * 2.0 * patch_strength;
	vec3 albedo = base_color * detail * patches;
	albedo *= mix(1.0, arm.r, occlusion_strength);
	albedo *= 1.0 - (1.0 - height) * ripple_shade;
	albedo *= depth_tint(world_pos);

	// Sand trails: a darker groove, a lighter stirred patch (albedo only).
	vec4 trail = trail_at(world_pos);
	albedo *= (1.0 - trail.x * furrow_darken) * (1.0 + trail.y * stirred_lighten);

	// Glints: a few grains with a polished facet leaning its own way.
	vec2 grain = p / sparkle_size;
	vec2 cell = floor(grain);
	float glint = step(1.0 - sparkle_density, hash21(cell))
		* (1.0 - smoothstep(0.2, 0.5, length(fract(grain) - 0.5)));
	vec2 facet = (vec2(hash21(cell + 17.0), hash21(cell + 43.0)) - 0.5) * sparkle_tilt;
	vec3 world_normal = normalize(vec3(lean.x + facet.x * glint, 1.0, lean.y + facet.y * glint));

	ALBEDO = albedo;
	ROUGHNESS = mix(clamp(arm.g, 0.6, 1.0), sparkle_roughness, glint);
	SPECULAR = mix(0.2, sparkle_specular, glint);
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);

	vec3 pulse_normal = normalize(mix(vec3(0.0, 1.0, 0.0), world_normal, pulse_relief));
	vec3 pulse = albedo * wave_color * wave_energy * sonar_light(world_pos, pulse_normal)
		* (1.0 + glint * sparkle_pulse);
	EMISSION = pulse + world_ambient(world_pos, albedo);
}
