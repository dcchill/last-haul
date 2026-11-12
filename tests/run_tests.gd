extends SceneTree

var failures: int = 0
var checks: int = 0
var catalog := Catalog.new()
var test_dir := "res://.godot/last_haul_tests/" + ProfileStore._new_id()

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(test_dir)
	check(catalog.load_all().is_empty(), "catalog loads every definition/reference")
	_test_catalog_validation()
	_test_inventory()
	_test_weapon()
	_test_damage()
	_test_persistence()
	_test_settings()
	await _test_raid()
	print("LAST HAUL TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _test_catalog_validation() -> void:
	var rifle: WeaponDef = catalog.definitions.rifle
	var original_id := rifle.id
	rifle.id = "salvage"
	check(not Catalog.new().load_all().is_empty(), "duplicate content IDs rejected")
	rifle.id = original_id
	var ammo := rifle.ammo
	rifle.ammo = null
	check(not Catalog.new().load_all().is_empty(), "missing ammunition reference rejected")
	rifle.ammo = ammo
	var interval := rifle.fire_interval
	rifle.fire_interval = 0
	check(not Catalog.new().load_all().is_empty(), "invalid fire interval rejected")
	rifle.fire_interval = interval

func _test_inventory() -> void:
	var pack := RaidInventory.new(catalog.items, 2)
	check(pack.add("salvage", 19), "add first stack")
	check(pack.add("salvage", 3) and pack.slots.size() == 2 and pack.slots[0].quantity == 20, "stack and spill to next slot")
	check(not pack.add("salvage", 19) and pack.count("salvage") == 22, "capacity rejection is atomic")
	check(not pack.add("unknown", 1) and not pack.add("salvage", -1), "invalid inventory requests")
	var snapshot := pack.snapshot()
	snapshot[0].quantity = 1
	check(pack.count("salvage") == 22, "snapshot does not alias live slots")

func _test_weapon() -> void:
	var weapon := WeaponState.new(catalog.definitions.rifle)
	check(weapon.fire() and weapon.magazine == 11, "fire consumes round")
	check(not weapon.fire(), "fire interval enforced")
	weapon.tick(weapon.definition.fire_interval)
	check(weapon.fire(), "fire after cooldown")
	check(weapon.reload() and not weapon.fire() and not weapon.reload(), "reload blocks fire and duplicate reload")
	weapon.tick(weapon.definition.reload_seconds)
	check(weapon.magazine == 12 and weapon.reserve == 46, "reload conserves ammo")
	weapon.tick(1)
	weapon.fire()
	weapon.reload()
	weapon.cancel_reload()
	weapon.tick(10)
	check(weapon.magazine == 11 and weapon.reserve == 46, "cancelled reload transfers nothing")
	weapon.magazine = 0
	weapon.reserve = 0
	check(not weapon.fire() and not weapon.reload(), "empty weapon cannot shoot/reload")

func _test_damage() -> void:
	var ballistics := Ballistics.new()
	check(is_equal_approx(ballistics.damage(30, catalog.definitions.steel, catalog.definitions.vest), 24), "armor reduction")
	check(is_equal_approx(ballistics.damage(30, catalog.definitions.concrete, null), 24), "material response")
	check(ballistics.damage(-10, null, null) == 0, "damage cannot heal")

func _result(id: String, success: bool = true) -> Dictionary:
	return {"raid_id": id, "success": success, "reason": "test"}

func _test_persistence() -> void:
	var path := test_dir + "/profile.json"
	var store := ProfileStore.new(catalog, path)
	check(store.load_profile() and store.save_profile(), "new profile saves")
	var player_id: String = store.profile.player_id
	var loot: Array[Dictionary] = [{"id": "salvage", "quantity": 3}]
	check(store.commit_result(_result("raid-a"), loot), "commit extraction")
	check(store.commit_result(_result("raid-a"), loot) and store.profile.stash[0].quantity == 3, "duplicate raid does not credit twice")
	var reloaded := ProfileStore.new(catalog, path)
	check(reloaded.load_profile() and reloaded.profile.player_id == player_id and reloaded.profile.stash[0].quantity == 3, "fresh store reloads stash and player identity")
	check(reloaded.commit_result(_result("raid-a"), loot) and reloaded.profile.stash[0].quantity == 3, "duplicate raid rejected after reload")
	check(reloaded.commit_result(_result("raid-b", false), loot) and reloaded.profile.stash[0].quantity == 3, "failure credits no loot")
	var invalid := reloaded.profile.duplicate(true)
	invalid.stash[0].quantity = -1
	check(not store.valid(invalid), "negative saved quantities rejected")
	invalid.stash[0].quantity = 1.5
	check(not store.valid(invalid), "fractional saved quantities rejected")
	invalid.stash[0] = {"id": "missing", "quantity": 1}
	check(not store.valid(invalid) and not store.valid({}), "unknown saved IDs and missing schema rejected")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	check(reloaded.load_profile() and reloaded.profile.stash[0].quantity == 3, "recover from validated backup")
	check(FileAccess.get_file_as_string(path) == "{broken", "corrupt main preserved during recovery")
	check(reloaded.save_profile(), "recovered profile can save")
	var bad_path := test_dir + "/broken.json"
	file = FileAccess.open(bad_path, FileAccess.WRITE)
	file.store_string("broken")
	file.close()
	var bad := ProfileStore.new(catalog, bad_path)
	check(not bad.load_profile() and not bad.writable and not bad.save_profile(), "unrecoverable save blocks destructive overwrite")
	var blocked := ProfileStore.new(catalog, test_dir + "/missing/never.json")
	check(not blocked.commit_result(_result("retry"), loot) and blocked.profile.stash.is_empty(), "failed write leaves in-memory stash untouched")
	blocked.path = test_dir + "/retry.json"
	check(blocked.commit_result(_result("retry"), loot) and blocked.profile.stash[0].quantity == 3, "failed result can be retried")
	check(blocked.commit_result(_result("retry"), loot) and blocked.profile.stash[0].quantity == 3, "retry is idempotent")

func _test_settings() -> void:
	var settings := SettingsStore.new(test_dir + "/settings.cfg")
	settings.sensitivity = 0.003
	settings.volume = 0.4
	settings.fullscreen = true
	check(settings.save_settings() == OK, "settings save")
	var reload_settings := SettingsStore.new(settings.path)
	reload_settings.load_settings()
	check(is_equal_approx(reload_settings.sensitivity, 0.003) and is_equal_approx(reload_settings.volume, 0.4) and reload_settings.fullscreen, "settings round trip")

func _yard() -> RaidAuthority:
	var yard: RaidAuthority = load("res://scenes/raid/test_yard.tscn").instantiate()
	root.add_child(yard)
	check(yard.deploy("test-player", catalog, SettingsStore.new()).is_empty(), "deploy and unique entity IDs")
	yard.set_physics_process(false)
	yard.player.set_physics_process(false)
	return yard

func _settle() -> void:
	for frame in range(5):
		await physics_frame
	await process_frame

func _test_raid() -> void:
	var yard := _yard()
	await _settle()
	check(yard.entities.size() == 7 and yard.is_active(), "raid registers player, guard, crate, extraction, targets")
	check(yard.get_node("NavigationRegion3D").navigation_mesh.get_polygon_count() > 0, "yard navigation is baked")
	var path := NavigationServer3D.map_get_path(yard.guard.navigation.get_navigation_map(), Vector3(4, 0, -8), Vector3(4, 0, 0), true)
	check(path.size() >= 3, "navigation routes around cover")
	check(not yard.request_fire("stranger") and not yard.request_reload("stranger") and not yard.request_extract("stranger"), "authority rejects other player")
	check(not yard.request_claim("test-player", "crate-01", 1), "claim requires open container and proximity")
	move_to_crate(yard)
	await _settle()
	check(yard.request_interact("test-player", "crate-01"), "open reachable crate via camera ray")
	check(not yard.request_claim("test-player", "crate-01", 4), "claim exceeds available loot")
	yard.participants["test-player"].inventory.capacity = 0
	check(not yard.request_claim("test-player", "crate-01", 1) and yard.entities["crate-01"].remaining == 3, "full pack does not consume container loot")
	yard.participants["test-player"].inventory.capacity = 8
	check(yard.request_claim("test-player", "crate-01", 3) and yard.objective_complete("test-player"), "claim completes objective")
	check(not yard.request_claim("test-player", "crate-01", 1) and yard.participants["test-player"].inventory.count("salvage") == 3, "repeat claim rejected without duplication")
	move_to_crate(yard)
	move_player(yard, Vector3(0, 0.1, 13))
	await _settle()
	check(not yard.request_claim("test-player", "crate-01", 1), "distant claim rejected")
	# Resolve a real physics ray against a target through the authority.
	move_player(yard, Vector3(-10, 0.1, -10))
	yard.player.camera.look_at(Vector3(-10, 1.1, -15))
	await _settle()
	check(yard.request_fire("test-player") and yard.entities["target-0"].health < 100, "authority hitscan damages target")
	check(not yard.request_fire("test-player"), "authority fire cooldown")
	# Sight is tested with and without a serialized cover block between the actors.
	move_player(yard, Vector3(7, 0.1, 0))
	yard.guard.global_position = Vector3(7, 0.1, -7)
	yard.guard.rotation.y = PI
	await _settle()
	check(yard.guard.can_see(yard.player, yard.ballistics), "guard sees player in FOV")
	move_player(yard, Vector3(4, 0.1, 0))
	yard.guard.global_position = Vector3(4, 0.1, -8)
	await _settle()
	check(not yard.guard.can_see(yard.player, yard.ballistics), "cover blocks perception")
	var guard_start := yard.guard.global_position
	yard.guard.hear(yard.player.global_position)
	for frame in range(90):
		yard.guard.authority_tick(1.0 / 60.0, yard.player, yard.ballistics)
		await physics_frame
	check(yard.guard.global_position.distance_to(guard_start) > 2.0, "guard follows baked navigation around cover")
	print("GUARD DEBUG ", guard_start, " -> ", yard.guard.global_position, " state=", yard.guard.state, " path=", yard.guard.navigation.get_current_navigation_path())
	yard.guard.state = RaidGuard.State.IDLE
	yard.guard.hear(yard.guard.global_position + Vector3(0, 0, 3))
	check(yard.guard.state == RaidGuard.State.INVESTIGATE, "nearby gunshot investigated")
	yard.guard.state = RaidGuard.State.IDLE
	yard.guard.hear(Vector3(1000, 0, 0))
	check(yard.guard.state == RaidGuard.State.IDLE, "distant gunshot ignored")
	move_player(yard, Vector3(7, 0.1, 0))
	yard.guard.global_position = Vector3(7, 0.1, -7)
	yard.guard.rotation.y = PI
	yard.guard.attack_left = 0
	await _settle()
	check(yard.guard.authority_tick(0.016, yard.player, yard.ballistics), "guard attack")
	check(not yard.guard.authority_tick(0.016, yard.player, yard.ballistics), "guard attack cooldown")
	yard._apply_damage(yard.guard, 1000, catalog.definitions.steel)
	check(yard.guard.state == RaidGuard.State.DEAD and not yard.guard.authority_tick(5, yard.player, yard.ballistics), "dead guard stops decisions")
	move_player(yard, Vector3(-10, 0.1, 11))
	await _settle()
	yard._update_extraction("test-player", 1.0)
	check(yard.participants["test-player"].extracting and is_equal_approx(yard.participants["test-player"].extraction_left, 2), "extraction countdown")
	move_player(yard, Vector3(0, 0.1, 11))
	await _settle()
	yard._update_extraction("test-player", 0.5)
	check(not yard.participants["test-player"].extracting and yard.participants["test-player"].extraction_left == 3, "leaving extraction resets countdown")
	move_player(yard, Vector3(-10, 0.1, 11))
	await _settle()
	yard._update_extraction("test-player", 3)
	check(yard.phase == RaidAuthority.Phase.SUCCESS and yard.result.success, "complete deploy fight loot extract loop")
	check(not yard.request_fire("test-player") and not yard.request_claim("test-player", "crate-01", 1), "finished raid rejects gameplay")
	yard.free()
	var invalid_yard: RaidAuthority = load("res://scenes/raid/test_yard.tscn").instantiate()
	root.add_child(invalid_yard)
	invalid_yard.get_node("Guard").entity_id = "test-player"
	check(not invalid_yard.deploy("test-player", catalog, SettingsStore.new()).is_empty(), "duplicate entity IDs block deployment")
	invalid_yard.free()
	yard = _yard()
	await _settle()
	check(yard.participants["test-player"].inventory.slots.is_empty() and yard.participants["test-player"].weapon.magazine == 12, "second raid has fresh kit and no carried loot")
	move_player(yard, Vector3(-10, 0.1, 11))
	await _settle()
	yard._update_extraction("test-player", 5)
	check(yard.is_active(), "objective required before extraction")
	yard.participants["test-player"].weapon.magazine = 1
	yard.request_reload("test-player")
	yard.request_abandon("test-player")
	check(yard.phase == RaidAuthority.Phase.FAILURE and yard.participants["test-player"].weapon.reload_left == 0, "abandon fails raid and cancels reload")
	yard.free()
	yard = _yard()
	move_player(yard, Vector3(7, 0.1, 0))
	yard.guard.rotation.y = PI
	yard.participants["test-player"].health = 1
	await _settle()
	yard._physics_process(0.016)
	check(yard.phase == RaidAuthority.Phase.FAILURE and yard.participants["test-player"].health == 0, "NPC damage causes raid failure")
	yard.free()

func move_player(yard: RaidAuthority, position: Vector3) -> void:
	yard.player.global_position = position
	yard.player.velocity = Vector3.ZERO

func move_to_crate(yard: RaidAuthority) -> void:
	move_player(yard, Vector3(9, 0.1, -7.5))
	yard.player.camera.look_at(Vector3(9, 0.5, -10))
