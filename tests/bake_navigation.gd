extends SceneTree

# Re-run after changing static raid geometry. Saves the baked editable scene.
func _initialize() -> void:
	call_deferred("_bake")

func _bake() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path := args[0] if not args.is_empty() else "res://scenes/raid/test_yard.tscn"
	var scene: PackedScene = load(scene_path)
	var yard := scene.instantiate()
	root.add_child(yard)
	yard.set_physics_process(false)
	yard.get_node("Player").set_physics_process(false)
	var region: NavigationRegion3D = yard.get_node("NavigationRegion3D")
	# Let voxel collision updates settle before collecting bake geometry.
	await physics_frame
	await physics_frame
	region.bake_navigation_mesh(false)
	# Save the authored scene with only the new navigation, excluding runtime sensor/robot changes.
	var output := scene.instantiate()
	output.get_node("NavigationRegion3D").navigation_mesh = region.navigation_mesh
	for node in output.find_children("*", "StaticBody3D", true, false):
		if node is VoxelDestructible:
			node.get_node("CollisionShape3D").shape = null
			node.get_node("MeshInstance3D").mesh = null
			node.get_node("MeshInstance3D").material_override = null
	var packed := PackedScene.new()
	var error := packed.pack(output)
	if error == OK:
		error = ResourceSaver.save(packed, scene_path)
	print("Navigation bake: ", error_string(error), " / polygons: ", region.navigation_mesh.get_polygon_count())
	var passed := error == OK and region.navigation_mesh.get_polygon_count() > 0
	output.free()
	yard.free()
	quit(0 if passed else 1)
