// Shared by every shader the sonar touches (room surfaces, the edge pass, the
// marine snow). ProtoSonar sets these uniforms on every registered material.
// A pulse is a cylinder growing from its origin (distance measured on the
// floor plane). occlusion_map holds, per pulse (row) and per direction
// (column), how far the pulse gets before a rock stops it.

const int PULSE_SLOTS = 2;

uniform vec3 pulse_origin[2];
// Seconds since the pulse was sent; below 0 = unused slot.
uniform float pulse_age[2];
uniform float pulse_speed = 11.0;
uniform float pulse_radius = 17.0;
uniform float pulse_hold = 1.4;
uniform float pulse_fade = 2.2;
uniform float front_width = 0.45;
uniform float occlusion_bias = 0.3;
uniform float occlusion_soft = 0.25;
// The top of a rock the pulse hits is shown this far back from its front edge
// (points above top_reach_height only), so its outline closes.
uniform float top_reach = 2.6;
uniform float top_reach_height = 0.8;
uniform sampler2D occlusion_map : filter_linear, repeat_enable;

// x = the wave front passing right now, y = the afterglow left behind,
// z = the afterglow shaded by how much the surface faces the pulse.
vec3 sonar_at(vec3 world, vec3 normal) {
	vec3 result = vec3(0.0);
	for (int i = 0; i < PULSE_SLOTS; i++) {
		float age = pulse_age[i];
		if (age < 0.0) {
			continue;
		}
		vec3 offset = world - pulse_origin[i];
		float dist = length(offset.xz);
		float angle = atan(offset.z, offset.x) / TAU + 0.5;
		float row = (float(i) + 0.5) / float(PULSE_SLOTS);
		float blocker = texture(occlusion_map, vec2(angle, row)).r + occlusion_bias;
		blocker += top_reach * smoothstep(top_reach_height, top_reach_height + 0.4, world.y);
		float seen = 1.0 - smoothstep(blocker, blocker + occlusion_soft, dist);
		float rim = 1.0 - smoothstep(pulse_radius * 0.8, pulse_radius, dist);
		float since = age - dist / pulse_speed;
		float glow = step(0.0, since) * (1.0 - smoothstep(pulse_hold, pulse_hold + pulse_fade, since));
		float front = 1.0 - smoothstep(0.0, front_width, abs(since) * pulse_speed);
		vec3 to_origin = normalize(pulse_origin[i] + vec3(0.0, 0.6, 0.0) - world);
		float facing = 0.25 + 0.75 * max(dot(normal, to_origin), 0.0);
		result = max(result, vec3(front, glow, glow * facing) * seen * rim);
	}
	return result;
}
