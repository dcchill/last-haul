extends SceneTree

var app: Node
var raid: RaidAuthority
var camera: Camera3D
var captures: Array[Dictionary]=[]
const OUT := "res://.godot/campus-review"

func _initialize() -> void: call_deferred("run")
func capture(title: String,at: Vector3,target: Vector3) -> void:
	camera.global_position=at
	if at.distance_to(target)<.01: target+=Vector3.FORWARD
	camera.look_at(target)
	var atmosphere:=raid.get_node("Atmosphere") as DistrictAtmosphere
	atmosphere.update_left=0
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	var path:=OUT+"/"+title.validate_filename()+".png"
	var error:=root.get_texture().get_image().save_png(path)
	if error!=OK: push_error("Cannot save capture: "+path)
	captures.append({"name":title,"file":path,"eye":[at.x,at.y,at.z],"target":[target.x,target.y,target.z]})

func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("Visual review requires a display"); quit(1); return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	app=load("res://scenes/main.tscn").instantiate()
	app.test_profile_path="res://.godot/campus-review-"+ProfileStore._new_id()+".json"
	app.settings=SettingsStore.new("res://.godot/campus-review-settings.cfg")
	app.requested_layout_seed=19381; app.requested_raid_seed=94731
	root.add_child(app); app.deploy(false)
	raid=app.raid
	if raid==null: push_error("Cannot deploy campus review"); quit(1); return
	raid.set_physics_process(false); raid.player.set_physics_process(false)
	app.ui.visible=false; raid.player.visible=false
	for npc in raid.npcs: npc.set_process(false); npc.set_physics_process(false); npc.visible=false
	for door in raid.entities.values():
		if door is RaidDoor: door.open=true; door.refresh()
	camera=Camera3D.new(); raid.add_child(camera); camera.current=true; camera.fov=78
	DirAccess.make_dir_recursive_absolute(OUT)
	for room in raid.find_children("*","Node3D",true,false):
		if not room.has_meta("room_bounds"): continue
		var bounds: AABB=room.get_meta("room_bounds")
		var title: String=room.get_meta("room_purpose")
		var entrance: Vector3=room.get_meta("entrance_points")[0]
		var direction:=Vector3(entrance.x,0,entrance.z).normalized()
		if direction.length()<.1: direction=Vector3.BACK
		var eye:=entrance-direction; eye.y=1.65
		var reverse:=-direction*minf(bounds.size.x,bounds.size.z)*.35; reverse.y=1.65
		await capture(title+"-entry",room.to_global(eye),room.to_global(Vector3(0,1.3,0)))
		await capture(title+"-reverse",room.to_global(reverse),room.to_global(entrance+Vector3.UP*1.3))
	for area: Dictionary in raid.get_meta("campus_audit"):
		if area.has("building"): continue
		var at:=Vector3(area.at[0],area.at[1],area.at[2])
		var eye:=at+Vector3(3,0,4); var target:=at-Vector3(3,0,4)
		if area.has("eye"):
			eye=Vector3(area.eye[0],area.eye[1],area.eye[2]); target=Vector3(area.target[0],area.target[1],area.target[2])
		await capture(area.name,eye,target)
		if area.has("eye_reverse"):
			await capture(area.name+"-reverse",Vector3(area.eye_reverse[0],area.eye_reverse[1],area.eye_reverse[2]),Vector3(area.target_reverse[0],area.target_reverse[1],area.target_reverse[2]))
	for preset in ["overcast_day","contaminated_dusk","foggy_morning","emergency_night"]:
		var atmosphere:=raid.get_node("Atmosphere") as DistrictAtmosphere
		atmosphere.preset=WorldEnvironmentPreset.make(preset); atmosphere.apply()
		await capture(preset+"-campus",Vector3(62,1.65,66),Vector3(0,2,-10))
	var atmosphere:=raid.get_node("Atmosphere") as DistrictAtmosphere
	atmosphere.preset=WorldEnvironmentPreset.make("overcast_day"); atmosphere.apply()
	raid.signal_decay.enabled=false
	raid.get_node("WorldEnvironment").environment.fog_enabled=false
	raid.get_node("WorldEnvironment").environment.volumetric_fog_enabled=false
	await capture("overview",Vector3(0,260,190),Vector3(0,0,0))
	for node in raid.find_children("*","Node3D",true,false):
		if node.has_meta("campus_roof") or (node.get_meta("campus_slab",false) and float(node.get_meta("surface_y",0))>3): node.visible=false
	await capture("cutaway",Vector3(0,220,130),Vector3(0,0,0))
	var file:=FileAccess.open(OUT+"/capture-index.json",FileAccess.WRITE); file.store_string(JSON.stringify(captures,"\t")); file.close()
	print("CAMPUS REVIEW: %d captures in %s"%[captures.size(),OUT])
	app.free(); quit()
