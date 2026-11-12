// Shared by every shader the sonar touches (room surfaces, the edge pass, the
// marine snow). The Sonar node sets these uniforms on every registered
// material. A pulse is a cylinder growing from its origin (distance measured
// on the floor plane), each with its own speed and reach. occlusion_map
// holds, per pulse (row) and per direction (column), how far the pulse gets
// before a rock stops it.

const int PULSE_SLOTS = 4;

uniform vec3 pulse_origin[4];
// Seconds since the pulse was sent; below 0 = unused slot.
uniform float pulse_age[4];
// World units per second, and how far the pulse reaches.
uniform float pulse_speed[4];
uniform float pulse_radius[4];
uniform float pulse_hold = 1.4;
uniform float pulse_fade = 2.2;
uniform float front_width = 0.3;
uniform float occlusion_bias = 0.3;
uniform float occlusion_soft = 0.25;
// The top of a rock the pulse hits is shown this far back from its front edge
// (points above top_reach_height only), so its outline closes.
uniform float top_reach = 2.6;
uniform float top_reach_height = 0.5;
uniform sampler2D occlusion_map : filter_linear, repeat_enable;

// The look of the sonar (Sonar.style): 0 = light wave (the pulse lights the
// surfaces it passes, shaded from its origin, then they fade back into the
// dark), 1 = point cloud (glowing dots on the surfaces it passed), 2 = soft
// outlines (the full-screen edge pass, thin and pale, plus the afterglow).
// Every style uses the same reach and the same rock blocking (occlusion_map).
uniform int sonar_style = 2;
// Light wave: colour and strength of the light, how much brighter the
// passing front is, the light's height above the origin, seconds until the
// lit surfaces are dark again, and its fall-off with distance.
uniform vec3 wave_color : source_color = vec3(0.65, 0.82, 0.95);
uniform float wave_energy = 14.0;
uniform float wave_front_boost = 1.2;
uniform float wave_height = 1.5;
uniform float wave_fade = 3.6;
uniform float wave_falloff = 0.05;
// Point cloud: dot spacing and radius (world units), longest seconds a dot
// glows (each its own share of it), dot strength, and a faint fill under them.
uniform float dot_spacing = 0.28;
uniform float dot_radius = 0.036;
uniform float dot_life = 2.6;
uniform float dot_energy = 2.4;
uniform float dot_fill_share = 0.25;

// The terms of pulse slot i at a world point; false for an unused slot.
// visible = inside its reach and not behind rock, since = seconds since its
// front passed (below 0 = not yet), front = the front passing right now.
bool sonar_pulse(int i, vec3 world, out float visible, out float since, out float front) {
	visible = 0.0;
	since = -1.0;
	front = 0.0;
	float age = pulse_age[i];
	if (age < 0.0) {
		return false;
	}
	float speed = max(pulse_speed[i], 0.01);
	float reach = pulse_radius[i];
	vec3 offset = world - pulse_origin[i];
	float dist = length(offset.xz);
	float angle = atan(offset.z, offset.x) / TAU + 0.5;
	float row = (float(i) + 0.5) / float(PULSE_SLOTS);
	float blocker = texture(occlusion_map, vec2(angle, row)).r + occlusion_bias;
	blocker += top_reach * smoothstep(top_reach_height, top_reach_height + 0.3, world.y);
	float seen = 1.0 - smoothstep(blocker, blocker + occlusion_soft, dist);
	float rim = 1.0 - smoothstep(reach * 0.8, reach, dist);
	visible = seen * rim;
	since = age - dist / speed;
	front = 1.0 - smoothstep(0.0, front_width, abs(since) * speed);
	return true;
}

// x = the wave front passing right now, y = the afterglow left behind,
// z = the afterglow shaded by how much the surface faces the pulse.
vec3 sonar_at(vec3 world, vec3 normal) {
	vec3 result = vec3(0.0);
	for (int i = 0; i < PULSE_SLOTS; i++) {
		float visible;
		float since;
		float front;
		if (!sonar_pulse(i, world, visible, since, front)) {
			continue;
		}
		float glow = step(0.0, since) * (1.0 - smoothstep(pulse_hold, pulse_hold + pulse_fade, since));
		vec3 to_origin = normalize(pulse_origin[i] + vec3(0.0, 0.6, 0.0) - world);
		float facing = 0.25 + 0.75 * max(dot(normal, to_origin), 0.0);
		result = max(result, vec3(front, glow, glow * facing) * visible);
	}
	return result;
}

// Light wave: how much of the pulse's light falls here (times albedo,
// wave_color and wave_energy), shaded by the surface's facing towards a point
// above the origin; dark behind rock. It fades slowly back into the dark.
float sonar_light(vec3 world, vec3 normal) {
	float result = 0.0;
	for (int i = 0; i < PULSE_SLOTS; i++) {
		float visible;
		float since;
		float front;
		if (!sonar_pulse(i, world, visible, since, front) || visible <= 0.0) {
			continue;
		}
		vec3 to_light = pulse_origin[i] + vec3(0.0, wave_height, 0.0) - world;
		float lambert = max(dot(normal, normalize(to_light)), 0.0);
		float t = clamp(since / max(wave_fade, 0.01), 0.0, 1.0);
		float lit = step(0.0, since) * (1.0 - t) * (1.0 - t);
		float falloff = 1.0 / (1.0 + dot(to_light, to_light) * wave_falloff);
		result = max(result, visible * lambert * falloff * (lit + front * wave_front_boost));
	}
	return result;
}

vec2 sonar_hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Point cloud: a glowing dot (0-1) where a jittered grid on the surface has
// one and the pulse has passed; each dot fades after its own time.
float sonar_dots(vec3 world, vec3 normal) {
	vec3 n = abs(normal);
	vec2 p = n.y >= max(n.x, n.z) ? world.xz : (n.x >= n.z ? world.zy : world.xy);
	vec2 grid = p / dot_spacing;
	vec2 cell = floor(grid);
	vec2 rnd = sonar_hash2(cell);
	float d = length(grid - cell - (0.1 + rnd * 0.8)) * dot_spacing;
	float shape = 1.0 - smoothstep(dot_radius * 0.4, dot_radius, d);
	if (shape <= 0.0) {
		return 0.0;
	}
	float life = dot_life * (0.45 + 0.55 * rnd.x);
	float result = 0.0;
	for (int i = 0; i < PULSE_SLOTS; i++) {
		float visible;
		float since;
		float front;
		if (!sonar_pulse(i, world, visible, since, front)) {
			continue;
		}
		float lit = step(0.0, since) * (1.0 - smoothstep(life * 0.4, life, since));
		result = max(result, visible * (lit + front * 1.5));
	}
	return result * shape;
}
