shader_type fog;
// Silt haze (natural look): a thin layer of drifting haze over the sea floor
// that the lights shine into. Densest at the floor, gone at `height`, in
// slow clouds that drift with `drift` (world units per second).

uniform float density = 0.06;
uniform float height = 1.6;
uniform float cloud_size = 7.0;
uniform vec2 drift = vec2(0.12, 0.05);
uniform vec3 color : source_color = vec3(0.5, 0.68, 0.85);

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

void fog() {
	float layer = 1.0 - smoothstep(0.0, height, WORLD_POSITION.y);
	vec3 p = vec3((WORLD_POSITION.xz - drift * TIME) / cloud_size, TIME * 0.02);
	float cloud = noise(p) * 0.65 + noise(p * 2.3 + 4.0) * 0.35;
	DENSITY = density * layer * smoothstep(0.25, 0.8, cloud);
	ALBEDO = color;
}
