extends SceneTree

class ProbeWall extends VoxelDestructible:
	var rebuilds := 0
	var support_checks := 0
	func _rebuild() -> void:
		rebuilds += 1
		super._rebuild()
	func _detach_unsupported(direction: Vector3) -> void:
		support_checks += 1
		super._detach_unsupported(direction)

var checks := 0
var failures := 0
var fixture := Node3D.new()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _initialize() -> void:
	call_deferred("_run")

func make_wall(size: Vector3i) -> ProbeWall:
	var wall := ProbeWall.new()
	wall.dimensions = size
	wall.debris_manager_path = NodePath("../Debris")
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	wall.add_child(collision)
	var surface := MeshInstance3D.new()
	surface.name = "MeshInstance3D"
	wall.add_child(surface)
	fixture.add_child(wall)
	return wall

func _run() -> void:
	check(not ClassDB.class_exists("VoxelTerrain") and not root.has_node("VoxelServer"), "our voxel system runs without external voxel plugins")
	root.add_child(fixture)
	var debris := VoxelDebrisManager.new()
	debris.name = "Debris"
	fixture.add_child(debris)
	var wall := make_wall(Vector3i(16, 8, 8))
	check(wall.surface.mesh.get_faces().size() == 36, "solid cover merges 1280 triangles into 12")
	verify_surface(wall, "solid")
	wall.free()
	for pattern in ["cavity", "tunnel", "checkerboard", "random", "empty"]:
		wall = make_wall(Vector3i(4, 3, 4))
		var rng := RandomNumberGenerator.new()
		rng.seed = 42
		for z in wall.dimensions.z:
			for y in wall.dimensions.y:
				for x in wall.dimensions.x:
					var remove: bool = (pattern == "cavity" and Vector3i(x, y, z) == Vector3i(1, 1, 1)) or (pattern == "tunnel" and x == 1 and y == 1) or (pattern == "checkerboard" and (x + y + z) % 2 == 0) or (pattern == "random" and rng.randf() < 0.4) or pattern == "empty"
					if remove: wall.cell_health[wall._index(Vector3i(x, y, z))] = 0
		wall._rebuild()
		verify_surface(wall, pattern)
		wall.free()
	wall = make_wall(Vector3i(16, 8, 8))
	wall.position = Vector3(0, 3, 0)
	for frame in 3: await physics_frame
	var ray := PhysicsRayQueryParameters3D.create(Vector3(0, 3, 3), Vector3(0, 3, -3), 1)
	check(not fixture.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "intact cover blocks a ray")
	wall.blast(Vector3(0, 3, 0.6), 2.0)
	check(wall.rebuilds == 2 and wall.support_checks == 1, "partial blast rebuilds and checks support once")
	check(wall.remaining_cells() > 0 and wall.remaining_cells() < 1024, "partial blast preserves surviving cells")
	verify_surface(wall, "partial blast")
	for frame in 3: await physics_frame
	var carved_hit := fixture.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not carved_hit.is_empty() and carved_hit.position.z < 0.75, "partial blast collision follows the carved surface")
	wall.free()
	wall = make_wall(Vector3i(8, 4, 4))
	wall.position = Vector3(0, 3, 0)
	for frame in 3: await physics_frame
	wall.blast(Vector3(100, 3, 0), 3)
	wall.blast(wall.global_position, 0)
	check(wall.rebuilds == 1 and wall.support_checks == 0, "missed and zero-power blasts skip rebuilding")
	wall.blast(wall.global_position, 3)
	check(wall.rebuilds == 2 and wall.support_checks == 1, "128 destroyed cells trigger one rebuild and support check")
	check(wall.remaining_cells() == 0 and wall.surface.mesh == null, "complete destruction clears the mesh")
	for frame in 3: await physics_frame
	check(wall.collision.shape == null and fixture.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "complete destruction clears collision")
	check(debris.debris.size() <= VoxelDebrisManager.MAX_BODIES, "batched destruction preserves the debris cap")
	wall.free()
	wall = make_wall(Vector3i(4, 3, 4))
	wall.position = Vector3(0, 3, 0)
	var blocker := StaticBody3D.new()
	var shield := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.25)
	shield.shape = box
	blocker.add_child(shield)
	fixture.add_child(blocker)
	blocker.position = Vector3(0, 3, 0.8)
	for frame in 3: await physics_frame
	wall.blast(Vector3(0, 3, 1.5), 3)
	check(wall.remaining_cells() == 48 and wall.rebuilds == 1, "solid shielding still occludes blast damage")
	blocker.free()
	wall.free()
	wall = make_wall(Vector3i(1, 3, 1))
	check(wall.damage_at(wall.global_position, 1), "direct damage still reduces cell health")
	check(wall.rebuilds == 1, "nonlethal damage does not rebuild geometry")
	wall.damage_at(wall.global_position + Vector3.DOWN * 0.25, VoxelDestructible.CELL_HEALTH)
	check(wall.remaining_cells() == 0, "unsupported cells detach after direct damage")
	fixture.free()
	for frame in 3: await process_frame
	print("VOXEL TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func verify_surface(wall: VoxelDestructible, label: String) -> void:
	# Independent per-cell visibility oracle checks that merging keeps every exposed face.
	var expected := {}
	for z in wall.dimensions.z:
		for y in wall.dimensions.y:
			for x in wall.dimensions.x:
				var cell := Vector3i(x, y, z)
				if wall.cell_health[wall._index(cell)] <= 0: continue
				for face in 6:
					var neighbor: Vector3i = cell + wall.FACE_NEIGHBORS[face]
					if not wall._inside(neighbor) or wall.cell_health[wall._index(neighbor)] <= 0:
						expected[Vector4i(x, y, z, face)] = true
	var actual := {}
	var valid := true
	if wall.surface.mesh != null:
		var arrays := wall.surface.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for start in range(0, vertices.size(), 6):
			var low := vertices[start]
			var high := low
			for offset in 6:
				low = low.min(vertices[start + offset])
				high = high.max(vertices[start + offset])
			var face: int = wall.FACE_NORMALS.find(normals[start].round())
			var axis := face / 2
			var u := (axis + 1) % 3
			var v := (axis + 2) % 3
			var first := Vector3i((low / wall.CELL_SIZE + Vector3(wall.dimensions) * 0.5).round())
			var end := Vector3i((high / wall.CELL_SIZE + Vector3(wall.dimensions) * 0.5).round())
			first[axis] -= 1 if face % 2 == 0 else 0
			for row in range(first[v], end[v]):
				for column in range(first[u], end[u]):
					var cell := first
					cell[u] = column
					cell[v] = row
					var key := Vector4i(cell.x, cell.y, cell.z, face)
					valid = valid and not actual.has(key)
					actual[key] = true
			for offset in [0, 3]:
				var normal := (vertices[start + offset + 1] - vertices[start + offset]).cross(vertices[start + offset + 2] - vertices[start + offset])
				valid = valid and normal.dot(normals[start]) < 0.0
	check(valid and actual.size() == expected.size() and expected.keys().all(func(key): return actual.has(key)), label + " preserves exposed faces, holes and winding")
