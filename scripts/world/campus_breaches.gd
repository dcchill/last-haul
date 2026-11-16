class_name CampusBreaches
extends Node3D

## The baked floor stays fixed; links bridge only physically cleared wall apertures.
var dirty: Dictionary = {}
var revisions := 0
var opened := 0

func _ready() -> void:
	add_to_group("campus_breaches")

func mark_dirty(run: Node3D) -> void:
	if run != null and run.has_meta("wall_length"): dirty[run] = 2

func _physics_process(_delta: float) -> void:
	for run: Node3D in dirty.keys():
		dirty[run] -= 1
		if dirty[run] > 0: continue
		dirty.erase(run)
		refresh(run)

func cell_clear(run: Node3D, x: float, y: float) -> bool:
	for panel in run.get_children():
		if not panel is CampusWall: continue
		var left: float = panel.position.x - panel.dimensions.x * VoxelDestructible.CELL_SIZE * .5
		var column := floori((x-left)/VoxelDestructible.CELL_SIZE)
		if column < 0 or column >= panel.dimensions.x: continue
		var row := floori(y/VoxelDestructible.CELL_SIZE)
		for layer in panel.dimensions.z:
			if panel.cell_health[panel._index(Vector3i(column,row,layer))] > 0: return false
		return true
	return false

func refresh(run: Node3D) -> void:
	for child in run.get_children():
		if child is NavigationLink3D:
			child.enabled=false; child.queue_free()
	var excluded: Array[RID] = []
	for actor in get_parent().find_children("*", "CharacterBody3D", true, false): excluded.append(actor.get_rid())
	var map: RID = get_parent().get_node("NavigationRegion3D").get_navigation_map()
	var width: float = run.get_meta("wall_length")
	var previous := -INF
	for start in range(maxi(0,roundi(width/.25)-4)):
		var left := -width*.5 + start*.25
		var clear := true
		for column in 5:
			for row in 9:
				if not cell_clear(run,left+column*.25+.125,row*.25+.125): clear=false; break
			if not clear: break
		if not clear or left-previous < 1.25: continue
		var center := left+.625
		var a := run.to_global(Vector3(center,.1,-1.1))
		var b := run.to_global(Vector3(center,.1,1.1))
		if NavigationServer3D.map_get_closest_point(map,a).distance_to(a) > 1.1 or NavigationServer3D.map_get_closest_point(map,b).distance_to(b) > 1.1: continue
		var supported := true
		for endpoint in [a,b]:
			var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(endpoint+Vector3.UP*.4,endpoint-Vector3.UP*.35,1,excluded))
			if hit.is_empty() or absf(hit.position.y-run.global_position.y)>.2: supported=false
		if not supported: continue
		var query := PhysicsShapeQueryParameters3D.new()
		var shape := BoxShape3D.new(); shape.size=Vector3(1.15,2.15,2.1)
		query.shape=shape; query.transform=run.global_transform*Transform3D(Basis.IDENTITY,Vector3(center,1.125,0))
		query.collision_mask=1; query.exclude=excluded
		if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): continue
		var link := NavigationLink3D.new(); run.add_child(link); link.set_navigation_map(map)
		link.name="Breach_%d"%start; link.start_position=run.to_local(a); link.end_position=run.to_local(b)
		link.bidirectional=true; link.set_meta("campus_breach",true)
		previous=left; opened+=1
	NavigationServer3D.map_force_update(map)
	revisions+=1
	for npc in get_parent().find_children("*","CharacterBody3D",true,false):
		if npc is RaidGuard: npc.navigation.target_position=npc.navigation.target_position
