// Shared by every shader the sonar touches (room surfaces, the ripple pass,
// the marine snow). The Sonar node sets these uniforms on every registered
// material. A pulse is a cylinder growing from its origin (distance measured
// on the floor plane), each with its own speed and reach. occlusion_map
// holds, per pulse (row) and per direction (column), how far the pulse gets
// before a rock stops it.
// The look is a wave of light (sonar_light): a soft bright band that lights
// the surfaces it passes, shaded towards a point above its origin, with soft
// shadows behind rock (a penumbra that widens with distance, never pure
// black), then the lit surfaces fade slowly back into the dark.

const int PULSE_SLOTS = 4;

uniform vec3 pulse_origin[4];
// Seconds since the pulse was sent; below 0 = unused slot.
uniform float pulse_age[4];
// World units per second, and how far the pulse reaches.
uniform float pulse_speed[4];
uniform float pulse_radius[4];
uniform float occlusion_bias = 0.3;
// Radial softness of a shadow's start behind a rock (units).
uniform float occlusion_soft = 0.35;
// The top of a rock the pulse hits is shown this far back from its front edge
// (points above top_reach_height only), so its outline closes.
uniform float top_reach = 2.6;
uniform float top_reach_height = 0.5;
uniform sampler2D occlusion_map : filter_linear, repeat_enable;
// Penumbra: its angle (radians) per unit behind the rock, relative to the
// distance from the origin, and its widest angle.
uniform float penumbra_rate = 0.35;
uniform float penumbra_max = 0.22;
// Light left in a shadow right behind the rock / far behind it (never black),
// and the distance (units) over which it goes from one to the other.
uniform float shadow_light_near = 0.08;
uniform float shadow_light_far = 0.25;
uniform float shadow_fade = 8.0;
// The wave's light: colour, strength, the light's height above the origin,
// seconds until the lit surfaces are dark again, fall-off with distance.
uniform vec3 wave_color : source_color = vec3(0.65, 0.82, 0.95);
uniform float wave_energy = 14.0;
uniform float wave_height = 1.5;
uniform float wave_fade = 3.6;
uniform float wave_falloff = 0.05;
// The front band: its peak, the soft lead ahead of it and the length of its
// tail (units); how much its light wraps round surfaces that face away (0 =
// plain facing, 1 = lights everything evenly); the light it leaves behind
// (then fading over wave_fade).
uniform float wave_peak = 3.0;
uniform float wave_lead = 0.5;
uniform float wave_tail = 1.3;
uniform float wave_wrap = 0.55;
uniform float wave_rest = 0.7;
// Marine snow: how far the front pushes a particle outward (units) and the
// seconds it takes to drift back.
uniform float push_distance = 0.5;
uniform float push_settle = 1.4;

float sonar_blocker(float angle, float row, float height) {
	return texture(occlusion_map, vec2(angle, row)).r + occlusion_bias
		+ top_reach * smoothstep(top_reach_height, top_reach_height + 0.3, height);
}

// The terms of pulse slot i at a world point; false for an unused slot.
// visible = inside its reach and not behind rock (soft: a penumbra that
// widens with distance behind the rock), behind = distance (units) past the
// nearest rock in that direction, since = seconds since its front passed
// (below 0 = not yet), along = units behind the front (below 0 = ahead).
bool sonar_pulse(int i, vec3 world, out float visible, out float behind, out float since, out float along) {
	visible = 0.0;
	behind = 0.0;
	since = -1.0;
	along = -1.0;
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
	float widest = penumbra_max / TAU;
	float nearest = min(sonar_blocker(angle, row, world.y),
		min(sonar_blocker(angle - widest, row, world.y), sonar_blocker(angle + widest, row, world.y)));
	behind = max(dist - nearest, 0.0);
	float spread = min(penumbra_rate * behind / max(dist, 0.5), penumbra_max) / TAU;
	float seen = 0.0;
	for (int k = -3; k <= 3; k++) {
		float blocker = sonar_blocker(angle + float(k) * spread / 3.0, row, world.y);
		seen += 1.0 - smoothstep(blocker, blocker + occlusion_soft, dist);
	}
	seen /= 7.0;
	float rim = 1.0 - smoothstep(reach * 0.8, reach, dist);
	visible = seen * rim;
	since = age - dist / speed;
	along = since * speed;
	return true;
}

// The wave front passing right now (0-1), for the marine snow's flash.
float sonar_front(vec3 world) {
	float result = 0.0;
	for (int i = 0; i < PULSE_SLOTS; i++) {
		float visible;
		float behind;
		float since;
		float along;
		if (!sonar_pulse(i, world, visible, behind, since, along)) {
			continue;
		}
		float band = along < 0.0 ? exp(along / wave_lead) : exp(-along / wave_tail);
		result = max(result, band * visible);
	}
	return result;
}

// How much of the pulses' light falls here (times albedo, wave_color and
// wave_energy): the soft bright front band, then the light it leaves behind
// fading slowly; shaded by the surface's facing towards a point above the
// origin; soft shadows behind rock.
float sonar_light(vec3 world, vec3 normal) {
	float result = 0.0;
	for (int i = 0; i < PULSE_SLOTS; i++) {
		float visible;
		float behind;
		float since;
		float along;
		if (!sonar_pulse(i, world, visible, behind, since, along)) {
			continue;
		}
		float rim = 1.0 - smoothstep(pulse_radius[i] * 0.8, pulse_radius[i], length((world - pulse_origin[i]).xz));
		float shadow_light = mix(shadow_light_near, shadow_light_far, smoothstep(0.0, shadow_fade, behind));
		float seen = visible / max(rim, 0.0001);
		float light = rim * mix(shadow_light, 1.0, seen);
		vec3 to_light = pulse_origin[i] + vec3(0.0, wave_height, 0.0) - world;
		float lambert = max(dot(normal, normalize(to_light)), 0.0);
		float wrapped = mix(lambert, 1.0, wave_wrap);
		float band;
		float rest = 0.0;
		if (along < 0.0) {
			band = exp(along / wave_lead);
		} else {
			float t = clamp(since / max(wave_fade, 0.01), 0.0, 1.0);
			band = exp(-along / wave_tail);
			rest = (1.0 - band) * (1.0 - t) * (1.0 - t);
		}
		float falloff = 1.0 / (1.0 + dot(to_light, to_light) * wave_falloff);
		result = max(result, light * falloff * (wave_peak * band * wrapped + wave_rest * rest * lambert));
	}
	return result;
}

// How far the fronts have pushed a point outward (marine snow): out with the
// front, then drifting back over push_settle seconds.
vec3 sonar_push(vec3 world) {
	vec3 result = vec3(0.0);
	for (int i = 0; i < PULSE_SLOTS; i++) {
		float visible;
		float behind;
		float since;
		float along;
		if (!sonar_pulse(i, world, visible, behind, since, along)) {
			continue;
		}
		vec2 out_dir = normalize((world - pulse_origin[i]).xz + vec2(0.0001));
		float amount = smoothstep(-wave_lead, wave_tail * 0.5, along) * exp(-max(since, 0.0) / max(push_settle, 0.01));
		result += vec3(out_dir.x, 0.0, out_dir.y) * amount * push_distance * visible;
	}
	return result;
}
