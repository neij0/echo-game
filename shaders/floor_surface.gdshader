shader_type spatial;
// The sea floor: dark sand, lit only by real lights, with faint ripples and
// the sand trails (furrows behind players and creatures, stirred puffs). A
// furrow only changes how the sand takes light (darker groove, a tilted
// slope), so it shows only where something lights it: a player's light, a
// lit coral, or the pulse's afterglow (which outlines it a little brighter,
// so the Echo can follow a creature's track). Plus the sonar in world space.

#include "res://shaders/sonar.gdshaderinc"
#include "res://shaders/sand_trails.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.15, 0.19, 0.25);
uniform float grain_scale = 3.0;
uniform float grain_strength = 0.18;
// Long, soft sand ripples (world units between crests) and how strongly
// they darken the troughs.
uniform float ripple_spacing = 0.55;
uniform float ripple_strength = 0.08;
uniform vec3 sonar_color : source_color = vec3(0.25, 0.85, 1.0);
uniform float front_energy = 0.9;
uniform float fill_energy = 0.07;
// Furrows: how much darker the groove is, how steep its sides look to the
// light, and how much brighter it shows in the pulse's afterglow.
uniform float furrow_darken = 0.6;
uniform float furrow_slope = 6.0;
uniform float furrow_sonar_energy = 0.35;
// Stirred sand: a little lighter for a moment.
uniform float stirred_lighten = 0.35;

varying vec3 world_pos;

float hash(vec2 p) {
	p = fract(p * vec2(0.3183099, 0.3678794) + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * (p.x + p.y));
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float grain = noise(p * grain_scale) * 0.6 + noise(p * grain_scale * 4.1) * 0.4;
	// Ripples: crests bent by a slow noise so they never look ruled.
	float bend = noise(p * 0.18) * 6.0;
	float ripple = sin((p.x * 0.8 + p.y * 0.6 + bend) / ripple_spacing * TAU) * 0.5 + 0.5;

	vec4 trail = trail_at(world_pos);
	vec3 albedo = base_color * (1.0 + (grain - 0.5) * 2.0 * grain_strength) * (1.0 - ripple * ripple_strength);
	albedo *= 1.0 - trail.x * furrow_darken;
	albedo *= 1.0 + trail.y * stirred_lighten;
	ALBEDO = albedo;
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;

	// The furrow's slope tilts the normal (world space -> view space).
	vec3 world_normal = normalize(vec3(trail.z * furrow_slope, 1.0, trail.w * furrow_slope));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);

	vec3 sonar = sonar_at(world_pos, world_normal);
	EMISSION = sonar_color * (sonar.x * front_energy + sonar.z * fill_energy
		+ sonar.y * trail.x * furrow_sonar_energy);
}
