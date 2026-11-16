class_name DistrictTactics
extends RefCounted

## Offline ray tests measure actual obstruction; authored cover tags alone do not
## qualify a position. The report is also consumed by the developer overlay.
static func analyze(scene: Node3D,layout: DistrictLayout,map: RID,config: DistrictGenerationConfig = null) -> Dictionary:
	if config==null: config=DistrictGenerationConfig.new()
	var space:=scene.get_world_3d().direct_space_state
	var points: Array[Vector3]=[]
	var rejected:=0
	var excluded: Array[RID]=[]
	for node in scene.find_children("*","CollisionObject3D",true,false):
		if node is RaidPlayer or node is RaidGuard: excluded.append(node.get_rid())
	for marker in scene.get_tree().get_nodes_in_group("district_cover"):
		if not scene.is_ancestor_of(marker): continue
		var at: Vector3=marker.global_position
		var closest:=NavigationServer3D.map_get_closest_point(map,at)
		if closest.distance_to(at)>1:
			rejected+=1; continue
		var direction: Vector3=marker.global_basis.x
		var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*1.27,at+Vector3.UP*1.27+direction*8,1,excluded))
		if hit.is_empty(): rejected+=1; continue
		points.append(at)
	var samples: Array[Dictionary]=[]
	var longest:=0.0
	for poi in layout.positions:
		for x in range(-24,25,8):
			for z in range(-24,25,8):
				var at:=Vector3(poi.x+x,1.62,poi.y+z)
				var open:=0
				var sight:=0.0
				for angle_index in 8:
					var direction:=Vector3(cos(angle_index*TAU/8),0,sin(angle_index*TAU/8))
					var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(at,at+direction*80,1,excluded))
					var distance: float=80 if hit.is_empty() else at.distance_to(hit.position)
					if distance>25: open+=1
					sight=maxf(sight,distance)
				longest=maxf(longest,sight)
				samples.append({"x":at.x,"z":at.z,"exposure":float(open)/8,"sightline_m":sight})
	var errors: Array[String]=[]
	var maximum_gap:=0.0
	var maximum_gap_at:=Vector3.ZERO
	for edge in layout.edges:
		var a:=Vector3(layout.positions[edge.x].x,.1,layout.positions[edge.x].y)
		var b:=Vector3(layout.positions[edge.y].x,.1,layout.positions[edge.y].y)
		var path:=RaidNavigation.path(map,a,b)
		for segment in range(1,path.size()):
			var count:=maxi(1,ceili(path[segment-1].distance_to(path[segment])/5))
			for index in count:
				var at:=path[segment-1].lerp(path[segment],float(index)/count)
				var distance:=INF
				for point in points: distance=minf(distance,Vector2(at.x,at.z).distance_to(Vector2(point.x,point.z)))
				if distance>maximum_gap: maximum_gap=distance; maximum_gap_at=at
	if points.size()<60: errors.append("insufficient physically verified crouch cover")
	if maximum_gap>config.maximum_exposure_gap: errors.append("mandatory traversal exceeds configured distance from useful cover: %.1fm"%maximum_gap)
	var serialized: Array[Dictionary]=[]
	for at in points: serialized.append({"x":at.x,"y":at.y,"z":at.z})
	return {"valid_cover":serialized,"rejected_cover_anchors":rejected,"exposure_samples":samples,"maximum_cover_distance_m":maximum_gap,"maximum_cover_gap_at":maximum_gap_at,"longest_sampled_sightline_m":longest,"errors":errors}
