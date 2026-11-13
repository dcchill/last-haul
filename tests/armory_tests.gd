extends SceneTree

var failures := 0
var checks := 0
var catalog := Catalog.new()
var test_dir := "res://.godot/armory-tests-" + ProfileStore._new_id()
var fixtures = preload("res://tests/fixtures/armory_reference.json")

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(test_dir)
	check(catalog.load_all().is_empty(), "catalog validates")
	check(Catalog.new().load_all().is_empty(), "catalog can be loaded repeatedly")
	_definitions()
	_inventory()
	_weapons()
	_references()
	_persistence()
	await _integration()
	await _raid_outcomes()
	await _physics_regressions()
	await load("res://tests/inventory_tests.gd").new().run(self)
	print("ARMORY TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _definitions() -> void:
	check(ArmoryContent.DATA.data.guns.size() == 12, "all 12 registered weapons imported")
	for source in ArmoryContent.DATA.data.guns:
		var gun: WeaponDef = catalog.definitions[source.id]
		check(gun.interval_ticks == int(source.interval) and gun.reload_ticks == int(source.reload_ticks), source.id + " timing matches source")
		check(gun.damage == source.damage and gun.pellets == int(source.pellets) and gun.magazine_size == int(source.capacity), source.id + " damage, pellets, feed capacity")
		check(gun.automatic == source.automatic and gun.projectile_speed == source.speed and gun.head_multiplier == source.head_multiplier, source.id + " fire mode, velocity, head multiplier")
		check(ResourceLoader.exists(gun.model_path) and ResourceLoader.exists(gun.texture_path) and ResourceLoader.exists(gun.animation_path), source.id + " presentation assets available offline")
		var clips: Dictionary = load(gun.animation_path).data.animations
		check(is_equal_approx(float(clips.reload.animation_length), gun.reload_seconds), source.id + " reload animation synchronized")
		for source_attachment in ArmoryContent.DATA.data.attachments:
			var attachment: AttachmentDef = catalog.definitions[source_attachment.id]
			var bit: int = {"optic": 1, "muzzle": 2, "grip": 4}[attachment.slot]
			check(attachment.supports(gun) == bool(gun.attachment_slots & bit), source.id + " attachment compatibility " + attachment.id)
	check(ArmoryContent.DATA.data.armor.is_empty(), "importer adds no vanilla armor items")
	for tier in ArmoryContent.REMOVED_ARMOR_TIERS:
		for slot in ["helmet", "chestplate", "leggings", "boots"]:
			check(not catalog.items.has(tier + "_" + slot), "no vanilla item in catalog: " + tier + "_" + slot)
	check(catalog.definitions.maska.points == 0 and catalog.definitions.maska.slot == "helmet", "Maska is cosmetic helmet")
	check(catalog.items.balanced_compensator.display_name.begins_with("Legacy"), "obsolete attachments retained as legacy")

func _inventory() -> void:
	var pack := RaidInventory.new(catalog.items, 4, 4)
	check(pack.add("salvage", 20), "grid add")
	var before := pack.snapshot()
	check(not pack.add("m_four", 1) and pack.snapshot() == before, "oversized add atomic")
	var mag := ArmoryInstance.fresh("stanag_magazine", catalog.items)
	mag.rounds = 17
	check(pack.add("stanag_magazine", 1, mag), "stateful magazine insert")
	var destination := RaidInventory.new(catalog.items, 4, 4)
	var index := pack.find_instance(mag.instance_id)
	check(pack.transfer_to(index, destination, 0, 0), "instance transfer")
	check(destination.slots[0].state.rounds == 17 and destination.slots[0].state.instance_id == mag.instance_id, "transfer preserves rounds and identity")
	check(destination.sort() and destination.slots[0].state.rounds == 17, "sort preserves state")
	var encoded := destination.serialize()
	var decoded := InventoryPersistence.decode(encoded, catalog.items)
	check(decoded != null and decoded.slots[0].state.rounds == 17, "inventory persistence round trip")
	var snapshot := decoded.snapshot()
	snapshot[0].state.rounds = 1
	check(decoded.slots[0].state.rounds == 17, "snapshot state does not alias")
	var bag := RaidInventory.new(catalog.items, 8, 8)
	if catalog.items.has("small_pack"):
		check(bag.add("small_pack", 1), "concurrent container content preserved")
		check(bag.slots[0].has("storage"), "container runtime storage preserved")
		check(InventoryPersistence.decode(bag.serialize(), catalog.items) != null, "nested container serialization")

func _gun_pack(id: String, loaded: int = 0) -> Dictionary:
	var pack := RaidInventory.new(catalog.items, 10, 10)
	pack.add(id, 1)
	var gun: WeaponDef = catalog.definitions[id]
	var entry: Dictionary = pack.slots[0]
	if not gun.magazine_id.is_empty() and loaded > 0:
		var mag := ArmoryInstance.fresh(gun.magazine_id, catalog.items)
		mag.rounds = loaded
		entry.state.magazine = {"id": gun.magazine_id, "quantity": 1, "state": mag}
	elif gun.magazine_id.is_empty():
		entry.state.rounds = loaded
		entry.state.erase("ammo")
	var weapon := WeaponState.new(gun)
	weapon.bind(pack, entry)
	return {"pack": pack, "weapon": weapon}

func _weapons() -> void:
	var kit := _gun_pack("m_four")
	var gun: WeaponState = kit.weapon
	var pack: RaidInventory = kit.pack
	pack.add("five_five_six", 64)
	var mag := ArmoryInstance.fresh("stanag_magazine", catalog.items)
	mag.rounds = 23
	pack.add("stanag_magazine", 1, mag)
	check(gun.reload() and gun.reload_action == "reload_insert", "first magazine uses insertion animation")
	for tick in range(39): gun.advance_tick()
	check(gun.magazine == 0 and pack.find_instance(mag.instance_id) >= 0, "reload does not transfer early")
	gun.advance_tick()
	check(gun.magazine == 23 and pack.find_instance(mag.instance_id) < 0, "reload transfers physical magazine at tick 40")
	check(gun.fire() and gun.magazine == 22 and not gun.fire(), "fire consumes once and enforces cooldown")
	for tick in range(3): gun.advance_tick()
	check(gun.fire() and gun.magazine == 21, "fire ready after source interval")
	check(not gun.reload("missing-magazine"), "invalid explicit magazine rejected without ejection")
	check(gun.reload("eject"), "explicit magazine ejection")
	for tick in range(40): gun.advance_tick()
	check(gun.magazine == 1 and gun.data.chamber == "five_five_six" and pack.find_instance(mag.instance_id) >= 0, "ejection retains chambered round and physical magazine")
	check(pack.slots[pack.find_instance(mag.instance_id)].state.rounds == 20, "magazine ammunition conserved separately from chamber")
	check(gun.reload(), "reload can begin again")
	gun.cancel_reload()
	for tick in range(100): gun.advance_tick()
	check(gun.magazine == 1 and pack.find_instance(mag.instance_id) >= 0, "cancelled reload transfers nothing")
	gun.reload()
	pack.remove_entry(pack.slots[pack.find_instance(mag.instance_id)])
	gun.advance_tick()
	check(gun.reload_left == 0 and gun.magazine == 1, "missing donor cancels reload")
	kit = _gun_pack("m_four", 10)
	gun = kit.weapon
	while kit.pack.add("salvage", 20): pass
	var before_eject: Array = kit.pack.snapshot()
	check(not gun.reload("eject") and gun.magazine == 10 and kit.pack.snapshot() == before_eject, "full pack rejects magazine ejection atomically")
	kit = _gun_pack("m_four")
	gun = kit.weapon
	var donor := ArmoryInstance.fresh("stanag_magazine", catalog.items)
	donor.rounds = 12
	kit.pack.add("stanag_magazine", 1, donor)
	gun.reload()
	kit.pack.move(kit.pack.find_instance(donor.instance_id), 8, 8)
	gun.advance_tick()
	check(gun.reload_left == 0 and gun.magazine == 0, "moving the selected donor cancels reload like source inventory slot changes")
	kit = _gun_pack("bolt_action_sniper", 5)
	gun = kit.weapon
	kit.pack.add("fifty_cal", 5)
	check(gun.fire() and gun.cycling_bolt() and not gun.reload(), "sniper cycle blocks reload")
	for tick in range(24): gun.advance_tick()
	check(not gun.fire(), "bolt cycle cannot be shortened")
	gun.advance_tick()
	check(gun.fire(), "sniper fires at 25 ticks")
	kit = _gun_pack("double_barrel", 0)
	gun = kit.weapon
	kit.pack.add("shotgun_shell", 3)
	check(gun.reload(), "shotgun direct reload")
	for tick in range(45): gun.advance_tick()
	check(gun.magazine == 2 and kit.pack.count("shotgun_shell") == 1, "direct reload conserves shells")

func _references() -> void:
	var bullet := Ballistics.new().make_bullet(Vector3(0, 1.57, 0), Vector3.FORWARD, 9, 0, 6, 1.5, 1, [])
	var sample := 0
	for tick in range(1, 101):
		Ballistics.advance(bullet)
		if tick == int(fixtures.data.bullet[sample].tick):
			var expected: Array = fixtures.data.bullet[sample].position
			check(bullet.position.distance_to(Vector3(expected[0], expected[1], expected[2])) < 0.003, "bullet trajectory source fixture tick %d" % tick)
			sample = mini(sample + 1, fixtures.data.bullet.size() - 1)
	for name in ["walk", "sprint"]:
		var movement := MinecraftMovement.new()
		var z := 0.0
		sample = 0
		for tick in range(1, 101):
			z += movement.integrate(Vector2(0, -1), 0, true, name == "sprint", false, false).z
			if tick == int(fixtures.data.movement[name][sample].tick):
				check(absf(z - float(fixtures.data.movement[name][sample].z)) < 0.001, name + " movement source fixture tick %d" % tick)
				sample = mini(sample + 1, fixtures.data.movement[name].size() - 1)
	for armor in fixtures.data.armor:
		check(is_equal_approx(ArmorPlates.reduce(armor.damage, armor.armor, armor.toughness), armor.result), "Minecraft armor fixture")
	var armor := ArmorPlates.new(catalog.definitions.patrol)
	armor.absorb(8)
	check(armor.entries.chestplate.state.wear == 2, "armor wear uses incoming damage / 4")
	armor.entries.chestplate.state.wear = armor.definition.max_durability - 1
	check(armor.absorb(4) == 4 and armor.points() == 0, "broken armor stops protecting")
	check(armor.movement_multiplier() == 1, "Minecraft armor has no weight slow")
	var results: Array[Dictionary] = []
	for fps in [30, 60, 144]:
		var accumulator := 0.0
		var ticks := 0
		var gun: WeaponState = _gun_pack("m_four", 30).weapon
		var shots := 0
		for frame in range(fps * 3):
			accumulator += 1.0 / fps
			while accumulator + 0.0000001 >= 0.05:
				accumulator -= 0.05
				ticks += 1
				gun.advance_tick()
				if gun.fire(): shots += 1
		results.append({"ticks": ticks, "shots": shots, "rounds": gun.magazine})
	check(results[0] == results[1] and results[1] == results[2] and results[0].ticks == 60, "30/60/144 FPS produce identical logical fire ticks")
	var motion_a := WeaponMotion.new()
	var motion_b := WeaponMotion.new()
	motion_a.fire(1)
	motion_b.fire(1)
	for tick in range(30): motion_a.update(1.0 / 30, true, 0.2, Vector2.ZERO, 0, false, true, -1)
	for tick in range(144): motion_b.update(1.0 / 144, true, 0.2, Vector2.ZERO, 0, false, true, -1)
	check(absf(motion_a.barrel_angle - motion_b.barrel_angle) < 0.01, "source minigun spin is frame independent")

func _persistence() -> void:
	var store := ProfileStore.new(catalog, test_dir + "/profile.json")
	check(store.load_profile() and store.valid(store.profile), "starter profile v4")
	var identity: String = store.profile.player_id
	var old := {"version": 2, "player_id": "legacy-player", "stash": [{"id": "rifle", "quantity": 1, "x": 0, "y": 0, "rotated": false}, {"id": "vest", "quantity": 1, "x": 2, "y": 0, "rotated": false}, {"id": "rifle_round", "quantity": 60, "x": 4, "y": 0, "rotated": false}], "starter_seeded": true, "last_result": {}, "committed_raids": ["old-raid"]}
	var old_path := test_dir + "/old.json"
	var file := FileAccess.open(old_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(old))
	file.close()
	var migrated := ProfileStore.new(catalog, old_path)
	check(migrated._valid_legacy(old), "legacy v2 accepted before conversion")
	check(migrated.load_profile() and migrated.profile.version == 5 and migrated.profile.player_id == "legacy-player", "v2 migration preserves identity")
	if migrated.profile.stash.is_empty():
		print("MIGRATION ERROR: ", migrated.load_error)
		return
	check(migrated.profile.stash[0].id == "m_four" and migrated.profile.stash[1].id == "vest" and migrated.profile.stash[2].quantity == 60, "legacy gun, armor and ammo mappings")
	check(migrated.profile.committed_raids.has("old-raid"), "migration preserves outcome ledger")
	var v3 := store.profile.duplicate(true)
	v3.version = 3
	var equipped_id: String = v3.stash[0].state.instance_id
	v3.stash[0].state.magazine = {"id": "stanag_magazine", "quantity": 1, "state": ArmoryInstance.fresh("stanag_magazine", catalog.items)}
	v3.stash[0].state.magazine.state.rounds = 17
	v3.stash[0].state.attachments.optic = {"id": "four_x_scope", "quantity": 1, "state": ArmoryInstance.fresh("four_x_scope", catalog.items)}
	v3.stash.append({"id": "leather_chestplate", "quantity": 1, "x": 8, "y": 10, "rotated": false, "state": {"instance_id": "old-vanilla-armor", "wear": 7}})
	var v3_path := test_dir + "/v3.json"
	file = FileAccess.open(v3_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(v3))
	file.close()
	var upgraded := ProfileStore.new(catalog, v3_path)
	check(upgraded.load_profile() and upgraded.profile.version == 5, "old vanilla-equipment save upgrades")
	var converted := false
	var gun_preserved := false
	for entry in upgraded.profile.stash:
		check(ArmoryContent.removed_armor_replacement(entry.id).is_empty(), "upgraded stash contains no vanilla item")
		if entry.state.get("instance_id", "") == "old-vanilla-armor":
			converted = entry.id == "patrol" and entry.state.wear == 7
		if entry.state.get("instance_id", "") == equipped_id:
			gun_preserved = entry.state.magazine.state.rounds == 17 and entry.state.attachments.optic.id == "four_x_scope"
	check(converted and gun_preserved, "v3 conversion keeps armor condition and gun attachments/ammunition")
	check(upgraded.profile.player_id == v3.player_id and upgraded.profile.committed_raids == v3.committed_raids, "v3 conversion preserves identity and history")

	var container_pack := RaidInventory.new(catalog.items, 10, 18)
	container_pack.add("small_pack", 1)
	var bag: Dictionary = container_pack.slots[0]
	bag.condition = 0.72
	bag.metadata = {"label": "original bag"}
	bag.storage.add("rifle_round", 20)
	bag.storage.slots[0].metadata = {"label": "original rounds"}
	var nested := old.duplicate(true)
	nested.stash = container_pack.snapshot()
	var nested_path := test_dir + "/nested-legacy.json"
	file = FileAccess.open(nested_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(nested))
	file.close()
	var nested_store := ProfileStore.new(catalog, nested_path)
	check(nested_store.load_profile(), "nested inventory profile migrates")
	var saved_bag: Dictionary = nested_store.profile.stash[0]
	check(saved_bag.condition == 0.72 and saved_bag.metadata.label == "original bag", "migration preserves existing inventory metadata")
	check(saved_bag.storage.slots[0].id == "five_five_six" and saved_bag.storage.slots[0].quantity == 20 and saved_bag.storage.slots[0].metadata.label == "original rounds", "nested ammunition migration preserves quantities and metadata")
	var legacy_one := {"version": 1, "player_id": "v1-player", "stash": [{"id": "salvage", "quantity": 2}], "last_result": {}, "committed_raids": []}
	var one_path := test_dir + "/v1.json"
	file = FileAccess.open(one_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy_one))
	file.close()
	var one_store := ProfileStore.new(catalog, one_path)
	check(one_store.load_profile() and one_store.profile.player_id == "v1-player" and one_store.profile.stash[0].quantity == 2, "version 1 flat-stack profile migrates")

	var gear: Dictionary = _gun_pack("barret", 4).pack.snapshot()[0]
	gear.state.attachments.optic = {"id": "sniper_scope", "quantity": 1, "state": ArmoryInstance.fresh("sniper_scope", catalog.items)}
	var loot: Array[Dictionary] = [gear]
	var result := {"raid_id": "extract-one", "success": true, "reason": "test"}
	check(store.commit_result(result, loot), "extracts stateful gun")
	var count: int = store.profile.stash.size()
	check(store.commit_result(result, loot) and store.profile.stash.size() == count, "result idempotence")
	var reload_store := ProfileStore.new(catalog, store.path)
	check(reload_store.load_profile() and reload_store.profile.player_id == identity, "profile reload")
	var saved: Dictionary = reload_store.profile.stash.back().state
	check(saved.magazine.state.rounds == 4 and saved.attachments.optic.id == "sniper_scope", "loaded magazine and optic survive disk round trip")
	var invalid := store.profile.duplicate(true)
	invalid.stash.append(invalid.stash.back().duplicate(true))
	invalid.stash.back().x = 8
	invalid.stash.back().y = 10
	check(not store.valid(invalid), "duplicate item identity rejected")
	invalid = store.profile.duplicate(true)
	invalid.stash.back().state.magazine.state.rounds = 900
	check(not store.valid(invalid), "overfilled saved magazine rejected")
	check(not store.commit_result({"raid_id": "practice", "success": true, "reason": "test", "practice": true}, loot), "practice cannot grant persistent items")
	check(store.commit_result({"raid_id": "death", "success": false, "reason": "test"}, loot) and store.profile.stash.size() == count, "death does not return equipment")
	file = FileAccess.open(store.path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	check(reload_store.load_profile() and reload_store.writable, "corrupt main recovers from valid backup")
	check(FileAccess.get_file_as_string(store.path) == "{broken", "corrupt main remains preserved until explicit save")
	check(reload_store.save_profile(), "backup recovery can be committed")
	var failed := ProfileStore.new(catalog, test_dir + "/missing/profile.json")
	check(not failed.commit_result(result, loot) and failed.profile.committed_raids.is_empty(), "failed write leaves result retryable")
	failed.path = test_dir + "/retry.json"
	check(failed.commit_result(result, loot), "failed write retry succeeds")

func _integration() -> void:
	var app = load("res://scenes/main.tscn").instantiate()
	app.test_profile_path = test_dir + "/app.json"
	root.add_child(app)
	for frame in range(3): await process_frame
	var original_profile: Dictionary = app.profile.profile.duplicate(true)
	app.deploy(true)
	for frame in range(8): await physics_frame
	var raid: RaidAuthority = app.raid
	check(raid != null and raid.practice and raid.participants.size() == 1, "practice deploys")
	var state: RaidParticipant = raid.participants[app.profile.profile.player_id]
	raid.set_physics_process(false)
	raid.player.accepts_local_input = false
	check(state.health == 20 and raid.mounts.size() == 2, "Minecraft health and mounted practice stations")
	check(not raid.request_fire("stranger") and not raid.request_reload("stranger"), "authority rejects unknown player")
	for source in ArmoryContent.DATA.data.guns:
		state.inventory.slots.clear()
		check(raid.practice_grant(state.actor.entity_id, source.id), source.id + " available in practice")
		check(not raid.player.rifle.bones.is_empty() and raid.player.rifle.clips.has("fire"), source.id + " rendered hierarchy and clips")
		var muzzle: Vector3 = raid.player.rifle.bones.muzzle_socket.global_position
		check(raid.request_fire(state.actor.entity_id), source.id + " fires through authority")
		check(not raid.projectiles.is_empty() and raid.projectiles[0].position.is_equal_approx(muzzle), source.id + " projectile starts at muzzle")
		raid.projectiles.clear()
		state.next_shot = 0
		state.weapon.next_shot = 0
	# Semiautomatic requires a new trigger edge; automatic repeats at source intervals.
	state.inventory.slots.clear()
	raid.practice_grant(state.actor.entity_id, "m_sixteen")
	state.weapon.next_shot = 0
	state.next_shot = 0
	raid.request_input(state.actor.entity_id, true, false)
	var remaining := state.weapon.magazine
	for tick in range(8):
		raid.request_input(state.actor.entity_id, true, false)
		raid.gameplay_step()
	check(state.weapon.magazine == remaining, "held semiautomatic trigger does not repeat")
	raid.request_input(state.actor.entity_id, false, false)
	raid.request_input(state.actor.entity_id, true, false)
	check(state.weapon.magazine == remaining - 1, "new trigger edge fires semiautomatic")
	state.inventory.slots.clear()
	raid.practice_grant(state.actor.entity_id, "m_four")
	state.weapon.next_shot = 0
	state.next_shot = 0
	raid.request_input(state.actor.entity_id, true, true)
	remaining = state.weapon.magazine
	for tick in range(6):
		raid.request_input(state.actor.entity_id, true, true)
		raid.gameplay_step()
	check(state.weapon.magazine == remaining - 2, "automatic repeats every three ticks")
	check(state.weapon.aiming, "ADS authority state")
	raid.request_input(state.actor.entity_id, false, false, true)
	check(not raid.request_fire(state.actor.entity_id), "customization blocks shooting")
	state.inventory.add("sniper_scope", 1)
	var optic: Dictionary = state.inventory.slots.back()
	check(raid.request_attachment(state.actor.entity_id, "optic", optic.state.instance_id), "authority installs compatible optic")
	check(state.weapon.magnification(catalog.definitions) == 6 and raid.player.scope_lens != null, "scope magnification and separate viewport lens")
	check(raid.request_attachment(state.actor.entity_id, "optic"), "attachment removal returns optic")
	state.inventory.add("impact_nade", 2)
	var grenades := state.inventory.count("impact_nade")
	check(raid.request_grenade(state.actor.entity_id, "impact_nade") and not raid.request_grenade(state.actor.entity_id, "impact_nade"), "grenade cooldown and duplicate rejection")
	raid.gameplay_step()
	check(state.inventory.count("impact_nade") == grenades - 1, "throw consumes exactly one grenade")
	raid.projectiles.clear()
	var mount: MountedArmory = raid.mounts[0]
	mount.powered = true
	mount.ammo = 2
	mount.next_shot = 0
	raid.gameplay_tick = 100
	mount.authority_tick(raid)
	check(mount.ammo == 1 and not raid.projectiles.is_empty(), "mounted weapon consumes ammo and launches projectile")
	mount.powered = false
	mount.authority_tick(raid)
	check(mount.ammo == 1, "unpowered mount cannot fire")
	state.health = 3
	raid._apply_damage(raid.player, 100, null, true)
	check(state.health == 20 and raid.is_active(), "practice death restores health")
	check(raid.practice_reset(state.actor.entity_id), "practice reset")
	check(app.profile.profile == original_profile, "practice never debits or mutates stash")
	raid.request_abandon(state.actor.entity_id)
	check(not app.pending_save and app.profile.profile == original_profile, "practice exit never commits loot")
	app.home()
	for frame in range(3): await process_frame
	app.deploy(false)
	for frame in range(4): await physics_frame
	raid = app.raid
	check(raid != null and not raid.practice, "raid deploys from staged gear")
	check(app.profile.profile.staged.is_empty() and not original_profile.staged.is_empty(), "raid debits persistent staged loadout before play")
	raid.request_abandon(app.profile.profile.player_id)
	check(not app.pending_save and app.profile.profile.last_result.success == false, "raid abandonment commits failure")
	app.free()
	for frame in range(3): await process_frame

func _aim_at(actor: RaidPlayer, point: Vector3) -> void:
	var direction := point - (actor.global_position + Vector3.UP * 1.62)
	actor.rotation.y = atan2(-direction.x, -direction.z)
	actor.look_pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	actor.camera.rotation.x = actor.look_pitch

func _raid_outcomes() -> void:
	var app = load("res://scenes/main.tscn").instantiate()
	app.test_profile_path = test_dir + "/outcomes.json"
	root.add_child(app)
	for frame in range(3): await physics_frame
	app.deploy(false)
	for frame in range(4): await physics_frame
	var raid: RaidAuthority = app.raid
	var id: String = app.profile.profile.player_id
	var state: RaidParticipant = raid.participants[id]
	raid.set_physics_process(false)
	raid.player.set_physics_process(false)
	check(not raid.request_claim(id, "crate-01", 1), "loot requires an opened reachable container")
	raid.player.global_position = Vector3(9, 0.02, -7.5)
	_aim_at(raid.player, raid.entities["crate-01"].global_position + Vector3.UP * 0.4)
	for frame in range(3): await physics_frame
	check(raid.request_interact(id, "crate-01"), "real camera interaction opens salvage crate")
	check(not raid.request_claim(id, "crate-01", 4), "claim cannot exceed available salvage")
	state.inventory.capacity = 0
	check(not raid.request_claim(id, "crate-01", 1) and raid.containers["crate-01"].count("salvage") == 3, "full pack rejects loot atomically")
	state.inventory.capacity = -1
	check(raid.request_claim(id, "crate-01", 3) and state.inventory.count("salvage") > 0, "salvage looted through authority")
	check(not raid.request_claim(id, "crate-01", 1), "empty container cannot duplicate loot")
	# Grab a stateful gun from a deterministic armory crate, preserving its identity.
	var crate_id := "crate-02"
	raid.player.global_position = raid.entities[crate_id].global_position + Vector3(0, 0.02, 2)
	_aim_at(raid.player, raid.entities[crate_id].global_position + Vector3.UP * 0.4)
	for frame in range(3): await physics_frame
	check(raid.request_interact(id, crate_id), "opens deterministic combat loot")
	var content: RaidInventory = raid.containers[crate_id]
	var gun_index := content.find_uid(content.slots.filter(func(entry): return entry.id == "m_four")[0].uid)
	var identity: String = content.slots[gun_index].state.instance_id
	check(raid.request_transfer(id, crate_id, gun_index) and state.inventory.find_instance(identity) >= 0, "combat loot preserves instance identity")
	# Loaded weapon, installed optic and armor wear must survive an actual extraction.
	state.weapon.data.magazine = {"id": "stanag_magazine", "quantity": 1, "state": ArmoryInstance.fresh("stanag_magazine", catalog.items)}
	state.weapon.data.magazine.state.rounds = 7
	var equipped_instance: String = state.weapon.instance_id
	state.weapon.data.attachments.optic = {"id": "four_x_scope", "quantity": 1, "state": ArmoryInstance.fresh("four_x_scope", catalog.items)}
	state.refresh_armor(catalog)
	state.armor.entries.chestplate.state.wear = 9
	raid.player.global_position = Vector3(-10, 0.02, 11)
	for frame in range(5): await physics_frame
	raid._update_extraction(id, 1)
	check(state.extracting and is_equal_approx(state.extraction_left, 14), "extraction countdown starts")
	raid.player.global_position = Vector3(0, 0.02, 11)
	for frame in range(4): await physics_frame
	raid._update_extraction(id, 1)
	check(not state.extracting and state.extraction_left == 15, "leaving extraction resets countdown")
	raid.player.global_position = Vector3(-10, 0.02, 11)
	for frame in range(4): await physics_frame
	raid._update_extraction(id, 15)
	check(raid.phase == RaidAuthority.Phase.SUCCESS and not app.pending_save, "actual extraction saves result")
	var saved_gun := false
	var saved_armor := false
	for entry in app.profile.profile.stash:
		if entry.id == "m_four" and entry.state.instance_id == equipped_instance:
			saved_gun = entry.state.magazine.state.rounds == 7 and entry.state.attachments.optic.id == "four_x_scope"
		elif entry.id == "patrol":
			saved_armor = entry.state.wear == 9
	check(saved_gun and saved_armor, "extraction persists loaded magazine, optic and armor wear")
	var stash_before: Array = app.profile.profile.stash.duplicate(true)
	app.retry_save()
	check(app.profile.profile.stash == stash_before, "saved extraction cannot be credited twice")
	app.home()
	for frame in range(3): await process_frame
	app.deploy(false)
	for frame in range(3): await physics_frame
	raid = app.raid
	check(raid != null and raid.is_active(), "surviving kit can redeploy")
	raid._apply_damage(raid.player, 1000, null, true)
	check(raid.phase == RaidAuthority.Phase.FAILURE and not app.pending_save, "death ends raid and saves failure")
	var has_rifle := false
	for entry in app.profile.profile.stash:
		if entry.id == "m_four" and entry.state.instance_id == equipped_instance: has_rifle = true
	check(not has_rifle, "death loses deployed gun")
	app.free()
	for frame in range(3): await process_frame

func _physics_regressions() -> void:
	var outcomes: Array[Dictionary] = []
	for fps in [30, 60, 144]:
		var raid: RaidAuthority = load("res://scenes/raid/test_yard.tscn").instantiate()
		root.add_child(raid)
		raid.deploy("fps-player", catalog, SettingsStore.new(), {"practice": true})
		raid.set_physics_process(false)
		raid.player.set_physics_process(false)
		raid.player.set_process(false)
		var state: RaidParticipant = raid.participants["fps-player"]
		state.inventory.slots.clear()
		raid.practice_grant("fps-player", "m_four")
		state.weapon.next_shot = 0
		state.next_shot = 0
		raid.player.move_input = Vector2(0, -1)
		for frame in range(fps * 2):
			raid.request_input("fps-player", true, false)
			raid._physics_process(1.0 / fps)
		outcomes.append({"tick": raid.gameplay_tick, "rounds": state.weapon.magazine, "position": raid.player.global_position})
		raid.free()
	check(outcomes[0] == outcomes[1] and outcomes[1] == outcomes[2], "actual authority + collision movement match at 30/60/144 FPS")
	var raid: RaidAuthority = load("res://scenes/raid/test_yard.tscn").instantiate()
	root.add_child(raid)
	raid.deploy("physics-player", catalog, SettingsStore.new(), {"practice": true})
	raid.set_physics_process(false)
	raid.player.set_physics_process(false)
	for frame in range(4): await physics_frame
	var state: RaidParticipant = raid.participants["physics-player"]
	# Ordinary bullets stop on destructible cover without modifying voxels.
	var walls := raid.find_children("*", "StaticBody3D", true, false)
	for wall in walls:
		if wall is VoxelDestructible:
			var count: int = wall.remaining_cells()
			var start: Vector3 = wall.global_position + Vector3(0, 0, 3)
			var bullet := raid.ballistics.make_bullet(start, Vector3.FORWARD, 8, 0, 18, 2, 1, [])
			check(not raid._step_projectile(bullet) and wall.remaining_cells() == count, "bullets stop on cover without terrain penetration/destruction")
			break
	# Unobstructed exposure exceeds exposure through a solid wall.
	raid.player.global_position = Vector3(10, 0.02, 10)
	for frame in range(3): await physics_frame
	var exposed := raid._exposure(Vector3(10, 1, 7), raid.player)
	check(exposed > 0.9, "open blast exposure")
	# Smoke throw waits ten logical ticks and is cancelled by switching hands.
	state.inventory.slots.clear()
	raid.practice_grant("physics-player", "m_four")
	state.inventory.add("smoke_nade", 2)
	state.grenade_cooldown = 0
	check(raid.request_grenade("physics-player", "smoke_nade"), "smoke pin starts delayed throw")
	for tick in range(9): raid.gameplay_step()
	check(state.inventory.count("smoke_nade") == 2, "smoke not consumed before ten ticks")
	raid.gameplay_step()
	check(state.inventory.count("smoke_nade") == 1, "smoke launches at ten ticks")
	state.grenade_cooldown = 0
	raid.request_grenade("physics-player", "smoke_nade")
	raid.request_select("physics-player", 1)
	for tick in range(10): raid.gameplay_step()
	check(state.inventory.count("smoke_nade") == 1, "changing held item cancels delayed throw")
	# Direct contact produces the exact four source smoke emission times.
	raid.smoke_events.clear()
	var smoke := raid.ballistics.make_bullet(Vector3(10, 0.02, 7), Vector3.FORWARD, 1, 0, 0, 1, 1, [], "smoke")
	raid._smoke_contact(smoke, {"position": Vector3(10, 0.02, 7), "normal": Vector3.UP})
	check(raid.smoke_events.size() == 4 and int(raid.smoke_events[3].tick) - int(raid.smoke_events[0].tick) == 60, "smoke bursts scheduled at 0/20/40/60 ticks")
	# Reload cancellation survives switching away and back during a sniper cycle.
	state.inventory.slots.clear()
	raid.practice_grant("physics-player", "bolt_action_sniper")
	state.next_shot = 0
	state.weapon.next_shot = 0
	raid.request_fire("physics-player")
	var ready: int = state.weapon.next_shot
	var selected_slot := state.selected
	raid.request_select("physics-player", (selected_slot + 1) % 9)
	raid.request_select("physics-player", selected_slot)
	check(state.weapon.next_shot == ready and not raid.request_reload("physics-player"), "sniper cooldown survives held-item switching")

	# Place, fill, power, and recover a mount through validated requests.
	state.inventory.slots.clear()
	raid.practice_grant("physics-player", "mounted_minigun")
	var mount_entry: Dictionary = state.inventory.slots.back()
	check(raid.request_assign("physics-player", 0, mount_entry.state.instance_id), "mount can occupy a quick slot")
	raid.request_select("physics-player", 0)
	raid.player.global_position = Vector3(10, 0.02, 10)
	_aim_at(raid.player, Vector3(10, 0, 8))
	for frame in range(3): await physics_frame
	var mount_count := raid.mounts.size()
	check(raid.request_place("physics-player") and raid.mounts.size() == mount_count + 1, "places mount on aimed-at ground")
	var placed: MountedArmory = raid.mounts.back()
	state.inventory.add("nine_mm", 64)
	check(raid.request_mount_refill("physics-player", placed.entity_id) and placed.ammo == 64, "mount refill conserves ammunition")
	check(raid.request_mount_power("physics-player", placed.entity_id) and placed.powered, "power toggle replaces redstone input")
	check(raid.request_mount_pickup("physics-player", placed.entity_id) and state.inventory.count("mounted_minigun") == 1 and state.inventory.count("nine_mm") == 64, "mount pickup returns gun and ammunition atomically")
	# Original Last Haul vests remain usable; cosmetic Maska adds no protection.
	for armor_id in ArmoryContent.ARMOR_IDS:
		var source: ArmorDef = catalog.definitions[armor_id]
		state.inventory.slots.clear()
		state.armor_slots.clear()
		state.inventory.add(source.id, 1)
		var armor_entry: Dictionary = state.inventory.slots.back()
		check(raid.request_equip_armor("physics-player", armor_entry.state.instance_id) and state.armor.points() == source.points, "equip " + str(source.id))
		check(raid.request_unequip_armor("physics-player", source.slot) and state.armor.points() == 0, "unequip " + str(source.id))
	state.inventory.slots.clear()
	state.inventory.add("maska", 1)
	check(raid.request_equip_armor("physics-player", state.inventory.slots[0].state.instance_id) and state.armor.points() == 0, "Maska remains cosmetic when equipped")
	raid.player.toggle_maska()
	check(raid.player.maska_open and raid.player.maska_view.clips.has("open"), "Maska opening animation comes from the closed model")
	# A physical wall occludes the same blast rays that were previously exposed.
	raid.player.global_position = Vector3(10, 0.02, 10)
	var blocker := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2, 3, 0.5)
	collision.shape = shape
	blocker.add_child(collision)
	raid.add_child(blocker)
	blocker.position = Vector3(10, 1.5, 8.5)
	for frame in range(3): await physics_frame
	check(raid._exposure(Vector3(10, 1, 7), raid.player) < 0.1, "solid cover occludes explosion exposure")
	blocker.queue_free()
	for frame in range(3): await physics_frame
	for wall in raid.find_children("*", "StaticBody3D", true, false):
		if wall is VoxelDestructible:
			var cells: int = wall.remaining_cells()
			wall.blast(wall.global_position + Vector3(0, 0, 0.6), 3)
			check(wall.remaining_cells() < cells, "explosions destroy eligible voxel cells")
			break
	state.health = 20
	raid.projectiles.clear()
	raid.player.global_position = Vector3(10, 6, 10)
	raid.player.movement.velocity = Vector3.ZERO
	raid.player.move_input = Vector2.ZERO
	for tick in range(45): raid.gameplay_step()
	check(raid.player.grounded and state.health < 20 and state.health > 10, "physical fall applies Minecraft fall damage")
	raid.player._set_crouching(true)
	var roof := StaticBody3D.new()
	var roof_collision := CollisionShape3D.new()
	var roof_shape := BoxShape3D.new()
	roof_shape.size = Vector3(0.8, 0.2, 0.8)
	roof_collision.shape = roof_shape
	roof.add_child(roof_collision)
	raid.add_child(roof)
	roof.position = raid.player.global_position + Vector3.UP * 1.7
	for frame in range(3): await physics_frame
	raid.player._set_crouching(false)
	check(raid.player.crouching, "low ceiling blocks standing up")
	roof.queue_free()
	for frame in range(3): await physics_frame
	raid.player._set_crouching(false)
	check(not raid.player.crouching, "standing resumes after headroom clears")
	raid.free()
	for frame in range(3): await process_frame
