extends SceneTree

var failures:=0
var inspected:=0

func inspect(path: String) -> void:
	var node: Node3D=load(path).instantiate()
	var mesh: Mesh=node.get_node("Mesh").mesh
	var groups: Dictionary={}
	for surface in mesh.get_surface_count():
		var arrays:=mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		for i in range(0,indices.size(),3):
			var a:=vertices[indices[i]]; var b:=vertices[indices[i+1]]; var c:=vertices[indices[i+2]]
			var normal:=(c-a).cross(b-a).normalized()
			var key:=str(normal.snapped(Vector3.ONE*.0001))+":"+str(snappedf(normal.dot(a),.0001))
			var axis:=normal.abs().max_axis_index(); var u: int=(axis+1)%3; var v: int=(axis+2)%3
			var triangle:=PackedVector2Array([Vector2(a[u],a[v]),Vector2(b[u],b[v]),Vector2(c[u],c[v])])
			if not groups.has(key): groups[key]=[]
			for previous in groups[key]:
				for overlap in Geometry2D.intersect_polygons(previous,triangle):
					if absf(DistrictSurfaceGeometry.area(overlap))>.0001:
						failures+=1; push_error("Coplanar overlapping faces: "+path)
			groups[key].append(triangle)
	inspected+=1; node.free()

func _initialize() -> void:
	for directory in ["res://scenes/props/district","res://scenes/props/medtac/detail"]:
		for file in DirAccess.get_files_at(directory):
			if file.ends_with(".tscn"): inspect(directory+"/"+file)
	var catalog: Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/world_props/catalog.json"))
	for entry: Dictionary in catalog: inspect(entry.scene)
	print("ASSET SURFACES: %d meshes, %d coplanar overlaps"%[inspected,failures])
	quit(1 if failures else 0)
