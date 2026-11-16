extends SceneTree

var app: Node
var raid: RaidAuthority
var capture_dir:="res://.godot/district-review"

func _initialize() -> void: call_deferred("run")

func settle(frames := 8) -> void:
	for frame in frames: await process_frame
	await RenderingServer.frame_post_draw

func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("District visual review needs a display"); quit(1); return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	app=load("res://scenes/main.tscn").instantiate()
	app.test_profile_path="res://.godot/district-review-"+ProfileStore._new_id()+".json"
	app.settings=SettingsStore.new("res://.godot/district-review-settings.cfg")
	app.normal_raid_scene=load("res://scenes/raid/district/district_19381.tscn")
	root.add_child(app); app.deploy(false)
	raid=app.raid
	if raid==null: push_error("Cannot review district deployment"); quit(1); return
	raid.set_physics_process(false); raid.player.set_physics_process(false)
	for npc in raid.npcs: npc.set_process(false)
	var camera:=Camera3D.new(); raid.add_child(camera); camera.current=true; camera.fov=72
	var atmosphere:=raid.get_node("Atmosphere") as DistrictAtmosphere
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var points: Array=raid.get_meta("layout_report").pois
	for preset in ["overcast_day","contaminated_dusk","foggy_morning","emergency_night"]:
		atmosphere.preset=WorldEnvironmentPreset.make(preset); atmosphere.apply()
		for poi: Dictionary in points:
			camera.position=Vector3(poi.x+2,2.2,poi.z+29); camera.look_at(Vector3(poi.x-10,1.6,poi.z-4))
			atmosphere.update_left=0
			await settle()
			root.get_texture().get_image().save_png(capture_dir+"/"+preset+"-"+poi.id+".png")
	# Include an eye-level clinical interior and a roof approach separately.
	var research: Dictionary=points[0]
	for view in ["clinical","roof","overview"]:
		atmosphere.preset=WorldEnvironmentPreset.make("overcast_day"); atmosphere.apply()
		if view=="clinical": camera.position=Vector3(research.x-19,1.65,research.z-2); camera.look_at(Vector3(research.x-22,1.3,research.z-7))
		elif view=="roof": camera.position=Vector3(research.x-10,4.8,research.z-1); camera.look_at(Vector3(research.x-20,4,research.z-7))
		else:
			camera.position=Vector3(0,320,120); camera.look_at(Vector3.ZERO)
			raid.signal_decay.enabled=false
			raid.get_node("WorldEnvironment").environment.fog_enabled=false
			raid.get_node("WorldEnvironment").environment.volumetric_fog_enabled=false
		atmosphere.update_left=0; await settle()
		root.get_texture().get_image().save_png(capture_dir+"/"+view+".png")
	# High local fog and rain are independent visual settings, not new geometry.
	raid.signal_decay.enabled=true
	for mode in ["rain","high_contamination"]:
		atmosphere.preset=WorldEnvironmentPreset.make("overcast_day")
		atmosphere.quality=WorldQualitySettings.make(2 if mode=="high_contamination" else 1)
		atmosphere.contamination_stage=3
		if mode=="rain":
			atmosphere.preset.rain=1; atmosphere.preset.wetness=1
			camera.position=Vector3(research.x,1.7,research.z+12); camera.look_at(Vector3(research.x-10,1.5,research.z-5))
		else:
			camera.position=Vector3(research.x-27,1.7,research.z-24); camera.look_at(Vector3(research.x-20,.7,research.z-18))
		atmosphere.apply(); atmosphere.update_left=0; await settle(15)
		root.get_texture().get_image().save_png(capture_dir+"/"+mode+".png")
	var inspector: DistrictDebugOverlay=raid.get_node("DeveloperOverlay/DistrictInspector")
	inspector.visible=true; await settle()
	root.get_texture().get_image().save_png(capture_dir+"/inspector.png")
	print("DISTRICT REVIEW: 34 in-engine captures at ",root.size)
	app.free(); quit()
