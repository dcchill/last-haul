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
func inventory_frames() -> Array[Node]:
	return app.ui.inventory_flow.get_children().filter(func(node): return node.has_meta("inventory_grid"))
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
	app.ui.show_inventory()
	await settle()
	var frames := inventory_frames()
	check(frames.size() == 2, "staging shows pack and stash")
	if frames.size() == 2:
		check(frames[0].custom_minimum_size.y == app.loadout.pack.height * 18 + 44, "pack frame fits its grid")
		check(frames[1].custom_minimum_size.y == app.stash_view.height * 18 + 44, "stash frame fits its grid")
		check(frames[0].get_node("Grid").cell_size == 18, "inventory uses native pixel slots")
		var grid = frames[0].get_node("Grid")
		var pack: RaidInventory = app.loadout.pack
		if not pack.slots.is_empty():
			var item: Dictionary = pack.slots[0]
			var origin := Vector2i(int(item.x), int(item.y))
			check(grid._slot_at(Vector2(origin * 18) + Vector2.ONE) == 0, "slot selection maps to native pixels")
			for y in range(pack.height):
				var moved := false
				for x in range(pack.width):
					if Vector2i(x, y) != origin and pack.can_place(item.id, x, y, bool(item.get("rotated", false)), 0):
						var data := {"inventory": pack, "index": 0}
						var target := Vector2(x * 18 + 1, y * 18 + 1)
						check(grid._can_drop_data(target, data), "grid accepts valid drag target")
						grid._drop_data(target, data)
						var moved_index := pack._slot_at(x, y)
						check(moved_index >= 0 and pack.slots[moved_index].id == item.id, "grid moves dragged item")
						moved = true
						break
				if moved: break
	await capture("staging")
	if DisplayServer.get_name() != "headless":
		var original_size := root.size
		root.size = Vector2i(1600, 900)
		await settle()
		await capture("staging-large")
		check(inventory_frames().size() == 2, "staging survives window resize")
		root.size = original_size
		await settle()
	app.ui.show_home()
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
	check(inventory_frames().size() == 1, "field inventory shows pack")
	if not raid.containers.is_empty():
		app.ui.open_container(id, raid.containers.keys()[0])
		await settle()
		check(app.ui.mode == "container", "loot container opens")
		check(app.ui.loot_pack_grid.global_position.y > app.ui.loot_container_grid.global_position.y, "loot grid is above player inventory")
		check(app.ui.loot_container_grid.plain_slots and app.ui.loot_pack_grid.plain_slots, "loot grids use plain slots")
		check(app.ui.container_weight.text.begins_with("%.2f" % app.ui.container_contents.total_weight()), "loot footer shows container weight")
		if not app.ui.container_contents.slots.is_empty():
			app.ui.loot_container_grid.slot_selected.emit(0)
			check(app.ui.loot_container_grid.selected_index == 0, "loot selection stays visible")
		check(state.inventory.add("patrol", 1), "add armor for loot equipment test")
		var armor_index := state.inventory.find_instance(state.inventory.slots.back().state.instance_id)
		var armor_id: String = state.inventory.slots[armor_index].state.instance_id
		app.ui._equip_loot({"inventory": state.inventory, "index": armor_index}, "chestplate")
		check(state.armor_slots.get("chestplate") == armor_id, "equip armor from player grid")
		check(not app.ui._can_equip_loot({"inventory": state.inventory, "index": state.inventory.find_instance(armor_id)}, "helmet"), "reject armor in wrong slot")
		var crate_id := "armory-crate-0"
		check(raid.containers.has(crate_id), "practice armor crate exists")
		if raid.containers.has(crate_id):
			raid.player.set_physics_process(false)
			raid.player.global_position = raid.entities[crate_id].global_position + Vector3(0, 0.02, 2)
			await settle()
			state.opened_container = crate_id
			app.ui.open_container(id, crate_id)
			var contents: RaidInventory = raid.containers[crate_id]
			var crate_armor := -1
			for index in range(contents.slots.size()):
				var definition: Resource = app.catalog.definitions.get(contents.slots[index].id)
				if definition is ArmorDef and definition.slot == "chestplate":
					crate_armor = index
					break
			check(crate_armor >= 0, "practice crate contains compatible armor")
			if crate_armor >= 0:
				var replacement_id: String = contents.slots[crate_armor].state.instance_id
				state.inventory.capacity = 0
				app.ui._equip_loot({"inventory": contents, "index": crate_armor}, "chestplate")
				check(state.armor_slots.get("chestplate") == armor_id and contents.find_instance(replacement_id) >= 0, "full pack leaves crate armor and equipment unchanged")
				state.inventory.capacity = -1
				app.ui._equip_loot({"inventory": contents, "index": crate_armor}, "chestplate")
				check(state.armor_slots.get("chestplate") == replacement_id and state.inventory.find_instance(armor_id) >= 0, "crate armor replaces equipped armor without losing the old item")
			raid.player.set_physics_process(true)
		await capture("container")
		app.ui._sort_pack()
		app.ui._close_container()
		check(app.ui.mode == "hud", "loot container closes")
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
