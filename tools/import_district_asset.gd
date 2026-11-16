extends SceneTree

## Read GLB/glTF through Godot's native parser into a reviewable static wrapper.
## godot --headless --path . --script res://tools/import_district_asset.gd -- source.glb id
func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2 or not args[0].get_extension().to_lower() in ["glb","gltf"] or not args[1].is_valid_identifier():
		push_error("Expected imported res:// GLB/glTF path and a unique asset_id"); quit(1); return
	var identity: String=args[1]
	var destination:="res://scenes/props/district/"+identity+".tscn"
	if FileAccess.file_exists(destination): push_error("Asset already exists; refusing to overwrite authored content"); quit(1); return
	var document:=GLTFDocument.new(); var state:=GLTFState.new()
	if document.append_from_file(args[0],state)!=OK: push_error("Cannot parse GLB/glTF source"); quit(1); return
	var wrapper:=Node3D.new(); wrapper.name=identity.to_pascal_case()
	var source:=document.generate_scene(state) as Node3D
	wrapper.add_child(source); source.owner=wrapper
	for child in source.find_children("*","",true,false): child.owner=wrapper
	var bounds:=AABB(); var first:=true; var triangles:=0
	var body:=DecorativeProp.new(); body.material=preload("res://resources/materials/steel.tres"); body.name="Collision"
	wrapper.add_child(body); body.owner=wrapper
	for node in source.find_children("*","MeshInstance3D",true,false):
		if node.mesh==null: continue
		var transform: Transform3D=node.transform
		var ancestor: Node=node.get_parent()
		while ancestor!=wrapper:
			transform=(ancestor as Node3D).transform*transform
			ancestor=ancestor.get_parent()
		var rect: AABB=transform*node.mesh.get_aabb()
		bounds=rect if first else bounds.merge(rect); first=false
		var shape:=CollisionShape3D.new(); shape.shape=node.mesh.create_trimesh_shape(); shape.transform=transform
		body.add_child(shape); shape.owner=wrapper
		for surface in node.mesh.get_surface_count():
			var arrays: Array=node.mesh.surface_get_arrays(surface)
			triangles+=arrays[Mesh.ARRAY_INDEX].size()/3 if arrays[Mesh.ARRAY_INDEX]!=null and not arrays[Mesh.ARRAY_INDEX].is_empty() else arrays[Mesh.ARRAY_VERTEX].size()/3
	if first: wrapper.free(); push_error("Imported asset contains no mesh"); quit(1); return
	# Artist export must already use meters and -Z forward. Ground/recenter only.
	var shift:=-Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
	source.position+=shift; body.position+=shift
	wrapper.set_meta("bounds",AABB(bounds.position+shift,bounds.size)); wrapper.set_meta("asset_id",identity)
	wrapper.set_meta("components",["imported_mesh"])
	var definition:=WorldAssetDefinition.new(); definition.id=identity; definition.scene_path=destination
	definition.expected_size=bounds.size; definition.source_file=args[0]; definition.provenance="Artist supplied; record author and license before distribution"
	definition.required_components=["imported_mesh"]
	if triangles>definition.triangle_budget: wrapper.free(); push_error("Imported mesh exceeds triangle budget; author an appropriate LOD first"); quit(1); return
	var output:=PackedScene.new(); output.pack(wrapper)
	var error:=ResourceSaver.save(output,destination)
	if error==OK: error=ResourceSaver.save(definition,"res://resources/district/assets/"+identity+".tres")
	wrapper.free()
	print("IMPORTED ASSET: ",identity," / ",triangles," triangles. Run the asset reviewer with its definition before placement.")
	quit(0 if error==OK else 1)
