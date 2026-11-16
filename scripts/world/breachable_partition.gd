extends VoxelDestructible

@export var link_path: NodePath
var passage_open := false

func _process(_delta: float) -> void:
	if passage_open: return
	if cell_health.size() != dimensions.x * dimensions.y * dimensions.z: return
	# Require a complete 1.25 x 2 meter clearance through both voxel layers.
	for x in range(3,8):
		for y in range(8):
			for z in range(dimensions.z):
				if cell_health[_index(Vector3i(x,y,z))] > 0: return
	passage_open = true
	var link := get_node_or_null(link_path) as NavigationLink3D
	if link != null: link.enabled = true
