extends SceneTree

var checks:=0
var failures:=0
var app: Node
var raid: RaidAuthority
var state: RaidParticipant
var actor_id: String
var slots: Array[MedTacVariantSlot]=[]
var routes: Array[MedTacRouteBlock]=[]

func _initialize() -> void: call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL: "+description)

func settle(frames:=3) -> void:
	for frame in range(frames): await physics_frame

func face(target: RaidEntity) -> void:
	var at:=target.global_position+Vector3(0,0,1.8)
	if target is RaidLootPickup: at.y=0.04 if target.global_position.y>=0 else -9.96
	raid.player.global_position=at
	raid.player.previous_position=at
	var offset:=target.global_position+target.interaction_offset-raid.player.eye_position()
	raid.player.rotation.y=atan2(-offset.x,-offset.z)
	raid.player.look_pitch=atan2(offset.y,Vector2(offset.x,offset.z).length())
	await settle()

func clear_capsule(at: Vector3, exclude: Array[RID]=[]) -> bool:
	var query:=PhysicsShapeQueryParameters3D.new()
	var shape:=BoxShape3D.new()
	shape.size=Vector3(.6,1.8,.6)
	query.shape=shape
	query.transform=Transform3D(Basis.IDENTITY,at+Vector3.UP*.95)
	var omitted: Array[RID]=exclude.duplicate()
	for npc in raid.npcs: omitted.append(npc.get_rid())
	query.exclude=omitted
	return raid.get_world_3d().direct_space_state.intersect_shape(query).is_empty()

func run() -> void:
	app=load("res://scenes/main.tscn").instantiate()
	app.selected_map=load("res://resources/maps/medtac_labs.tres")
	app.test_profile_path="res://.godot/medtac-detail-"+ProfileStore._new_id()+".json"
	root.add_child(app)
	await settle()
	app.deploy(false)
	await settle(6)
	raid=app.raid
	raid.set_physics_process(false)
	raid.player.set_physics_process(false)
	actor_id=app.profile.profile.player_id
	state=raid.participants[actor_id]
	for npc in raid.npcs: npc.state=RaidGuard.State.DEAD
	var furniture: Array[SearchableFurniture]=[]
	var pickups: Array[RaidLootPickup]=[]
	var breakables: Array[MedTacBreakable]=[]
	var rooms:=0
	var signs:=0
	var fixtures:=0
	for node in raid.find_children("*","",true,false):
		check(not node is Label3D,"playable map contains no floating text")
		if node.has_meta("room_purpose"): rooms+=1
		if node is SearchableFurniture: furniture.append(node)
		if node is RaidLootPickup: pickups.append(node)
		if node is MedTacVariantSlot: slots.append(node)
		if node is MedTacRouteBlock: routes.append(node)
		if node is MedTacBreakable:
			breakables.append(node)
			if node.kind=="light": fixtures+=1
		if node is MeshInstance3D and node.has_meta("sign_text"):
			signs+=1
			check(node.material_override.albedo_texture!=null,"physical sign has printed lettering")
	check(rooms==79,"seventy-nine named rooms and suites")
	check(furniture.size()==128 and pickups.size()==64,"128 searchable sources and 64 loose sockets")
	check(pickups.filter(func(p): return p.available).size()==32,"exactly 32 loose sources active")
	check(slots.size()==24 and routes.size()==6,"24 cover slots and six secondary passages")
	var profiles: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/medtac/loot_profiles.json"))
	var weapon_cases:=0
	var ammo_cases:=0
	for source in furniture:
		check(source.has_node("MovingPanel"),"each searchable furnishing has a visible opening component")
		check(profiles.has(source.loot_profile),"container has an explicit loot profile")
		var allowed: Array=[]
		for entry: Array in profiles[source.loot_profile]: allowed.append(entry[0])
		for entry: Dictionary in source.loot_table.entries:
			check(entry.id in allowed,"container rolls only its own profile")
			var definition: ItemDef=app.catalog.items[entry.id]
			if definition.kind in ["weapon","attachment"]: check(source.loot_profile=="weapons","weapons and attachments stay in weapon cases")
			if definition.kind in ["ammo","magazine"]: check(source.loot_profile=="ammo","ammunition and magazines stay in ammunition boxes")
			if definition.heal_amount>0 or definition.infection_seconds>0: check(source.loot_profile=="medical","medicine stays in medical bags and medical storage")
		for identity: String in source.guaranteed_items: check(identity in allowed,"guaranteed loot respects its container")
		if source.loot_profile=="weapons": weapon_cases+=1
		if source.loot_profile=="ammo": ammo_cases+=1
	check(weapon_cases==8 and ammo_cases==12,"eight weapon cases and twelve ammunition boxes")
	for pickup in pickups: check(app.catalog.items[pickup.item_id].kind not in ["ammo","weapon","attachment","magazine"],"authored loose loot does not bypass dedicated weapon and ammunition containers")
	check(signs>=100 and fixtures>=100,"physical wayfinding and extensive room lighting")
	var recipes: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/medtac/prop_recipes.json"))
	check(recipes.size()>=49,"at least forty furnishings plus item-specific loose models")
	for identity: String in recipes:
		var prop: Node3D=load("res://scenes/props/medtac/detail/"+identity+".tscn").instantiate()
		var mesh: Mesh=prop.get_node("Mesh").mesh
		check(mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV].size()>0,"UVs authored for "+identity)
		prop.free()
	await furniture_checks(furniture)
	await pickup_checks(pickups)
	await breakable_checks(breakables)
	await variant_checks()
	await seed_checks()
	app.free()
	await settle(4)
	print("MEDTAC DETAIL: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func furniture_checks(furniture: Array[SearchableFurniture]) -> void:
	var source:=furniture.filter(func(f): return f.entity_id=="security-office-cabinet")[0] as SearchableFurniture
	await face(source)
	check(raid.request_interact(actor_id,source.entity_id),"furniture component resolves to authoritative loot source")
	check(source.opened,"search opens furniture")
	await settle(24)
	var panel:=source.get_node("MovingPanel") as Node3D
	check(absf(panel.rotation.y)>1 or panel.position.z>.5,"drawer or door actually moves")
	var transform:=panel.transform
	source.open_furniture()
	await settle(4)
	check(panel.transform.is_equal_approx(transform),"repeated search does not restart or duplicate opening")
	state.opened_container=""
	for container in furniture:
		var position:=container.global_position+Vector3(0,0,1.8)
		position.y=.04 if container.global_position.y>=0 else -9.96
		check(clear_capsule(position,[raid.player.get_rid()]),"search approach is clear: "+container.entity_id)

func pickup_checks(pickups: Array[RaidLootPickup]) -> void:
	for item in pickups:
		if not item.available: continue
		await face(item)
		check(clear_capsule(raid.player.global_position,[raid.player.get_rid()]),"loose pickup approach is clear: "+item.entity_id)
		check(raid._container_reachable(actor_id,item.entity_id),"loose pickup has an unobstructed interaction: "+item.entity_id)
	var pickup:=pickups.filter(func(p): return p.available and p.global_position.y>0 and p.item_id=="medkit")[0] as RaidLootPickup
	await face(pickup)
	var roots: Array[RaidInventory]=[state.inventory,state.pockets]
	roots.append_array(state.equipment.roots())
	var saved: Dictionary={}
	for carried in roots:
		for grid in carried.all_grids():
			saved[grid]=grid.snapshot()
			for i in range(1000):
				if not grid.add("salvage",20): break
	var source: RaidInventory=raid.containers[pickup.entity_id]
	var identity: String=source.slots[0].uid
	check(not raid.request_pickup(actor_id,pickup.entity_id) and pickup.available and source.slots.size()==1,"full inventory preserves physical pickup")
	for grid: RaidInventory in saved: grid.slots.assign(saved[grid])
	check(raid.request_pickup(actor_id,pickup.entity_id),"loose item transfers directly without a search panel")
	check(not pickup.available and not pickup.visible and source.slots.is_empty(),"successful pickup removes only its world representation")
	check(not state.entry_for(identity).is_empty(),"pickup retains original physical item identity")
	check(not raid.request_pickup(actor_id,pickup.entity_id),"repeated pickup cannot duplicate an item")
	var hidden:=pickups.filter(func(p): return not p.available and p!=pickup)[0] as RaidLootPickup
	check(not raid.request_pickup(actor_id,hidden.entity_id),"inactive socket cannot grant loot")

func breakable_checks(breakables: Array[MedTacBreakable]) -> void:
	var glass:=breakables.filter(func(p): return p.kind=="glass")[0] as MedTacBreakable
	var fixture:=breakables.filter(func(p): return p.kind=="light" and not p.protected)[0] as MedTacBreakable
	var emergency:=breakables.filter(func(p): return p.kind=="light" and p.protected)[0] as MedTacBreakable
	raid._apply_damage(glass,300)
	raid._apply_damage(fixture,300)
	raid._apply_damage(emergency,10000)
	await settle()
	check(glass.broken and glass.get_node("CollisionShape3D").disabled,"glass loses its physical pane")
	if not glass.navigation_link.is_empty(): check(glass.get_node(glass.navigation_link).enabled,"broken exterior glass enables its authored traversal")
	check(fixture.broken and not fixture.light_enabled and not fixture.get_node("Light").visible,"shooting a fixture removes its light")
	check(not emergency.broken and emergency.get_node("Light").visible,"essential emergency fixture survives damage")
	check(not raid.entities["research-lab-entrance"].unlocked and not raid.entities["research-maintenance-entrance"].unlocked,"breakables cannot authorize restricted access")
	var route:=routes[0]
	route.set_blocked(true)
	raid._apply_damage(route,1000)
	await settle()
	check(route.broken and route.get_node(route.navigation_link).enabled,"destroyed weak barricade opens its secondary traversal link")

func variant_checks() -> void:
	for theme in ["exterior","clinical","laboratory","warehouse","basement"]:
		for variant in range(3):
			var scene: Node3D=load("res://scenes/raid/medtac/variants/"+theme+"_%d.tscn"%variant).instantiate()
			root.add_child(scene)
			scene.position=Vector3(450,0,450)
			await settle()
			var map: RID=scene.get_node("NavigationRegion3D").get_navigation_map()
			for axis in [Vector3.RIGHT,Vector3.FORWARD]:
				var path:=RaidNavigation.path(map,scene.position-axis*3,scene.position+axis*3)
				check(not path.is_empty() and path[-1].distance_to(scene.position+axis*3)<1,"baked variant crosses its reserved portals")
				for offset in [-3,-1,0,1,3]: check(clear_capsule(scene.position+axis*offset),"variant keeps the central walking lanes physically clear")
			scene.free()
			await settle(1)

func seed_checks() -> void:
	var controller:=raid.get_node("Dressing") as MedTacDressing
	var signatures: Dictionary={}
	var nav: RID=raid.get_node("NavigationRegion3D").get_navigation_map()
	for seed_value in range(200):
		controller.configure(seed_value)
		await settle(2)
		var signature: Array=[]
		for slot in slots:
			signature.append(slot.selected)
			check(slot.selected>=0 and slot.selected<3 and slot.active!=null,"seed selects a complete cover arrangement")
			check(clear_capsule(slot.global_position,[raid.player.get_rid()]),"seed preserves central cover-slot clearance "+slot.slot_id)
		signatures[str(signature)]=true
		check(controller.selected_routes.size()<=2,"at most two secondary passages blocked")
		for marker in raid.spawn_markers:
			for zone in raid.extraction_zones:
				if zone.entity_id not in marker.get_meta("assigned_extracts"): continue
				var path:=RaidNavigation.path(nav,marker.global_position,zone.global_position)
				check(not path.is_empty() and path[-1].distance_to(zone.global_position)<3,"seed retains both assigned extracts from every spawn")
		var locked:=RaidNavigation.path(nav,Vector3(-32,0,-40),Vector3(-32,-10,-92))
		check(locked.is_empty() or locked[-1].distance_to(Vector3(-32,-10,-92))>3,"seed never bypasses basement access")
		if seed_value%50==0: print("MEDTAC SEED AUDIT: ",seed_value,"/200")
	check(signatures.size()>190,"different raids materially vary cover arrangements")
	controller.configure(37)
	var before: Array=[]
	for slot in slots: before.append(slot.selected)
	controller.configure(38)
	controller.configure(37)
	var after: Array=[]
	for slot in slots: after.append(slot.selected)
	check(before==after,"same seed reproduces the same cover selection")
	raid.random.seed=37
	raid._build_loot()
	var cards_before:=raid.keycard_spawned
	controller.configure(1001)
	raid.random.seed=37
	raid._build_loot()
	check(cards_before==raid.keycard_spawned,"cover randomization cannot alter keycard rarity")
