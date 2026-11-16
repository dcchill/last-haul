extends SceneTree

var checks := 0
var failures := 0
var entries: Array

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func settle(frames: int = 3) -> void:
	for i in range(frames): await physics_frame

func ray(from: Vector3, to: Vector3) -> Dictionary:
	return root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))

func run() -> void:
	entries = JSON.parse_string(FileAccess.get_file_as_string("res://resources/world_props/catalog.json"))
	check(entries.size() == 64, "exactly 64 props")
	var ids := {}
	var categories := {}
	var signatures := {}
	for entry: Dictionary in entries:
		check(not ids.has(entry.id), "unique ID: " + entry.id)
		ids[entry.id] = true
		categories[entry.category] = categories.get(entry.category, 0) + 1
		var prop: Node3D = load(entry.scene).instantiate()
		root.add_child(prop)
		var visual: MeshInstance3D = prop.get_node("Mesh")
		var mesh := visual.mesh
		check(mesh != null and mesh.get_surface_count() == 1, entry.id + " has merged mesh")
		var data := mesh.surface_get_arrays(0)
		var triangles: int = data[Mesh.ARRAY_INDEX].size() / 3
		check(triangles > 0 and triangles < 5000, entry.id + " triangle budget")
		var signature := hash(data[Mesh.ARRAY_VERTEX])
		check(not signatures.has(signature), entry.id + " has distinct geometry")
		signatures[signature] = true
		var bounds := mesh.get_aabb()
		check(bounds.size.x > 0 and bounds.size.y > 0 and bounds.size.z > 0 and absf(bounds.position.y) < 0.001, entry.id + " grounded valid bounds")
		check(bounds.size.is_equal_approx(Vector3(entry.bounds.size[0], entry.bounds.size[1], entry.bounds.size[2])), entry.id + " catalog bounds")
		check(prop.get_meta("prop_id") == entry.id and prop.get_meta("collision_mode") == entry.collision_mode, entry.id + " metadata")
		check(data[Mesh.ARRAY_COLOR].size() == data[Mesh.ARRAY_VERTEX].size(), entry.id + " vertex colors")
		var material: StandardMaterial3D = mesh.surface_get_material(0)
		check(material.vertex_color_use_as_albedo and material.resource_path.ends_with("palette.tres"), entry.id + " shared palette")
		if entry.collision_mode == "static":
			var body: DecorativeProp = prop.get_node("Collision")
			check(body.material != null and body.collision_layer == 1 and body.get_child_count() > 0, entry.id + " collision and material")
			for shape: CollisionShape3D in body.get_children():
				check(shape.shape is BoxShape3D and shape.shape.size.x > 0 and shape.shape.size.y > 0 and shape.shape.size.z > 0, entry.id + " valid box")
		else:
			check(not prop.has_node("Collision"), entry.id + " visual only")
		prop.free()
	check(categories.size() == 8 and categories.values().all(func(count): return count == 8), "eight categories of eight")
	for id in ["sedan", "concrete_barrier", "short_shipping_container"]:
		var prop: Node3D = load("res://scenes/props/" + id + ".tscn").instantiate()
		root.add_child(prop)
		await settle()
		var hit := ray(Vector3(4, 0.8, 0), Vector3(-4, 0.8, 0))
		check(not hit.is_empty() and hit.collider == prop.get_node("Collision"), id + " blocks projectile ray")
		var mover := CharacterBody3D.new()
		var capsule := CollisionShape3D.new()
		capsule.shape = CapsuleShape3D.new()
		mover.add_child(capsule)
		root.add_child(mover)
		mover.position = Vector3(4, 0.9, 0)
		check(mover.move_and_collide(Vector3(-8, 0, 0), true) != null, id + " blocks player capsule")
		mover.free()
		prop.free()
	var open: Node3D = load("res://scenes/props/open_shipping_container.tscn").instantiate()
	root.add_child(open)
	await settle()
	check(ray(Vector3(0, 1, -5), Vector3(0, 1, 2)).is_empty(), "container opening admits rays")
	check(not ray(Vector3(0, 1, 0), Vector3(2, 1, 0)).is_empty(), "container side remains solid")
	open.free()
	var fence: Node3D = load("res://scenes/props/damaged_gate.tscn").instantiate()
	root.add_child(fence)
	await settle()
	check(ray(Vector3(1, 1, -2), Vector3(1, 1, 2)).is_empty(), "damaged gate gap stays open")
	fence.free()
	var shelf: Node3D = load("res://scenes/props/shelving_unit.tscn").instantiate()
	root.add_child(shelf)
	await settle()
	check(ray(Vector3(0, 0.8, -2), Vector3(0, 0.8, 2)).is_empty(), "shelving opening stays open")
	shelf.free()
	var clutter: Node3D = load("res://scenes/props/broken_pipe_heap.tscn").instantiate()
	root.add_child(clutter)
	await settle()
	check(ray(Vector3(4, 0.125, 0), Vector3(-4, 0.125, 0)).is_empty(), "small clutter does not block")
	clutter.free()
	var depot: Node3D = load("res://scenes/raid/veyra_depot.tscn").instantiate()
	root.add_child(depot)
	var dressing: Node3D = depot.get_node("NavigationRegion3D/Decoration")
	check(dressing.get_child_count() == 24, "24 depot instances")
	var placed := {}
	for prop in dressing.get_children(): placed[prop.get_meta("prop_id")] = true
	check(placed.size() >= 20, "at least 20 distinct placed props")
	depot.free()
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await captures()
	if "--benchmark" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await benchmark()
	print("WORLD PROP TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func captures() -> void:
	var gallery: Node3D = load("res://scenes/props_preview.tscn").instantiate()
	root.add_child(gallery)
	await settle()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.godot/props-gallery.png") == OK, "gallery capture")
	var camera: Camera3D = gallery.get_node("Camera")
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.set_process(false)
	for child in gallery.get_children():
		if child is Label3D: child.visible = false
	for child in camera.get_children():
		if child is CanvasLayer: child.visible = false
	var overlay := CanvasLayer.new()
	var caption := Label.new()
	caption.add_theme_font_size_override("font_size", 26)
	caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x", 2)
	caption.add_theme_constant_override("shadow_offset_y", 2)
	caption.position = Vector2((root.size.x - root.size.y) / 2 + 15, root.size.y - 45)
	overlay.add_child(caption)
	gallery.add_child(overlay)
	# Crop a square from the root image for each labeled contact-sheet tile.
	var sheet := Image.create(2048, 2048, false, Image.FORMAT_RGB8)
	var previous: Node3D
	for child in gallery.get_children():
		if child.has_meta("prop_id"): child.visible = false
	for i in range(entries.size()):
		var prop: Node3D
		# Locate by stable metadata, independently of generated scene child order.
		for child in gallery.get_children():
			if child.get_meta("prop_id", "") == entries[i].id: prop = child; break
		if previous != null: previous.visible = false
		prop.visible = true
		previous = prop
		var size := Vector3(entries[i].bounds.size[0], entries[i].bounds.size[1], entries[i].bounds.size[2])
		var target: Vector3 = prop.position + Vector3.UP * size.y * 0.5
		var distance := maxf(size.x, maxf(size.y, size.z)) * 1.25 + 0.75
		camera.position = target + Vector3(1, 0.7, -1).normalized() * distance
		camera.look_at(target)
		caption.text = "%02d / %s" % [i + 1, entries[i].name]
		await process_frame
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		var side := mini(frame.get_width(), frame.get_height())
		var tile := frame.get_region(Rect2i((frame.get_width() - side) / 2, 0, side, side))
		tile.resize(256, 256, Image.INTERPOLATE_LANCZOS)
		tile.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(tile, Rect2i(0, 0, 256, 256), Vector2i((i % 8) * 256, (i / 8) * 256))
	check(sheet.save_png("res://.godot/props-contact-sheet.png") == OK, "64 prop contact sheet")
	gallery.free()

func benchmark() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var app = load("res://scenes/main.tscn").instantiate()
	app.normal_raid_scene = load("res://scenes/raid/veyra_depot.tscn")
	app.test_profile_path = "res://.godot/props-benchmark-" + ProfileStore._new_id() + ".json"
	root.add_child(app)
	app.deploy(false)
	var raid: RaidAuthority = app.raid
	raid.set_physics_process(false)
	raid.player.set_physics_process(false)
	for npc in raid.npcs: npc.set_physics_process(false)
	app.ui.root.visible = false
	var dressing: Node3D = raid.get_node("NavigationRegion3D/Decoration")
	var directions := [Vector3(0, 1.4, -5), Vector3(10, 1.4, 4)]
	var positions := [Vector3(0, 0.02, 13), Vector3(-7, 0.02, 2)]
	for view in range(2):
		raid.player.global_position = positions[view]
		var direction: Vector3 = directions[view] - raid.player.eye_position()
		raid.player.rotation.y = atan2(-direction.x, -direction.z)
		raid.player.look_pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
		var timings := {false: [], true: []}
		for sample in range(6):
			dressing.visible = sample % 2 == 1
			for frame in range(30): await process_frame
			var start := Time.get_ticks_usec()
			for frame in range(120): await process_frame
			timings[dressing.visible].append((Time.get_ticks_usec() - start) / 120000.0)
		for active in timings: timings[active].sort()
		var before: float = timings[false][1]
		var after: float = timings[true][1]
		print("PROP FRAME MS view %d (3-run median, 120 frames, sensor on): bare=%.3f dressed=%.3f change=%.1f%%" % [view, before, after, (after / before - 1) * 100])
		if "--capture" in OS.get_cmdline_user_args():
			dressing.visible = true
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/props-depot-%d.png" % view)
	app.free()
