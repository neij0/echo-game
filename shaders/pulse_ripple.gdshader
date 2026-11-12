shader_type spatial;
// Full-screen pass (a quad glued to the camera, drawn only while a pulse is
// expanding): a subtle refraction ripple travelling with each wave front. It
// finds the world point under every pixel (depth buffer), and near a front it
// shifts the picture outward from the pulse's origin, like water bending the
// light. Drawn before the characters, so they stay sharp.
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://shaders/sonar.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
// Width of the ripple round the front (world units) and its strongest shift
// (share of the screen).
uniform float ripple_width = 0.7;
uniform float ripple_strength = 0.004;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz / view.w, 1.0)).xyz;
	vec2 shift = vec2(0.0);
	float amount = 0.0;
	for (int i = 0; i < PULSE_SLOTS; i++) {
		float age = pulse_age[i];
		if (age < 0.0) {
			continue;
		}
		float reach = pulse_radius[i];
		float front = age * max(pulse_speed[i], 0.01);
		if (front > reach + ripple_width) {
			continue;
		}
		float x = (length(world.xz - pulse_origin[i].xz) - front) / ripple_width;
		// One soft crest and trough round the front, fading as it nears its reach.
		float wave = sin(x * PI) * exp(-x * x * 1.5) * (1.0 - smoothstep(0.7, 1.0, front / reach));
		vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(pulse_origin[i], 1.0);
		vec2 origin_uv = clip.xy / clip.w * 0.5 + 0.5;
		vec2 out_dir = SCREEN_UV - origin_uv;
		out_dir.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
		out_dir = normalize(out_dir + vec2(0.00001));
		out_dir.x *= VIEWPORT_SIZE.y / VIEWPORT_SIZE.x;
		shift += out_dir * wave * ripple_strength;
		amount = max(amount, abs(wave));
	}
	if (amount < 0.02) {
		discard;
	}
	ALBEDO = texture(screen_tex, SCREEN_UV + shift).rgb;
}
