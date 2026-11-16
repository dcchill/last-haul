extends SceneTree

var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok: failures+=1; push_error(label)

func _initialize() -> void:
	var square:=PackedVector2Array([Vector2(0,0),Vector2(10,0),Vector2(10,10),Vector2(0,10)])
	for cutter in [PackedVector2Array([Vector2(4,4),Vector2(6,4),Vector2(6,6),Vector2(4,6)]),PackedVector2Array([Vector2(0,0),Vector2(2,0),Vector2(2,2),Vector2(0,2)])]:
		var pieces:=DistrictSurfaceGeometry.subtract(square,cutter)
		var area:=0.0
		for piece in pieces:
			area+=absf(DistrictSurfaceGeometry.area(piece))
			check(not Geometry2D.triangulate_polygon(piece).is_empty(),"subtracted surface triangulates")
		check(absf(area-96)<.001,"subtraction preserves exact exposed area, including interior holes")
		for i in pieces.size():
			for j in range(i+1,pieces.size()):
				for overlap in Geometry2D.intersect_polygons(pieces[i],pieces[j]): check(absf(DistrictSurfaceGeometry.area(overlap))<.0001,"pavement pieces do not overlap")
	for seed_number in [19381]:
		var scene: Node3D=load("res://scenes/raid/district/district_%d.tscn"%seed_number).instantiate()
		var author:=DistrictSceneAuthor.new(); author.scene=scene
		var footprints: Array[AABB]=[]
		for building in scene.find_children("Building*","Node3D",true,false):
			if not building.has_meta("building_bounds"): continue
			footprints.append(author.world_transform(building)*building.get_meta("building_bounds"))
			var props: Array[AABB]=[]
			for node in building.get_children():
				var bounds:=AABB()
				if node is SearchableFurniture:
					var shape: CollisionShape3D=node.get_node("CollisionShape3D")
					bounds=AABB(shape.position-shape.shape.size*.5,shape.shape.size)
				elif node is RaidLootPickup:
					for child in node.get_children():
						if child is Node3D and child.has_meta("bounds"): bounds=child.transform*child.get_meta("bounds")
				elif node is Node3D and node.has_meta("bounds"): bounds=node.get_meta("bounds")
				else: continue
				bounds=node.transform*bounds
				check(bounds.end.y<=8.51,"interior prop remains below roof")
				for previous in props:
					var overlap:=previous.intersection(bounds)
					check(not (overlap.size.x>.1 and overlap.size.y>.1 and overlap.size.z>.1),"interior props do not interpenetrate")
				props.append(bounds)
		var exterior: Array[AABB]=[]
		for node in scene.find_children("*","Node3D",true,false):
			if not node.has_meta("bounds") or not node.visible: continue
			var ancestor:=node.get_parent()
			var interior:=false
			while ancestor!=scene:
				if ancestor.has_meta("building_id"): interior=true; break
				ancestor=ancestor.get_parent()
			if interior: continue
			var bounds: AABB=author.world_transform(node)*node.get_meta("bounds")
			if bounds.position.y>1: continue
			for previous in exterior+footprints:
				var overlap: AABB=previous.intersection(bounds)
				check(not (overlap.size.x>.1 and overlap.size.y>.1 and overlap.size.z>.1),"exterior props clear other props and buildings")
			exterior.append(bounds)
		var foliage: DistrictFoliage=scene.get_node("NavigationRegion3D/AbandonedWoodland/TreeInstances")
		for transform in foliage.instance_transforms:
			for footprint in footprints:
				check(not footprint.grow(1.8).has_point(transform.origin+Vector3.UP),"tree canopy clears building")
		scene.free()
	print("DISTRICT SURFACES: ",failures," failures")
	quit(1 if failures else 0)
