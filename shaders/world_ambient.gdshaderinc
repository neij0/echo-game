// The world's own faint light (Darkness, "world ambient"): a uniform deep-blue
// light from the far surface on every level surface, sinking into darkness
// with distance from the camera's focus like fog, so the floor and the rock
// silhouettes on screen read faintly while the far layout stays black (the
// pulse is the way to see it). Lights and the pulse are not affected. The
// values are pushed by Darkness (register_material); energy 0 = off.

uniform vec3 world_ambient_color : source_color = vec3(0.14, 0.26, 0.62);
uniform float world_ambient_energy = 0.0;
// The camera's focus on the floor (x, z are used).
uniform vec3 world_ambient_focus = vec3(0.0);
// Distance from the focus (world units, on the floor) where the fog starts
// and where everything has sunk into darkness.
uniform float world_ambient_fog_begin = 9.0;
uniform float world_ambient_fog_end = 22.0;

vec3 world_ambient(vec3 world, vec3 albedo) {
	float distance_to_focus = length(world.xz - world_ambient_focus.xz);
	float keep = 1.0 - smoothstep(world_ambient_fog_begin, world_ambient_fog_end, distance_to_focus);
	return albedo * world_ambient_color * world_ambient_energy * keep;
}
