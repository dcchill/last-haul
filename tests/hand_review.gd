extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var catalog := Catalog.new()
	catalog.load_all()
	var stage := Node3D.new()
	root.add_child(stage)
	var camera := Camera3D.new()
	camera.fov = 70
	camera.near = 0.05
	camera.cull_mask = 3
	stage.add_child(camera)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.09, 0.12, 0.15)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.8
	world.environment = environment
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -35, 0)
	stage.add_child(light)
	var view = load("res://scripts/weapons/bedrock_weapon.gd").new()
	stage.add_child(view)
	var rig := WeaponHands.new()
	stage.add_child(rig)
	var label := Label.new()
	label.position = Vector2(16, 12)
	label.add_theme_font_size_override("font_size", 26)
	root.add_child(label)
	DirAccess.make_dir_recursive_absolute("res://.godot/hand_review")
	for source in ArmoryContent.DATA.data.guns:
		var definition: WeaponDef = catalog.definitions[source.id]
		var weapon := WeaponState.new(definition)
		if not definition.magazine_id.is_empty():
			var mag := ArmoryInstance.fresh(definition.magazine_id, catalog.items)
			mag.rounds = definition.magazine_size
			weapon.data.magazine = {"id": definition.magazine_id, "quantity": 1, "state": mag}
		else:
			weapon.data.rounds = definition.magazine_size
		view.configure(definition.model_path, definition.texture_path, definition.animation_path)
		rig.bind(definition.hand_profile)
		var sheet := Image.create(1536, 648, false, Image.FORMAT_RGBA8)
		var frames: Array = [["idle", 0.0, 0.0], ["idle", 0.0, 1.0 if definition.can_aim else 0.0], ["fire", float(view.clips.fire.length) * 0.45, 0.0], ["equip", 0.12, 0.0]]
		for phase in [0.07, 0.14, 0.30, 0.42, 0.55, 0.70, 0.84, 0.95]:
			frames.append(["reload", definition.reload_seconds * phase, 0.0])
		for index in range(frames.size()):
			var sample: Array = frames[index]
			WeaponPoseEvaluator.seek(view, rig, weapon, sample[0], sample[1], sample[2])
			label.text = "%s | %s %.2fs%s" % [source.id, sample[0], sample[1], " ADS" if sample[2] > 0 else ""]
			await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			image.resize(384, 216, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(image, Rect2i(0, 0, 384, 216), Vector2i(index % 4 * 384, index / 4 * 216))
		sheet.save_png("res://.godot/hand_review/" + str(source.id) + ".png")
		# A second sheet covers the largest legal attachment configuration and
		# live cancellation/equip transitions, rather than only isolated poses.
		for attachment in ArmoryContent.DATA.data.attachments:
			if catalog.definitions[attachment.id].supports(definition):
				weapon.data.attachments[attachment.slot] = {"id": attachment.id, "quantity": 1, "state": ArmoryInstance.fresh(attachment.id, catalog.items)}
		view.configure(definition.model_path, definition.texture_path, definition.animation_path)
		view.show_attachments(weapon)
		var zoom := weapon.magnification(catalog.definitions)
		var frames_attached: Array = [["idle", 0, 0], ["idle", 0, 1 if definition.can_aim else 0], ["fire", float(view.clips.fire.length) * 0.23, 0], ["fire", float(view.clips.fire.length) * 0.65, 0]]
		for phase in [0.14, 0.30, 0.55, 0.70]: frames_attached.append(["reload", definition.reload_seconds * phase, 0])
		for moment in [0.0, 0.08, 0.16, 0.25]: frames_attached.append(["reset", moment, 0])
		var previous_reset := 0.0
		for index in range(frames_attached.size()):
			var sample: Array = frames_attached[index]
			if sample[0] == "reset":
				var count := maxi(1, ceili((float(sample[1]) - previous_reset) * 120))
				var delta := (float(sample[1]) - previous_reset) / count
				for step in range(count):
					var time := previous_reset + (step + 1) * delta
					view.seek_visual(weapon, "reset", time)
					WeaponPoseEvaluator.place(view, weapon, 0, zoom)
					rig.evaluate(view, weapon, "reset", time, delta, false)
				previous_reset = sample[1]
			else:
				WeaponPoseEvaluator.seek(view, rig, weapon, sample[0], sample[1], sample[2], zoom)
				# Seed the live interruption with this exact evaluated grasp.
				rig.evaluate(view, weapon, sample[0], sample[1], 0, false)
			label.text = "%s + attachments | %s %.2fs%s" % [source.id, sample[0], sample[1], " ADS" if sample[2] > 0 else ""]
			await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			image.resize(384, 216, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(image, Rect2i(0, 0, 384, 216), Vector2i(index % 4 * 384, index / 4 * 216))
		sheet.save_png("res://.godot/hand_review/" + str(source.id) + "-attachments.png")
		print("HAND REVIEW: ", source.id)
	stage.free()
	label.free()
	await process_frame
	quit()
