shader_type spatial;
// Room surfaces (floor, rocks, walls): dark lit rock with a little grain, plus
// the sonar in world space: the wave front crossing the surface, a faint
// afterglow shaded towards the pulse and contour lines on steep faces.

#include "res://proto3d/proto_sonar.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.1, 0.12, 0.16);
uniform float grain_scale = 1.6;
uniform float grain_strength = 0.3;
uniform vec3 sonar_color : source_color = vec3(0.25, 0.85, 1.0);
uniform float front_energy = 0.9;
uniform float fill_energy = 0.22;
uniform float contour_spacing = 0.5;
uniform float contour_width = 0.035;
uniform float contour_energy = 0.5;

varying vec3 world_pos;

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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float grain = noise(world_pos * grain_scale) * 0.65 + noise(world_pos * grain_scale * 3.7) * 0.35;
	ALBEDO = base_color * (1.0 + (grain - 0.5) * 2.0 * grain_strength);
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;

	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 sonar = sonar_at(world_pos, world_normal);
	float steep = 1.0 - abs(world_normal.y);
	float band = abs(fract(world_pos.y / contour_spacing + 0.5) - 0.5) * contour_spacing;
	float contour = (1.0 - smoothstep(0.0, contour_width, band)) * steep;
	EMISSION = sonar_color * (sonar.x * front_energy + sonar.z * fill_energy + sonar.y * contour * contour_energy);
}
