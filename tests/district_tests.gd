extends SceneTree

var checks:=0
var failures:=0
var app: Node
var raid: RaidAuthority
var actor_id: String

func _initialize() -> void: call_deferred("run")

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error("FAIL: "+label)

func settle(frames := 3) -> void:
	for frame in frames: await physics_frame

func walk_line(destination: Vector3,max_ticks := 600) -> bool:
	var actor:=raid.player
	actor.movement.velocity=Vector3.ZERO
	for tick in max_ticks:
		var offset:=destination-actor.global_position
		if Vector2(offset.x,offset.z).length()<.55 and absf(offset.y)<.65: return true
		actor.rotation.y=atan2(-offset.x,-offset.z)
		actor.drive_movement(Vector2(0,-1),false,false,.05)
		if tick%10==0: await physics_frame
	return false

func face(at: Vector3,target: Vector3) -> void:
	raid.player.global_position=at; raid.player.previous_position=at
	var offset:=target-raid.player.eye_position()
	raid.player.rotation.y=atan2(-offset.x,-offset.z)
	raid.player.look_pitch=atan2(offset.y,Vector2(offset.x,offset.z).length())
	raid.player.camera.rotation.x=raid.player.look_pitch
	await settle()

func run() -> void:
	for seed_number in 200:
		var layout:=DistrictLayout.generate(seed_number)
		check(layout.validate().is_empty(),"connected biconnected traversal seed "+str(seed_number))
		check(layout.report()==DistrictLayout.generate(seed_number).report(),"deterministic graph "+str(seed_number))
		check(DistrictLayout.stream(seed_number,"loot")!=DistrictLayout.stream(seed_number,"layout"),"independent random streams")
	var settings:=SettingsStore.new("res://.godot/district-settings-test.cfg")
	settings.world_quality=0; check(settings.save_settings()==OK,"quality saves")
	var restored:=SettingsStore.new(settings.path); restored.load_settings(); check(restored.world_quality==0,"quality roundtrip")
	var definition: RaidMapDefinition=load("res://resources/maps/medtac_quarantine_district.tres")
	check(definition.validation_error().is_empty() and definition.approved_layouts.size()==3,"curated district resource")
	app=load("res://scenes/main.tscn").instantiate()
	app.test_profile_path="res://.godot/district-test-"+ProfileStore._new_id()+".json"
	app.settings=SettingsStore.new("res://.godot/district-isolated-settings.cfg")
	root.add_child(app)
	actor_id=app.profile.profile.player_id
	for path in definition.approved_layouts:
		app.normal_raid_scene=load(path); app.deploy(false); await settle(6)
		raid=app.raid
		check(raid!=null,"district deploys: "+path)
		if raid==null: continue
		raid.set_physics_process(false); raid.player.set_physics_process(false)
		for npc in raid.npcs: npc.state=RaidGuard.State.DEAD
		var state: RaidParticipant=raid.participants[actor_id]
		check(raid.npcs.size()==28 and raid.npcs.filter(func(n): return n.archetype.melee).size()==18,"28 actors / 18 infected")
		check(state.infection_capacity==1500 and state.infection_remaining>1498,"25 minute infection")
		check(state.assigned_extracts.size()==2,"two assigned exits")
		check(raid.containers.size()==144,"96 furnishings and 48 active loose items")
		var storage:=raid.entities["district-storage-008"] as SearchableFurniture
		await face(storage.global_position+Vector3(0,.05,1.8),storage.global_position+storage.interaction_offset)
		check(raid.request_interact(actor_id,storage.entity_id) and storage.opened,"real camera interaction opens district furnishing")
		var contents: RaidInventory=raid.containers[storage.entity_id]
		contents.tick_search(100)
		check(not contents.slots.is_empty() and raid.request_transfer(actor_id,storage.entity_id,0),"searched district loot transfers through authority")
		var card_sources:=raid.entities.values().filter(func(n): return n is RaidEntity and n.keycard_candidate)
		check(card_sources.size()==2,"keycard candidates remain in accessible medical/security storage")
		var voxel_cover:=raid.find_children("*","",true,false).filter(func(n): return n is VoxelDestructible)
		check(voxel_cover.size()==6 and voxel_cover.all(func(n): return n.remaining_cells()==144),"six integrated destructible cover sections")
		var foliage:=raid.get_node("NavigationRegion3D/AbandonedWoodland/TreeInstances") as DistrictFoliage
		check(foliage.instance_transforms.size()==110 and foliage.multimesh.instance_count==110,"authored foliage transforms survive headless baking")
		var nav:=raid.get_node("NavigationRegion3D") as NavigationRegion3D
		var layout:=DistrictLayout.generate(int(raid.get_meta("layout_seed")))
		check(DistrictValidator.inspect(raid,layout).errors.is_empty(),"baked physical map validated")
		var tactics: Dictionary=raid.get_meta("tactical_report")
		check(tactics.errors.is_empty() and tactics.valid_cover.size()>=60 and tactics.maximum_cover_distance_m<=25,"ray-tested useful cover and exposure limits")
		for start in raid.spawn_markers:
			check(start.get_meta("assigned_extracts").size()==2,"baked far-side assignment")
			for exit in raid.extraction_zones: check(DistrictValidator.reaches(nav.get_navigation_map(),start.global_position,exit.global_position),"physical spawn/extract reachability")
		for building in raid.find_children("Building*","Node3D",true,false):
			if not building.has_meta("enterable"): continue
			var front: Vector3=building.to_global(Vector3(0,.1,9))
			var interior: Vector3=building.to_global(Vector3(0,.1,4))
			check(DistrictValidator.reaches(nav.get_navigation_map(),front,interior),"enterable building interior: "+str(building.name))
			if building.name in ["Building00_medical","Building03_residential","Building06_warehouse"]:
				var stair_start: Vector3=building.to_global(Vector3(7.25,.05,7))
				var landing: Vector3=building.to_global(Vector3(7.25,3.6,-5.9))
				check(DistrictValidator.reaches(nav.get_navigation_map(),stair_start,building.to_global(Vector3(4,3.6,-5.9))),"upper floor connects: "+str(building.name))
				raid.player.global_position=stair_start; raid.player.previous_position=stair_start
				await settle()
				check(await walk_line(landing),"actual player walks stairs: "+str(building.name))
				check(await walk_line(building.to_global(Vector3(4,3.6,-5.9))),"actual player enters upper floor: "+str(building.name))
			if building.has_node("ResearchAccessLink"):
				var inside: Vector3=building.to_global(Vector3(-2,.1,-2.5))
				check(not DistrictValidator.reaches(nav.get_navigation_map(),front,inside),"research starts securely gated")
				var door: RaidDoor=building.get_children().filter(func(n): return n is RaidDoor and n.restricted)[0]
				# The explicit link is what authorizes navigation across the sealed gate.
				if door!=null:
					door.unlocked=true; door.activate(); await settle()
					check(DistrictValidator.reaches(nav.get_navigation_map(),front,inside),"unlocked research link connects")
		var atmosphere:=raid.get_node("Atmosphere") as DistrictAtmosphere
		var collision_count:=raid.find_children("*","CollisionShape3D",true,false).size()
		for preset in ["overcast_day","contaminated_dusk","foggy_morning","emergency_night"]:
			atmosphere.preset=WorldEnvironmentPreset.make(preset); atmosphere.apply()
			check(raid.get_node("WorldEnvironment").environment.fog_enabled,"atmosphere applies "+preset)
		atmosphere.contamination_stage=0; atmosphere.apply()
		check(raid.find_children("*","CollisionShape3D",true,false).size()==collision_count,"visual contamination/preset changes preserve geometry")
		atmosphere.contamination_stage=3
		for quality in 3:
			atmosphere.quality=WorldQualitySettings.make(quality); atmosphere.apply()
			check(atmosphere.local_fog.size()==2 and atmosphere.local_fog.all(func(v): return v.visible==(quality==2)),"localized fog follows quality budget")
		raid.signal_decay.enabled=false
		check(raid.get_node("WorldEnvironment").environment.fog_enabled,"disabling treatment preserves world atmosphere")
		var supplies:=state.inventory
		supplies.add("infection_suppressant",1)
		for entry in supplies.slots:
			if entry.id=="infection_suppressant":
				state.infection_remaining=1450
				check(raid.request_use(actor_id,entry.uid) and state.infection_remaining==1500,"suppressant respects district cap")
				break
		var exit: ExtractionZone=raid.extraction_zones.filter(func(z): return z.entity_id in state.assigned_extracts)[0]
		raid.player.global_position=exit.global_position; raid.player.previous_position=raid.player.global_position
		await settle()
		raid._update_extraction(actor_id,14)
		check(raid.is_active() and is_equal_approx(state.extraction_left,1),"extraction still needs continuous 15 seconds")
		raid._update_extraction(actor_id,1)
		check(raid.result.success and not app.pending_save,"district extraction journals carried loot")
		app.home(); await settle()
	app.normal_raid_scene=null
	app.requested_layout_seed=19381; app.requested_raid_seed=94731
	app.deploy(false); await settle()
	check(app.raid!=null and app.raid.get_meta("layout_seed")==19381 and app.raid.random.seed==94731,"explicit layout and raid seeds reproduce deployment")
	if app.raid!=null: app.raid.request_abandon(actor_id); app.home(); await settle()
	var before: Dictionary=app.profile.profile.duplicate(true)
	app.requested_layout_seed=1234567
	app.deploy(false)
	check(app.raid==null and app.profile.profile==before,"unapproved layout is rejected without loadout debit")
	app.free()
	await settle()
	print("DISTRICT TESTS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
