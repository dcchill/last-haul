class_name DistrictValidator
extends RefCounted

static func path_length(path: PackedVector3Array) -> float:
	var length:=0.0
	for i in range(1,path.size()): length+=path[i-1].distance_to(path[i])
	return length

static func reaches(map: RID,a: Vector3,b: Vector3,tolerance := 1.5) -> bool:
	var path:=RaidNavigation.path(map,a,b)
	return not path.is_empty() and path[-1].distance_to(b)<tolerance

static func inspect(scene: Node3D,layout: DistrictLayout) -> Dictionary:
	var errors: Array[String]=layout.validate()
	var nav:=scene.get_node("NavigationRegion3D") as NavigationRegion3D
	var map:=nav.get_navigation_map()
	var pois: Array[Node3D]=[]
	var starts: Array[Marker3D]=[]
	var exits: Array[ExtractionZone]=[]
	var enterable:=0
	var buildings:=0
	var cover:=0
	var furniture:=0
	var pickups:=0
	var ids: Dictionary={}
	for node in scene.find_children("*","",true,false):
		if node is Node3D and node.has_meta("poi_id"): pois.append(node)
		if node is Marker3D and node.is_in_group("raid_spawns"): starts.append(node)
		if node is ExtractionZone: exits.append(node)
		if node is Node3D and node.has_meta("enterable"):
			buildings+=1
			if node.get_meta("enterable"): enterable+=1
		if node is Marker3D and node.is_in_group("district_cover"): cover+=1
		if node is SearchableFurniture: furniture+=1
		if node is RaidLootPickup: pickups+=1
		if node is Label3D: errors.append("floating text in playable world")
		if node is RaidEntity or node is RaidDoor or node is RaidGuard or node is ExtractionZone:
			if node.entity_id.is_empty() or ids.has(node.entity_id): errors.append("missing/duplicate entity ID: "+node.entity_id)
			ids[node.entity_id]=true
	if buildings==0 or float(enterable)/buildings<.7: errors.append("insufficient enterable buildings")
	if furniture!=128 or pickups!=96: errors.append("campus loot socket budget mismatch")
	if buildings!=4 or enterable!=4: errors.append("campus needs four enterable principal buildings")
	if pois.size()!=4 or starts.size()!=7 or exits.size()!=4: errors.append("campus landmark/insertion/extraction count")
	if nav.navigation_mesh==null or nav.navigation_mesh.get_polygon_count()==0: errors.append("empty navigation")
	var longest:=0.0
	for start in starts:
		var distances: Array[Dictionary]=[]
		for exit in exits:
			var path:=RaidNavigation.path(map,start.global_position,exit.global_position)
			if path.is_empty() or path[-1].distance_to(exit.global_position)>1.5:
				errors.append("unreachable extract: "+str(start.name)+" -> "+exit.entity_id)
			var length:=path_length(path); longest=maxf(longest,length)
			distances.append({"id":exit.entity_id,"distance":length})
		distances.sort_custom(func(a,b): return a.distance>b.distance)
		if distances.size()>=2:
			start.set_meta("assigned_extracts",[distances[0].id,distances[1].id])
			start.set_meta("route_distances",distances)
	for edge in layout.edges:
		var a:=Vector3(layout.positions[edge.x].x,.1,layout.positions[edge.x].y)
		var b:=Vector3(layout.positions[edge.y].x,.1,layout.positions[edge.y].y)
		if not reaches(map,a,b): errors.append("physical POI connection missing: "+str(edge))
	for node in pois:
		if not starts.is_empty() and not reaches(map,starts[0].global_position,node.global_position+Vector3.UP*.1): errors.append("unreachable POI: "+str(node.name))
	return {"seed":layout.seed_value,"errors":errors,"pois":pois.size(),"buildings":buildings,"enterable":enterable,"cover_positions":cover,"furniture":furniture,"loose_sockets":pickups,"longest_extraction_route_m":longest,"navigation_polygons":nav.navigation_mesh.get_polygon_count() if nav.navigation_mesh!=null else 0}
