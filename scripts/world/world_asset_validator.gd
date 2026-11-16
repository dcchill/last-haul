class_name WorldAssetValidator
extends RefCounted

static func island_root(parents: Array[int],index: int) -> int:
	var current:=index
	while parents[current]!=current:
		parents[current]=parents[parents[current]]
		current=parents[current]
	return current

static func inspect(asset: Node3D,definition: WorldAssetDefinition) -> Dictionary:
	var errors: Array[String]=[]
	var triangles:=0
	var bounds:=AABB()
	var first:=true
	var collisions:=0
	var materials: Array[String]=[]
	var welded: Dictionary={}
	var parents: Array[int]=[]
	for node in asset.find_children("*","",true,false):
		if node is CollisionShape3D:
			if node.shape==null or node.disabled: errors.append("missing/disabled collision shape")
			else: collisions+=1
		if not node is MeshInstance3D: continue
		if node.mesh==null: errors.append("missing mesh"); continue
		var transform: Transform3D=asset.global_transform.affine_inverse()*node.global_transform
		var rect: AABB=transform*node.mesh.get_aabb()
		bounds=rect if first else bounds.merge(rect)
		first=false
		for surface in node.mesh.get_surface_count():
			var arrays: Array=node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			triangles+=indices.size()/3 if not indices.is_empty() else vertices.size()/3
			var vertex_ids: Array[int]=[]
			for vertex in vertices:
				if not vertex.is_finite(): errors.append("nonfinite vertex"); break
				var position: Vector3=(transform*vertex).snapped(Vector3.ONE*.0001)
				if not welded.has(position): welded[position]=parents.size(); parents.append(parents.size())
				vertex_ids.append(welded[position])
			if indices.is_empty():
				for i in vertices.size(): indices.append(i)
			for i in range(0,indices.size(),3):
				if i+2>=indices.size() or indices[i]<0 or indices[i+1]<0 or indices[i+2]<0 or indices[i]>=vertex_ids.size() or indices[i+1]>=vertex_ids.size() or indices[i+2]>=vertex_ids.size():
					errors.append("invalid triangle indices"); break
				var a:=island_root(parents,vertex_ids[indices[i]])
				for j in [1,2]: parents[island_root(parents,vertex_ids[indices[i+j]])]=a
				if (vertices[indices[i+1]]-vertices[indices[i]]).cross(vertices[indices[i+2]]-vertices[indices[i]]).length_squared()<.0000000001:
					errors.append("degenerate triangle"); break
			var material: Material=node.mesh.surface_get_material(surface)
			if material==null: errors.append("missing material")
			elif not materials.has(material.resource_name): materials.append(material.resource_name)
	if first or bounds.size.x<=0 or bounds.size.y<=0 or bounds.size.z<=0: errors.append("invalid bounds")
	for axis in 3:
		if absf(bounds.size[axis]-definition.expected_size[axis])>definition.dimension_tolerance: errors.append("dimension outside authored tolerance: "+str(axis))
	if bounds.position.y<-.02: errors.append("below ground origin")
	if triangles<=0 or triangles>definition.triangle_budget: errors.append("triangle budget")
	if not asset.scale.is_equal_approx(Vector3.ONE) or not asset.rotation.is_zero_approx(): errors.append("wrapper must have normalized scale/orientation")
	if definition.collision_required and collisions==0: errors.append("no collision")
	for component in definition.required_components:
		if not component in asset.get_meta("components",[]): errors.append("missing authored component: "+component)
	var islands: Dictionary={}
	for index in parents.size(): islands[island_root(parents,index)]=true
	return {"id":definition.id,"triangles":triangles,"bounds":[bounds.size.x,bounds.size.y,bounds.size.z],"collision_shapes":collisions,"materials":materials,"welded_geometry_islands":islands.size(),"connectivity_review":"Separated trims, intersecting solids and detached damage need rendered review; island count is diagnostic, not artistic approval.","errors":errors,"visual_review":"requires rendered inspection"}
