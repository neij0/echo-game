shader_type spatial;
// Room surfaces (floor, rocks, walls): dark lit rock with a little grain, the
// world's faint ambient (world_ambient.gdshaderinc), plus
// the sonar in world space (the wave front crossing the surface, a faint
// afterglow shaded towards the pulse, contour lines on steep faces) and the
// cut-away (rock between the camera and a character is removed; turned on
// per material with cut_enabled: the floor never is).

#include "res://shaders/sonar.gdshaderinc"
#include "res://shaders/cutaway.gdshaderinc"
#include "res://shaders/world_ambient.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.1, 0.12, 0.16);
uniform float grain_scale = 1.6;
uniform float grain_strength = 0.3;
uniform vec3 sonar_color : source_color = vec3(0.25, 0.85, 1.0);
uniform float front_energy = 0.9;
uniform float fill_energy = 0.22;
uniform float contour_spacing = 0.5;
uniform float contour_width = 0.035;
uniform float contour_energy = 0.5;
uniform bool cut_enabled = false;
uniform vec3 cut_rim_color : source_color = vec3(0.25, 0.6, 0.8);
uniform float cut_rim_energy = 0.35;

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
	vec2 cut = vec2(0.0);
	if (cut_enabled) {
		cut = cutaway_at(world_pos);
		// The rock still casts its whole shadow: only the view is cut.
		if (cut.x > 0.5 && !IN_SHADOW_PASS) {
			discard;
		}
	}

	float grain = noise(world_pos * grain_scale) * 0.65 + noise(world_pos * grain_scale * 3.7) * 0.35;
	vec3 albedo = base_color * (1.0 + (grain - 0.5) * 2.0 * grain_strength);
	ALBEDO = albedo;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;

	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 sonar = sonar_at(world_pos, world_normal);
	float steep = 1.0 - abs(world_normal.y);
	float band = abs(fract(world_pos.y / contour_spacing + 0.5) - 0.5) * contour_spacing;
	float contour = (1.0 - smoothstep(0.0, contour_width, band)) * steep;
	EMISSION = sonar_color * (sonar.x * front_energy + sonar.z * fill_energy + sonar.y * contour * contour_energy)
		+ cut_rim_color * cut.y * cut_rim_energy + world_ambient(world_pos, albedo);
}
