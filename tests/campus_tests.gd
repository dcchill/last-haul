extends SceneTree

var checks:=0
var failures:=0
var raid: RaidAuthority
var app: Node
var actor_id: String

func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error("FAIL: "+label)
func settle(frames := 4) -> void:
	for frame in frames: await physics_frame
func face(at: Vector3,target: Vector3) -> void:
	raid.player.global_position=at; raid.player.previous_position=at; raid.player.movement.velocity=Vector3.ZERO
	var offset:=target-raid.player.eye_position()
	raid.player.rotation.y=atan2(-offset.x,-offset.z)
	raid.player.look_pitch=atan2(offset.y,Vector2(offset.x,offset.z).length())
	raid.player.camera.rotation.x=raid.player.look_pitch
	await settle()
func walk(destination: Vector3) -> bool:
	for tick in 700:
		var offset:=destination-raid.player.global_position
		if Vector2(offset.x,offset.z).length()<.2 and absf(offset.y)<.65: return true
		raid.player.rotation.y=atan2(-offset.x,-offset.z)
		raid.player.drive_movement(Vector2(0,-1),false,false,.05)
		if tick%10==0: await physics_frame
	print("WALK BLOCKED ",raid.player.global_position," -> ",destination)
	return false

func snapshot() -> String:
	var result: Dictionary={}
	for id: String in raid.containers:
		var items: Array=[]
		for entry: Dictionary in raid.containers[id].slots: items.append([entry.id,entry.quantity])
		result[id]=items
	return JSON.stringify(result)

func walk_route(destination: Vector3) -> bool:
	var nav: NavigationRegion3D=raid.get_node("NavigationRegion3D")
	var path:=RaidNavigation.path(nav.get_navigation_map(),raid.player.global_position,destination)
	if path.is_empty(): return false
	for point in path:
		if not await walk(point): return false
	return raid.player.global_position.distance_to(destination)<1.0

func run() -> void:
	app=load("res://scenes/main.tscn").instantiate()
	app.test_profile_path="res://.godot/campus-test-"+ProfileStore._new_id()+".json"
	app.settings=SettingsStore.new("res://.godot/campus-test-settings.cfg")
	app.requested_layout_seed=19381; app.requested_raid_seed=94731
	root.add_child(app); app.deploy(false); await settle(8)
	raid=app.raid
	check(raid!=null,"campus deploys")
	if raid==null: app.free(); quit(1); return
	actor_id=app.profile.profile.player_id
	raid.set_physics_process(false); raid.player.set_physics_process(false)
	for npc in raid.npcs:
		npc.state=RaidGuard.State.DEAD; npc.collision_layer=0; npc.collision_mask=0
	var state: RaidParticipant=raid.participants[actor_id]
	var nav:=raid.get_node("NavigationRegion3D") as NavigationRegion3D
	var audit:=CampusValidator.inspect(raid)
	check(audit.rooms==58 and audit.props_checked>=250,"all 58 functional spaces have equipment clearance audits")
	check(audit.errors.is_empty(),"all room bounds, furnishing clearances and doorway paths: "+str(audit.errors))
	check(raid.get_meta("campus_audit").size()>=80,"room and exterior audit records")
	for entity in raid.entities.values():
		if entity is RaidDoor and not entity.restricted: entity.open=true; entity.refresh()
	await settle()
	for room in raid.find_children("*","Node3D",true,false):
		if not room.has_meta("room_bounds"): continue
		var at: Vector3=room.to_global(room.get_meta("entry_local"))
		raid.player.global_position=at; raid.player.previous_position=at; raid.player.movement.velocity=Vector3.ZERO
		await settle()
		check(await walk_route(room.to_global(Vector3(0,.05,0))),"actual player enters room: "+str(room.get_meta("room_purpose")))
	# Actual camera rays must resolve every furnishing from its usable side.
	for source in raid.entities.values():
		if not source is SearchableFurniture: continue
		await face(source.global_position+source.global_basis.z*1.5+Vector3.UP*.05,source.to_global(source.interaction_offset))
		check(raid.request_interact(actor_id,source.entity_id),"accessible furnishing: "+source.entity_id)
		state.opened_container=""
	# A sealed basement has no navigation route from any above-ground floor/ruin.
	var basement_target:=Vector3(-2,-4.1,-35)
	for start in [Vector3(0,.1,45),Vector3(0,4.3,100),Vector3(110,4.3,-34),Vector3(23,3.9,-29)]:
		check(not DistrictValidator.reaches(nav.get_navigation_map(),start,basement_target),"no security bypass from "+str(start))
	var gates:=raid.entities.values().filter(func(n): return n is RaidDoor and n.restricted)
	check(gates.size()==2,"two independent basement gates")
	for stair: Dictionary in raid.get_meta("campus_stairs"):
		if not stair.restricted: continue
		var gate: RaidDoor=gates.filter(func(g): return g.get_meta("campus_gate")==stair.name)[0]
		var outside: Vector3=gate.global_position+Vector3(0,-1.15,1.6)
		await face(outside,gate.global_position)
		check(not raid.request_interact(actor_id,gate.entity_id),"entry requires carried card: "+stair.name)
		state.inventory.add("medtac_keycard",1)
		check(raid.request_interact(actor_id,gate.entity_id) and gate.unlocked and state.inventory.count("medtac_keycard")==0,"one card opens chosen entrance: "+stair.name)
		await settle(); NavigationServer3D.map_force_update(nav.get_navigation_map()); await settle()
		check(DistrictValidator.reaches(nav.get_navigation_map(),stair.start,stair.end),"basement NPC navigation: "+stair.name)
		raid.player.global_position=stair.start; raid.player.previous_position=stair.start; raid.player.movement.velocity=Vector3.ZERO
		await settle()
		check(await walk(stair.end),"player descends basement: "+stair.name)
		check(await walk(stair.start),"player ascends basement: "+stair.name)
		gate.unlocked=false; gate.open=false; gate.refresh(); await settle()
		await face(gate.global_position+Vector3(0,-1.15,-1.5),gate.global_position)
		check(raid.request_interact(actor_id,gate.entity_id) and not gate.unlocked,"emergency egress does not grant entry: "+stair.name)
		raid.player.global_position=outside+Vector3(0,0,3); gate.auto_close_left=.01; gate._physics_process(.1); await settle()
		check(not gate.open and not gate.unlocked,"emergency gate closes: "+stair.name)
	var profiles: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/medtac/loot_profiles.json"))
	var card_rolls:=0
	for seed_number in 200:
		raid.random.seed=seed_number; raid._build_loot()
		var first:=snapshot()
		var cards:=0; var guaranteed_suppressants:=0; var guaranteed_drives:=0
		for entity in raid.entities.values():
			if not entity is SearchableFurniture: continue
			var contents: RaidInventory=raid.containers[entity.entity_id]
			cards+=contents.count("medtac_keycard")
			var allowed: Array=[]
			for entry: Array in profiles[entity.loot_profile]: allowed.append(entry[0])
			check(contents.slots.all(func(e): return e.id in allowed or (entity.keycard_candidate and e.id=="medtac_keycard")),"physical container loot profile")
			if entity.guaranteed_items.has("infection_suppressant"): guaranteed_suppressants+=contents.count("infection_suppressant")
			if entity.guaranteed_items.has("research_drive"): guaranteed_drives+=contents.count("research_drive")
		check(cards<=1,"at most one keycard per raid")
		if cards: card_rolls+=1
		check(guaranteed_suppressants>=2 and guaranteed_drives>=2,"basement guaranteed rewards")
		check(raid.containers.size()==176,"128 containers plus exactly 48 active loose sockets")
		raid._build_loot(); check(first==snapshot(),"reproducible loot and keycard seed "+str(seed_number))
		if seed_number%20==0: await process_frame
	check(card_rolls>0 and card_rolls<50,"10 percent card roll exercised without guaranteeing entry")
	app.free(); await settle()
	print("CAMPUS TESTS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

