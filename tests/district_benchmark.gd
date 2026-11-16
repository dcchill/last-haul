extends SceneTree

## Rendered soak benchmark, not a balance playtest. High actor health and ammo
## replenishment keep the same 28 AI and live ballistics active throughout.
func _initialize() -> void: call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("Benchmark requires a GPU/display"); quit(1); return
	var seconds:=600.0
	var args:=OS.get_cmdline_user_args()
	if args.has("--seconds") and args.find("--seconds")+1<args.size(): seconds=maxf(5,float(args[args.find("--seconds")+1]))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var app: Node=load("res://scenes/main.tscn").instantiate()
	app.test_profile_path="res://.godot/district-benchmark-"+ProfileStore._new_id()+".json"
	app.settings=SettingsStore.new("res://.godot/district-benchmark-settings.cfg")
	app.settings.world_quality=1
	app.requested_raid_seed=94731
	app.normal_raid_scene=load("res://scenes/raid/district/district_19381.tscn")
	root.add_child(app)
	var load_start:=Time.get_ticks_usec(); app.deploy(false)
	var load_ms:=(Time.get_ticks_usec()-load_start)/1000.0
	var raid: RaidAuthority=app.raid
	if raid==null: push_error("Benchmark deployment failed"); quit(1); return
	var id: String=app.profile.profile.player_id
	var state: RaidParticipant=raid.participants[id]
	state.health=100000
	raid.player.accepts_local_input=false; raid.player.set_physics_process(false)
	for npc in raid.npcs:
		npc.health=100000
		# Immortal benchmark actors must not physically pin the camera route. Normal
		# gameplay collision is unchanged; NPC-vs-NPC collision remains active.
		raid.player.add_collision_exception_with(npc)
		npc.add_collision_exception_with(raid.player)
	for entity in raid.entities.values():
		if entity is RaidDoor and not entity.restricted: entity.open=true; entity.refresh()
	raid.request_reload(id)
	for frame in 120: await process_frame
	var points: Array=raid.get_meta("layout_report").pois
	var order: Array[int]=[0,2,6,5,4,1,3]
	var nav: NavigationRegion3D=raid.get_node("NavigationRegion3D")
	var route:=PackedVector3Array()
	var destination:=0
	var times: Array[float]=[]
	var started:=Time.get_ticks_usec()
	var previous:=started
	var last_update:=started
	var last_report:=started
	var last_position:=raid.player.global_position
	var distance:=0.0
	var peak_memory:=0.0
	var peak_video_memory:=0.0
	var max_draw_calls:=0.0
	var visited:=0
	var moving_actors: Dictionary={}
	var starts: Array[Vector3]=[]
	for npc in raid.npcs: starts.append(npc.global_position)
	var next_shot:=started
	while Time.get_ticks_usec()-started<seconds*1000000:
		await process_frame
		var now:=Time.get_ticks_usec()
		times.append((now-previous)/1000.0); previous=now
		distance+=raid.player.global_position.distance_to(last_position); last_position=raid.player.global_position
		if route.is_empty():
			var poi: Dictionary=points[order[destination%order.size()]]
			route=RaidNavigation.path(nav.get_navigation_map(),raid.player.global_position,Vector3(poi.x,.1,poi.z))
			destination+=1; visited+=1
		if not route.is_empty():
			var offset:=route[0]-raid.player.global_position
			if Vector2(offset.x,offset.z).length()<.65: route.remove_at(0)
			else:
				raid.player.rotation.y=atan2(-offset.x,-offset.z); raid.player.move_input=Vector2(0,-1)
		if now>=next_shot:
			raid.request_fire(id); next_shot=now+700000
		if now-last_update>1000000:
			last_update=now
			peak_memory=maxf(peak_memory,Performance.get_monitor(Performance.MEMORY_STATIC))
			peak_video_memory=maxf(peak_video_memory,Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
			max_draw_calls=maxf(max_draw_calls,Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			for i in raid.npcs.size():
				var npc:=raid.npcs[i]
				if npc.global_position.distance_to(starts[i])>.5: moving_actors[npc.entity_id]=true
				if npc.weapon_state!=null: npc.weapon_state.magazine=30
			if state.weapon!=null and state.weapon.magazine>0: state.weapon.magazine=30
		if now-last_report>30000000:
			last_report=now
			print("BENCH PROGRESS: %.0fs / %.0fm / %d route legs / %d shots / at %s -> %s"%[(now-started)/1000000.0,distance,visited,raid.projectile_serial,raid.player.global_position,route[0] if not route.is_empty() else Vector3.ZERO])
	var elapsed:=(Time.get_ticks_usec()-started)/1000000.0
	times.sort()
	var total:=0.0
	for value in times: total+=value
	var report:={"duration_seconds":elapsed,"resolution":[root.size.x,root.size.y],"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"quality":"Medium","seed":19381,"mean_ms":total/times.size(),"p95_ms":times[int(times.size()*.95)],"p99_ms":times[int(times.size()*.99)],"worst_ms":times[-1],"load_ms":load_ms,"peak_static_memory_mb":peak_memory/1048576,"peak_video_memory_mb":peak_video_memory/1048576,"maximum_draw_calls":max_draw_calls,"player_distance_m":distance,"route_legs":visited,"ai_present":raid.npcs.size(),"ai_moved":moving_actors.size(),"projectiles":raid.projectile_serial,"reference_hardware_verified":false,"note":"Protected health, replenished ammo, player/NPC collision exceptions prevent immortal crowd pinning; normal geometry and NPC/NPC collision active. Not a balance playtest."}
	var file:=FileAccess.open("res://.godot/district-benchmark.json",FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	print("DISTRICT BENCHMARK: ",JSON.stringify(report))
	raid.request_abandon(id); app.home(); app.free()
	for frame in 4: await process_frame
	quit()
