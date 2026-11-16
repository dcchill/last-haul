extends SceneTree

var app: Node
var raid: RaidAuthority
var state: RaidParticipant
var actor_id: String
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + description)

func settle() -> void:
	for frame in range(6): await physics_frame

func face(at: Vector3, target: Vector3) -> void:
	raid.player.global_position = at
	raid.player.previous_position = at
	var offset := target - raid.player.eye_position()
	raid.player.rotation.y = atan2(-offset.x,-offset.z)
	raid.player.look_pitch = atan2(offset.y,Vector2(offset.x,offset.z).length())
	raid.player.camera.rotation.x = raid.player.look_pitch
	await settle()

func walk_line(destination: Vector3, max_ticks := 800) -> bool:
	var actor := raid.player
	actor.movement.velocity = Vector3.ZERO
	for tick in range(max_ticks):
		var offset := destination - actor.global_position
		if Vector2(offset.x,offset.z).length() < 0.6 and absf(offset.y)<0.7: return true
		actor.rotation.y = atan2(-offset.x,-offset.z)
		actor.drive_movement(Vector2(0,-1),false,false,0.05)
		if tick%12==0: await physics_frame
	return false

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	app.selected_map=load("res://resources/maps/medtac_labs.tres")
	app.test_profile_path = "res://.godot/medtac-"+ProfileStore._new_id()+".json"
	root.add_child(app)
	await settle()
	app.deploy(false)
	await settle()
	raid = app.raid
	check(raid!=null and raid.map_definition!=null and raid.map_definition.id=="medtac_labs","normal deployment loads MedTac")
	if raid==null:
		quit(1)
		return
	raid.set_physics_process(false)
	raid.player.set_physics_process(false)
	actor_id = app.profile.profile.player_id
	state = raid.participants[actor_id]
	check(raid.npcs.size()==22 and raid.npcs.filter(func(n): return n.archetype.melee).size()==16,"sixteen infected and six scavengers")
	check(raid.spawn_markers.size()==7 and raid.extraction_zones.size()==4,"seven sketch insertions and four extracts")
	check(state.assigned_extracts.size()==2 and not state.insertion_id.is_empty(),"random insertion assigns two far-side extracts")
	check(raid.player.has_node("HumanBody") and not raid.player.has_node("RobotBody"),"civilian human replaces robot")
	check(raid.player.hand_rig.get_child_count()==4,"human hands preserve weapon rig contract")
	check(state.infection_remaining>1198 and state.infection_remaining<=1200,"twenty-minute initial infection countdown")
	check(raid.containers.size()==160,"authored loot in grounds, reception, labs, warehouse, and basement")
	var minimum_supplies := 0
	var minimum_drives := 0
	for identity: String in raid.containers:
		if identity.begins_with("basement-"):
			minimum_supplies += raid.containers[identity].count("infection_suppressant")
			minimum_drives += raid.containers[identity].count("research_drive")
	check(minimum_supplies>=2 and minimum_drives>=2,"basement guarantees medical and technical value")
	var npc_states: Array[int] = []
	for npc in raid.npcs:
		npc_states.append(npc.state)
		npc.state = RaidGuard.State.DEAD
		raid.player.add_collision_exception_with(npc)
	for marker in raid.spawn_markers:
		for npc in raid.npcs: check(marker.global_position.distance_to(npc.home_position)>40,"insertion is outside encounter pockets")
		var query:=PhysicsShapeQueryParameters3D.new()
		var capsule:=BoxShape3D.new()
		capsule.size=Vector3(0.6,1.8,0.6)
		query.shape=capsule
		query.transform=Transform3D(Basis.IDENTITY,marker.global_position+Vector3.UP*0.9)
		query.exclude=[raid.player.get_rid()]
		check(raid.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),"insertion has clear player collision volume")
	var nav := raid.get_node("NavigationRegion3D") as NavigationRegion3D
	await settle()
	var longest := 0.0
	for marker in raid.spawn_markers:
		var distances: Array = marker.get_meta("route_distances")
		check(marker.get_meta("assigned_extracts")==[distances[0].id,distances[1].id] and distances[0].distance>=distances[1].distance,"stored assignment follows baked route distance")
		longest = maxf(longest,distances[0].distance)
		for zone in raid.extraction_zones:
			var path := RaidNavigation.path(nav.get_navigation_map(),marker.global_position,zone.global_position)
			check(not path.is_empty() and path[-1].distance_to(zone.global_position)<3,"every insertion reaches "+zone.entity_id)
	check(longest/4.317>=180 and longest/4.317<=240,"representative longest crossing takes three to four walking minutes")
	print("MEDTAC CROSSING: %.1fm / %.1fs at unloaded walking speed"%[longest,longest/4.317])
	# Every named department is connected to the lobby without basement access.
	for entity in raid.entities.values():
		if not entity is RaidEntity or entity.kind!="container": continue
		var path := RaidNavigation.path(nav.get_navigation_map(),Vector3(-150,0,60),entity.global_position)
		if entity.global_position.y>=-1 and (not entity is RaidLootPickup or entity.available):
			check(not path.is_empty() and path[-1].distance_to(entity.global_position)<3,"ground-floor loot route: "+entity.entity_id)
	var lab_door: RaidDoor = raid.entities["research-lab-entrance"]
	var maintenance_door: RaidDoor = raid.entities["research-maintenance-entrance"]
	var locked_path := RaidNavigation.path(nav.get_navigation_map(),Vector3(-32,0,-40),Vector3(-32,-10,-92))
	check(locked_path.is_empty() or locked_path[-1].distance_to(Vector3(-32,-10,-92))>3,"locked security circuit excludes basement from ground-floor navigation")
	await face(Vector3(-32,0.02,-41.5),lab_door.global_position)
	check(not raid.request_interact(actor_id,lab_door.entity_id) and not lab_door.open,"no credential rejects basement entry")
	# A card in an open loot container is not a carried credential.
	var candidate: RaidInventory = raid.containers["security-office-cabinet"]
	candidate.add("medtac_keycard",1)
	state.opened_container="security-office-cabinet"
	check(not raid.request_interact(actor_id,lab_door.entity_id),"unowned container card cannot unlock a door")
	state.opened_container=""
	check(state.inventory.add("medtac_keycard",1),"keycard fits carried inventory")
	check(raid.request_interact(actor_id,lab_door.entity_id),"carried card unlocks chosen entrance")
	check(lab_door.unlocked and lab_door.open and not maintenance_door.unlocked and state.inventory.count("medtac_keycard")==0,"exactly one card consumed for exactly one entrance")
	check(not raid.request_interact(actor_id,maintenance_door.entity_id),"remote door interaction rejected")
	await settle()
	NavigationServer3D.map_force_update(nav.get_navigation_map())
	await settle()
	var unlocked_path := RaidNavigation.path(nav.get_navigation_map(),Vector3(-32,0,-40),Vector3(-32,-10,-92))
	check(not unlocked_path.is_empty() and unlocked_path[-1].distance_to(Vector3(-32,-10,-92))<3,"unlock enables basement navigation")
	check(await walk_line(Vector3(-32,-10,-91),1200),"physical walking descends laboratory stairs")
	check(await walk_line(Vector3(-32,0,-40),1200),"physical walking climbs laboratory stairs")
	for node in raid.find_children("*","",true,false):
		if not node is VoxelDestructible: continue
		var link:=node.get_node(node.link_path) as NavigationLink3D
		check(not link.enabled,"weak partition shortcut starts closed")
		node.blast(node.global_position,4)
		await settle()
		check(link.enabled and node.passage_open,"destruction updates traversal after passage clearance")
	# The other door allows egress without permanently authorizing ingress.
	await face(Vector3(54,-0.1,-46),maintenance_door.global_position)
	check(raid.request_interact(actor_id,maintenance_door.entity_id) and maintenance_door.open and not maintenance_door.unlocked,"locked second entrance permits emergency egress without a card")
	maintenance_door.auto_close_left=0.01
	raid.player.global_position=Vector3(54,0,-39)
	maintenance_door._physics_process(0.1)
	await settle()
	check(not maintenance_door.open and not maintenance_door.unlocked,"emergency egress relocks")
	# Literal time, consuming treatments, and cap handling.
	state.infection_remaining=900
	raid.player.sprinting=true
	raid._update_infection(state,2)
	check(state.infection_remaining==898,"sprinting uses literal simulation seconds")
	raid.player.sprinting=false
	state.inventory.add("infection_suppressant",1)
	var supply: Dictionary
	for entry in state.inventory.slots:
		if entry.id=="infection_suppressant": supply=entry
	check(raid.request_use(actor_id,supply.uid) and state.infection_remaining==1078,"suppressant adds exactly three minutes")
	check(not raid.request_use(actor_id,supply.uid),"consumed suppressant cannot be reused")
	state.inventory.add("infection_suppressant",1)
	for entry in state.inventory.slots:
		if entry.id=="infection_suppressant": supply=entry
	state.infection_remaining=1200
	check(not raid.request_use(actor_id,supply.uid) and state.inventory.count("infection_suppressant")==1,"full infection time preserves treatment")
	state.infection_remaining=1190
	check(raid.request_use(actor_id,supply.uid) and state.infection_remaining==1200,"treatment clamps at twenty minutes")
	# Faction targeting chooses a visible hostile NPC, not a nearby friendly scavenger.
	var infected := raid.npcs[0]
	var scav := raid.npcs[16]
	var friend := raid.npcs[17]
	infected.state=RaidGuard.State.IDLE
	scav.state=RaidGuard.State.IDLE
	friend.state=RaidGuard.State.IDLE
	infected.global_position=Vector3(-280,0,180)
	scav.global_position=Vector3(-280,0,185)
	friend.global_position=Vector3(-278,0,185)
	infected.rotation.y=PI
	scav.rotation.y=0
	raid.player.global_position=Vector3(0,0,200)
	await settle()
	check(infected.select_target(raid)==scav,"infected targets a scavenger")
	check(scav.select_target(raid)==infected and not scav.hostile_to(friend),"scavengers target infected and cooperate")
	for npc in raid.npcs: npc.state=RaidGuard.State.DEAD
	await migration_checks()
	await seed_checks()
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless": await capture_views()
	# Ineligible extracts never start; switching active extracts always restarts the timer.
	var assigned := raid.extraction_zones.filter(func(z): return z.entity_id in state.assigned_extracts)
	var other := raid.extraction_zones.filter(func(z): return z.entity_id not in state.assigned_extracts)
	raid.player.global_position=other[0].global_position
	await settle()
	check(not raid.request_extract(actor_id),"unassigned extract is inactive")
	raid.player.global_position=assigned[0].global_position
	await settle()
	raid._update_extraction(actor_id,14)
	check(state.extracting and state.extraction_left==1 and raid.is_active(),"assigned extract requires fifteen seconds")
	raid.player.global_position=assigned[1].global_position
	await settle()
	raid._update_extraction(actor_id,0.1)
	check(is_equal_approx(state.extraction_left,14.9),"changing extract discards previous progress")
	state.infection_remaining=0.025
	state.extraction_left=0.025
	raid.gameplay_step()
	check(not raid.result.success and "turned" in raid.result.reason,"turning wins simultaneous extraction")
	var snapshot: Dictionary=app.profile.profile.duplicate(true)
	raid._finish(true,"duplicate")
	check(app.profile.profile==snapshot,"terminal raid result cannot award loot twice")
	app.home()
	await settle()
	await persistent_card_check()
	app.deploy(true)
	await settle()
	var practice_state: RaidParticipant=app.raid.participants[actor_id]
	var before:=practice_state.infection_remaining
	app.raid.gameplay_step()
	check(practice_state.infection_remaining==before,"practice is exempt from infection")
	app.free()
	await settle()
	print("MEDTAC: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func persistent_card_check() -> void:
	app.deploy(false)
	await settle()
	raid=app.raid
	raid.set_physics_process(false)
	raid.player.set_physics_process(false)
	state=raid.participants[actor_id]
	for npc in raid.npcs: npc.state=RaidGuard.State.DEAD
	state.inventory.add("medtac_keycard",1)
	var identity: String=state.inventory.slots.back().uid
	for zone in raid.extraction_zones:
		if zone.entity_id in state.assigned_extracts:
			raid.player.global_position=zone.global_position
			break
	await settle()
	raid._update_extraction(actor_id,15)
	check(raid.result.success and not app.pending_save,"successful MedTac extraction commits its journal")
	app.home()
	await settle()
	check(app.stash_view.count("medtac_keycard")==1,"unused keycard persists in stash")
	for i in range(app.stash_view.slots.size()):
		if app.stash_view.slots[i].id=="medtac_keycard":
			check(InventoryManager.move(app.stash_view,i,app.loadout.pockets),"extracted keycard can be staged")
			break
	app._save_stash_layout()
	app.deploy(false)
	await settle()
	raid=app.raid
	raid.set_physics_process(false)
	raid.player.set_physics_process(false)
	state=raid.participants[actor_id]
	check(state.pockets.count("medtac_keycard")==1 and state.pockets.slots[0].uid==identity,"redeployment retains physical keycard identity")
	var gate: RaidDoor=raid.entities["research-lab-entrance"]
	await face(Vector3(-32,0.02,-41.5),gate.global_position)
	check(raid.request_interact(actor_id,gate.entity_id) and state.pockets.count("medtac_keycard")==0,"persisted card is consumed when used")
	raid.request_abandon(actor_id)
	app.home()
	await settle()
	check(app.stash_view.count("medtac_keycard")==0,"consumed card cannot return to stash")

func migration_checks() -> void:
	var path: String="res://.godot/medtac-migration-"+ProfileStore._new_id()+".json"
	var legacy := ProfileStore.new(app.catalog,path)
	legacy.load_profile()
	var saved: Dictionary=legacy.profile.duplicate(true)
	saved.version=5
	var nested:=RaidInventory.new(app.catalog.items)
	nested.configure(preload("res://resources/containers/base_pack.tres"))
	nested.add("battery_cell",1)
	var pack:=RaidInventory.new(app.catalog.items,10,6)
	pack.add("small_pack",1)
	pack.slots[0].storage.add("battery_cell",1)
	pack.add("battery_cell",1)
	saved.staged={"pack":pack.serialize()}
	var pending:=RaidInventory.new(app.catalog.items,10,6)
	pending.add("battery_cell",1)
	saved.pending_result={"result":{"raid_id":"migration-pending","success":true,"reason":"Extraction complete"},"items":pending.snapshot()}
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(saved))
	file.close()
	var restored:=ProfileStore.new(app.catalog,path)
	check(restored.load_profile() and restored.profile.version==ProfileStore.VERSION,"version five medical migration succeeds")
	check(restored.profile.staged.pack.slots[0].storage.slots[0].id=="infection_suppressant" and restored.profile.staged.pack.slots[1].id=="infection_suppressant","nested and staged legacy supplies converted")
	check(restored.profile.pending_result.items[0].id=="infection_suppressant" and restored.profile.pending_result.result.raid_id=="migration-pending","pending reward survives conversion")
	check(restored.profile.staged.pack.slots[1].uid==saved.staged.pack.slots[1].uid and JSON.parse_string(JSON.stringify(restored.profile.stash))==JSON.parse_string(JSON.stringify(saved.stash)),"migration retains item identities and unrelated possessions")
	check(Array(DirAccess.get_files_at("res://.godot")).any(func(n): return n.begins_with(path.get_file()+".v5-")),"original version-five profile backed up")

func seed_checks() -> void:
	var hits:=0
	# Exercise the production loot generator without constructing another world.
	for seed_value in range(400):
		raid.random.seed=seed_value
		raid._build_loot()
		var cards:=0
		for inventory: RaidInventory in raid.containers.values(): cards+=inventory.count("medtac_keycard")
		check(cards<=1,"at most one authored keycard per raid")
		if cards==1: hits+=1
	check(hits>=20 and hits<=60,"seeded card generation is consistent with ten percent rarity")
	raid.random.seed=42
	raid._build_loot()
	var first: Dictionary={}
	for identity: String in raid.containers:
		first[identity]={}
		for entry in raid.containers[identity].slots: first[identity][entry.id]=first[identity].get(entry.id,0)+entry.quantity
	raid.random.seed=42
	raid._build_loot()
	for identity: String in raid.containers:
		var second: Dictionary={}
		for entry in raid.containers[identity].slots: second[entry.id]=second.get(entry.id,0)+entry.quantity
		check(first[identity]==second,"raid seed reproduces loot composition")

func capture_views() -> void:
	app.ui.visible=false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	var camera:=Camera3D.new()
	raid.add_child(camera)
	camera.current=true
	var views: Array=[
		["entrance",Vector3(-147,2,90),Vector3(-150,2,-10)],
		["clinical",Vector3(-163,1.7,-4),Vector3(-168,1,-16)],
		["laboratory",Vector3(-133,1.7,-173),Vector3(-140,1,-188)],
		["warehouse",Vector3(112,2.3,-145),Vector3(150,1.5,-165)],
		["containment",Vector3(-45,-8.3,-151),Vector3(-55,-9,-165)],
		["human",Vector3(-148.5,1.3,89),Vector3(-150,1,92)]
	]
	raid.player.global_position=Vector3(-150,0,92)
	raid.player.previous_position=raid.player.global_position
	raid.player.velocity=Vector3.ZERO
	raid.player.rotation.y=0
	raid.player.body_visual.set_first_person(false)
	for view in views:
		if view[0]=="human":
			raid.player.rifle.visible=false
			raid.player.hand_rig.visible=false
		camera.position=view[1]
		camera.look_at(view[2])
		for frame in range(5): await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://.godot/medtac-"+view[0]+".png")==OK,"capture "+view[0])
		var started:=Time.get_ticks_usec()
		for frame in range(45): await process_frame
		var frame_ms:=float(Time.get_ticks_usec()-started)/45000.0
		print("MEDTAC RENDER %s: %.2fms / %.1f FPS / %d draws"%[view[0],frame_ms,1000.0/frame_ms,int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	await capture_encounter(camera)
	# Cutaway is for review only; the playable building keeps its ceilings.
	for node in raid.find_children("*Roof*","",true,false): node.visible=false
	for node in raid.find_children("RoomCeiling*","",true,false): node.visible=false
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=670
	camera.position=Vector3(0,550,0)
	camera.look_at(Vector3.ZERO,Vector3.FORWARD)
	for frame in range(5): await process_frame
	await RenderingServer.frame_post_draw
	check(camera.current and not app.ui.visible,"cutaway uses its review camera without HUD")
	check(root.get_texture().get_image().save_png("res://.godot/medtac-overhead.png")==OK,"capture cutaway")
	camera.queue_free()
	raid.player.camera.current=true
	app.ui.visible=true

func capture_encounter(camera: Camera3D) -> void:
	# Exercise real perception, navigation, firing, ballistics and effects on the dressed map.
	var health_before:=state.health
	var infection_before:=state.infection_remaining
	var tick_before:=raid.gameplay_tick
	var shots_before:=raid.projectile_serial
	var starts: Array[Vector3]=[]
	for i in range(raid.npcs.size()):
		var npc:=raid.npcs[i]
		npc.global_position=npc.home_position
		if i<4: npc.global_position=Vector3(130+i*8,.04,-147)
		if i in [18,19,20,21]: npc.global_position=Vector3(130+(i-18)*8,.04,-139)
		npc.health=100000
		npc.state=RaidGuard.State.IDLE
		npc.attack_left=0
		npc.rotation.y=PI if i<4 else 0
		starts.append(npc.global_position)
	state.health=100000
	state.infection_remaining=1200
	raid.player.global_position=Vector3(172,.04,-143)
	raid.player.previous_position=raid.player.global_position
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	camera.position=Vector3(170,2,-145)
	camera.look_at(Vector3(140,1,-143))
	raid.set_physics_process(true)
	var times: Array[float]=[]
	var started:=Time.get_ticks_usec()
	var previous:=started
	while Time.get_ticks_usec()-started<3000000:
		await process_frame
		var now:=Time.get_ticks_usec()
		times.append((now-previous)/1000.0)
		previous=now
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.godot/medtac-encounter.png")==OK,"capture active encounter")
	raid.set_physics_process(false)
	var moving:=0
	for i in range(raid.npcs.size()):
		if raid.npcs[i].global_position.distance_to(starts[i])>.2: moving+=1
		raid.npcs[i].state=RaidGuard.State.DEAD
	check(raid.gameplay_tick>tick_before+40 and raid.projectile_serial>shots_before and moving>0,"encounter sample runs all AI with movement and live gunfire")
	var elapsed:=float(Time.get_ticks_usec()-started)/1000.0
	times.sort()
	print("MEDTAC ACTIVE: %.2fms mean / %.1f FPS / %.2fms p95 / %d AI / %d moving / %d shots"%[elapsed/times.size(),times.size()*1000.0/elapsed,times[int(times.size()*.95)],raid.npcs.size(),moving,raid.projectile_serial-shots_before])
	state.health=health_before
	state.infection_remaining=infection_before
