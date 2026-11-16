extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func any_torso_corner_in_view(player: RaidPlayer) -> bool:
	var camera := player.camera
	var half_fov := tan(deg_to_rad(camera.fov / 2))
	var aspect := float(root.size.x) / root.size.y
	for node in player.body_visual.torso.get_children():
		if not node is MeshInstance3D: continue
		var bounds: AABB = node.get_aabb()
		for i in range(8):
			var point: Vector3 = camera.to_local(node.to_global(bounds.get_endpoint(i)))
			var depth := -point.z
			if depth >= camera.near and absf(point.y) <= depth * half_fov and absf(point.x) <= depth * half_fov * aspect:
				return true
	return false

func run() -> void:
	var app = load("res://scenes/main.tscn").instantiate()
	app.test_profile_path = "res://.godot/body-tests-" + ProfileStore._new_id() + ".json"
	root.add_child(app)
	app.deploy(true)
	var player: RaidPlayer = app.raid.player
	var body = player.body_visual
	app.raid.set_physics_process(false)
	player.set_physics_process(false)
	player.set_process(false)
	body.set_process(false)
	body.boot_left = 0
	body.damage_left = 0
	body.landing = 0
	# Reproduce the largest ordinary sprint lag before checking the fix.
	player.global_position = Vector3(0, 0.02, 13)
	player.previous_position = player.global_position + Vector3(0, 0, 0.28)
	player.velocity = Vector3(0, 0, -5.6)
	player.sprinting = true
	app.raid.accumulator = 0
	player._process(1.0 / 60)
	body.position = Vector3.ZERO
	# The human torso differs from the old robot; validate the rendered body below
	# without requiring the retired robot geometry to reproduce its old clipping bug.
	for yaw in [0.0, PI / 2, PI, -PI / 2]:
		player.rotation.y = yaw
		for movement in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT, Vector3(-1, 0.5, -1).normalized(), Vector3.ZERO]:
			for fraction in [0.0, 0.25, 0.5, 0.75, 0.999]:
				player.previous_position = player.global_position - movement * 0.28
				app.raid.accumulator = fraction * 0.05
				for crouched in [false, true]:
					player.crouching = crouched
					player.look_pitch = 0
					body.pose(1.0 / 60, 5.6, crouched)
					player._process(1.0 / 60)
					var eye_height := 1.27 if crouched else 1.62
					var rendered_feet := player.camera.global_position - Vector3.UP * eye_height
					check(body.global_position.is_equal_approx(rendered_feet), "body follows camera through sprint, strafe, crouch, jump, turn, and stop")
					check(player.armor_visuals.global_position.is_equal_approx(rendered_feet), "armor follows rendered body")
					check(not any_torso_corner_in_view(player), "torso stays out of level first-person view")
	player.previous_position = player.global_position + Vector3(10, 0, 0)
	player.crouching = false
	player._process(1.0 / 60)
	check(body.position.is_zero_approx(), "teleport resets camera and body together")
	player.look_pitch = deg_to_rad(-75)
	player._process(1.0 / 60)
	check(any_torso_corner_in_view(player), "body remains visible when looking down")
	check(body.head.get_child(0).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "head keeps first-person shadow policy")
	for arm in body.arms:
		check(arm.get_child(0).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "body arms keep first-person shadow policy")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		for label in ["sprint", "look-down"]:
			player.look_pitch = 0 if label == "sprint" else deg_to_rad(-75)
			player.previous_position = player.global_position + Vector3(0, 0, 0.28)
			app.raid.accumulator = 0
			player._process(1.0 / 60)
			for frame in range(3): await process_frame
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("res://.godot/player-body-" + label + ".png") == OK, label + " captured")
	app.free()
	for frame in range(3): await process_frame
	print("PLAYER BODY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
