extends SceneTree

var failures: int = 0
var checks: int = 0
var app: Node
var captures: bool = false

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func settle() -> void:
	for frame in range(6):
		await physics_frame
	await process_frame

func capture(name: String) -> void:
	if not captures:
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/" + name + ".png")

func _run() -> void:
	captures = "--capture" in OS.get_cmdline_user_args()
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	var directory := "res://.godot/app_test_" + ProfileStore._new_id()
	DirAccess.make_dir_recursive_absolute(directory)
	app.profile = ProfileStore.new(app.catalog, directory + "/profile.json")
	app.profile.problem.connect(app.ui.show_notice)
	app.settings.path = directory + "/settings.cfg"
	app.ui.show_home()
	await settle()
	check(app.ui.mode == "home" and app.raid == null, "app starts at stash")
	check(root.gui_get_focus_owner() is Button and root.gui_get_focus_owner().text == "Deploy to yard", "deploy button receives initial keyboard focus")
	await capture("home")
	# Activate the actual deploy button rather than instantiate a yard directly.
	root.gui_get_focus_owner().pressed.emit()
	await settle()
	check(app.raid != null and app.raid.is_active() and app.ui.mode == "hud", "deploy button launches playable scene")
	var start: Vector3 = app.raid.player.global_position
	Input.action_press("move_forward")
	for frame in range(30):
		await physics_frame
	Input.action_release("move_forward")
	if DisplayServer.get_name() != "headless":
		check(app.raid.player.global_position.z < start.z - 1, "player moves through input map")
		var walking_distance: float = start.z - app.raid.player.global_position.z
		start = app.raid.player.global_position
		Input.action_press("sprint")
		Input.action_press("move_forward")
		for frame in range(30):
			await physics_frame
		Input.action_release("sprint")
		Input.action_release("move_forward")
		check(start.z - app.raid.player.global_position.z > walking_distance * 1.3, "sprint is faster than walking")
		Input.action_press("jump")
		await physics_frame
		Input.action_release("jump")
		for frame in range(12):
			await physics_frame
		check(app.raid.player.global_position.y > 0.5, "jump rises above ground")
		for frame in range(45):
			await physics_frame
		check(app.raid.player.is_on_floor() and absf(app.raid.player.global_position.y) < 0.1, "player lands on floor collision")
		var look := InputEventMouseMotion.new()
		look.relative = Vector2(100, 1000)
		app.raid.player._unhandled_input(look)
		check(app.raid.player.rotation.y < 0 and is_equal_approx(app.raid.player.camera.rotation.x, -1.45), "mouse look and pitch clamp")
		app.raid.player.rotation.y = 0
		app.raid.player.camera.rotation.x = 0
	else:
		print("SKIP: headless display has no captured mouse; run with --capture for movement check")
	app.ui.show_pause()
	check(paused and app.ui.mode == "pause", "pause menu suspends raid")
	app.ui.show_settings(true)
	check(app.ui.mode == "settings", "settings open from pause")
	app.ui.show_pause()
	app.ui._resume()
	check(not paused and app.ui.mode == "hud", "resume restores HUD")
	await capture("yard")
	# Freeze AI during the UI transaction checks; behavior is covered by run_tests.
	app.raid.set_physics_process(false)
	app.raid.player.set_physics_process(false)
	app.raid.player.global_position = Vector3(9, 0.1, -7.5)
	app.raid.player.camera.look_at(Vector3(9, 0.5, -10))
	await settle()
	app.raid.request_interact(app.raid.player.entity_id, "crate-01")
	check(app.ui.mode == "container", "interaction signal opens container panel")
	app.ui._take()
	check(app.raid.participants[app.profile.profile.player_id].inventory.count("salvage") == 1 and app.raid.entities["crate-01"].remaining == 2, "take button claims loot through authority")
	await capture("loot")
	app.ui._close_container()
	app.raid.player.global_position = Vector3(-10, 0.1, 11)
	await settle()
	app.raid._update_extraction(app.profile.profile.player_id, 3)
	check(app.ui.mode == "result" and not app.pending_save and app.profile.profile.stash[0].quantity == 1, "extraction signal saves result and shows results")
	await capture("result")
	var reload_profile := ProfileStore.new(app.catalog, app.profile.path)
	check(reload_profile.load_profile() and reload_profile.profile.stash[0].quantity == 1, "application reward survives profile reload")
	app.home()
	await settle()
	app.deploy()
	await settle()
	check(app.raid.participants[app.profile.profile.player_id].weapon.magazine == 12 and app.raid.participants[app.profile.profile.player_id].inventory.slots.is_empty(), "second deployment resets kit and raid inventory")
	# Failed disk write must keep the actual result screen retryable.
	var valid_path: String = app.profile.path
	app.profile.path = directory + "/missing/profile.json"
	app.raid.request_abandon(app.profile.profile.player_id)
	check(app.pending_save and app.ui.mode == "result", "failed result save stays pending")
	app.home()
	check(app.raid != null, "pending save prevents leaving results")
	app.profile.path = valid_path
	app.retry_save()
	app.ui.show_result()
	check(not app.pending_save and app.profile.profile.stash[0].quantity == 1, "retry saves failure without crediting loot")
	app.home()
	await settle()
	app.free()
	print("APPLICATION SMOKE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
