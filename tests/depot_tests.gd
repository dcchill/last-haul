extends SceneTree

var app: Node
var raid: RaidAuthority
var actor_id: String
var state: RaidParticipant
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + description)

func settle() -> void:
	for frame in range(5): await physics_frame

func deploy() -> void:
	app.deploy(false)
	raid = app.raid
	check(raid != null and raid.depot, "normal menu deployment selects depot")
	raid.set_physics_process(false)
	raid.player.set_physics_process(false)
	actor_id = app.profile.profile.player_id
	state = raid.participants[actor_id]
	await settle()

func finish_home() -> void:
	app.home()
	await settle()

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	app.test_profile_path = "res://.godot/depot-" + ProfileStore._new_id() + ".json"
	root.add_child(app)
	await settle()
	check(app.ui.mode == "home", "game starts at menu")
	check(app.ui.panel.get_children().any(func(node): return node is Button and node.text.begins_with("Enter raid")), "menu exposes raid entry")
	await deploy()
	check(raid.npcs.size() == 4 and raid.npcs.filter(func(npc): return npc.archetype.melee).size() == 2, "two scavs and two zombies")
	check(raid.containers.size() == 5, "three loot containers and two power lockers")
	check(raid.containers["battery-0"].count("battery_cell") == 1 and raid.containers["battery-1"].count("battery_cell") == 1, "two authored power cells")
	check(raid.player.has_node("RobotBody"), "procedural robot installed")
	await capture_at("insertion", Vector3(0, 0.02, 13), Vector3(0, 1.5, -2))
	await capture_at("yard", Vector3(-8, 0.02, 3), Vector3(-8, 1.4, -10))
	await capture_at("medical", Vector3(8, 0.27, -4), Vector3(8, 1.5, -11))
	await capture_at("rear", Vector3(5, 0.27, -13), Vector3(10, 1.3, -14))
	await capture_at("robot", Vector3(0, 0.02, 13), Vector3(0, 0.5, 12.7))
	raid.player.global_position = Vector3(0, 0.02, 13)
	raid.player.look_pitch = 0
	await settle()
	var nav := raid.guard.navigation.get_navigation_map()
	for destination in [Vector3(-10, 0, 11), Vector3(-10, 0, -11), Vector3(8, 0.25, -9), Vector3(5, 0.25, -14)]:
		var path := NavigationServer3D.map_get_path(nav, raid.player.global_position, destination, true)
		check(not path.is_empty() and path[path.size() - 1].distance_to(destination) < 1.0, "navigation reaches " + str(destination))
	for destination in [Vector3(8, 0.25, -9), Vector3(5, 0.25, -14), Vector3(-10, 0, -11), Vector3(-10, 0, 11)]:
		await walk_to(destination)
	raid.player.global_position = Vector3(0, 0.02, 13)
	await settle()
	var warnings: Array[String] = []
	raid.notice.connect(func(message): warnings.append(message))
	check(state.battery == 480, "starts with eight minutes")
	raid._update_battery(state, 1)
	check(state.battery == 479, "base drain")
	raid.player.sprinting = true
	raid._update_battery(state, 2)
	check(state.battery == 476, "sprint drains 1.5x")
	raid.player.sprinting = false
	state.battery = 120.05
	raid._update_battery(state, 0.1)
	raid._update_battery(state, 0.1)
	check(warnings.size() == 1 and state.battery_warning == 1, "low warning emitted once")
	state.battery = 60.05
	raid._update_battery(state, 0.1)
	raid._update_battery(state, 0.1)
	check(warnings.size() == 2 and state.battery_warning == 2, "critical warning emitted once")
	check(state.inventory.add("battery_cell", 1), "cell fits normal inventory")
	var cell: Dictionary = state.inventory.slots.back()
	state.battery = 480
	check(not raid.request_use(actor_id, cell.uid) and state.inventory.count("battery_cell") == 1, "full charge preserves cell")
	state.battery = 450
	check(not raid.request_use(actor_id, "unowned-cell"), "cannot consume an unowned cell")
	check(raid.request_use(actor_id, cell.uid) and state.battery == 480 and state.inventory.count("battery_cell") == 0, "cell consumes once and clamps charge")
	check(not raid.request_use(actor_id, cell.uid), "consumed identity cannot be reused")
	state.inventory.add("battery_cell", 1)
	state.battery = 200
	check(raid.request_use(actor_id, state.inventory.slots.back().uid) and state.battery == 290, "cell restores exactly ninety seconds")

	# Keep all enemies blind for deterministic lifecycle tests, then exercise AI separately.
	for npc in raid.npcs: npc.state = RaidGuard.State.DEAD
	raid.set_physics_process(true)
	var before := state.battery
	app.ui.show_pause()
	await settle()
	check(state.battery == before, "pause freezes battery")
	app.ui._resume()
	app.ui.show_inventory(true)
	await settle()
	check(state.battery < before, "inventory keeps battery running")
	app.ui.show_hud()
	raid.set_physics_process(false)
	state.battery = 480
	raid.player.global_position = Vector3(-10, 0.02, 11)
	await settle()
	raid._update_extraction(actor_id, 14.95)
	check(raid.is_active() and state.extracting and state.extraction_left > 0, "cannot extract before fifteen seconds")
	raid.player.global_position = Vector3(0, 0.02, 11)
	await settle()
	raid._update_extraction(actor_id, 0.05)
	check(not state.extracting and state.extraction_left == 15, "leaving fully resets countdown")
	raid.player.global_position = Vector3(-10, 0.02, 11)
	await settle()
	state.extracting = true
	state.extraction_left = 0.05
	state.battery = 0.025
	raid.gameplay_step()
	check(raid.phase == RaidAuthority.Phase.FAILURE and "shutdown" in raid.result.reason, "shutdown wins simultaneous extraction")
	check(not raid.request_extract(actor_id) and not raid.request_use(actor_id, "anything") and not raid.request_fire(actor_id), "shutdown rejects gameplay")
	var saved: Dictionary = app.profile.profile.duplicate(true)
	raid.gameplay_step()
	raid._finish(true, "duplicate")
	check(app.profile.profile == saved and not raid.result.success, "failure saved once, no duplicate result")
	await finish_home()
	await deploy()
	check(state.battery == 480 and state.recovered_items().is_empty(), "new empty loadout resets power without gear grant")
	raid.player.global_position = Vector3(-10, 0.02, 11)
	await settle()
	check(raid.request_extract(actor_id), "empty-handed unarmed extraction needs no objective or activation")
	var hp := state.health
	raid._apply_damage(raid.player, 1, null, true)
	raid.gameplay_step()
	check(state.health == hp - 1 and state.battery < 480, "damage and drain continue during extraction")
	raid._update_extraction(actor_id, 15)
	check(raid.result.success and not app.pending_save and state.recovered_items().is_empty(), "empty extraction completes and saves")
	check(app.ui.panel.get_children().any(func(node): return node is Label and node.text == "Recovered: nothing"), "empty result is explicit")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/depot-result.png")
	await finish_home()
	await deploy()
	await ai_checks()
	raid.player.global_position = Vector3(-10, 0.02, 11)
	await settle()
	raid._update_extraction(actor_id, 14)
	raid._apply_damage(raid.player, 1000, null, true)
	raid._update_extraction(actor_id, 1)
	check(not raid.result.success and "Killed" in raid.result.reason, "death interrupts extraction")
	await finish_home()
	await deploy()
	state.inventory.add("battery_cell", 1)
	raid.player.global_position = Vector3(-10, 0.02, 11)
	await settle()
	raid._update_extraction(actor_id, 15)
	check(raid.result.success and not app.pending_save, "unused cell extracts")
	await finish_home()
	check(app.stash_view.count("battery_cell") == 1, "extracted cell persists in stash")
	app.deploy(true)
	await settle()
	check(app.raid.practice and not app.raid.depot, "practice still uses yard")
	var practice_state: RaidParticipant = app.raid.participants[actor_id]
	check(practice_state.battery == 480, "practice has no power drain")
	app.raid.request_abandon(actor_id)
	app.free()
	await settle()
	print("DEPOT TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func walk_to(destination: Vector3) -> void:
	var path := NavigationServer3D.map_get_path(raid.guard.navigation.get_navigation_map(), raid.player.global_position, destination, true)
	var steps := 0
	for point in path:
		while Vector2(raid.player.global_position.x - point.x, raid.player.global_position.z - point.z).length() > 0.4 and steps < 700:
			var direction := point - raid.player.global_position
			raid.player.rotation.y = atan2(-direction.x, -direction.z)
			raid.player.drive_movement(Vector2(0, -1), false, false, 0.05)
			steps += 1
			if steps % 5 == 0: await physics_frame
	check(raid.player.global_position.distance_to(destination) < 1.1, "player physically walks route to " + str(destination))

func capture_at(label: String, position: Vector3, target: Vector3) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	raid.player.global_position = position
	var direction := target - raid.player.eye_position()
	raid.player.rotation.y = atan2(-direction.x, -direction.z)
	raid.player.look_pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	await settle()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.godot/depot-" + label + ".png") == OK, "capture " + label)

func ai_checks() -> void:
	var scav := raid.guard
	# Player is behind the medical wall; visibility must fail despite proximity.
	raid.player.global_position = Vector3(8, 0.25, -8)
	scav.global_position = Vector3(1, 0.02, -8)
	scav.rotation.y = -PI / 2
	await settle()
	check(not scav.can_see(raid.player, raid.ballistics), "medical wall blocks sight")
	scav.state = RaidGuard.State.IDLE
	scav.authority_tick(0.05, raid.player, raid.ballistics)
	check(scav.state == RaidGuard.State.PATROL, "unalerted scav patrols")
	scav.hear(Vector3(1, 0.02, -8))
	check(scav.state == RaidGuard.State.INVESTIGATE, "scav hears nearby sound")
	scav.authority_tick(0.05, raid.player, raid.ballistics)
	check(scav.state == RaidGuard.State.SEARCH, "investigation searches at last heard position")
	scav.authority_tick(3.1, raid.player, raid.ballistics)
	check(scav.state == RaidGuard.State.RETURN, "search ends in return")
	scav.authority_tick(0.05, raid.player, raid.ballistics)
	check(scav.navigation.target_position == scav.home_position, "return targets authored home")
	var zombie: RaidGuard = raid.npcs.filter(func(npc): return npc.archetype.melee)[0]
	zombie.state = RaidGuard.State.CHASE
	zombie.hear(raid.player.global_position)
	check(zombie.state == RaidGuard.State.INVESTIGATE, "zombie redirects toward sound during pursuit")
	zombie.global_position = Vector3(8, 0.25, -7)
	zombie.rotation.y = 0
	zombie.attack_left = 0
	await settle()
	check(zombie.authority_tick(0.05, raid.player, raid.ballistics), "zombie attacks in visible melee range")
	check(zombie.state == RaidGuard.State.ATTACK, "zombie ignores cover points")
	# A reachable position behind the road barrier protects the lower body.
	scav.global_position = Vector3(-4, 0.02, 0)
	scav.cover_points = PackedVector3Array([Vector3(-2, 0, 0.8)])
	raid.player.global_position = Vector3(-2, 0.02, 5)
	await settle()
	check(scav.choose_cover(raid.player, raid.ballistics).distance_to(Vector3(-2, 0, 0.8)) < 0.1, "scav selects reachable shielded cover")
	check(not raid.get_node("NavigationRegion3D/MedicalWest").damage_at(Vector3(3, 1, -8), 999), "structural wall resists destruction")
	var cover: VoxelDestructible = raid.get_node("NavigationRegion3D/PartitionCover")
	var before := cover.remaining_cells()
	cover.damage_at(cover.global_position + Vector3(0, 0, 0.24), 20)
	check(cover.remaining_cells() < before, "authored cover breaks")
