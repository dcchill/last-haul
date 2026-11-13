extends SceneTree

var checks := 0
var failures := 0
var directory := "res://.godot/sensor-tests-" + ProfileStore._new_id()
var app: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func settle(frames: int = 4) -> void:
	for frame in range(frames): await process_frame

func run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var settings := SettingsStore.new(directory + "/settings.cfg")
	settings.load_settings()
	check(settings.sensor_enabled and settings.sensor_flicker and is_equal_approx(settings.sensor_strength, 0.85), "new settings defaults")
	check(settings.sensor_pixel_size == 2, "pixelation defaults to 2x")
	var config := ConfigFile.new()
	config.set_value("settings", "sensor_enabled", "false")
	config.set_value("settings", "sensor_strength", NAN)
	config.set_value("settings", "sensor_flicker", 0)
	config.save(settings.path)
	settings.load_settings()
	check(settings.sensor_enabled and settings.sensor_flicker and is_equal_approx(settings.sensor_strength, 0.85), "invalid settings rejected")
	config.set_value("settings", "sensor_strength", 5.0)
	config.save(settings.path)
	settings.load_settings()
	check(settings.sensor_strength == 1.0, "strength clamped")
	for invalid in ["2", 2.0, true, 0, 5]:
		config.set_value("settings", "sensor_pixel_size", invalid)
		config.save(settings.path)
		settings.load_settings()
		check(settings.sensor_pixel_size == 2, "invalid pixel setting rejected: " + str(invalid))
	settings.sensor_enabled = false
	settings.sensor_flicker = false
	settings.sensor_strength = 0.4
	settings.sensor_pixel_size = 4
	check(settings.save_settings() == OK, "settings saved")
	var restored := SettingsStore.new(settings.path)
	restored.load_settings()
	check(not restored.sensor_enabled and not restored.sensor_flicker and is_equal_approx(restored.sensor_strength, 0.4), "settings round trip")
	check(restored.sensor_pixel_size == 4, "pixelation setting round trip")
	app = load("res://scenes/main.tscn").instantiate()
	app.settings = SettingsStore.new(directory + "/app-settings.cfg")
	app.test_profile_path = directory + "/profile.json"
	root.add_child(app)
	app.deploy(false)
	check(app.raid != null, "normal yard deployed")
	if app.raid == null:
		quit(1)
		return
	var raid: RaidAuthority = app.raid
	var sensor: SignalDecay = raid.signal_decay
	await settle()
	check(sensor.screen.visible and sensor.world_environment.environment == sensor.sensor_environment, "shader and isolated haze enabled")
	check(not sensor.original_environment.fog_enabled, "source environment unmodified")
	check(is_equal_approx(sensor.shader.get_shader_parameter("strength"), 1.7) and is_equal_approx(sensor.sensor_environment.fog_density, 0.765), "default sensor intensity doubled")
	sensor.strength = 0.25
	check(sensor.shader.get_shader_parameter("strength") == 0.5, "saved slider strength receives double intensity")
	sensor.strength = 1.0
	check(sensor.shader.get_shader_parameter("strength") == 2.0 and sensor.sensor_environment.fog_density <= 1.0, "maximum intensity and fog stay bounded")
	sensor.strength = 0.85
	check(sensor.pixel_size == 2 and sensor.shader.get_shader_parameter("pixel_size") == 2.0, "pixelation configured on deployment")
	sensor.pixel_size = 1
	check(sensor.is_active() and sensor.shader.get_shader_parameter("pixel_size") == 1.0 and sensor.world_environment.environment == sensor.sensor_environment, "pixelation off retains other effects")
	sensor.pixel_size = 99
	check(sensor.pixel_size == 4 and sensor.shader.get_shader_parameter("pixel_size") == 4.0, "runtime pixel size clamped and refreshed")
	sensor.pixel_size = 2
	check(sensor.screen.mouse_filter == Control.MOUSE_FILTER_IGNORE and sensor.layer < app.ui.layer, "overlay preserves HUD and input")
	check(raid.player.scope_viewport.world_3d == raid.get_world_3d(), "scope shares fog environment")
	sensor.strength = 0.0
	check(not sensor.screen.visible and sensor.world_environment.environment == sensor.original_environment, "zero strength restores original")
	sensor.strength = 0.85
	sensor.enabled = false
	check(not sensor.screen.visible and sensor.world_environment.environment == sensor.original_environment, "disable restores original")
	sensor.enabled = true
	sensor.set_sensor_stress(2.0)
	check(sensor.sensor_stress == 1.0 and sensor.shader.get_shader_parameter("color_levels") == 16.0, "stress clamped and applied")
	sensor.set_sensor_stress(NAN)
	check(sensor.sensor_stress == 0.0, "invalid stress rejected")
	sensor.flicker_left = 0.0
	sensor._process(0.01)
	check(sensor.shader.get_shader_parameter("disturbance") <= 0.02 and sensor.pulse_left > 0.0, "ordinary flicker stays faint and brief")
	check(sensor.flicker_left >= 12.0 and sensor.flicker_left <= 25.0, "ordinary flicker remains rare")
	sensor.trigger_glitch(5.0, 20.0)
	check(sensor.pulse_intensity == 1.0 and sensor.pulse_left == 1.0, "pulse bounds")
	sensor._process(0.01)
	check(sensor.shader.get_shader_parameter("disturbance") <= 0.08, "brightness bounded")
	app.ui.show_pause()
	var pulse := sensor.pulse_left
	await settle()
	check(sensor.pulse_left == pulse, "pause freezes sensor timer")
	var compare := InputEventKey.new()
	compare.physical_keycode = KEY_F8
	compare.pressed = true
	Input.parse_input_event(compare)
	await settle()
	check(sensor.bypassed and not sensor.screen.visible and app.settings.sensor_enabled, "F8 bypass works during pause without saving")
	sensor.toggle_comparison()
	sensor.flicker_enabled = false
	sensor.trigger_glitch(1.0, 1.0)
	check(sensor.pulse_left == 0.0 and sensor.shader.get_shader_parameter("disturbance") == 0.0, "flicker preference suppresses pulses")
	app.ui.show_settings(true)
	await settle()
	var sliders: Array[Node] = app.ui.panel.find_children("*", "HSlider", false, false)
	var strength: HSlider = sliders.back()
	strength.grab_focus()
	var before := strength.value
	var key := InputEventKey.new()
	key.keycode = KEY_RIGHT
	key.pressed = true
	root.push_input(key)
	await settle()
	check(strength.has_focus() and strength.value > before, "sensor strength supports keyboard navigation")
	var pixels: OptionButton = app.ui.panel.find_children("*", "OptionButton", false, false).front()
	check(pixels.selected == 1 and pixels.item_count == 4, "pixelation dropdown defaults and choices")
	pixels.grab_focus()
	key.keycode = KEY_SPACE
	root.push_input(key)
	await settle()
	check(pixels.get_popup().visible, "pixelation dropdown opens with keyboard")
	key.keycode = KEY_DOWN
	root.push_input(key)
	await settle()
	key.keycode = KEY_ENTER
	root.push_input(key)
	await settle()
	check(pixels.get_selected_id() == 3, "pixelation keyboard selection")
	strength.value = 0.6
	for button in app.ui.panel.find_children("*", "Button", false, false):
		if button.text == "Apply and save": button.pressed.emit()
	check(is_equal_approx(sensor.strength, 0.6), "settings apply to paused raid")
	var saved := SettingsStore.new(app.settings.path)
	saved.load_settings()
	check(sensor.pixel_size == 3 and saved.sensor_pixel_size == 3, "pixelation applied and saved from menu")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await capture("settings")
	app.ui._resume()
	raid.process_mode = Node.PROCESS_MODE_DISABLED
	sensor.strength = 0.85
	sensor.flicker_enabled = false
	sensor.pixel_size = 2
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await rendered_views(raid)
		await pixel_sampling(raid)
	if "--benchmark" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await benchmark(sensor)
	var original := sensor.original_environment
	sensor.free()
	check(raid.get_node("WorldEnvironment").environment == original, "controller teardown restores environment")
	app.home()
	await settle()
	app.deploy(true)
	check(app.raid != null and not app.raid.signal_decay.bypassed and app.raid.signal_decay.sensor_stress == 0.0, "redeployment has fresh effect state")
	check(app.raid.signal_decay.pixel_size == 3, "pixelation preference survives redeployment")
	app.free()
	await settle()
	print("SIGNAL DECAY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func capture(label: String) -> Image:
	await settle()
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.save_png("res://.godot/sensor-" + label + ".png") == OK, "capture " + label)
	return image

func pair(raid: RaidAuthority, label: String) -> void:
	var probe := ColorRect.new()
	probe.position = Vector2(12, 300)
	probe.size = Vector2(4, 4)
	probe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app.ui.root.add_child(probe)
	raid.signal_decay.bypassed = true
	raid.signal_decay.refresh()
	var off := await capture(label + "-off")
	raid.signal_decay.bypassed = false
	raid.signal_decay.refresh()
	var on := await capture(label + "-on")
	check(on.get_size() == root.size, "capture matches viewport size")
	check(off.get_data() != on.get_data(), "effect changes rendered scene " + label)
	check(off.get_pixel(13, 301) == Color.WHITE and on.get_pixel(13, 301) == Color.WHITE, "HUD layer remains ungraded")
	raid.signal_decay.pixel_size = 1
	var pixels_off := await capture(label + "-pixels-off")
	check(pixels_off.get_data() != on.get_data(), "pixelation changes scene independently " + label)
	raid.signal_decay.pixel_size = 4
	await capture(label + "-pixels-4x")
	raid.signal_decay.pixel_size = 2
	probe.free()

func pixel_sampling(raid: RaidAuthority) -> void:
	var sensor := raid.signal_decay
	var size := Vector2i(1283, 725)
	DisplayServer.window_set_size(size)
	root.size = size
	root.content_scale_size = size
	app.ui.root.visible = false
	sensor.bypassed = true
	sensor.refresh()
	var reference := await capture("sampling-reference")
	sensor.bypassed = false
	sensor.refresh()
	# Isolate the sample grid from grading and fog, including partial edge blocks.
	sensor.shader.set_shader_parameter("strength", 0.0)
	sensor.world_environment.environment = sensor.original_environment
	for block in range(1, 5):
		sensor.shader.set_shader_parameter("pixel_size", float(block))
		var sampled := await capture("sampling-%dx" % block)
		check(sampled.get_size() == size, "sampling check uses non-divisible dimensions")
		if block == 1:
			check(sampled.get_data() == reference.get_data(), "size 1 preserves source pixels exactly")
		else:
			var matches := true
			var changed := 0
			for y in range(size.y):
				for x in range(size.x):
					var center := Vector2i(mini((x / block) * block + block / 2, size.x - 1), mini((y / block) * block + block / 2, size.y - 1))
					if sampled.get_pixel(x, y) != reference.get_pixelv(center): matches = false
					if sampled.get_pixel(x, y) != reference.get_pixel(x, y): changed += 1
			check(matches, "block-center sampling and clamped edges at %dx" % block)
			check(changed > 100, "pixelation changes real scene pixels at %dx" % block)
	app.ui.root.visible = true
	sensor.refresh()
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)

func view(raid: RaidAuthority, at: Vector3, target: Vector3, aiming: bool = false) -> void:
	var player := raid.player
	player.global_position = at
	player.previous_position = at
	var direction := target - player.eye_position()
	player.rotation.y = atan2(-direction.x, -direction.z)
	player.look_pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	var gun := raid.participants[player.entity_id].weapon
	for frame in range(90): player.animate_weapon(1.0 / 60.0, aiming, gun)

func rendered_views(raid: RaidAuthority) -> void:
	var state: RaidParticipant = raid.participants[raid.player.entity_id]
	check(state.weapon != null and raid.npcs.size() == 2, "real scav and zombie scene with weapon")
	for size in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		DisplayServer.window_set_size(size)
		root.size = size
		root.content_scale_size = size
		await settle()
		check(root.size == size, "requested render resolution")
		var suffix := "-%dx%d" % [size.x, size.y]
		view(raid, Vector3(0, 0.1, 13), Vector3(0, 1.2, -5))
		await pair(raid, "yard" + suffix)
		view(raid, Vector3(8, 0.1, -1), Vector3(6, 1.2, -7), true)
		await pair(raid, "sights" + suffix)
		view(raid, Vector3(10, 0.1, -5), Vector3(9, 0.6, -10))
		await pair(raid, "loot" + suffix)
		view(raid, Vector3(0, 0.1, 8), raid.extraction.global_position + Vector3.UP)
		await pair(raid, "extraction" + suffix)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	check(state.inventory.add("sniper_scope", 1), "scope added")
	var optic: Dictionary = state.inventory.slots.back()
	raid.request_input(raid.player.entity_id, false, false, true)
	check(raid.request_attachment(raid.player.entity_id, "optic", optic.state.instance_id), "magnified optic installed")
	for size in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		DisplayServer.window_set_size(size)
		root.size = size
		root.content_scale_size = size
		await settle()
		check(root.size == size, "requested scope resolution")
		view(raid, Vector3(8, 0.1, 0), raid.guard.global_position + Vector3.UP * 1.4, true)
		check(raid.player.scope_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "scope rendering active")
		await pair(raid, "scope-%dx%d" % [size.x, size.y])
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	view(raid, Vector3(0, 0.1, 13), Vector3(0, 1.2, -5))

func benchmark(sensor: SignalDecay) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	sensor.flicker_enabled = true
	sensor.process_mode = Node.PROCESS_MODE_ALWAYS
	var timings := {false: [], true: []}
	for sample in range(6):
		sensor.enabled = sample % 2 == 1
		await settle(120)
		var start := Time.get_ticks_usec()
		await settle(360)
		timings[sensor.enabled].append((Time.get_ticks_usec() - start) / 360000.0)
	for active in timings:
		timings[active].sort()
	print("SENSOR FRAME MS (3-run median, 360 frames, vsync off): off=%.3f on=%.3f" % [timings[false][1], timings[true][1]])
