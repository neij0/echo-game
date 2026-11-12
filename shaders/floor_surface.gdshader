shader_type spatial;
// The sea floor: dark sand, lit by real lights and the world's faint ambient,
// with faint ripples and the sand trails (furrows behind players and
// creatures, stirred puffs). A furrow is only a darker groove: it shows where
// something lights the sand (a player's light, a lit coral, the pulse's
// afterglow, which shows it like any other sand). It never tilts the
// surface's normal: the sonar's outline pass finds creases in the normal
// buffer, and would draw glowing lines along every groove. Plus the sonar in
// world space.

#include "res://shaders/sonar.gdshaderinc"
#include "res://shaders/sand_trails.gdshaderinc"
#include "res://shaders/world_ambient.gdshaderinc"

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
// Furrows: how much darker the groove is.
uniform float furrow_darken = 0.6;
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
	// The furrow's shade also shades the pulse's afterglow, so the pulse
	// shows the groove as it is.
	float furrow_shade = (1.0 - trail.x * furrow_darken) * (1.0 + trail.y * stirred_lighten);
	albedo *= furrow_shade;
	ALBEDO = albedo;
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;

	// The normal stays straight up (see the top).
	vec3 sonar = sonar_at(world_pos, vec3(0.0, 1.0, 0.0));
	EMISSION = sonar_color * (sonar.x * front_energy + sonar.z * fill_energy * furrow_shade)
		+ world_ambient(world_pos, albedo);
}
