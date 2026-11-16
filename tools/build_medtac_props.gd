extends SceneTree

func _initialize() -> void: call_deferred("build")

func build() -> void:
	var recipes: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/medtac/prop_recipes.json"))
	DirAccess.make_dir_recursive_absolute("res://scenes/props/medtac/detail")
	DirAccess.make_dir_recursive_absolute("res://resources/medtac/meshes")
	var material:=StandardMaterial3D.new()
	material.albedo_texture=load("res://assets/medtac/materials.png")
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness=0.85
	ResourceSaver.save(material,"res://resources/medtac/textured.tres")
	var normals: Array[Vector3]=[Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]
	var faces: Array=[[1,3,7,5],[4,6,2,0],[2,6,7,3],[4,0,1,5],[5,7,6,4],[0,2,3,1]]
	var uv: Array[Vector2]=[Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]
	for identity: String in recipes:
		var node:=Node3D.new()
		node.name=identity.to_pascal_case()
		var builder:=SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		var bounds:=AABB()
		var first:=true
		for part: Array in recipes[identity]:
			var at:=Vector3(part[0],part[1],part[2])
			var size:=Vector3(part[3],part[4],part[5])
			var tile:=int(part[6])
			var rect:=AABB(at-size*.5,size)
			bounds=rect if first else bounds.merge(rect)
			first=false
			var vertices: Array[Vector3]=[]
			for i in range(8): vertices.append(at+Vector3(size.x*.5 if i&1 else -size.x*.5,size.y*.5 if i&2 else -size.y*.5,size.z*.5 if i&4 else -size.z*.5))
			for face in range(6):
				for corner in [0,2,1,0,3,2]:
					builder.set_normal(normals[face])
					builder.set_uv((Vector2(tile%8,tile/8)+Vector2(.025,.025)+uv[corner]*.95)/8.0)
					builder.add_vertex(vertices[faces[face][corner]])
		builder.index()
		builder.set_material(material)
		var mesh:=WorldMeshKit.remove_coplanar_overdraw(builder.commit())
		ResourceSaver.save(mesh,"res://resources/medtac/meshes/"+identity+".res")
		var visual:=MeshInstance3D.new()
		visual.name="Mesh"
		visual.mesh=mesh
		visual.visibility_range_end=100
		node.add_child(visual)
		visual.owner=node
		if not identity.begins_with("pickup_"):
			var body:=DecorativeProp.new()
			body.name="Collision"
			body.material=preload("res://resources/materials/steel.tres")
			node.add_child(body)
			body.owner=node
			for part: Array in recipes[identity]:
				if not bool(part[7]): continue
				var shape:=BoxShape3D.new()
				shape.size=Vector3(part[3],part[4],part[5])
				var collision:=CollisionShape3D.new()
				collision.shape=shape
				collision.position=Vector3(part[0],part[1],part[2])
				body.add_child(collision)
				collision.owner=node
		node.set_meta("bounds",bounds)
		node.set_meta("medtac_prop_id",identity)
		var packed:=PackedScene.new()
		packed.pack(node)
		ResourceSaver.save(packed,"res://scenes/props/medtac/detail/"+identity+".tscn")
		node.free()
	print("MEDTAC PROPS: ",recipes.size()," original textured models")
	quit()
