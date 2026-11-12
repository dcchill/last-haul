class_name VoxelDebrisManager
extends Node3D

const MAX_BODIES := 24
const LIFETIME := 6.0
const CELL_SIZE := 0.25
const TRIANGLE_INDICES := [0, 2, 1, 0, 3, 2]
const FACE_NEIGHBORS := [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.BACK, Vector3i.FORWARD]
const FACE_NORMALS := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
const FACE_CORNERS := [
	[Vector3(1,-1,-1), Vector3(1,1,-1), Vector3(1,1,1), Vector3(1,-1,1)],
	[Vector3(-1,-1,1), Vector3(-1,1,1), Vector3(-1,1,-1), Vector3(-1,-1,-1)],
	[Vector3(-1,1,-1), Vector3(-1,1,1), Vector3(1,1,1), Vector3(1,1,-1)],
	[Vector3(-1,-1,1), Vector3(-1,-1,-1), Vector3(1,-1,-1), Vector3(1,-1,1)],
	[Vector3(1,-1,1), Vector3(1,1,1), Vector3(-1,1,1), Vector3(-1,-1,1)],
	[Vector3(-1,-1,-1), Vector3(-1,1,-1), Vector3(1,1,-1), Vector3(1,-1,-1)]]
var debris: Array[Dictionary] = []

func spawn_debris(position: Vector3, color: Color, impulse_direction: Vector3 = Vector3.FORWARD) -> void:
	for piece in debris:
		if piece.body.global_position.distance_to(position) <= CELL_SIZE * 1.5:
			_add_cell(piece.body, piece.body.to_local(position), color)
			piece.body.linear_velocity += impulse_direction.normalized() * 1.5
			return
	while debris.size() >= MAX_BODIES:
		debris.pop_front().body.queue_free()
	var body := _new_body()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * CELL_SIZE
	_add_cell(body, Vector3.ZERO, color, mesh)
	add_child(body)
	body.global_position = position
	body.linear_velocity = impulse_direction.normalized() * 1.5 + Vector3.UP * 0.4
	debris.append({"body": body, "age": 0.0})

func spawn_cluster(positions: Array[Vector3], color: Color, impulse_direction: Vector3) -> void:
	if positions.is_empty():
		return
	while debris.size() >= MAX_BODIES:
		debris.pop_front().body.queue_free()
	var low := positions[0]
	var high := positions[0]
	for position in positions:
		low = low.min(position)
		high = high.max(position)
	var center := (low + high) * 0.5
	var size := high - low + Vector3.ONE * CELL_SIZE
	var occupied := {}
	for position in positions:
		occupied[_cell_key(position)] = true
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for position in positions:
		var cell := _cell_key(position)
		for face in 6:
			if occupied.has(cell + FACE_NEIGHBORS[face]):
				continue
			for index in TRIANGLE_INDICES:
				tool.set_normal(FACE_NORMALS[face])
				tool.add_vertex(position - center + FACE_CORNERS[face][index] * CELL_SIZE * 0.5)
	var mesh := tool.commit()
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	var surface := StandardMaterial3D.new()
	surface.albedo_color = color
	visual.material_override = surface
	var body := _new_body()
	body.add_child(visual)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	add_child(body)
	body.global_position = center
	body.linear_velocity = impulse_direction.normalized() * 1.5 + Vector3.UP * 0.4
	debris.append({"body": body, "age": 0.0})

func _new_body() -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1
	return body

func _cell_key(position: Vector3) -> Vector3i:
	return Vector3i(roundi(position.x / CELL_SIZE), roundi(position.y / CELL_SIZE), roundi(position.z / CELL_SIZE))

func _add_cell(body: RigidBody3D, local_position: Vector3, color: Color, mesh: BoxMesh = null) -> void:
	if mesh == null:
		mesh = BoxMesh.new()
		mesh.size = Vector3.ONE * CELL_SIZE
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.position = local_position
	body.add_child(visual)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = mesh.size
	shape.shape = box
	shape.position = local_position
	body.add_child(shape)

func _process(delta: float) -> void:
	for index in range(debris.size() - 1, -1, -1):
		debris[index].age += delta
		if debris[index].age >= LIFETIME:
			debris[index].body.queue_free()
			debris.remove_at(index)
