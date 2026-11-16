extends SceneTree

## MedTac Research Campus integration test. Deploys the real map through the
## application, validates the physical layout, walks every stair flight and the
## skybridge with the player body, and checks floor loot progression.
var checks := 0
var failures := 0
var app: Node
var raid: RaidAuthority
var actor_id: String

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: " + label)

func settle(frames := 3) -> void:
	for frame in frames: await physics_frame

func walk_line(destination: Vector3, max_ticks := 900) -> bool:
	var actor := raid.player
	actor.movement.velocity = Vector3.ZERO
	for tick in max_ticks:
		var offset := destination - actor.global_position
		if Vector2(offset.x, offset.z).length() < .45 and absf(offset.y) < .7: return true
		actor.rotation.y = atan2(-offset.x, -offset.z)
		actor.drive_movement(Vector2(0, -1), false, false, .05)
		if tick % 10 == 0: await physics_frame
	return false

func walk(points: Array) -> bool:
	raid.player.global_position = points[0]; raid.player.previous_position = points[0]
	await settle()
	for i in range(1, points.size()):
		if not await walk_line(points[i]): return false
	return true

func deploy(seed_value: int) -> void:
	app.requested_raid_seed = seed_value
	app.deploy(false); await settle(6)
	raid = app.raid

func snapshot() -> Dictionary:
	var result := {}
	for id: String in raid.containers:
		var contents: RaidInventory = raid.containers[id]
		var items: Array = []
		for entry in contents.slots: items.append([entry.id, entry.quantity])
		result[id] = items
	return result

func run() -> void:
	var definition: RaidMapDefinition = load("res://resources/maps/medtac_campus.tres")
	check(definition != null and definition.validation_error().is_empty(), "campus map definition is valid")
	app = load("res://scenes/main.tscn").instantiate()
	app.test_profile_path = "res://.godot/campus-test-" + ProfileStore._new_id() + ".json"
	app.settings = SettingsStore.new("res://.godot/campus-isolated-settings.cfg")
	root.add_child(app)
	actor_id = app.profile.profile.player_id
	check(app.selected_map.id == "medtac_campus", "normal deployment selects the MedTac Research Campus")
	await deploy(94731)
	check(raid != null, "campus deploys")
	if raid == null:
		print("MEDTAC CAMPUS TESTS: %d checks, %d failures" % [checks, failures]); quit(1); return
	raid.set_physics_process(false); raid.player.set_physics_process(false)
	for npc in raid.npcs: npc.state = RaidGuard.State.DEAD
	var state: RaidParticipant = raid.participants[actor_id]
	var furnishings := raid.entities.values().filter(func(e): return e is SearchableFurniture).size()
	var sockets := raid.entities.values().filter(func(e): return e is RaidLootPickup).size()
	check(raid.npcs.size() == definition.enemy_count and raid.npcs.filter(func(n): return n.archetype.melee).size() == definition.infected_count, "encounter budget matches the map definition")
	check(raid.containers.size() == furnishings + definition.active_loose_loot, "all furnishings plus exactly the active loose sockets are stocked")
	check(definition.active_loose_loot * 2 <= sockets + 1, "half the loose sockets are active per raid")
	check(state.infection_capacity == 1500 and state.assigned_extracts.size() == 2, "25 minute infection and two assigned exits")
	check(raid.spawn_markers.size() == 7 and raid.extraction_zones.size() == 4, "seven insertions and four extracts")
	# Every lab floor is its own saved scene, instanced by the playable root.
	for building in ["lab1", "lab2"]:
		var node := raid.get_node("NavigationRegion3D/Building_" + building)
		for level in range(1, 5):
			var path := "res://scenes/raid/campus/%s/floor_%d.tscn" % [building, level]
			var instance := node.get_node_or_null("Floor%d" % level)
			check(instance != null and instance.scene_file_path == path, "%s floor %d is an inspectable scene" % [building, level])
			var count := MedTacCampusValidator.rooms(instance).size() if instance != null else 0
			check(count >= 12, "%s floor %d has a full room programme (%d rooms)" % [building, level, count])
		check(node.get_node_or_null("Roof") != null, building + " has a roof level")
	var titles: Dictionary = {}
	for room in MedTacCampusValidator.rooms(raid):
		var key := "%s/%d" % [room.get_meta("campus_building"), room.get_meta("campus_floor")]
		if not titles.has(key): titles[key] = []
		titles[key].append(room.get_meta("room_role"))
	for building in ["lab1", "lab2"]:
		for level in range(2, 5):
			check(titles["%s/%d" % [building, level]] != titles["%s/%d" % [building, level - 1]], "%s floor %d is not a copy of floor %d" % [building, level, level - 1])
	# Stair cores line up storey to storey.
	var stairs: Array = raid.get_meta("campus_stairs")
	var cores: Dictionary = {}
	for stair: Dictionary in stairs:
		var key: String = stair.building + "/" + stair.core
		var plan := Vector2(stair.points[0].x, stair.points[0].z)
		if cores.has(key): check(plan.distance_to(cores[key]) < .01, key + " landing is vertically aligned at level %d" % stair.from)
		cores[key] = plan
	for key in ["lab1/StairA", "lab1/StairB", "lab2/StairWest", "lab2/StairEast"]:
		var flights := stairs.filter(func(s): return s.building + "/" + s.core == key).size()
		check(flights == (4 if key.ends_with("B") or key.ends_with("East") else 3), key + " connects every storey")
	for door in raid.entities.values():
		if door is RaidDoor and not door.restricted: door.open = true; door.refresh()
	await settle()
	var report := MedTacCampusValidator.inspect(raid)
	for line in report.errors.slice(0, 25): print("  validator: ", line)
	check(report.errors.is_empty(), "physical campus validation (%d rooms, %d errors)" % [report.rooms_checked, report.errors.size()])
	for stair: Dictionary in stairs:
		var label := "%s %s level %d to %d" % [stair.building, stair.core, stair.from, stair.to]
		check(await walk(stair.points), "player climbs " + label)
		var down: Array = stair.points.duplicate(); down.reverse()
		check(await walk(down), "player descends " + label)
	var nav: NavigationRegion3D = raid.get_node("NavigationRegion3D")
	var bridge := raid.find_child("Skybridge", true, false) as Node3D
	var ends := [bridge.to_global(Vector3(0, .1, -20)), bridge.to_global(Vector3(0, .1, 20))]
	var route := RaidNavigation.path(nav.get_navigation_map(), ends[0], ends[1])
	check(not route.is_empty() and await walk(Array(route)), "player crosses the skybridge between floor three of both labs")
	check(raid.player.global_position.distance_to(ends[1]) < 1.2 and absf(raid.player.global_position.y - 8.45) < .5, "skybridge arrives on Lab 2 floor three")
	# Loot rises with height without inflating item values.
	var loot := MedTacCampusValidator.loot_report(raid, app.catalog.items, float(definition.active_loose_loot) / maxf(1, sockets))
	var config := CampusLoot.config()
	var previous := 0.0
	for level in range(1, 5):
		var ratio: float = loot.lab_floor_ratio[str(level)]
		var target := float(config.targets[str(level)])
		check(ratio > previous, "lab floor %d expected value rises (%.2fx)" % [level, ratio])
		check(absf(ratio - target) <= target * float(config.tolerance), "lab floor %d expected value %.2fx is within tolerance of %.1fx" % [level, ratio, target])
		previous = ratio
	print("  loot ratios: ", loot.lab_floor_ratio, " values: ", loot.lab_floor_value)
	for entity in raid.entities.values():
		if entity is RaidLootPickup:
			check(app.catalog.items[entity.item_id].rarity in ["common", "uncommon"], "rare items never lie loose: " + entity.entity_id)
	var locked := raid.entities.values().filter(func(e): return e is SearchableFurniture and e.locked)
	check(locked.size() >= 6 and locked.all(func(e): return int(e.get_meta("loot_tier", 1)) >= 3), "keycard-locked storage exists only on floors three and four")
	check(raid.entities.values().filter(func(e): return e is RaidEntity and e.keycard_candidate).size() >= 3, "keycard candidates exist in accessible security storage")
	# Real interaction through the authority.
	var storage: SearchableFurniture
	for entity in raid.entities.values():
		if entity is SearchableFurniture and not entity.locked and not entity.starts_empty and entity.get_meta("campus_building", "") == "lab1": storage = entity; break
	var front := storage.global_position + storage.global_basis * (Vector3(0, 0, -1.3) if storage.container_config != null else Vector3(0, 0, 1.3))
	raid.player.global_position = front + Vector3.UP * .05; raid.player.previous_position = raid.player.global_position
	var aim := storage.to_global(storage.interaction_offset) - raid.player.eye_position()
	raid.player.rotation.y = atan2(-aim.x, -aim.z); raid.player.look_pitch = atan2(aim.y, Vector2(aim.x, aim.z).length()); raid.player.camera.rotation.x = raid.player.look_pitch
	await settle()
	check(raid.request_interact(actor_id, storage.entity_id), "real camera interaction opens campus storage")
	var first := snapshot()
	var exit: ExtractionZone = raid.extraction_zones.filter(func(z): return z.entity_id in state.assigned_extracts)[0]
	raid.player.global_position = exit.global_position; raid.player.previous_position = exit.global_position
	await settle()
	raid._update_extraction(actor_id, 14)
	check(raid.is_active(), "extraction still needs 15 continuous seconds")
	raid._update_extraction(actor_id, 1)
	check(raid.result.get("success", false), "campus extraction succeeds")
	app.home(); await settle()
	await deploy(94731)
	check(raid != null and snapshot() == first, "a raid seed reproduces campus loot")
	if raid != null: raid.request_abandon(actor_id); app.home(); await settle()
	app.free()
	await settle()
	print("MEDTAC CAMPUS TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
