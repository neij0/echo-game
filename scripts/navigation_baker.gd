class_name NavigationBaker
extends RefCounted
## Bakes a 3D navigation mesh straight from the 2D floor plans (no physics or
## mesh parsing, so it is fast): the floor areas are walkable, every rock
## outline is an obstruction pulled up to its height, and the agent's radius
## keeps paths that far from rock. Outlines are on the floor plane (x, z) in
## world units. One mesh per agent size (the LevelBuilder bakes a second one
## for large creatures).


## floors: walkable areas (e.g. one square per room). rocks: outline + height.
## cell_size: the bake resolution (smaller = more exact, slower; the
## navigation map must use the same, see apply_to_map).
static func bake(floors: Array[PackedVector2Array], rocks: Array[Dictionary], agent_radius: float,
		cell_size: float, cell_height: float, agent_height: float = 1.0) -> NavigationMesh:
	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.cell_size = cell_size
	navigation_mesh.cell_height = cell_height
	navigation_mesh.agent_radius = agent_radius
	navigation_mesh.agent_height = agent_height
	# Nothing to climb on: every rock is a wall.
	navigation_mesh.agent_max_climb = cell_height
	navigation_mesh.agent_max_slope = 10.0
	navigation_mesh.region_min_size = 1.0

	var source := NavigationMeshSourceGeometryData3D.new()
	for outline: PackedVector2Array in floors:
		source.add_faces(_floor_faces(outline), Transform3D.IDENTITY)
	for rock: Dictionary in rocks:
		var outline: PackedVector2Array = rock["outline"]
		var points := PackedVector3Array()
		for point: Vector2 in outline:
			points.append(Vector3(point.x, 0.0, point.y))
		# From below the floor to the top, so it cuts through the floor.
		source.add_projected_obstruction(points, -1.0, float(rock["height"]) + 1.0, false)
	NavigationServer3D.bake_from_source_geometry_data(navigation_mesh, source)
	return navigation_mesh


## The world's navigation map must use the bake's cell size.
static func apply_to_map(map: RID, cell_size: float, cell_height: float) -> void:
	NavigationServer3D.map_set_cell_size(map, cell_size)
	NavigationServer3D.map_set_cell_height(map, cell_height)


## The floor area as triangles facing up.
static func _floor_faces(outline: PackedVector2Array) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(outline)
	for i: int in range(0, indices.size(), 3):
		var a: Vector2 = outline[indices[i]]
		var b: Vector2 = outline[indices[i + 1]]
		var c: Vector2 = outline[indices[i + 2]]
		var va := Vector3(a.x, 0.0, a.y)
		var vb := Vector3(b.x, 0.0, b.y)
		var vc := Vector3(c.x, 0.0, c.y)
		# Godot's front-face order (clockwise seen from above), or the floor is
		# not walkable.
		if (vb - va).cross(vc - va).y < 0.0:
			faces.append_array([va, vb, vc])
		else:
			faces.append_array([va, vc, vb])
	return faces
