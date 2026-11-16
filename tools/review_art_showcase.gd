extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("Rendered showcase review requires a display"); quit(1); return
	var scene: Node3D=load("res://scenes/review/art_direction_showcase.tscn").instantiate()
	root.add_child(scene)
	var camera: Camera3D=scene.get_node("ReviewCamera")
	var atmosphere: DistrictAtmosphere=scene.get_node("Atmosphere")
	var sensor: SignalDecay=load("res://scenes/rendering/signal_decay.tscn").instantiate()
	sensor.manages_environment=false; scene.add_child(sensor)
	var views: Dictionary={"street":[Vector3(-21,1.7,6),Vector3(-16,1,-8)],"medical":[Vector3(3,1.7,-10),Vector3(0,1.4,-19)],"industrial":[Vector3(8,2,22),Vector3(16,1.8,10)],"contamination":[Vector3(-4,1.8,29),Vector3(0,1,22)],"overview":[Vector3(-40,35,45),Vector3(0,0,0)]}
	var directory:="res://.godot/art-showcase"
	DirAccess.make_dir_recursive_absolute(directory)
	for preset in ["overcast_day","contaminated_dusk","foggy_morning","emergency_night"]:
		atmosphere.preset=WorldEnvironmentPreset.make(preset); atmosphere.contamination_stage=3; atmosphere.apply()
		for identity: String in views:
			camera.position=views[identity][0]; camera.look_at(views[identity][1])
			for treatment in [false,true]:
				sensor.enabled=treatment
				atmosphere.update_left=0
				for frame in 5: await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(directory+"/"+preset+"-"+identity+("-retro" if treatment else "-clear")+".png")
	scene.free()
	print("ART SHOWCASE REVIEW: 40 captures; inspect images before district build")
	quit()
