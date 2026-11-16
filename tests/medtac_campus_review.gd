extends SceneTree

## Rendered review of the MedTac Research Campus: one orthographic cutaway per
## floor (floors above, roofs and ceilings hidden), a site plan, an entry view
## of every room and views of the major exterior areas. Requires a display.
const OUT := "res://.godot/medtac-campus-review"
const DOCS := "res://docs/medtac-campus"
var app: Node
var raid: RaidAuthority
var camera: Camera3D
var captures: Array[Dictionary] = []

func _initialize() -> void: call_deferred("run")

func capture(title: String, frames := 5, docs := false) -> void:
	for frame in frames: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := OUT + "/" + title.validate_filename() + ".png"
	if image.save_png(path) != OK: push_error("Cannot save capture: " + path)
	if docs:
		var small := image.duplicate() as Image
		small.resize(1280, int(1280.0 * image.get_height() / image.get_width()), Image.INTERPOLATE_BILINEAR)
		small.save_png(DOCS + "/" + title.validate_filename() + ".png")
	captures.append({"name": title, "file": path, "eye": [camera.global_position.x, camera.global_position.y, camera.global_position.z]})

func perspective(title: String, eye: Vector3, target: Vector3, docs := false) -> void:
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE; camera.fov = 78
	camera.global_position = eye
	if eye.distance_to(target) < .01: target += Vector3.FORWARD
	camera.look_at(target, Vector3.UP if absf((target - eye).normalized().y) < .99 else Vector3.FORWARD)
	await capture(title, 5, docs)

func plan_view(title: String, center: Vector3, size: float) -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = size
	camera.global_position = center + Vector3.UP * 60
	camera.look_at(center, Vector3.FORWARD)
	await capture(title, 6, true)

func set_visible_levels(building: Node3D, level: int) -> void:
	for child in building.get_children():
		if not child is Node3D: continue
		if child.name.begins_with("Floor"):
			var index := int(str(child.name).trim_prefix("Floor"))
			child.visible = index <= level
			for ceiling in child.find_children("Ceiling", "Node3D", true, false): ceiling.visible = index != level
		elif child.name == "Roof": child.visible = level > 4

func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("Visual review requires a display"); quit(1); return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(OUT); DirAccess.make_dir_recursive_absolute(DOCS)
	app = load("res://scenes/main.tscn").instantiate()
	app.test_profile_path = "res://.godot/campus-review-" + ProfileStore._new_id() + ".json"
	app.settings = SettingsStore.new("res://.godot/campus-review-settings.cfg")
	app.requested_raid_seed = 94731
	root.add_child(app); app.deploy(false)
	raid = app.raid
	if raid == null: push_error("Cannot deploy campus review"); quit(1); return
	raid.set_physics_process(false); raid.player.set_physics_process(false)
	app.ui.visible = false; raid.player.visible = false
	for npc in raid.npcs: npc.set_process(false); npc.set_physics_process(false); npc.visible = false
	for door in raid.entities.values():
		if door is RaidDoor: door.open = true; door.refresh()
	camera = Camera3D.new(); raid.add_child(camera); camera.current = true; camera.far = 600
	var atmosphere := raid.get_node("Atmosphere") as DistrictAtmosphere
	atmosphere.preset = WorldEnvironmentPreset.make("overcast_day"); atmosphere.apply()
	raid.signal_decay.enabled = false
	var environment: Environment = raid.get_node("WorldEnvironment").environment
	environment.fog_enabled = false; environment.volumetric_fog_enabled = false
	await plan_view("site_plan", Vector3(0, 0, 0), 250)
	var nav := raid.get_node("NavigationRegion3D")
	for id in ["lab1", "lab2", "distribution_wing"]:
		var building := nav.get_node("Building_" + id) as Node3D
		var bounds: AABB = building.global_transform * (building.get_meta("building_bounds") as AABB)
		var levels := building.get_children().filter(func(n): return str(n.name).begins_with("Floor")).size()
		for level in range(1, levels + 1):
			set_visible_levels(building, level)
			await plan_view("%s_floor_%d" % [id, level], bounds.get_center() * Vector3(1, 0, 1) + Vector3.UP * (level - 1) * 4.2, maxf(bounds.size.x, bounds.size.z) * 1.05)
		set_visible_levels(building, 99)
	var hall := nav.get_node("Building_distribution") as Node3D
	hall.find_child("HallRoof", true, false).visible = false
	await plan_view("distribution_hall", Vector3(-52, 0, -47), 84)
	hall.find_child("HallRoof", true, false).visible = true
	for room in MedTacCampusValidator.rooms(raid):
		var bounds: AABB = room.get_meta("room_bounds")
		var title := "%s_%d_%s" % [room.get_meta("campus_building"), room.get_meta("campus_floor"), room.get_meta("room_purpose")]
		var entrance: Vector3 = room.get_meta("entrance_points")[0]
		var inward := -Vector3(entrance.x, 0, entrance.z).normalized()
		var eye := entrance + inward * .4 + Vector3.UP * 1.65
		await perspective(title, room.to_global(eye), room.to_global(Vector3(-entrance.x * .6, 1.2, -entrance.z * .6)))
	for view in [
		["skybridge_interior", Vector3(47.5, 10.05, -1), Vector3(47.5, 9.6, 28)],
		["skybridge_from_road", Vector3(30, 1.7, 12.6), Vector3(47.5, 8, 13)],
		["western_blockade", Vector3(-80, 1.7, 13), Vector3(-53.6, 1.2, 12.6)],
		["parking_lot", Vector3(-15, 3, 70), Vector3(-60, 0, 40)],
		["truck_yard", Vector3(-10, 3, 6), Vector3(-35, 1.5, -22)],
		["lab1_forecourt", Vector3(-4, 1.7, -45), Vector3(11.5, 4, -36)],
		["lab2_ambulance_bay", Vector3(-4, 1.7, 30), Vector3(5.5, 2, 38.5)],
		["lab1_atrium_garden", Vector3(42, 1.7, -45), Vector3(52, 1.5, -36)],
		["lab1_atrium_from_level_four", Vector3(42, 14.5, -45), Vector3(52, 0, -36)],
		["distribution_aisles", Vector3(-20, 1.7, -40), Vector3(-80, 2, -48)],
		["lab1_roof", Vector3(90, 18.5, -66), Vector3(50, 16.8, -36)],
		["campus_overview", Vector3(-60, 70, 110), Vector3(10, 0, -10)],
	]:
		await perspective(view[0], view[1], view[2], true)
	for preset in ["contaminated_dusk", "foggy_morning", "emergency_night"]:
		atmosphere.preset = WorldEnvironmentPreset.make(preset); atmosphere.apply()
		environment = raid.get_node("WorldEnvironment").environment
		await perspective(preset + "_campus", Vector3(30, 1.7, 22), Vector3(47.5, 6, -10), true)
	var file := FileAccess.open(OUT + "/capture-index.json", FileAccess.WRITE); file.store_string(JSON.stringify(captures, "\t")); file.close()
	print("MEDTAC CAMPUS REVIEW: %d captures in %s" % [captures.size(), OUT])
	app.free(); quit()
