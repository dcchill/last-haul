class_name VoxelDestructible
extends StaticBody3D

const CELL_SIZE := 0.25
const CELL_HEALTH := 6.25
const TRIANGLE_INDICES := [0, 2, 1, 0, 3, 2]
const FACE_NEIGHBORS := [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const FACE_NORMALS := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
const FACE_CORNERS := [
	[Vector3(1,-1,-1), Vector3(1,1,-1), Vector3(1,1,1), Vector3(1,-1,1)],
	[Vector3(-1,-1,1), Vector3(-1,1,1), Vector3(-1,1,-1), Vector3(-1,-1,-1)],
	[Vector3(-1,1,-1), Vector3(-1,1,1), Vector3(1,1,1), Vector3(1,1,-1)],
	[Vector3(-1,-1,1), Vector3(-1,-1,-1), Vector3(1,-1,-1), Vector3(1,-1,1)],
	[Vector3(1,-1,1), Vector3(1,1,1), Vector3(-1,1,1), Vector3(-1,-1,1)],
	[Vector3(-1,-1,-1), Vector3(-1,1,-1), Vector3(1,1,-1), Vector3(1,-1,-1)]]

@export var dimensions := Vector3i(8, 4, 4)
@export var material: MaterialDef
@export var surface_color := Color(0.32, 0.4, 0.43)
@export var debris_manager_path: NodePath

@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var surface: MeshInstance3D = $MeshInstance3D
var cell_health := PackedFloat32Array()
@export var blast_resistance: float = 6.0

func blast(origin: Vector3, power: float) -> void:
	# Adapter: source explosion pressure applied to the existing quarter-meter cells.
	var hits: Array[Vector3] = []
	for z in range(dimensions.z):
		for y in range(dimensions.y):
			for x in range(dimensions.x):
				if cell_health[_index(Vector3i(x, y, z))] <= 0:
					continue
				var point: Vector3 = global_transform * ((Vector3(x, y, z) + Vector3.ONE * 0.5) * CELL_SIZE - Vector3(dimensions) * CELL_SIZE * 0.5)
				var distance := point.distance_to(origin)
				if distance > power:
					continue
				var query := PhysicsRayQueryParameters3D.create(origin, point, 1, [get_rid()])
				if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
					continue
				if power * 1.3 - distance * 0.75 > (blast_resistance + 0.3) * 0.3:
					hits.append(point)
	for point in hits:
		damage_at(point, CELL_HEALTH, (point - origin).normalized())

func _ready() -> void:
	cell_health.resize(dimensions.x * dimensions.y * dimensions.z)
	cell_health.fill(CELL_HEALTH)
	var visual_material := StandardMaterial3D.new()
	visual_material.albedo_color = surface_color
	surface.material_override = visual_material
	_rebuild()

func damage_at(world_position: Vector3, damage: float, impulse_direction: Vector3 = Vector3.FORWARD) -> bool:
	var local := to_local(world_position) + Vector3(dimensions) * CELL_SIZE * 0.5
	var cell := Vector3i(floori(local.x / CELL_SIZE), floori(local.y / CELL_SIZE), floori(local.z / CELL_SIZE))
	cell = Vector3i(clampi(cell.x, 0, dimensions.x - 1), clampi(cell.y, 0, dimensions.y - 1), clampi(cell.z, 0, dimensions.z - 1))
	var index := _index(cell)
	if cell_health[index] <= 0.0:
		return false
	cell_health[index] = maxf(0.0, cell_health[index] - damage)
	if cell_health[index] == 0.0:
		var center := (Vector3(cell) + Vector3.ONE * 0.5) * CELL_SIZE - Vector3(dimensions) * CELL_SIZE * 0.5
		get_node(debris_manager_path).call_deferred("spawn_debris", global_transform * center, surface_color, impulse_direction)
		_detach_unsupported(impulse_direction)
		_rebuild()
	return true

func remaining_cells() -> int:
	var count := 0
	for health in cell_health:
		if health > 0.0:
			count += 1
	return count

func _index(cell: Vector3i) -> int:
	return cell.x + dimensions.x * (cell.y + dimensions.y * cell.z)

func _rebuild() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in dimensions.z:
		for y in dimensions.y:
			for x in dimensions.x:
				var cell := Vector3i(x, y, z)
				if cell_health[_index(cell)] <= 0.0:
					continue
				for face in 6:
					var neighbor: Vector3i = cell + FACE_NEIGHBORS[face]
					if _inside(neighbor) and cell_health[_index(neighbor)] > 0.0:
						continue
					_add_face(tool, cell, face)
	var mesh := tool.commit()
	surface.mesh = mesh
	var shape := mesh.create_trimesh_shape() if mesh.get_surface_count() > 0 else null
	if is_inside_tree():
		collision.set_deferred("shape", shape)
	else:
		collision.shape = shape

func _inside(cell: Vector3i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.z >= 0 and cell.x < dimensions.x and cell.y < dimensions.y and cell.z < dimensions.z

func _detach_unsupported(impulse_direction: Vector3) -> void:
	var support := PackedByteArray()
	support.resize(cell_health.size())
	var queue: Array[Vector3i] = []
	for z in dimensions.z:
		for x in dimensions.x:
			var floor_cell := Vector3i(x, 0, z)
			var floor_index := _index(floor_cell)
			if cell_health[floor_index] > 0.0:
				support[floor_index] = 1
				queue.append(floor_cell)
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for neighbor_offset in FACE_NEIGHBORS:
			var neighbor: Vector3i = cell + neighbor_offset
			if _inside(neighbor):
				var index := _index(neighbor)
				if support[index] == 0 and cell_health[index] > 0.0:
					support[index] = 1
					queue.append(neighbor)
	for z in dimensions.z:
		for y in dimensions.y:
			for x in dimensions.x:
				var start := Vector3i(x, y, z)
				var start_index := _index(start)
				if support[start_index] != 0 or cell_health[start_index] <= 0.0:
					continue
				support[start_index] = 2
				var component: Array[Vector3i] = [start]
				head = 0
				while head < component.size():
					var cell := component[head]
					head += 1
					for neighbor_offset in FACE_NEIGHBORS:
						var neighbor: Vector3i = cell + neighbor_offset
						if _inside(neighbor):
							var index := _index(neighbor)
							if support[index] == 0 and cell_health[index] > 0.0:
								support[index] = 2
								component.append(neighbor)
				var positions: Array[Vector3] = []
				for member in component:
					var local_center := (Vector3(member) + Vector3.ONE * 0.5) * CELL_SIZE - Vector3(dimensions) * CELL_SIZE * 0.5
					positions.append(global_transform * local_center)
					cell_health[_index(member)] = 0.0
				get_node(debris_manager_path).call_deferred("spawn_cluster", positions, surface_color, impulse_direction)

func _add_face(tool: SurfaceTool, cell: Vector3i, face: int) -> void:
	var center := (Vector3(cell) + Vector3.ONE * 0.5) * CELL_SIZE - Vector3(dimensions) * CELL_SIZE * 0.5
	var points: Array = FACE_CORNERS[face]
	for index in TRIANGLE_INDICES:
		tool.set_normal(FACE_NORMALS[face])
		tool.add_vertex(center + points[index] * CELL_SIZE * 0.5)

