extends SceneTree

var props := preload("res://scripts/data/environmental_props.gd").new()
var stage: Node3D
var camera: Camera3D
var caption: Label

func _initialize() -> void:
	call_deferred("review")

func review() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Rendered review requires a display/rendering driver")
		quit(1)
		return
	if not props.load_catalog().is_empty(): quit(1); return
	root.size = Vector2i(512, 512)
	root.content_scale_size = Vector2i.ZERO
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	stage = Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("293438")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b6c4c2")
	environment.ambient_light_energy = .65
	world.environment = environment
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42, -35, 0)
	light.light_color = Color("f2e6d0")
	light.light_energy = 1.7
	light.shadow_enabled = true
	stage.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(40, .1, 40)
	floor_mesh.mesh = plane
	floor_mesh.position.y = -.052
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("535d5b")
	material.roughness = .95
	floor_mesh.material_override = material
	stage.add_child(floor_mesh)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 42
	stage.add_child(camera)
	var hud := CanvasLayer.new()
	caption = Label.new()
	caption.position = Vector2(12, 452)
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x", 2)
	caption.add_theme_constant_override("shadow_offset_y", 2)
	hud.add_child(caption)
	stage.add_child(hud)
	var output := "res://resources/environment_props/review/"
	DirAccess.make_dir_recursive_absolute(output)
	var category_filter := 0
	var args := OS.get_cmdline_user_args()
	if "--category" in args: category_filter = int(args[args.find("--category") + 1])
	for category in range(1, 12):
		if category_filter != 0 and category != category_filter: continue
		var entries: Array[Dictionary] = []
		for entry: Dictionary in props.entries.values():
			if int(entry.category_index) == category: entries.append(entry)
		var all_variants := Image.create(1024, entries.size() * 256, false, Image.FORMAT_RGB8)
		all_variants.fill(Color("1c2528"))
		var bases := Image.create(1600, ceili(entries.size() / 5.0) * 320, false, Image.FORMAT_RGB8)
		bases.fill(Color("1c2528"))
		for row in entries.size():
			var entry := entries[row]
			for variant: Dictionary in entry.variants:
				var prop := props.instantiate_prop(entry.id, variant.index, 0, "review-" + entry.id)
				stage.add_child(prop)
				var box := props.bounds(entry.id, variant.index)
				var target := box.get_center()
				var distance := maxf(box.size.x, maxf(box.size.y, box.size.z)) * 1.65 + .25
				camera.position = target + Vector3(1, .65, -1).normalized() * distance
				camera.look_at(target)
				caption.text = "%s %s\n%d / %s" % [entry.id, entry.name, variant.index, variant.name]
				await process_frame
				await RenderingServer.frame_post_draw
				var frame := root.get_texture().get_image()
				frame.convert(Image.FORMAT_RGB8)
				if int(variant.index) == 0:
					var tile := frame.duplicate() as Image
					tile.resize(320, 320, Image.INTERPOLATE_LANCZOS)
					bases.blit_rect(tile, Rect2i(0, 0, 320, 320), Vector2i((row % 5) * 320, (row / 5) * 320))
				frame.resize(256, 256, Image.INTERPOLATE_LANCZOS)
				all_variants.blit_rect(frame, Rect2i(0, 0, 256, 256), Vector2i(int(variant.index) * 256, row * 256))
				prop.free()
		if bases.save_png(output + "%02d_bases.png" % category) != OK or all_variants.save_png(output + "%02d_variants.png" % category) != OK:
			push_error("Failed to save review sheets")
			quit(1)
			return
		print("RENDERED CATEGORY %02d: %d IDs and all variants" % [category, entries.size()])
	quit(0)
