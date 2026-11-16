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
	# Optional scene argument benchmarks another map (e.g. the MedTac Research Campus).
	var scene_path:="res://scenes/raid/district/district_19381.tscn"
	for arg in args:
		if arg.ends_with(".tscn"): scene_path=arg
	app.normal_raid_scene=load(scene_path)
	root.add_child(app)
	var load_start:=Time.get_ticks_usec(); app.deploy(false)
	var load_ms:=(Time.get_ticks_usec()-load_start)/1000.0
	var raid: RaidAuthority=app.raid
	if raid==null: push_error("Benchmark deployment failed"); quit(1); return
	var id: String=app.profile.profile.player_id
	var state: RaidParticipant=raid.participants[id]
	state.health=100000
	if state.weapon==null: push_error("Benchmark requires a staged rifle"); app.free(); quit(1); return
	state.weapon.data.magazine=ItemInstance.create(app.catalog.items.stanag_magazine,app.catalog.items)
	state.weapon.data.chamber="five_five_six"; state.weapon.magazine=30
	raid.player.accepts_local_input=false; raid.player.set_physics_process(false)
	for npc in raid.npcs:
		npc.health=100000
		# Immortal benchmark actors must not physically pin the camera route. Normal
		# gameplay collision is unchanged; NPC-vs-NPC collision remains active.
		raid.player.add_collision_exception_with(npc)
		npc.add_collision_exception_with(raid.player)
	for entity in raid.entities.values():
		if entity is RaidDoor:
			entity.unlocked=true; entity.open=true; entity.refresh()
	for frame in 120: await process_frame
	if state.weapon==null or state.weapon.magazine<=0:
		push_error("Benchmark requires a loaded player weapon"); app.free(); quit(1); return
	var points: Array[Vector3]=[Vector3(47,.1,43)]
	var route_titles: Array=["Reception and screening","Central analysis","Research office and records","Trial control","Cure transfer archive","Public waiting and reception","Administration open office","Security desk and control","Maintenance workshop","Receiving inspection","Dispatch mezzanine office","Bulk rack hall"]
	if raid.has_meta("campus_anchors"):
		points=[Vector3(6,.1,-36)]
		route_titles=["Main reception lobby","Pharmaceutical laboratory B","Skybridge access","Skybridge security post","Intensive care unit","Patient reception","Warehouse offices","Goods-in inspection","Restricted access checkpoint","Subject observation ward"]
	for title in route_titles:
		var matches:=CampusValidator.rooms(raid).filter(func(n): return n.get_meta("room_purpose")==title)
		if matches.is_empty(): continue
		var room: Node3D=matches[0]
		points.append(room.to_global(Vector3(0,.1,0)))
	var nav: NavigationRegion3D=raid.get_node("NavigationRegion3D")
	NavigationServer3D.map_force_update(nav.get_navigation_map())
	for i in points.size(): points[i]=NavigationServer3D.map_get_closest_point(nav.get_navigation_map(),points[i])
	# Route stops are the reachable ends of each leg, not isolated pockets near room centres.
	for i in range(1,points.size()):
		var leg:=RaidNavigation.path(nav.get_navigation_map(),points[i-1],points[i])
		if not leg.is_empty() and leg[-1].distance_to(points[i])<6: points[i]=leg[-1]
	for i in points.size():
		if not DistrictValidator.reaches(nav.get_navigation_map(),points[i],points[(i+1)%points.size()],2.5):
			var leg:=RaidNavigation.path(nav.get_navigation_map(),points[i],points[(i+1)%points.size()])
			push_error("Benchmark route is disconnected at leg %d: %s -> %s ends %s"%[i,points[i],points[(i+1)%points.size()],leg[-1] if not leg.is_empty() else Vector3.INF]); app.free(); quit(1); return
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
	var next_blast:=started+30000000
	var blasts:=0
	var blast_ms: Array[float]=[]
	var panels: Array=raid.find_children("*","StaticBody3D",true,false).filter(func(n): return n is CampusWall)
	while Time.get_ticks_usec()-started<seconds*1000000:
		await process_frame
		var now:=Time.get_ticks_usec()
		times.append((now-previous)/1000.0); previous=now
		distance+=raid.player.global_position.distance_to(last_position); last_position=raid.player.global_position
		if route.is_empty():
			var target: Vector3=points[destination%points.size()]
			route=RaidNavigation.path(nav.get_navigation_map(),raid.player.global_position,target)
			destination+=1; visited+=1
		if not route.is_empty():
			var offset:=route[0]-raid.player.global_position
			raid.player.move_input=Vector2.ZERO
			if Vector2(offset.x,offset.z).length()<.2: route.remove_at(0)
			else:
				raid.player.rotation.y=atan2(-offset.x,-offset.z); raid.player.move_input=Vector2(0,-1)
		if now>=next_blast and not panels.is_empty():
			var panel: CampusWall=panels[(blasts*37)%panels.size()]
			var blast_start:=Time.get_ticks_usec()
			raid._explode(panel.global_position,3.0)
			blast_ms.append((Time.get_ticks_usec()-blast_start)/1000.0)
			blasts+=1; next_blast=now+30000000
		if now>=next_shot:
			raid.request_fire(id); next_shot=now+700000
		if now-last_update>1000000:
			last_update=now
			state.health=100000
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
	var report:={"scripted_blasts":blasts,"blast_ms":blast_ms,"map":scene_path,"breach_updates":raid.get_node("BreachNavigation").revisions if raid.has_node("BreachNavigation") else 0,"breach_links":raid.find_children("*","NavigationLink3D",true,false).filter(func(n): return n.get_meta("campus_breach",false)).size(),"duration_seconds":elapsed,"resolution":[root.size.x,root.size.y],"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"quality":"Medium","seed":raid.get_meta("layout_seed",0),"mean_ms":total/times.size(),"p95_ms":times[int(times.size()*.95)],"p99_ms":times[int(times.size()*.99)],"worst_ms":times[-1],"load_ms":load_ms,"peak_static_memory_mb":peak_memory/1048576,"peak_video_memory_mb":peak_video_memory/1048576,"maximum_draw_calls":max_draw_calls,"player_distance_m":distance,"route_legs":visited,"ai_present":raid.npcs.size(),"ai_moved":moving_actors.size(),"projectiles":raid.projectile_serial,"reference_hardware_verified":false,"note":"Protected health, replenished ammo, all doors open including authorized basement gates, and player/NPC collision exceptions. Normal geometry and NPC/NPC collision remain active; scripted explosions damage ordinary walls every 30 seconds. Route includes interiors, basement and upper floors. Not a balance playtest."}
	var file:=FileAccess.open("res://.godot/district-benchmark.json",FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	print("DISTRICT BENCHMARK: ",JSON.stringify(report))
	raid.request_abandon(id); app.home(); app.free()
	for frame in 4: await process_frame
	quit()
