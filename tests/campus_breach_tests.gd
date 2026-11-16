extends SceneTree

var failures := 0
var checks := 0
var scene: Node3D
var run: Node3D
var nav: NavigationRegion3D
var manager: CampusBreaches
var map: RID

func _initialize() -> void: call_deferred("test")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error("FAIL: "+label)
func settle() -> void:
	for i in 6: await physics_frame
func box(parent: Node3D,at: Vector3,size: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new(); parent.add_child(body); body.position=at
	var collision:=CollisionShape3D.new(); var shape:=BoxShape3D.new(); shape.size=size; collision.shape=shape; body.add_child(collision)
	return body
func reset() -> void:
	for child in run.get_children():
		if child is CampusWall: child.reset_cells(); child._rebuild()
	await settle()
func clear_cells(left: float,width: float,bottom := 0.0,height := 2.25) -> void:
	for panel in run.get_children():
		if not panel is CampusWall: continue
		for x in panel.dimensions.x:
			var at: float=panel.position.x-panel.dimensions.x*.125+x*.25+.125
			if at<left or at>=left+width: continue
			for y in range(roundi(bottom/.25),roundi((bottom+height)/.25)):
				panel.cell_health[panel._index(Vector3i(x,y,0))]=0
		panel._rebuild()
	await settle()
func connected() -> bool:
	return DistrictValidator.reaches(map,Vector3(0,.1,-3),Vector3(0,.1,3),.8)

func test() -> void:
	scene=Node3D.new(); root.add_child(scene)
	nav=RaidNavigationRegion.new(); nav.name="NavigationRegion3D"; scene.add_child(nav)
	box(nav,Vector3(0,-.15,0),Vector3(16,.3,12))
	box(nav,Vector3(-6,1.75,0),Vector3(4,3.5,.25)); box(nav,Vector3(6,1.75,0),Vector3(4,3.5,.25))
	run=Node3D.new(); nav.add_child(run); run.set_meta("wall_length",8.0)
	for x in [-2,2]:
		var panel:=CampusWall.new(); panel.dimensions=Vector3i(16,14,1); panel.position=Vector3(x,1.75,0)
		var collision:=CollisionShape3D.new(); collision.name="CollisionShape3D"; panel.add_child(collision)
		var visual:=MeshInstance3D.new(); visual.name="MeshInstance3D"; panel.add_child(visual); run.add_child(panel)
	manager=CampusBreaches.new(); scene.add_child(manager)
	map=NavigationServer3D.map_create(); NavigationServer3D.map_set_active(map,true); NavigationServer3D.map_set_use_async_iterations(map,false); nav.set_navigation_map(map)
	var mesh:=NavigationMesh.new(); mesh.geometry_parsed_geometry_type=NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.cell_size=.25; mesh.cell_height=.25; mesh.agent_radius=.5; mesh.agent_height=2; mesh.agent_max_climb=.4
	nav.navigation_mesh=mesh; await settle(); nav.bake_navigation_mesh(false); NavigationServer3D.map_force_update(map); await settle()
	check(not connected(),"intact wall separates navigation")
	await clear_cells(1.5,1.0); check(not connected(),"one-meter firing hole is not a route")
	await reset(); await clear_cells(1.5,1.25,1.0,2.25); check(not connected(),"elevated window is not a grounded route")
	await reset(); var obstruction:=box(nav,Vector3(2.125,1.1,.7),Vector3(1.5,2.2,.7))
	await clear_cells(1.5,1.25); check(not connected(),"furniture blocks an otherwise sufficient opening")
	obstruction.free(); manager.mark_dirty(run); await settle(); check(connected(),"off-center grounded opening creates bidirectional navigation")
	var player: RaidPlayer=load("res://scenes/player/player.tscn").instantiate(); scene.add_child(player); player.set_physics_process(false)
	player.global_position=Vector3(2.125,.05,-2)
	for i in 45: player.drive_movement(Vector2(0,1),false,false,.05)
	check(player.global_position.z>1,"actual player walks through off-center breach")
	player.free()
	var npc: RaidGuard=load("res://scenes/npcs/guard.tscn").instantiate(); scene.add_child(npc); npc.set_process(false)
	npc.navigation.set_navigation_map(map); npc.global_position=Vector3(2.125,.05,-2); npc.patrol_points=PackedVector3Array([Vector3(2.125,.05,2)])
	var target:=Node3D.new(); scene.add_child(target); target.position=Vector3(1000,0,1000)
	for i in 180:
		npc.authority_tick(.05,target,Ballistics.new())
		if i%5==0: await physics_frame
	check(npc.global_position.z>1,"actual NPC follows breach link")
	npc.free(); target.free()
	await reset(); await clear_cells(-.75,1.5); check(connected(),"opening spanning adjacent panels is navigable")
	await clear_cells(1.5,1.5); check(run.get_children().filter(func(n): return n is NavigationLink3D and n.enabled).size()>=2,"independent simultaneous openings")
	await reset(); check(not connected(),"fresh raid wall state closes breach routes")
	var fixture:=Node3D.new(); var floor_node:=Node3D.new(); fixture.add_child(floor_node)
	for i in 6:
		var room:=Node3D.new(); floor_node.add_child(room); room.set_meta("room_bounds",AABB(Vector3.ZERO,Vector3(8,3.6,8)))
		room.set_meta("room_purpose","fixture "+str(i)); room.set_meta("room_role","store" if i%2 else "clinical"); room.set_meta("entrance_points",PackedVector3Array([Vector3.ZERO]))
	check(CampusValidator.plan_errors(fixture).any(func(e): return "checkerboard" in e),"reject unrelated repeated cell plan")
	floor_node.get_child(0).remove_meta("entrance_points")
	check(CampusValidator.plan_errors(fixture).any(func(e): return "no declared entrance" in e),"reject missing room access")
	fixture.free(); scene.free(); NavigationServer3D.free_rid(map)
	print("CAMPUS BREACH TESTS: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
