extends RefCounted

var t: SceneTree
var catalog: Catalog

func armor(entry: Dictionary) -> ArmorPlates:
	var result := ArmorPlates.new()
	result.definitions = catalog.definitions
	result.entries.chestplate = entry
	return result

func run(context: SceneTree) -> void:
	t = context
	catalog = t.catalog
	for id in ProfileStore.VESTS: t.check(not catalog.items.has(id), "legacy vest absent from playable catalog: " + id)
	for id in ArmoryContent.ARMOR_IDS:
		var empty := ItemInstance.create(catalog.items[id], catalog.items)
		t.check(armor(empty).absorb(100) == 100 and armor(empty).movement_multiplier() == 1, "empty carrier gives no protection or plate penalty")
	var carrier := PlateInventory.loaded("carrier_dual", "plate_steel", catalog.items)
	carrier.state.plates[1] = ItemInstance.create(catalog.items.plate_ceramic, catalog.items)
	var protection := armor(carrier)
	t.check(is_equal_approx(protection.absorb(100), 55) and carrier.state.plates[0].state.wear == 45 and carrier.state.plates[1].state.wear == 0, "one plate absorbs each hit in slot order")
	t.check(is_equal_approx(protection.movement_multiplier(), 0.95) and is_equal_approx(ItemInstance.weight(carrier, catalog.items), 5.75), "mixed plate movement cost and nested weight")
	carrier.state.plates[0].state.wear = 175.0
	t.check(protection.absorb(100) == 95 and carrier.state.plates[0].is_empty() and carrier.state.plates[1].state.wear == 0, "breaking hit spills to health without consuming next plate")
	t.check(is_equal_approx(protection.absorb(100), 35) and carrier.state.plates[1].state.wear == 65, "next hit uses next material")
	t.check(protection.absorb(100) == 75 and carrier.state.plates[1].is_empty() and protection.movement_multiplier() == 1, "broken plates disappear with their movement cost")
	var full := armor(PlateInventory.loaded("carrier_triple", "plate_steel", catalog.items))
	t.check(is_equal_approx(full.movement_multiplier(), 0.91), "three steel plates cap movement penalty at nine percent")
	t.check(is_equal_approx(full.absorb(100, true, 0.2), 64) and full.entries.chestplate.state.plates[0].state.wear == 36, "bypass damage never consumes absorption capacity")
	_transactions()
	_migration()
	for tier in range(1, 5):
		var table := CampusLoot.table("security_gear", tier, catalog.items)
		var weights := {}
		for entry in table.entries: weights[entry.id] = entry.weight
		t.check(is_equal_approx(weights.carrier_single / weights.carrier_triple, 85) and is_equal_approx(weights.carrier_dual / weights.carrier_triple, 14), "carrier rarity ratio on floor tier %d" % tier)
		t.check(is_equal_approx(weights.plate_steel / weights.plate_composite, 14) and is_equal_approx(weights.plate_ceramic / weights.plate_composite, 5), "material rarity ratio on floor tier %d" % tier)

func _transactions() -> void:
	var grid := RaidInventory.new(catalog.items, 8, 6)
	grid.add("carrier_single", 1)
	grid.add("plate_steel", 1)
	var carrier_uid: String = grid.slots[0].uid
	var plate_uid: String = grid.slots[1].uid
	var service := InventoryTransactions.new()
	service.roots = [grid]
	service.actor_id = "plate-test"
	var request := service.request("insert_plate", grid, grid, plate_uid)
	request.carrier_uid = carrier_uid
	request.plate_slot = 0
	t.check(service.submit(request, true).ok and grid.slots.size() == 2, "plate insertion preview is read only")
	t.check(service.submit(request).ok and grid.slots.size() == 1, "base insertion is immediate and atomic")
	t.check(service.submit(request).ok and grid.slots.size() == 1 and grid.slots[0].state.plates[0].uid == plate_uid, "duplicate plate request cannot duplicate item")
	var encoded := grid.serialize()
	var decoded := InventoryPersistence.decode(encoded, catalog.items)
	t.check(decoded != null and decoded.slots[0].state.plates[0].uid == plate_uid, "nested plate identity survives serialization")
	var corrupt := encoded.duplicate(true)
	corrupt.slots[0].state.plates[0].state.wear = -1
	t.check(InventoryPersistence.decode(corrupt, catalog.items) == null, "negative plate wear rejected")
	corrupt = encoded.duplicate(true)
	corrupt.slots[0].state.plates[0].state.wear = NAN
	t.check(InventoryPersistence.decode(corrupt, catalog.items) == null, "nonfinite plate wear rejected")
	corrupt = encoded.duplicate(true)
	corrupt.slots[0].state.plates[0].state = "invalid"
	t.check(InventoryPersistence.decode(corrupt, catalog.items) == null, "malformed nested plate state rejected")
	corrupt = encoded.duplicate(true)
	corrupt.slots[0].state.plates.append({})
	t.check(InventoryPersistence.decode(corrupt, catalog.items) == null, "overcapacity carrier rejected")
	corrupt = encoded.duplicate(true)
	corrupt.slots[0].state.plates[0].state.instance_id = carrier_uid
	corrupt.slots[0].state.plates[0].uid = carrier_uid
	t.check(InventoryPersistence.decode(corrupt, catalog.items) == null, "duplicate carrier and plate identity rejected")
	var tiny := RaidInventory.new(catalog.items, 1, 1)
	service.roots.append(tiny)
	request = service.request("remove_plate", grid, tiny, carrier_uid)
	request.plate_slot = 0
	t.check(not service.submit(request).ok and not grid.slots[0].state.plates[0].is_empty(), "full destination leaves installed plate intact")
	request = service.request("remove_plate", grid, grid, carrier_uid)
	request.plate_slot = 0
	grid._notify()
	t.check(not service.submit(request).ok, "stale plate operation rejected")
	request = service.request("remove_plate", grid, grid, carrier_uid)
	request.plate_slot = 0
	t.check(service.submit(request).ok and grid.slots.size() == 2 and grid.slots[1].uid == plate_uid, "removal preserves physical identity")

func _migration() -> void:
	var store := ProfileStore.new(catalog, t.test_dir + "/plates-migration.json")
	var old_catalog := store._historical_catalog()
	var inventory := RaidInventory.new(old_catalog.items, 10, 18)
	for id in ProfileStore.VESTS:
		var entry := ItemInstance.create(old_catalog.items[id], old_catalog.items)
		entry.state.wear = old_catalog.definitions[id].max_durability / 2
		entry.metadata = {"keep": "original", "id": "vest"}
		inventory.insert_instance(entry)
	var candidate := store._empty_profile()
	candidate.version = 6
	candidate.starter_seeded = true
	candidate.stash = inventory.snapshot()
	candidate.stash_width = 10
	candidate.stash_height = 18
	var gear := EquipmentComponent.new(old_catalog.items)
	gear.slots.body_armor.insert_instance(ItemInstance.create(old_catalog.items.vest, old_catalog.items))
	candidate.staged = gear.serialize()
	var bag := ItemInstance.create(old_catalog.items.small_pack, old_catalog.items)
	bag.storage.insert_instance(ItemInstance.create(old_catalog.items.juggernaut, old_catalog.items))
	candidate.pending_result = {"result": {"raid_id": "plates-pending", "success": true, "reason": "extracted"}, "items": [bag]}
	# Pending journal entries are serialized dictionaries, including child storage.
	var pending_grid := RaidInventory.new(old_catalog.items)
	pending_grid.insert_instance(bag)
	candidate.pending_result.items = pending_grid.snapshot()
	t.check(store._valid_legacy(candidate), "v6 armor validated against original definitions")
	var file := FileAccess.open(store.path, FileAccess.WRITE)
	file.store_string(JSON.stringify(candidate))
	file.close()
	t.check(store.load_profile() and store.profile.version == 7, "v6 profile migrates to modular armor")
	if store.profile.stash.is_empty(): return
	for index in range(inventory.slots.size()):
		var before: Dictionary = inventory.slots[index]
		var after: Dictionary = store.profile.stash[index]
		t.check(after.uid == before.uid and after.metadata == before.metadata and after.id == ProfileStore.VESTS[before.id][0], "migration preserves carrier identity and metadata")
		for plate in after.state.plates:
			t.check(is_equal_approx(plate.state.wear, catalog.definitions[plate.id].capacity * 0.5), "migration preserves remaining durability percentage")
	t.check(store.profile.staged.body_armor.slots[0].id == "carrier_single", "staged armor migrated")
	t.check(store.profile.pending_result.items[0].storage.slots[0].id == "carrier_triple", "nested pending reward migrated without early credit")
	t.check(FileAccess.file_exists(store.path + ".bak"), "original profile backed up")
	var broken := ItemInstance.create(old_catalog.items.vest, old_catalog.items)
	broken.state.wear = old_catalog.definitions.vest.max_durability
	store._convert_armor(broken)
	t.check(broken.state.plates == [{}], "broken vest migrates into empty carrier")
	var constrained: ContainerDef = catalog.items.small_pack.container
	var old_limit := constrained.weight_limit
	constrained.weight_limit = 3.0
	var overflow_candidate := candidate.duplicate(true)
	overflow_candidate.version = 5
	store._convert_armor(overflow_candidate)
	var pending_uid: String = overflow_candidate.pending_result.items[0].storage.slots[0].uid
	t.check(store._repair_armor_layout(overflow_candidate) and overflow_candidate.pending_result.items.size() == 2 and overflow_candidate.pending_result.items[1].uid == pending_uid, "overweight nested pending gear stays in pending journal")
	var staged_bag := ItemInstance.create(catalog.items.small_pack, catalog.items)
	staged_bag.storage.insert_instance(ItemInstance.create(catalog.items.plate_steel, catalog.items))
	var staged_grid := RaidInventory.new(catalog.items)
	staged_grid.insert_instance(staged_bag)
	var staged_serialized := staged_grid.serialize()
	staged_serialized.slots[0].storage.slots[0] = PlateInventory.loaded("carrier_triple", "plate_composite", catalog.items)
	overflow_candidate.staged.pack = staged_serialized
	var overflow_uid: String = staged_serialized.slots[0].storage.slots[0].uid
	t.check(store._repair_armor_layout(overflow_candidate) and overflow_candidate.stash.any(func(entry): return entry.uid == overflow_uid), "overweight staged contents move into stash without loss")
	constrained.weight_limit = old_limit
	var invalid := candidate.duplicate(true)
	invalid.stash[0].state.wear = 999999
	t.check(not store._valid_legacy(invalid), "invalid historical condition rejected before conversion")

func _prepare(raid: RaidAuthority, state: RaidParticipant) -> Dictionary:
	state.pending_plate.clear()
	state.inventory.slots.clear()
	var equipped: RaidInventory = state.equipment.slots.body_armor
	equipped.slots = [ItemInstance.create(catalog.items.carrier_single, catalog.items)]
	equipped._notify()
	state.inventory.add("plate_steel", 1)
	state.refresh_armor(catalog)
	var service := raid.inventory_service(state.actor.entity_id)
	var request := service.request("insert_plate", state.inventory, equipped, state.inventory.slots[0].uid)
	request.carrier_uid = equipped.slots[0].uid
	request.plate_slot = 0
	return request

func integration(context: SceneTree, raid: RaidAuthority, state: RaidParticipant) -> void:
	t = context
	catalog = t.catalog
	var pack_before := state.inventory.slots.duplicate(true)
	var armor_before: Array[Dictionary] = state.equipment.slots.body_armor.slots.duplicate(true)
	var request := _prepare(raid, state)
	var service := raid.inventory_service(state.actor.entity_id)
	t.check(service.submit(request).ok and not state.pending_plate.is_empty() and state.armor.protection() == 0, "raid insertion starts without moving items")
	t.check(not raid.request_fire(state.actor.entity_id) and not raid.request_reload(state.actor.entity_id) and not raid.request_melee(state.actor.entity_id) and not raid.request_grenade(state.actor.entity_id, "impact_nade"), "plate action prevents weapons and reload")
	var start_tick := raid.gameplay_tick
	t.paused = true
	raid.set_physics_process(true)
	for frame in range(3): await t.physics_frame
	t.check(raid.gameplay_tick == start_tick and not state.pending_plate.is_empty(), "pause freezes plate timer")
	t.paused = false
	raid.set_physics_process(false)
	for tick in range(59): raid.gameplay_step()
	t.check(state.armor.protection() == 0 and not state.pending_plate.is_empty(), "plate action remains pending before three seconds")
	raid.gameplay_step()
	t.check(state.pending_plate.is_empty() and is_equal_approx(state.armor.protection(), 0.45) and state.inventory.count("plate_steel") == 0, "plate insertion commits at sixty ticks")
	t.check(service.submit(request).ok and state.inventory.count("plate_steel") == 0, "duplicate timed request does not create another plate")
	var equipped: RaidInventory = state.equipment.slots.body_armor
	request = service.request("remove_plate", equipped, state.inventory, equipped.slots[0].uid)
	request.plate_slot = 0
	t.check(service.submit(request).ok and state.inventory.count("plate_steel") == 0 and state.armor.protection() > 0, "timed removal retains protection until completion")
	for tick in range(60): raid.gameplay_step()
	t.check(state.pending_plate.is_empty() and state.inventory.count("plate_steel") == 1 and state.armor.protection() == 0, "timed removal commits intact plate")
	request = _prepare(raid, state)
	if state.weapon != null: state.weapon.reload_end = raid.gameplay_tick + 10
	t.check(not service.submit(request).ok and state.pending_plate.is_empty(), "reload prevents starting plate action")
	if state.weapon != null: state.weapon.cancel_reload()
	request = _prepare(raid, state)
	t.check(service.submit(request).ok, "start interruptible plate insertion")
	raid._apply_damage(state.actor, 1)
	t.check(state.pending_plate.is_empty() and state.inventory.count("plate_steel") == 1 and state.armor.protection() == 0, "incoming damage cancels without consuming plate")
	request = _prepare(raid, state)
	service.submit(request)
	raid.cancel_plate_change(state.actor.entity_id)
	t.check(state.pending_plate.is_empty() and state.inventory.count("plate_steel") == 1, "explicit cancellation preserves plate")
	request = _prepare(raid, state)
	service.submit(request)
	raid.request_select(state.actor.entity_id, state.selected)
	t.check(state.pending_plate.is_empty(), "weapon selection cancels plate change")
	request = _prepare(raid, state)
	service.submit(request)
	InventoryManager.move(state.inventory, 0, state.inventory, Vector2i(2, 0))
	raid.gameplay_step()
	t.check(state.pending_plate.is_empty() and state.armor.protection() == 0, "moving participating plate cancels insertion")
	request = _prepare(raid, state)
	service.submit(request)
	state.actor.sprint_input = true
	state.actor.drive_movement(Vector2(0, -1), false, true, 0.05)
	t.check(not state.actor.sprinting, "plate action blocks sprint while allowing movement")
	raid.cancel_plate_change(state.actor.entity_id)
	# Moving the bag containing the source plate must invalidate the action too.
	request = _prepare(raid, state)
	state.inventory.add("small_pack", 1)
	var bag: Dictionary = state.inventory.slots.back()
	InventoryManager.move(state.inventory, 0, bag.storage)
	request = service.request("insert_plate", bag.storage, equipped, bag.storage.slots[0].uid)
	request.carrier_uid = equipped.slots[0].uid
	request.plate_slot = 0
	t.check(service.submit(request).ok, "plate in nested bag can start insertion")
	InventoryManager.move(state.inventory, state.inventory.find_uid(bag.uid), state.inventory, Vector2i(4, 0))
	raid.gameplay_step()
	t.check(state.pending_plate.is_empty() and bag.storage.count("plate_steel") == 1, "moving containing bag cancels without losing plate")
	request = _prepare(raid, state)
	service.submit(request)
	state.inventory.capacity = 0
	state.inventory._notify()
	raid.gameplay_step()
	t.check(state.pending_plate.is_empty() and state.inventory.count("plate_steel") == 1, "inventory restriction change cancels safely")
	state.inventory.capacity = -1
	var player := state.actor
	var origin := player.global_position
	t.check(Ballistics.torso_hit(player, origin + Vector3.UP) and not Ballistics.torso_hit(player, origin + Vector3.UP * 0.4) and not Ballistics.torso_hit(player, player.eye_position()), "standing torso excludes legs and head")
	player._set_crouching(true)
	t.check(Ballistics.torso_hit(player, origin + Vector3.UP * 0.9) and not Ballistics.torso_hit(player, player.eye_position()) and not Ballistics.torso_hit(player, origin + Vector3.UP * 0.4), "crouched torso boundary follows collision height")
	player._set_crouching(false)
	equipped.slots = [PlateInventory.loaded("carrier_single", "plate_steel", catalog.items)]
	state.refresh_armor(catalog)
	state.health = 200
	raid._apply_damage(player, 100)
	t.check(state.health == 145 and equipped.slots[0].state.plates[0].state.wear == 45, "player melee uses real equipped plate state")
	state.health = 200
	var wear: float = equipped.slots[0].state.plates[0].state.wear
	raid._apply_damage(player, 20, null, true)
	t.check(state.health == 180 and equipped.slots[0].state.plates[0].state.wear == wear, "fall/bypass damage leaves plates unchanged")
	raid._initialize_npc(raid.guard)
	var health: float = raid.guard.health
	raid._apply_damage(raid.guard, 100)
	var npc_plate := raid.guard.armor_plates.active_plate()
	t.check(raid.guard.health == health - 55 and npc_plate.state.wear == 45, "NPC armor shares player protection and lootable wear")
	t.check(raid.guard.inventory.snapshot().any(func(entry): return entry.id == "carrier_single" and entry.state.plates[0].uid == npc_plate.uid), "NPC corpse inventory retains physical plate")
	raid._initialize_npc(raid.guard)
	state.inventory.slots = pack_before
	state.equipment.slots.body_armor.slots = armor_before
	state.pending_plate.clear()
	state.health = RaidParticipant.MAX_HEALTH
	state.actor.sprint_input = false
	state.actor.movement.velocity = Vector3.ZERO
	state.refresh_armor(catalog)
	state.inventory._notify()
	state.equipment.slots.body_armor._notify()
