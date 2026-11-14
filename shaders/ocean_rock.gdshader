shader_type spatial;
render_mode ensure_correct_normals;
// Rock of the natural look (WorldLook): the room's rock, the kit pieces
// standing on it and the outer rock. A CC0 PBR rock texture laid on in world
// space from three sides (no UVs: pieces of any size and turn read as one
// rock), strata bands and cracks, a darker base dusted with sand, moss in
// sheltered spots (low, in crevices, on ledges), barnacle clusters low on
// the sides, darker with depth; plus everything the classic rock has: the
// world's faint ambient, the pulse's wave of light and the cut-away.

#include "res://shaders/sonar.gdshaderinc"
#include "res://shaders/cutaway.gdshaderinc"
#include "res://shaders/world_ambient.gdshaderinc"
#include "res://shaders/surface_detail.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.24, 0.29, 0.36);
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : filter_linear_mipmap_anisotropic, repeat_enable;
// r = ambient occlusion, g = roughness.
uniform sampler2D rock_arm : filter_linear_mipmap, repeat_enable;
// World units one tile of the texture covers.
uniform float texture_size = 3.0;
// The texture's average colour (linear): see ocean_floor.
uniform vec3 texture_mean = vec3(0.2, 0.13, 0.09);
uniform float texture_tint : hint_range(0.0, 1.0) = 0.25;
uniform float texture_contrast = 1.1;
uniform float normal_strength = 1.0;
uniform float occlusion_strength : hint_range(0.0, 1.0) = 0.8;
// Share of the pulse's light this surface takes (0 = the outer rock).
uniform float pulse_share = 1.0;
uniform bool cut_enabled = false;
uniform vec3 cut_rim_color : source_color = vec3(0.25, 0.6, 0.8);
uniform float cut_rim_energy = 0.35;
// The world ambient comes from above: the share a face looking sideways or
// down keeps.
uniform float ambient_side_share : hint_range(0.0, 1.0) = 0.7;

group_uniforms strata;
// Layers of rock: their thickness (units), how much lighter / darker a layer
// is, the dark seam between two, and how far a noise bends them.
uniform float strata_spacing = 0.2;
uniform float strata_strength = 0.2;
uniform float strata_seam = 0.3;
uniform float strata_warp = 0.3;

group_uniforms cracks;
uniform float crack_scale = 1.1;
uniform float crack_width = 0.016;
uniform float crack_strength : hint_range(0.0, 1.0) = 0.5;
// Share of the cracks that shows on faces looking up.
uniform float crack_top_share : hint_range(0.0, 1.0) = 0.3;

group_uniforms base;
// Up to this height the rock darkens towards the floor and takes a dusting
// of the sand's colour.
uniform float base_height = 0.5;
uniform float base_darken : hint_range(0.0, 1.0) = 0.4;
uniform vec3 sand_color : source_color = vec3(0.15, 0.19, 0.25);
uniform float sand_dusting : hint_range(0.0, 1.0) = 0.5;
// Silt settled on faces that look up (a little lighter).
uniform float silt_lighten = 0.18;

group_uniforms growth;
uniform vec3 moss_color : source_color = vec3(0.07, 0.17, 0.13);
uniform float moss_scale = 0.55;
uniform float moss_amount : hint_range(0.0, 1.0) = 0.6;
// Moss thins out above this height.
uniform float moss_height = 1.0;
uniform vec3 barnacle_color : source_color = vec3(0.42, 0.44, 0.4);
// Size of a barnacle's cell (units), their share inside a cluster, and the
// height they thin out at.
uniform float barnacle_size = 0.13;
uniform float barnacle_amount : hint_range(0.0, 1.0) = 0.55;
uniform float barnacle_height = 0.8;

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 cut = vec2(0.0);
	if (cut_enabled) {
		cut = cutaway_at(world_pos);
		// The rock still casts its whole shadow: only the view is cut.
		if (cut.x > 0.5 && !IN_SHADOW_PASS) {
			discard;
		}
	}
	vec3 face_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	// The texture from three sides, weighted by the facing.
	vec3 weight = pow(abs(face_normal), vec3(4.0));
	weight /= weight.x + weight.y + weight.z;
	vec2 uv_x = world_pos.zy / texture_size;
	vec2 uv_y = world_pos.xz / texture_size;
	vec2 uv_z = world_pos.xy / texture_size;
	vec3 texel = texture(rock_albedo, uv_x).rgb * weight.x + texture(rock_albedo, uv_y).rgb * weight.y
		+ texture(rock_albedo, uv_z).rgb * weight.z;
	vec2 arm = texture(rock_arm, uv_x).rg * weight.x + texture(rock_arm, uv_y).rg * weight.y
		+ texture(rock_arm, uv_z).rg * weight.z;
	vec2 lean_x = (texture(rock_normal, uv_x).xy * 2.0 - 1.0) * normal_strength;
	vec2 lean_y = (texture(rock_normal, uv_y).xy * 2.0 - 1.0) * normal_strength;
	vec2 lean_z = (texture(rock_normal, uv_z).xy * 2.0 - 1.0) * normal_strength;
	// Each side's bumps added to the face normal ("whiteout" blend).
	vec3 bump_x = vec3(lean_x + face_normal.zy, face_normal.x);
	vec3 bump_y = vec3(lean_y + face_normal.xz, face_normal.y);
	vec3 bump_z = vec3(lean_z + face_normal.xy, face_normal.z);
	vec3 world_normal = normalize(bump_x.zyx * weight.x + bump_y.xzy * weight.y + bump_z.xyz * weight.z);

	vec3 detail = texel / max(texture_mean, vec3(0.001));
	float light_dark = dot(detail, vec3(0.3333));
	detail = mix(vec3(light_dark), detail, texture_tint);
	detail = max(mix(vec3(1.0), detail, texture_contrast), vec3(0.0));
	vec3 albedo = base_color * detail;
	float sheltered = 1.0 - arm.r;
	albedo *= mix(1.0, arm.r, occlusion_strength);

	// Strata: layers of uneven tone with a dark seam between them, on the
	// sides only.
	float upward = clamp(face_normal.y, 0.0, 1.0);
	float sideways = 1.0 - smoothstep(0.55, 0.9, upward);
	float layer_at = (world_pos.y + (noise3(world_pos * 0.6) - 0.5) * 2.0 * strata_warp
		+ dot(world_pos.xz, vec2(0.05, 0.03))) / strata_spacing;
	float layer_tone = hash21(vec2(floor(layer_at), 3.0)) - 0.5;
	float in_layer = fract(layer_at);
	float seam = 1.0 - smoothstep(0.0, 0.14, min(in_layer, 1.0 - in_layer));
	albedo *= 1.0 + sideways * (layer_tone * 2.0 * strata_strength - seam * strata_seam);

	// Cracks: thin dark lines where two noises cross their middle, in patches.
	// Stretched upwards, so they run down the sides as fissures; fainter on top.
	vec3 crack_at = world_pos * vec3(crack_scale, crack_scale * 0.4, crack_scale);
	float crack_a = abs(noise3(crack_at) - 0.5);
	float crack_b = abs(noise3(crack_at * 2.3 + 7.0) - 0.5) * 1.6;
	float crack = 1.0 - smoothstep(0.0, crack_width, min(crack_a, crack_b));
	crack *= smoothstep(0.45, 0.7, noise3(world_pos * 0.4 + 3.0)) * mix(crack_top_share, 1.0, sideways);
	albedo *= 1.0 - crack * crack_strength;

	// The base: darker towards the floor, dusted with sand; silt on top faces.
	float low = 1.0 - smoothstep(0.0, base_height, world_pos.y);
	float dust = low * low * sand_dusting * (0.5 + 0.5 * noise3(world_pos * 2.3));
	albedo = mix(albedo * (1.0 - low * base_darken), sand_color * (1.0 - base_darken * 0.5), dust);
	albedo *= 1.0 + upward * upward * silt_lighten;

	// Moss in sheltered spots: low, in crevices and on ledges, in patches.
	float moss_patch = smoothstep(0.42, 0.68, noise3(world_pos * moss_scale + 13.0) * 0.7
		+ noise3(world_pos * moss_scale * 3.1) * 0.3);
	float moss_place = (1.0 - smoothstep(moss_height * 0.4, moss_height, world_pos.y))
		* clamp(0.35 + 0.65 * upward + sheltered * 1.5, 0.0, 1.0);
	float moss = moss_patch * moss_place * moss_amount;
	albedo = mix(albedo, moss_color * (0.7 + 0.6 * light_dark), moss);

	// Barnacles: pale specks with a dark middle, clustered low on the sides.
	vec3 spot = world_pos / barnacle_size;
	vec3 spot_cell = floor(spot);
	vec3 spot_middle = vec3(hash31(spot_cell), hash31(spot_cell + 5.0), hash31(spot_cell + 11.0)) * 0.4 + 0.3;
	float spot_reach = length(fract(spot) - spot_middle);
	float cluster = smoothstep(0.55, 0.75, noise3(world_pos * 0.7 + 31.0))
		* (1.0 - smoothstep(barnacle_height * 0.5, barnacle_height, world_pos.y)) * (0.4 + 0.6 * sideways);
	float barnacle = (1.0 - smoothstep(0.2, 0.27, spot_reach)) * step(1.0 - barnacle_amount, hash31(spot_cell + 19.0)) * cluster;
	float barnacle_hole = 1.0 - smoothstep(0.05, 0.1, spot_reach);
	albedo = mix(albedo, barnacle_color * (1.0 - barnacle_hole * 0.75), barnacle);

	albedo *= depth_tint(world_pos);

	ALBEDO = albedo;
	ROUGHNESS = clamp(arm.g, 0.55, 1.0);
	SPECULAR = 0.2;
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);

	vec3 pulse = albedo * wave_color * wave_energy * pulse_share * sonar_light(world_pos, world_normal);
	float from_above = mix(ambient_side_share, 1.0, clamp(world_normal.y, 0.0, 1.0));
	EMISSION = pulse + cut_rim_color * cut.y * cut_rim_energy + world_ambient(world_pos, albedo) * from_above;
}
