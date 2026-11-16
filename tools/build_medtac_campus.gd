extends SceneTree

## Authors, splits, bakes and validates the MedTac Research Campus.
## Every lab floor, roof, the distribution building, the skybridge and the
## exterior are saved as separately inspectable scenes under scenes/raid/campus/;
## the playable root instances them and owns the baked navigation.
const OUT := "res://scenes/raid/campus/"
const STAGE := "res://.godot/campus-build/"
const MAP := "res://resources/maps/medtac_campus.tres"
var k

func _initialize() -> void: call_deferred("run")

func write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "\t"))

func run() -> void:
	for dir in [OUT + "lab1", OUT + "lab2", OUT + "distribution", OUT + "distribution_wing", STAGE, "res://resources/campus/reports"]: DirAccess.make_dir_recursive_absolute(dir)
	var started := Time.get_ticks_msec()
	k = load("res://tools/campus/campus_kit.gd").new()
	k.setup()
	var scene: Node3D = k.begin("MedTacCampus", true)
	var exterior = load("res://tools/campus/campus_exterior.gd")
	var distribution = load("res://tools/campus/distribution_plan.gd")
	for plan_path in ["res://tools/campus/lab1_plan.gd", "res://tools/campus/lab2_plan.gd"]:
		var data: Dictionary = load(plan_path).plan()
		var t0 := Time.get_ticks_usec()
		k.build_building(data)
		k.lap("building:" + data.id, t0)
	var t1 := Time.get_ticks_usec()
	k.build_building(distribution.wing())
	distribution.build_hall(k)
	t1 = k.lap("distribution", t1)
	exterior.build(k)
	t1 = k.lap("exterior", t1)
	k.finish()
	t1 = k.lap("finish", t1)
	# Exterior panes are numerous small meshes; cull them with distance.
	for pane in scene.find_children("*", "MedTacBreakable", true, false):
		if pane.get_meta("exterior_pane", false):
			for mesh in pane.find_children("*", "MeshInstance3D", true, false): mesh.visibility_range_end = 70
	write_json("res://resources/campus/reports/decay.json", {"profiles": k.decayer.PROFILES, "decals": k.decayer.decal_count, "windows": k.window_states})
	var timing: Array = []
	for key in k.prof: timing.append([key, k.prof[key] / 1000])
	timing.sort_custom(func(a, b): return a[1] > b[1])
	print("CAMPUS TIMING ms: ", timing.slice(0, 25))
	write_json(STAGE + "timing.json", timing)
	var definition := RaidMapDefinition.new()
	definition.id = "medtac_campus"; definition.display_name = "MedTac Research Campus"
	definition.scene_path = OUT + "medtac_campus.tscn"
	definition.infection_seconds = 1500
	gameplay(scene, definition, exterior)
	scene.set_meta("campus_stairs", k.stair_log)
	scene.set_meta("campus_anchors", {
		"lab1": Vector3(6, .1, -36), "lab2": Vector3(32, .1, 24), "distribution": Vector3(-30, .1, -20), "distribution_wing": Vector3(-30, .1, -20),
		"exterior": Vector3(-6.2, .1, 12.6), "skybridge": Vector3(6, .1, -36)})
	var rooms: Array[Dictionary] = []
	for record: Dictionary in k.room_log:
		var copy := record.duplicate(); copy.erase("node"); rooms.append(copy)
	print("CAMPUS AUTHORED: %d rooms, %d doors, %d storage, %d loose, %d lights in %d ms" % [rooms.size(), k.door_serial, k.source_serial, k.loose_total, k.light_serial, Time.get_ticks_msec() - started])
	split(scene)
	print("CAMPUS BUILD: %d decorative colliders disabled" % MedTacDressing.apply_nonsolid(scene))
	root.add_child(scene)
	scene.set_physics_process(false); scene.get_node("Player").set_physics_process(false)
	var doors: Array[RaidDoor] = []
	for node in scene.find_children("*", "StaticBody3D", true, false):
		if node is RaidDoor: doors.append(node)
	for door in doors:
		if not door.restricted: door.open = true; door.refresh()
	var nav: NavigationRegion3D = scene.get_node("NavigationRegion3D")
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.cell_size = .25; mesh.cell_height = .25; mesh.agent_height = 1.9; mesh.agent_radius = .45; mesh.agent_max_climb = .45
	mesh.agent_max_slope = 40; mesh.region_min_size = 4
	mesh.filter_baking_aabb = AABB(Vector3(-125, -2, -105), Vector3(250, 26, 210))
	nav.navigation_mesh = mesh
	var bake_map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(bake_map, true)
	NavigationServer3D.map_set_use_async_iterations(bake_map, false)
	NavigationServer3D.map_set_cell_size(bake_map, .25); NavigationServer3D.map_set_cell_height(bake_map, .25)
	nav.set_navigation_map(bake_map)
	for node in scene.find_children("*", "NavigationLink3D", true, false): (node as NavigationLink3D).set_navigation_map(bake_map)
	for frame in 3: await physics_frame
	print("CAMPUS BUILD: baking navigation")
	var geometry := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, geometry, nav)
	# Furniture tops are not walkable shelves; project their footprints as obstructions.
	for prop in scene.find_children("*", "Node3D", true, false):
		if not prop.has_meta("bounds") or not prop.has_meta("campus_equipment"): continue
		if prop.get_meta("nonsolid", false) or prop.get_meta("supported_by", "floor") != "floor": continue
		var bounds: AABB = prop.get_meta("bounds")
		if bounds.size.x * bounds.size.z < .01: continue
		bounds = prop.global_transform * bounds
		var corners := PackedVector3Array([Vector3(bounds.position.x, 0, bounds.position.z), Vector3(bounds.end.x, 0, bounds.position.z), Vector3(bounds.end.x, 0, bounds.end.z), Vector3(bounds.position.x, 0, bounds.end.z)])
		geometry.add_projected_obstruction(corners, bounds.position.y, maxf(2.0, bounds.size.y + .3), false)
	NavigationServer3D.bake_from_source_geometry_data(mesh, geometry)
	var baked := nav.navigation_mesh.duplicate(true) as NavigationMesh
	nav.navigation_mesh = null; nav.navigation_mesh = baked
	NavigationServer3D.map_force_update(bake_map)
	for frame in 6: await physics_frame
	# Authored spawn and patrol points snap to the walkable floor of their own storey.
	for npc in scene.get_children():
		if not npc is RaidGuard: continue
		var snapped := NavigationServer3D.map_get_closest_point(bake_map, npc.position)
		if snapped.distance_to(npc.position) < 2.5 and absf(snapped.y - npc.position.y) < .8: npc.position = snapped + Vector3.UP * .05
		var patrol := PackedVector3Array()
		for p in npc.patrol_points:
			var q := NavigationServer3D.map_get_closest_point(bake_map, p)
			patrol.append(q + Vector3.UP * .05 if q.distance_to(p) < 2.5 and absf(q.y - p.y) < .8 else p)
		patrol[0] = npc.position
		npc.patrol_points = patrol
	print("CAMPUS BUILD: %d navigation polygons; validating" % baked.get_polygon_count())
	var report := MedTacCampusValidator.inspect(scene)
	var active := float(definition.active_loose_loot) / maxf(1, k.loose_total)
	var loot := MedTacCampusValidator.loot_report(scene, k.item_defs, active)
	report.navigation_polygons = baked.get_polygon_count()
	report.rooms = rooms.size(); report.doors = k.door_serial; report.storage = k.source_serial; report.loose_sockets = k.loose_total
	report.lights = k.light_serial; report.enemies = definition.enemy_count; report.infected = definition.infected_count
	write_json(STAGE + "validation.json", report)
	write_json("res://resources/campus/reports/validation.json", report)
	write_json("res://resources/campus/reports/loot.json", loot)
	write_json("res://resources/campus/reports/rooms.json", {"rooms": rooms, "areas": k.area_log})
	write_json("res://resources/campus/reports/assets.json", k.usage)
	var encounter_log: Array = []
	for spec: Dictionary in k.encounter_specs: encounter_log.append({"kind": spec.kind, "building": spec.building, "floor": spec.floor, "at": [spec.at.x, spec.at.y, spec.at.z]})
	write_json("res://resources/campus/reports/encounters.json", encounter_log)
	print("CAMPUS LOOT RATIOS: ", loot.lab_floor_ratio)
	if not report.errors.is_empty():
		var shown: Array = report.errors.slice(0, 60)
		for line in shown: printerr("CAMPUS ERROR: ", line)
		push_error("Campus rejected with %d errors (see %svalidation.json)" % [report.errors.size(), STAGE])
		root.remove_child(scene)
		var debug := PackedScene.new()
		if debug.pack(scene) == OK: ResourceSaver.save(debug, STAGE + "rejected.tscn")
		NavigationServer3D.free_rid(bake_map); quit(1); return
	for door in doors: door.open = false; door.refresh()
	for title in ["Player", "SignalDecay"]:
		var node := scene.get_node(title)
		var replacement: Node = load(node.scene_file_path).instantiate()
		var transform: Transform3D = node.transform if node is Node3D else Transform3D.IDENTITY
		scene.remove_child(node); node.free(); k.add(scene, replacement, title)
		if replacement is Node3D: replacement.transform = transform
		if replacement is SignalDecay: replacement.manages_environment = false
	scene.set_meta("campus_report", {"rooms": rooms.size(), "storage": k.source_serial, "loose": k.loose_total, "navigation_polygons": baked.get_polygon_count()})
	root.remove_child(scene)
	var packed := PackedScene.new()
	if packed.pack(scene) != OK or ResourceSaver.save(packed, OUT + "medtac_campus.tscn") != OK:
		push_error("Cannot save campus scene"); quit(1); return
	ResourceSaver.save(definition, MAP)
	scene.free(); NavigationServer3D.free_rid(bake_map)
	print("CAMPUS BUILD COMPLETE in %d ms" % (Time.get_ticks_msec() - started))
	quit()

func split(scene: Node3D) -> void:
	for entry: Dictionary in k.split_scenes:
		var node: Node3D = entry.node
		for child in node.find_children("*", "", true, false):
			if child.owner == scene: child.owner = node
		var packed := PackedScene.new()
		if packed.pack(node) != OK or ResourceSaver.save(packed, entry.path) != OK:
			push_error("Cannot save " + entry.path); continue
		var parent := node.get_parent()
		var index := node.get_index()
		var title := node.name
		var transform := node.transform
		parent.remove_child(node); node.free()
		var instance: Node3D = ResourceLoader.load(entry.path, "", ResourceLoader.CACHE_MODE_REPLACE).instantiate()
		parent.add_child(instance); parent.move_child(instance, index)
		instance.name = title; instance.transform = transform; instance.owner = scene

func gameplay(scene: Node3D, definition: RaidMapDefinition, exterior) -> void:
	scene.set("map_definition", definition)
	var player: RaidPlayer = load("res://scenes/player/player.tscn").instantiate(); k.add(scene, player, "Player")
	var first: Vector2 = exterior.INSERTIONS[0]
	player.position = Vector3(first.x, .05, first.y)
	var sensor: SignalDecay = load("res://scenes/rendering/signal_decay.tscn").instantiate(); sensor.manages_environment = false; k.add(scene, sensor, "SignalDecay")
	var impacts := Node3D.new(); impacts.set_script(preload("res://scripts/combat/impact_presenter.gd")); k.add(scene, impacts, "ImpactPresenter")
	var debris := VoxelDebrisManager.new(); k.add(scene, debris, "VoxelDebris")
	var dressing := MedTacDressing.new(); k.add(scene, dressing, "Dressing")
	var debug_layer := CanvasLayer.new(); debug_layer.layer = 90; k.add(scene, debug_layer, "DeveloperOverlay")
	var overlay := DistrictDebugOverlay.new(); k.add(debug_layer, overlay, "DistrictInspector")
	scene.set_meta("building_ids", ["lab1", "lab2", "distribution", "distribution_wing"])
	scene.set_meta("layout_report", {"seed": "campus", "loops": 0})
	for i in exterior.INSERTIONS.size():
		var p: Vector2 = exterior.INSERTIONS[i]
		var marker := Marker3D.new(); k.add(scene, marker, "Insertion%02d" % i)
		marker.position = Vector3(p.x, .05, p.y); marker.rotation.y = atan2(p.x, p.y)
		marker.add_to_group("raid_spawns", true)
	for i in exterior.EXTRACTS.size():
		var data: Array = exterior.EXTRACTS[i]
		var at: Vector2 = data[2]
		var zone := ExtractionZone.new(); zone.entity_id = "campus-extract-" + data[0]; zone.display_name = data[1]
		zone.collision_layer = 0; zone.collision_mask = 1; zone.position = Vector3(at.x, 0, at.y)
		k.add(scene, zone, "Extraction" if i == 0 else "Extraction%d" % i)
		var collider_node := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size = Vector3(10, 5, 10); collider_node.shape = shape; collider_node.position.y = 2
		k.add(zone, collider_node, "CollisionShape3D")
		var marker: Node3D = k.section("ExtractMarker%d" % i, zone.position)
		k.box(marker, Vector3(0, .045, 0), Vector3(9, .02, 9), "paint", false)
		k.printed_sign(marker, "extract_" + data[0], Vector3(0, 3.2, 0), atan2(-at.x, -at.y), 4.0)
		k.light(marker, Vector3(0, 3.0, 0), true, 10.0)
	# Infected are listed first: the definition's infected count covers indices 0..n-1.
	var specs: Array[Dictionary] = []
	for spec: Dictionary in k.encounter_specs:
		if spec.kind == "infected": specs.append(spec)
	for spec: Dictionary in k.encounter_specs:
		if spec.kind != "infected": specs.append(spec)
	definition.enemy_count = specs.size()
	definition.infected_count = specs.filter(func(s): return s.kind == "infected").size()
	definition.active_loose_loot = int(k.loose_total * .5)
	for i in specs.size():
		var spec: Dictionary = specs[i]
		var npc: RaidGuard = load("res://scenes/npcs/guard.tscn").instantiate()
		npc.entity_id = "campus-%s-%02d" % [spec.kind, i]
		npc.archetype = load("res://resources/npcs/" + ("zombie" if spec.kind == "infected" else "guard") + ".tres")
		npc.material = k.steel; npc.position = spec.at
		npc.patrol_points = PackedVector3Array(spec.patrol)
		npc.set_meta("campus_building", spec.building); npc.set_meta("campus_floor", spec.floor)
		k.add(scene, npc, "Guard" if i == 0 else "Occupant%02d" % i)
