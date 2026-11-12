// Sand trails (SandTrails): furrows and puffs of disturbed sand stamped into
// a texture that wraps over the world (a point's texel is its floor position
// modulo trail_window), so it never scrolls. r = the furrow (0 = untouched,
// 1 = deepest), g = freshly stirred sand (a short lighter patch).

uniform sampler2D trail_map : filter_linear, repeat_enable;
// World units covered by the texture before it wraps.
uniform float trail_window = 64.0;
// World units of one texel (for the slope of the furrow).
uniform float trail_texel = 0.0625;

vec2 trail_uv(vec3 world) {
	return world.xz / trail_window;
}

// x = furrow depth (0-1), y = stirred sand (0-1), zw = slope of the furrow
// along x and z (never used to tilt the floor's normal: a tilted normal
// would get sonar outlines).
vec4 trail_at(vec3 world) {
	vec2 uv = trail_uv(world);
	float step_uv = trail_texel / trail_window;
	vec2 here = texture(trail_map, uv).rg;
	float right = texture(trail_map, uv + vec2(step_uv * 1.5, 0.0)).r;
	float left = texture(trail_map, uv - vec2(step_uv * 1.5, 0.0)).r;
	float down = texture(trail_map, uv + vec2(0.0, step_uv * 1.5)).r;
	float up = texture(trail_map, uv - vec2(0.0, step_uv * 1.5)).r;
	return vec4(min(here.r, 1.0), min(here.g, 1.0), right - left, down - up);
}
