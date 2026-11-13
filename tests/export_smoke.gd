extends SceneTree

# Run as an external script against the exported PCK, from any working directory.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var catalog := Catalog.new()
	var error := catalog.load_all()
	if not error.is_empty():
		push_error(error)
		quit(1)
		return
	var app = load("res://scenes/main.tscn").instantiate()
	var directory := OS.get_user_data_dir() + "/export-tests/" + ProfileStore._new_id()
	DirAccess.make_dir_recursive_absolute(directory)
	app.test_profile_path = directory + "/profile.json"
	root.add_child(app)
	app.deploy(true)
	if app.raid == null:
		quit(1)
		return
	if not app.raid.signal_decay.is_active() or app.raid.signal_decay.shader.shader == null or not app.raid.signal_decay.sensor_environment.fog_enabled:
		push_error("Export cannot load sensor shader and haze")
		quit(1)
		return
	if app.raid.signal_decay.shader.get_shader_parameter("pixel_size") != float(app.settings.sensor_pixel_size):
		push_error("Export cannot configure sensor pixelation")
		quit(1)
		return
	var id: String = app.profile.profile.player_id
	for source in ArmoryContent.DATA.data.guns:
		app.raid.participants[id].inventory.slots.clear()
		if not app.raid.practice_grant(id, source.id):
			push_error("Export cannot load " + source.id)
			quit(1)
			return
		await process_frame
		if app.raid.player.hand_rig.get_child_count() != 4 or app.raid.player.hand_rig.profile.weapon_id != source.id or not app.raid.player.hand_rig.intersections().is_empty():
			push_error("Export hand rig/profile failed for " + source.id)
			quit(1)
			return
	print("EXPORTED ARMORY: 12 weapons and mounted practice stations loaded from PCK")
	app.free()
	for frame in range(3):
		await process_frame
	quit(0)
