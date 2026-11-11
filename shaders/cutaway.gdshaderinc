// The rock cut-away: rock that stands between the camera and a character is
// removed inside a circle round that character on screen, so nobody is ever
// hidden. The ViewCutaway node sets these uniforms on every registered rock
// material. Everything is measured in world units on the camera's own axes
// (an orthographic camera, so this is exact).

const int CUT_POINTS = 6;

// The middle of each character to keep visible.
uniform vec3 cut_point[6];
// Radius of the hole on the screen plane; 0 = no hole for this point.
uniform float cut_radius[6];
// The camera's axes in world space (right, up, and towards the camera).
uniform vec3 cut_view_right = vec3(1.0, 0.0, 0.0);
uniform vec3 cut_view_up = vec3(0.0, 1.0, 0.0);
uniform vec3 cut_view_back = vec3(0.0, 0.0, 1.0);
// Rock this much nearer the camera than the character counts as in front.
uniform float cut_depth_margin = 0.25;
// Width of the glowing rim round the hole.
uniform float cut_rim_width = 0.22;

// x = 1 inside a hole (the fragment is dropped), y = the rim round it (0-1).
vec2 cutaway_at(vec3 world) {
	float hole = 0.0;
	float rim = 0.0;
	for (int i = 0; i < CUT_POINTS; i++) {
		float radius = cut_radius[i];
		if (radius <= 0.0) {
			continue;
		}
		vec3 offset = world - cut_point[i];
		if (dot(offset, cut_view_back) < cut_depth_margin) {
			continue;
		}
		float dist = length(vec2(dot(offset, cut_view_right), dot(offset, cut_view_up)));
		hole = max(hole, step(dist, radius));
		rim = max(rim, 1.0 - smoothstep(radius, radius + cut_rim_width, dist));
	}
	return vec2(hole, rim);
}
