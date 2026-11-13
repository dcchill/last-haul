extends RefCounted

func run(t: SceneTree) -> void:
	var catalog: Catalog = t.catalog
	var check: Callable = t.check
	await reload_integration(t)
	var a := RaidInventory.new(catalog.items, 4, 4)
	var b := RaidInventory.new(catalog.items, 4, 4)
	var service := InventoryTransactions.new()
	service.actor_id = "test"
	service.roots = [a, b]
	a.add("salvage", 12)
	var identity: String = a.slots[0].uid
	var request := service.request("split", a, b, identity, Vector2i(0, 0), false, 5)
	check.call(service.submit(request).ok and a.count("salvage") == 7 and b.count("salvage") == 5, "split transfers exactly selected quantity")
	check.call(a.slots[0].uid != b.slots[0].uid, "split creates independent stack identity")
	check.call(service.submit(request).ok and b.count("salvage") == 5, "duplicate inventory request is idempotent")
	var stale := service.request("move", a, b, identity)
	a.add("food", 1)
	var before := [a.snapshot(), b.snapshot()]
	check.call(not service.submit(stale).ok and before == [a.snapshot(), b.snapshot()], "stale request leaves both inventories unchanged")
	var malformed := service.request("move", a, b, identity)
	malformed.revisions = 42
	check.call(not service.submit(malformed).ok, "malformed request rejected at boundary")
	var outsider := service.request("move", a, b, identity)
	outsider.actor_id = "stranger"
	check.call(not service.submit(outsider).ok, "inventory actor ownership enforced")
	var denied := service.request("move", a, b, identity)
	service.authorize = func(_grid): return false
	check.call(not service.submit(denied).ok and before == [a.snapshot(), b.snapshot()], "authority denial cannot change inventory")
	service.authorize = Callable()
	check.call(service.submit(service.request("merge", a, b, identity, Vector2i(0, 0))).ok and b.count("salvage") == 12, "compatible stacks merge")
	var wide := RaidInventory.new(catalog.items, 2, 1)
	wide.add("stanag_magazine", 1)
	check.call(wide.slots[0].rotated, "auto placement rotates at boundary")
	check.call(not InventoryManager.move(wide, 0, wide, Vector2i(1, 0), false), "out of bounds rotation rejected")
	var swaps := RaidInventory.new(catalog.items, 4, 4)
	swaps.add_at("food", 1, 0, 0)
	swaps.add_at("salvage", 1, 1, 0)
	check.call(InventoryManager.move(swaps, 0, swaps, Vector2i(1, 0)) and swaps.slots[swaps._slot_at(0, 0)].id == "salvage", "same grid swap commits both placements")
	var small := RaidInventory.new(catalog.items, 1, 1)
	small.add("food", 1)
	var larger := RaidInventory.new(catalog.items, 4, 4)
	larger.add("medkit", 1)
	before = [small.snapshot(), larger.snapshot()]
	check.call(not InventoryManager.move(small, 0, larger, Vector2i(0, 0)) and before == [small.snapshot(), larger.snapshot()], "illegal reverse swap rolls back both grids")
	var bags := RaidInventory.new(catalog.items, 12, 12)
	bags.add("small_pack", 1)
	bags.add("small_pack", 1)
	var first: Dictionary = bags.slots[0]
	var second: Dictionary = bags.slots[1]
	check.call(first.storage != second.storage and first.uid != second.uid, "physical containers never share mutable storage")
	first.storage.add("food", 2)
	check.call(second.storage.slots.is_empty(), "editing one bag leaves the other independent")
	check.call(not InventoryManager.move(bags, 0, first.storage), "container cannot contain itself")
	check.call(InventoryManager.move(bags, 1, first.storage), "compatible nested container moves with identity")
	var nested: RaidInventory = first.storage.slots[1].storage
	check.call(not InventoryManager.move(bags, 0, nested), "container cannot move into descendant")
	var encoded := bags.serialize()
	var decoded := InventoryPersistence.decode(encoded, catalog.items)
	check.call(decoded != null and decoded.slots[0].storage.count("food") == 2 and decoded.slots[0].storage.slots[1].uid == second.uid, "nested save retains contents and identities")
	var restricted := RaidInventory.new(catalog.items, 5, 5)
	var config := ContainerDef.new()
	config.dimensions = Vector2i(5, 5)
	config.allow_containers = false
	restricted.configure(config)
	check.call(not InventoryManager.move(bags, 0, restricted), "container nesting restriction enforced")
	var equipment := EquipmentComponent.new(catalog.items)
	check.call(not InventoryManager.move(first.storage, 0, equipment.slots.primary), "equipment rejects incompatible category")
	var ammo := RaidInventory.new(catalog.items, 10, 6)
	ammo.add("stanag_magazine", 1)
	ammo.add("five_five_six", 3)
	ammo.add("five_five_six_ap", 2)
	check.call(Ammunition.load(ammo, 0, "five_five_six") and Ammunition.load(ammo, 0, "five_five_six_ap"), "manual magazine loading consumes two compatible ammo types")
	var sequence: Array = ammo.slots[0].state.ammo.duplicate()
	check.call(sequence == ["five_five_six_ap", "five_five_six_ap", "five_five_six", "five_five_six", "five_five_six"], "magazine preserves next round order")
	var ammo_copy := InventoryPersistence.decode(ammo.serialize(), catalog.items)
	check.call(ammo_copy != null and ammo_copy.slots[0].state.ammo == sequence, "mixed ammunition survives serialization")
	ammo.add("nine_mm", 1)
	check.call(not Ammunition.load(ammo, 0, "nine_mm"), "magazine rejects wrong caliber")
	check.call(Ammunition.load(ammo, 0, "", true) and ammo.count("five_five_six") == 3 and ammo.count("five_five_six_ap") == 2, "unload restores actual mixed ammunition types")
	var search_grid := RaidInventory.new(catalog.items, 4, 3)
	search_grid.add("food", 1)
	search_grid.add("tool", 1)
	var search_config := ContainerDef.new()
	search_config.dimensions = Vector2i(4, 3)
	search_config.searchable = true
	search_config.progressive_discovery = true
	search_config.search_seconds = 2.0
	search_grid.configure(search_config)
	search_grid.begin_search()
	search_grid.tick_search(1.1)
	check.call(search_grid.visible_item(0) and not search_grid.visible_item(1), "progressive search reveals only discovered identities")
	InventoryManager.move(search_grid, 0, b)
	check.call(not search_grid.visible_item(0), "looting a discovered item cannot reveal the next hidden item early")
	var weight := ammo.total_weight()
	Ammunition.load(ammo, 0, "five_five_six")
	check.call(is_equal_approx(ammo.total_weight(), weight), "loading rounds does not change total weight")
	var crowded := RaidInventory.new(catalog.items, 4, 4)
	crowded.add("small_pack", 1)
	crowded.add("stanag_magazine", 1)
	var crowded_bag: Dictionary = crowded.slots[0]
	crowded_bag.storage.add("food", 1)
	crowded.slots[1].state.rounds = 2
	crowded.slots[1].state.ammo = ["five_five_six", "five_five_six_ap"]
	while crowded.add("salvage", 20): pass
	crowded.remove_entry(crowded.slots.back())
	var crowded_before := crowded.snapshot()
	check.call(not Ammunition.load(crowded, crowded.find_uid(crowded.slots[1].uid), "", true), "mixed unload with insufficient space fails atomically")
	check.call(crowded.snapshot() == crowded_before and crowded_bag.storage.parent_inventory.get_ref() == crowded, "failed draft cannot change nested contents or parent ownership")
	var sorter := RaidInventory.new(catalog.items, 4, 4)
	sorter.add_at("salvage", 3, 0, 0)
	sorter.add_at("salvage", 5, 2, 0)
	sorter.add("medkit", 1)
	check.call(sorter.sort() and sorter.count("salvage") == 8 and sorter.slots.size() == 2, "sorting consolidates stacks without loss")
	var rules := WeightRules.new()
	check.call(rules.burden(0) == 0 and rules.burden(30) == 0.5 and rules.burden(100) == 1, "weight thresholds clamp predictably")
	var path: String = t.test_dir + "/inventory-v5.json"
	var store := ProfileStore.new(catalog, path)
	check.call(store.load_profile(), "inventory profile starts with current one-time kit")
	var stash := store.stash_grid()
	stash.add_entry(bags.slots[0])
	check.call(store.save_layout(stash, {"pack": ammo}), "save persists separate staged root")
	var restarted := ProfileStore.new(catalog, path)
	check.call(restarted.load_profile() and restarted.profile.staged.pack.slots[0].state.ammo.size() == 3, "staged loadout persists across reload")
	var duplicate: Dictionary = restarted.profile.duplicate(true)
	duplicate.stash.append(duplicate.staged.pack.slots[0].duplicate(true))
	duplicate.stash.back().x = 8
	duplicate.stash.back().y = 15
	check.call(not restarted.valid(duplicate), "duplicate identity across profile roots rejected")
	var result := {"raid_id": "pending-inventory", "success": true, "reason": "test"}
	var loot_grid := RaidInventory.new(catalog.items, 4, 4)
	loot_grid.add("tool", 1)
	var loot: Array[Dictionary] = loot_grid.snapshot()
	check.call(restarted.stage_result(result, loot), "completed result journal saved before credit")
	var recovery := ProfileStore.new(catalog, path)
	check.call(recovery.load_profile() and not recovery.profile.pending_result.is_empty(), "pending result survives restart")
	check.call(recovery.commit_result(result, loot) and recovery.profile.pending_result.is_empty(), "pending result clears only after credit")
	var count: int = recovery.stash_grid().count("tool")
	check.call(recovery.commit_result(result, loot) and recovery.stash_grid().count("tool") == count, "extraction journal replay cannot duplicate loot")
	var v4: Dictionary = recovery.profile.duplicate(true)
	v4.version = 4
	v4.stash = []
	var legacy := RaidInventory.new(catalog.items, 10, 18)
	legacy.add("stanag_magazine", 1)
	legacy.slots[0].state.rounds = 9
	legacy.slots[0].state.erase("ammo")
	v4.stash = legacy.snapshot()
	var legacy_path: String = t.test_dir + "/version4.json"
	var file := FileAccess.open(legacy_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(v4))
	file.close()
	var migrated := ProfileStore.new(catalog, legacy_path)
	check.call(migrated.load_profile() and migrated.profile.version == 5 and migrated.profile.stash[0].state.ammo.size() == 9, "version 4 count migration preserves every round")
	var app = load("res://scenes/main.tscn").instantiate()
	app.test_profile_path = t.test_dir + "/inventory-world.json"
	t.root.add_child(app)
	for frame in range(3): await t.physics_frame
	app.ui.show_inventory(false)
	for frame in range(2): await t.process_frame
	var drag_grid: Control = app.ui.workspace.grids[app.loadout.pockets.uid]
	var drag_before: Array[Dictionary] = app.loadout.pockets.snapshot()
	var drag: Dictionary = drag_grid.drag_data(0)
	var preview_label := Label.new()
	preview_label.text = "Test drag"
	drag_grid.force_drag(drag, preview_label)
	check.call(app.get_viewport().gui_is_dragging(), "inventory starts real viewport drag")
	var rotate := InputEventKey.new()
	rotate.physical_keycode = KEY_R
	rotate.pressed = true
	drag_grid._input(rotate)
	check.call(bool(app.get_viewport().gui_get_drag_data().rotated) != bool(drag_before[0].rotated), "rotation action toggles drag orientation")
	var cancel := InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.pressed = true
	drag_grid._input(cancel)
	check.call(not app.get_viewport().gui_is_dragging() and app.loadout.pockets.snapshot() == drag_before, "Escape cancels drag without inventory mutation")
	var staging_before: Dictionary = app.profile.profile.duplicate(true)
	var staging_service: InventoryTransactions = app.inventory_service()
	var source: RaidInventory = app.loadout.pockets
	var saved_path: String = app.profile.path
	app.profile.path = t.test_dir + "/missing-directory/profile.json"
	var failed: Dictionary = app.submit_inventory(staging_service.request("move", source, app.loadout.pack, source.slots[0].uid))
	app.profile.path = saved_path
	check.call(not failed.ok and source.snapshot() == drag_before and app.profile.profile == staging_before, "failed staging save restores inventory and profile")
	app.deploy(false)
	for frame in range(3): await t.physics_frame
	var raid: RaidAuthority = app.raid
	raid.set_physics_process(false)
	raid.player.set_physics_process(false)
	var id: String = app.profile.profile.player_id
	var state: RaidParticipant = raid.participants[id]
	check.call(raid.npcs.size() == 2 and raid.npcs[1].archetype.melee, "normal yard includes playable zombie encounter")
	for npc in raid.npcs:
		var npc_items := npc.inventory.snapshot()
		raid._apply_damage(npc, 10000, null, true)
		check.call(not npc.corpse_id.is_empty() and raid.containers[npc.corpse_id] == npc.inventory and npc.inventory.snapshot() == npc_items, "NPC death exposes surviving original inventory")
		var corpse_id: String = npc.corpse_id
		raid._apply_damage(npc, 10000, null, true)
		check.call(npc.corpse_id == corpse_id, "repeated NPC death cannot regenerate corpse loot")
	for npc in raid.npcs:
		var target: RaidInventory = npc.inventory
		raid.player.global_position = raid.entities[npc.corpse_id].global_position + Vector3(0, 0.02, 2)
		var offset: Vector3 = raid.entities[npc.corpse_id].global_position - raid.player.eye_position()
		raid.player.rotation.y = atan2(-offset.x, -offset.z)
		raid.player.look_pitch = atan2(offset.y, Vector2(offset.x, offset.z).length())
		raid.player.camera.rotation.x = raid.player.look_pitch
		for frame in range(3): await t.physics_frame
		check.call(raid.request_interact(id, npc.corpse_id) and not target.visible_item(0), "corpse search hides undiscovered items")
		for tick in range(31): raid.gameplay_step()
		var corpse_item: String = target.slots[0].uid
		check.call(target.searched and raid.request_transfer(id, npc.corpse_id, 0) and state.owner_of(corpse_item) != null, "timed corpse search transfers surviving original item")
	state.inventory.add("small_pack", 1)
	var bag: Dictionary = state.inventory.slots.back()
	bag.storage.add("food", 2)
	bag.storage.add("stanag_magazine", 1)
	var nested_magazine: Dictionary = bag.storage.slots.back()
	nested_magazine.state.ammo = ["five_five_six_ap", "five_five_six"]
	nested_magazine.state.rounds = 2
	var nested_magazine_uid: String = nested_magazine.uid
	var bag_uid: String = bag.uid
	bag.storage.add("tool_case", 1)
	app.ui.show_inventory(true)
	var workspace: InventoryWorkspace = app.ui.workspace
	workspace.open_storage(bag.storage)
	workspace.open_storage(bag.storage.slots.back().storage)
	for frame in range(2): await t.process_frame
	check.call(workspace.windows.size() == 2, "multiple nested container windows open together")
	workspace.windows[0].position = Vector2(240, 100)
	workspace._unhandled_input(cancel)
	check.call(workspace.windows.size() == 1 and app.ui.mode == "raid_inventory", "Escape closes active container before fullscreen inventory")
	workspace._unhandled_input(cancel)
	check.call(workspace.windows.is_empty() and app.ui.container_positions[bag.storage.uid] == Vector2(240, 100), "container positions persist for the session")
	workspace._unhandled_input(cancel)
	check.call(app.ui.mode == "hud", "Escape closes fullscreen inventory after container windows")
	check.call(raid.request_drop(id, bag_uid) and state.owner_of(bag_uid) == null, "drop removes exact carried container")
	var dropped_id: String = raid.containers.keys().back()
	check.call(raid.containers[dropped_id].slots[0].uid == bag_uid and raid.containers[dropped_id].slots[0].storage.count("food") == 2, "world drop retains bag and nested contents")
	raid.player.global_position = raid.entities[dropped_id].global_position + Vector3(0, 0.02, 2)
	var point: Vector3 = raid.entities[dropped_id].global_position
	var direction := point - raid.player.eye_position()
	raid.player.rotation.y = atan2(-direction.x, -direction.z)
	raid.player.look_pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	raid.player.camera.rotation.x = raid.player.look_pitch
	for frame in range(3): await t.physics_frame
	check.call(raid.request_interact(id, dropped_id), "ground drops are reachable through actual interaction ray")
	check.call(raid.request_transfer(id, dropped_id, 0) and state.owner_of(bag_uid) != null, "world item can be looted back without changing identity")
	var carried: Array[Dictionary] = state.recovered_items()
	check.call(not carried.is_empty(), "recovery snapshot includes equipment roots")
	state.inventory.add("salvage", 1)
	raid.player.global_position = Vector3(-10, 0.02, 11)
	for frame in range(5): await t.physics_frame
	raid._update_extraction(id, 3.0)
	check.call(raid.phase == RaidAuthority.Phase.SUCCESS and not app.pending_save, "nested mixed-ammo loadout extracts through actual zone")
	var disk := ProfileStore.new(catalog, app.test_profile_path)
	check.call(disk.load_profile(), "extracted inventory reloads from disk")
	var disk_bag := disk.stash_grid().owner_of(bag_uid)
	check.call(disk_bag != null, "same physical backpack survives extraction and restart")
	if disk_bag != null:
		var disk_entry: Dictionary = disk_bag.slots[disk_bag.find_uid(bag_uid)]
		var disk_mag: RaidInventory = disk_entry.storage.owner_of(nested_magazine_uid)
		check.call(disk_mag != null and disk_mag.slots[disk_mag.find_uid(nested_magazine_uid)].state.ammo == ["five_five_six_ap", "five_five_six"], "nested magazine identity and ammunition order survive extraction and restart")
	app.home()
	for frame in range(3): await t.process_frame
	for root: RaidInventory in app.staged_roots().values(): root.slots.clear()
	app._save_stash_layout()
	app.deploy(false)
	for frame in range(3): await t.physics_frame
	check.call(app.raid != null and app.raid.participants[id].weapon == null, "unarmed deployment does not synthesize firearm")
	app.free()
	for frame in range(3): await t.process_frame

func reload_integration(t: SceneTree) -> void:
	var app = load("res://scenes/main.tscn").instantiate()
	app.test_profile_path = t.test_dir + "/reload-regression.json"
	t.root.add_child(app)
	for frame in range(3): await t.process_frame
	app.deploy(true)
	var raid: RaidAuthority = app.raid
	raid.set_physics_process(false)
	raid.player.set_physics_process(false)
	var id: String = app.profile.profile.player_id
	var state: RaidParticipant = raid.participants[id]
	var gun := state.weapon
	t.check(raid.request_reload(id), "practice starter magazine is reachable for combat reload")
	for tick in range(gun.definition.reload_ticks): gun.advance_tick()
	t.check(gun.magazine == 30 and gun.data.magazine.get("uid", "") != "", "practice reload inserts a complete physical magazine")
	if gun.magazine > 0:
		gun.fire()
		raid.practice_reset(id)
		t.check(gun.magazine == gun.definition.magazine_size and gun.data.chamber == "" and gun.data.magazine.state.ammo.size() == gun.definition.magazine_size, "practice reset refills equipped weapon consistently")
	var magazine_index := -1
	for grid in state.reload_grids():
		for i in range(grid.slots.size()):
			if grid.slots[i].id == gun.definition.magazine_id:
				magazine_index = i
	t.check(magazine_index >= 0, "practice spare magazine stays in quick-access storage")
	raid.request_abandon(id)
	app.home()
	for frame in range(3): await t.process_frame
	app.deploy(false)
	raid = app.raid
	raid.set_physics_process(false)
	raid.player.set_physics_process(false)
	state = raid.participants[id]
	gun = state.weapon
	t.check(raid.request_reload(id), "normal starter reload draws from clothing pockets")
	for tick in range(gun.definition.reload_ticks): gun.advance_tick()
	t.check(gun.magazine == 30, "normal reload completes across separate equipment and pocket roots")
	var loaded_uid: String = gun.data.magazine.get("uid", "")
	for grid in state.reload_grids():
		for i in range(grid.slots.size() - 1, -1, -1):
			if grid.slots[i].id == gun.definition.magazine_id: InventoryManager.move(grid, i, state.inventory)
	var before := state.recovered_items()
	t.check(not raid.request_reload(id) and state.recovered_items() == before and gun.data.magazine.get("uid", "") == loaded_uid, "reload without reachable spare does not eject or mutate loaded weapon")
	app.free()
	for frame in range(3): await t.process_frame
