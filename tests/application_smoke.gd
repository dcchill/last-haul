extends SceneTree
var app: Node
var captures := false
var failures := 0
var checks := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)
func settle(frames: int = 5) -> void:
	for frame in range(frames): await physics_frame
	await process_frame
func capture(name: String) -> void:
	if not captures: return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/armory-" + name + ".png")
func run() -> void:
	captures = "--capture" in OS.get_cmdline_user_args()
	app = load("res://scenes/main.tscn").instantiate()
	app.test_profile_path = "res://.godot/smoke-" + ProfileStore._new_id() + ".json"
	root.add_child(app)
	await settle()
	check(app.ui.mode == "home", "home screen")
	await capture("home")
	app.deploy(true)
	await settle()
	var raid: RaidAuthority = app.raid
	var id: String = app.profile.profile.player_id
	var state: RaidParticipant = raid.participants[id]
	check(raid.is_active() and app.ui.mode == "hud", "practice playable")
	if DisplayServer.get_name() != "headless":
		Input.action_press("move_forward")
		var before: Vector3 = raid.player.global_position
		await settle(35)
		Input.action_release("move_forward")
		check(raid.player.global_position.z < before.z - 1, "captured mouse input drives movement")
		Input.action_press("jump")
		await settle(8)
		Input.action_release("jump")
		check(raid.player.global_position.y > 0.4, "Minecraft jump")
		await settle(40)
		check(raid.player.grounded, "Minecraft movement lands")
	# Exercise every handheld model and action with each supported optic in a rendered viewport.
	for source in ArmoryContent.DATA.data.guns:
		state.inventory.slots.clear()
		raid.practice_grant(id, source.id)
		state.weapon.next_shot = 0
		state.next_shot = 0
		check(raid.player.rifle.bones.has("right_hand_socket"), source.id + " right hand")
		for action in ["idle", "fire", "reload", "equip", "reset"]:
			check(raid.player.rifle.play_clip(action), source.id + " clip " + action)
			await settle(2)
		for optic_id in ["reflex_sight", "four_x_scope", "sniper_scope"]:
			if not app.catalog.definitions[optic_id].supports(state.weapon.definition): continue
			state.inventory.add(optic_id, 1)
			var optic: Dictionary = state.inventory.slots.back()
			raid.request_input(id, false, false, true)
			check(raid.request_attachment(id, "optic", optic.state.instance_id), source.id + " installs " + optic_id)
			raid.request_input(id, false, true, false)
			# Use the real view update; input is disabled temporarily so the synthetic ADS state persists.
			raid.player.set_physics_process(false)
			for tick in range(20): raid.player.animate_weapon(1.0 / 60, true, state.weapon)
			await process_frame
			check(raid.player.aim_blend > 0.95, source.id + " ADS aligned")
			if optic_id == "sniper_scope" and source.id in ["m_four", "bolt_action_sniper"]:
				await capture(source.id + "-scope")
			raid.request_input(id, false, false, true)
			raid.request_attachment(id, "optic")
			raid.player.set_physics_process(true)
		await settle(30)
		await capture(source.id)
	# Mouse-look and real world collision damage.
	state.inventory.slots.clear()
	raid.practice_grant(id, "m_four")
	state.weapon.next_shot = 0
	state.next_shot = 0
	raid.player.global_position = Vector3(-10, 0.02, -10)
	raid.player.movement.velocity = Vector3.ZERO
	raid.player.rotation = Vector3.ZERO
	raid.player.look_pitch = -0.1
	await settle()
	var target: RaidEntity = raid.entities["target-0"]
	var old_health := target.health
	var direction := target.global_position + Vector3.UP - raid.player.eye_position()
	raid.player.rotation.y = atan2(-direction.x, -direction.z)
	raid.player.look_pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	check(raid.request_fire(id), "authority accepts real shot")
	await settle(8)
	check(target.health < old_health, "swept projectile damages real target")
	await capture("range")
	app.ui.show_inventory(true)
	await settle()
	await capture("inventory")
	check(app.ui.mode == "raid_inventory", "raid inventory controls")
	app.ui.show_practice()
	await settle()
	await capture("armory")
	# Every retained geometry can be built; includes box UVs and duplicate source bones.
	for model in ArmoryContent.DATA.data.previews:
		app.ui._preview_model(model)
		await process_frame
	app.ui.show_hud()
	raid.request_grenade(id, "impact_nade")
	raid._explode(Vector3(0, 1, -3), 3)
	raid._smoke_burst(Vector3(0, 0.1, -3))
	await settle()
	await capture("effects")
	app.ui.show_pause()
	check(paused, "pause freezes game")
	app.ui._resume()
	check(not paused, "resume unpauses game")
	raid.request_abandon(id)
	check(app.ui.mode == "result" and not app.pending_save, "practice ends without save")
	app.home()
	await settle()
	app.free()
	await settle()
	print("ARMORY APPLICATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
