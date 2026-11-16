class_name CampusValidator
extends RefCounted

static func rooms(scene: Node) -> Array[Node]:
	return scene.find_children("*","Node3D",true,false).filter(func(n): return n.has_meta("room_bounds"))

static func plan_errors(scene: Node3D) -> Array[String]:
	var errors: Array[String]=[]
	var modules: Dictionary={}
	for room in rooms(scene):
		var bounds: AABB=room.get_meta("room_bounds")
		var title: String=room.get_meta("room_purpose","")
		if title.is_empty() or not room.has_meta("room_role"): errors.append(str(room.name)+": missing functional purpose")
		if minf(bounds.size.x,bounds.size.z)<3 or bounds.size.x*bounds.size.z<12: errors.append(title+": implausible usable room dimensions")
		if not room.has_meta("entrance_points") or room.get_meta("entrance_points").is_empty(): errors.append(title+": no declared entrance")
		var key:="%s/%.1f/%.1f"%[room.get_parent().get_instance_id(),bounds.size.x,bounds.size.z]
		if not modules.has(key): modules[key]=[]
		modules[key].append(room.get_meta("room_role",""))
	for key: String in modules:
		var roles: Array=modules[key]
		if roles.size()>=6 and roles.any(func(r): return r!=roles[0]): errors.append("checkerboard: repeated cells across unrelated functions: "+key)
	return errors

static func inspect(scene: Node3D) -> Dictionary:
	var errors:=plan_errors(scene)
	var prop_count:=0
	var nav: NavigationRegion3D=scene.get_node("NavigationRegion3D")
	var map:=nav.get_navigation_map()
	var space:=scene.get_world_3d().direct_space_state
	var excluded: Array[RID]=[]
	for actor in scene.find_children("*","CharacterBody3D",true,false): excluded.append(actor.get_rid())
	for room in rooms(scene):
		var title: String=room.get_meta("room_purpose")
		var bounds: AABB=room.get_meta("room_bounds")
		var props: Array[Dictionary]=[]
		for prop in room.get_children():
			if not prop is Node3D: continue
			var local:=AABB()
			if prop is SearchableFurniture:
				var collision: CollisionShape3D=prop.get_node("CollisionShape3D")
				local=AABB(collision.position-collision.shape.size*.5,collision.shape.size)
			elif prop.has_meta("campus_equipment") and prop.has_meta("bounds"): local=prop.get_meta("bounds")
			else: continue
			var box: AABB=prop.transform*local
			prop_count+=1
			if not bounds.grow(.15).encloses(box): errors.append(title+": equipment outside room: "+str(prop.name))
			for previous in props:
				var other: Node3D=previous.node
				if prop.get_meta("supported_by","")==other.get_meta("campus_equipment","-") or other.get_meta("supported_by","")==prop.get_meta("campus_equipment","-"): continue
				var overlap:=box.intersection(previous.bounds)
				if overlap.size.x>.08 and overlap.size.y>.08 and overlap.size.z>.08: errors.append(title+": overlapping equipment: "+str(prop.name)+" / "+str(other.name))
			props.append({"node":prop,"bounds":box})
		var entry: Vector3=room.to_global(room.get_meta("entry_local"))
		var center: Vector3=room.to_global(Vector3(0,.1,0))
		if room.get_meta("enclosed",true):
			var opening: Vector3=room.get_meta("entrance_points")[0]
			var along_x:=minf(absf(opening.z-bounds.position.z),absf(opening.z-bounds.end.z))<.3
			var query:=PhysicsShapeQueryParameters3D.new(); var shape:=BoxShape3D.new()
			shape.size=Vector3(1.2,2.15,.4); query.shape=shape
			query.transform=room.global_transform*Transform3D(Basis(Vector3.UP,0 if along_x else PI*.5),opening+Vector3.UP*1.1)
			query.collision_mask=1; query.exclude=excluded
			var door_excluded: Array[RID]=excluded.duplicate()
			for door in scene.find_children("*","StaticBody3D",true,false):
				if door is RaidDoor: door_excluded.append(door.get_rid())
			query.exclude=door_excluded
			if not space.intersect_shape(query,1).is_empty(): errors.append(title+": declared doorway blocked by geometry or equipment")
		if not DistrictValidator.reaches(map,entry,center,.8): errors.append(title+": entry cannot reach working area")
		var anchor:=Vector3(0,.1,70)
		if center.y<0:
			for stair: Dictionary in scene.get_meta("campus_stairs"):
				if stair.restricted: anchor=stair.end; break
		if not DistrictValidator.reaches(map,anchor,center,.8): errors.append(title+": disconnected from floor circulation")
		var floor_hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(center+Vector3.UP*.4,center-Vector3.UP*.4,1,excluded))
		if floor_hit.is_empty(): errors.append(title+": unsupported accessible floor")
	for node in scene.find_children("*","Marker3D",true,false):
		if not node.has_meta("route_points"): continue
		var points: PackedVector3Array=node.get_meta("route_points")
		for i in range(1,points.size()):
			if not DistrictValidator.reaches(map,node.to_global(points[i-1]),node.to_global(points[i]),.8): errors.append(str(node.name)+": broken circulation")
			var a: Vector3=node.to_global(points[i-1]); var b: Vector3=node.to_global(points[i]); var delta:=b-a
			var samples:=maxi(1,ceili(Vector2(delta.x,delta.z).length()))
			for sample in range(samples+1):
				var query:=PhysicsShapeQueryParameters3D.new(); var shape:=BoxShape3D.new()
				shape.size=Vector3(float(node.get_meta("route_width"))-.1,2.1,.2); query.shape=shape
				query.transform=Transform3D(Basis(Vector3.UP,atan2(-delta.x,-delta.z)),a.lerp(b,float(sample)/samples)+Vector3.UP*1.08)
				query.collision_mask=1; query.exclude=excluded
				if not space.intersect_shape(query,1).is_empty(): errors.append(str(node.name)+": inadequate reserved route width at "+str(query.transform.origin)); break
	return {"rooms":rooms(scene).size(),"props_checked":prop_count,"errors":errors}


