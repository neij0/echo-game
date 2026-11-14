// Shared by the natural-look surface shaders (ocean_floor, ocean_rock): small
// hash / value-noise helpers and the depth tint (the colour of everything
// sinks towards depth_tint_deep from the top of a stage to its bottom; the
// LevelBuilder sets where this level starts and how fast it deepens).

uniform vec3 depth_tint_deep : source_color = vec3(0.6, 0.72, 0.9);
// Stage progress (0-1) at world z = 0, and how much it grows per world unit.
uniform float depth_start = 0.0;
uniform float depth_per_unit = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(0.3183099, 0.3678794) + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * (p.x + p.y));
}

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash31(i), hash31(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash31(i + vec3(0.0, 1.0, 0.0)), hash31(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash31(i + vec3(0.0, 0.0, 1.0)), hash31(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash31(i + vec3(0.0, 1.0, 1.0)), hash31(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

// The colour multiplier of the depth at a world point (1 = the stage's top).
vec3 depth_tint(vec3 world) {
	float depth = clamp(depth_start + world.z * depth_per_unit, 0.0, 1.0);
	return mix(vec3(1.0), depth_tint_deep, depth);
}
