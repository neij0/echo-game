shader_type spatial;
// Full-screen pass (a quad glued to the camera): finds the edges of the opaque
// world in the depth + normal buffers (silhouettes and creases) and lights
// them where a pulse has passed. Only rock, landmarks and creatures get
// outlines: a crease between two surfaces that both face up (floor detail,
// sand trails, a gentle bump on a rock top) is never one. Characters are drawn in the transparent pass,
// so they are not in these buffers and get their own outlines instead.
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://shaders/sonar.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;
uniform vec3 edge_color : source_color = vec3(0.3, 0.9, 1.0);
uniform float edge_energy = 3.2;
uniform float front_boost = 1.5;
// Line thickness in pixels.
uniform float edge_width = 1.4;
// Depth curvature (world units) that counts as a silhouette.
uniform float depth_threshold = 0.12;
uniform float normal_threshold = 0.1;
// A surface whose world normal points up more than this counts as floor-like.
uniform float up_facing = 0.8;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

vec3 view_at(vec2 uv, mat4 inv_projection) {
	float depth = texture(depth_tex, uv).r;
	vec4 view = inv_projection * vec4(uv * 2.0 - 1.0, depth, 1.0);
	return view.xyz / view.w;
}

vec3 normal_at(vec2 uv) {
	return normalize(texture(normal_tex, uv).xyz * 2.0 - 1.0);
}

// How sharply two neighbouring view-space normals bend; 0 when both face up
// (floor-like surfaces never get an outline).
float crease(vec3 a, vec3 b, mat4 inv_view) {
	float a_up = (inv_view * vec4(a, 0.0)).y;
	float b_up = (inv_view * vec4(b, 0.0)).y;
	if (min(a_up, b_up) > up_facing) {
		return 0.0;
	}
	return 1.0 - dot(a, b);
}

void fragment() {
	vec2 px = edge_width / VIEWPORT_SIZE;
	vec2 uv = SCREEN_UV;
	vec3 center = view_at(uv, INV_PROJECTION_MATRIX);
	vec3 left = view_at(uv - vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	vec3 right = view_at(uv + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	vec3 up = view_at(uv - vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	vec3 down = view_at(uv + vec2(0.0, px.y), INV_PROJECTION_MATRIX);

	// Second derivative of the depth: zero on any flat surface, large where one
	// object ends in front of another.
	float curve = abs(left.z + right.z - 2.0 * center.z) + abs(up.z + down.z - 2.0 * center.z);
	float depth_edge = smoothstep(depth_threshold, depth_threshold * 2.0, curve);

	vec3 normal = normal_at(uv);
	float bend = 0.0;
	bend = max(bend, crease(normal, normal_at(uv - vec2(px.x, 0.0)), INV_VIEW_MATRIX));
	bend = max(bend, crease(normal, normal_at(uv + vec2(px.x, 0.0)), INV_VIEW_MATRIX));
	bend = max(bend, crease(normal, normal_at(uv - vec2(0.0, px.y)), INV_VIEW_MATRIX));
	bend = max(bend, crease(normal, normal_at(uv + vec2(0.0, px.y)), INV_VIEW_MATRIX));
	float normal_edge = smoothstep(normal_threshold, normal_threshold * 3.0, bend);

	float edge = max(depth_edge, normal_edge);
	if (edge <= 0.001) {
		discard;
	}

	// The edge belongs to whatever is in front: light it by that point.
	vec3 nearest = center;
	if (left.z > nearest.z) { nearest = left; }
	if (right.z > nearest.z) { nearest = right; }
	if (up.z > nearest.z) { nearest = up; }
	if (down.z > nearest.z) { nearest = down; }
	vec3 world = (INV_VIEW_MATRIX * vec4(nearest, 1.0)).xyz;
	vec3 sonar = sonar_at(world, vec3(0.0, 1.0, 0.0));

	ALBEDO = edge_color * edge_energy * edge * (sonar.y + sonar.x * front_boost);
}
