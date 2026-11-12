extends SceneTree

# Re-run after changing the yard's static geometry. Saves the baked editable scene.
func _initialize() -> void:
	call_deferred("_bake")

func _bake() -> void:
	var scene: PackedScene = load("res://scenes/raid/test_yard.tscn")
	var yard := scene.instantiate()
	root.add_child(yard)
	yard.set_physics_process(false)
	yard.get_node("Player").set_physics_process(false)
	var region: NavigationRegion3D = yard.get_node("NavigationRegion3D")
	region.bake_navigation_mesh(false)
	var packed := PackedScene.new()
	var error := packed.pack(yard)
	if error == OK:
		error = ResourceSaver.save(packed, "res://scenes/raid/test_yard.tscn")
	print("Navigation bake: ", error_string(error), " · polygons: ", region.navigation_mesh.get_polygon_count())
	var passed := error == OK and region.navigation_mesh.get_polygon_count() > 0
	yard.free()
	quit(0 if passed else 1)
