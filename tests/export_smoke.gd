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
	app.raid.request_abandon(id)
	app.home()
	await process_frame
	app.deploy(false)
	var campus: RaidMapDefinition=load("res://resources/maps/medtac_campus.tres")
	if app.raid==null or app.raid.map_definition.id!="medtac_campus" or app.raid.npcs.size()!=campus.enemy_count:
		push_error("Export cannot deploy the MedTac Research Campus with actors")
		quit(1)
		return
	var furnishings:=app.raid.entities.values().filter(func(e): return e is SearchableFurniture).size()
	if app.raid.containers.size()!=furnishings+campus.active_loose_loot or app.raid.get_node_or_null("Atmosphere")==null or app.raid.find_child("Skybridge",true,false)==null:
		push_error("Export is missing campus loot, atmosphere or the skybridge")
		quit(1)
		return
	print("EXPORTED CAMPUS: MedTac Research Campus with %d actors and %d active loot sources" % [app.raid.npcs.size(), app.raid.containers.size()])
	app.raid.request_abandon(id)
	app.home()
	await process_frame
	app.selected_map=load("res://resources/maps/medtac_labs.tres")
	app.deploy(false)
	if app.raid == null or app.raid.map_definition == null or app.raid.npcs.size() != 22 or app.raid.extraction_zones.size() != 4 or app.raid.spawn_markers.size() != 7:
		push_error("Export cannot deploy MedTac Labs")
		quit(1)
		return
	if not app.raid.player.has_node("HumanBody") or not app.raid.containers.has("basement-research-0"):
		push_error("Export cannot load human player and restricted laboratory content")
		quit(1)
		return
	print("EXPORTED MEDTAC: seven insertions, four extracts, 22 enemies and human player loaded from PCK")
	if app.raid.containers.size()!=160 or app.raid.get_node("Dressing")==null:
		push_error("Export cannot assemble detailed loot and raid variations")
		quit(1)
		return
	for slot in app.raid.find_children("*","",true,false):
		if slot is MedTacVariantSlot and (slot.variants.size()!=3 or slot.active==null):
			push_error("Export cannot load a cover arrangement")
			quit(1)
			return
		if slot is Label3D:
			push_error("Export contains floating MedTac text")
			quit(1)
			return
	print("EXPORTED MEDTAC DETAIL: typed loot, 24 cover slots, textured props and physical signs loaded")
	app.raid.request_abandon(id)
	app.home()
	await process_frame
	app.normal_raid_scene = load("res://scenes/raid/veyra_depot.tscn")
	app.deploy(false)
	if app.raid == null or not app.raid.depot or app.raid.npcs.size() != 4 or app.raid.containers["battery-0"].count("infection_suppressant") != 1:
		push_error("Export cannot deploy Veyra Depot")
		quit(1)
		return
	print("EXPORTED DEPOT FIXTURE: four enemies, voxel map, human and supplies loaded from PCK")
	var props: Array = JSON.parse_string(FileAccess.get_file_as_string("res://resources/world_props/catalog.json"))
	if props.size() != 64 or app.raid.get_node("NavigationRegion3D/Decoration").get_child_count() != 24:
		push_error("Export cannot load world prop catalog and depot dressing")
		quit(1)
		return
	for entry: Dictionary in props:
		var prop: Node3D = load(entry.scene).instantiate()
		if prop.get_node("Mesh").mesh == null:
			push_error("Export cannot load " + entry.id)
			prop.free()
			quit(1)
			return
		prop.free()
	print("EXPORTED WORLD PROPS: 64 baked meshes and 24 depot instances loaded from PCK")
	app.free()
	for frame in range(3):
		await process_frame
	quit(0)
