class_name WorldMeshKit
extends RefCounted

## Authored profiles and functional components, merged by material. No per-voxel
## scene nodes, no hidden internal box faces in the vehicle body or machinery.
var builders: Dictionary={}
var materials: Dictionary={}
var art: WorldArtDirection=load("res://resources/district/art_direction.tres") if ResourceLoader.exists("res://resources/district/art_direction.tres") else WorldArtDirection.new()
static var shared_materials: Dictionary={}
static var refresh_materials := false

func surface(key: String) -> SurfaceTool:
	if not builders.has(key):
		var tool:=SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		builders[key]=tool
		if shared_materials.has(key): materials[key]=shared_materials[key]
		var saved_path:="res://resources/district/materials/"+key+".tres"
		if not materials.has(key) and not refresh_materials and ResourceLoader.exists(saved_path): materials[key]=load(saved_path)
		if not materials.has(key):
			var mat:=StandardMaterial3D.new()
			mat.resource_name=key
			mat.albedo_color=art.palette.get(key,Color("777b75"))
			mat.roughness=.92
			var image:=Image.create(64,64,false,Image.FORMAT_RGB8)
			for y in 64:
				for x in 64:
					var coarse:=float((int(x/8.0)*71+int(y/8.0)*37)%17)/17.0
					var fine:=float((x*73+y*151)%23)/23.0
					var tone:=.95+coarse*.035+fine*.015
					if key in ["steel","paint","rust"] and y%31==0: tone*=.88
					image.set_pixel(x,y,Color(tone,tone,tone))
			mat.albedo_texture=ImageTexture.create_from_image(image)
			mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mat.set_meta("wettable",key in ["asphalt","steel","concrete","paint","rust"])
			if key in ["steel","rust"]: mat.metallic=.55
			if key=="glass": mat.metallic=.35; mat.roughness=.22
			if key=="light": mat.emission_enabled=true; mat.emission=mat.albedo_color; mat.emission_energy_multiplier=.5
			materials[key]=mat
		shared_materials[key]=materials[key]
	return builders[key]

func tri(a: Vector3,b: Vector3,c: Vector3,normal: Vector3,key: String) -> void:
	if (b-a).cross(c-a).length_squared()<.0000000001: return
	var tool:=surface(key)
	var vertices: Array=[a,c,b] if (b-a).cross(c-a).dot(normal)>0 else [a,b,c]
	for vertex in vertices:
		tool.set_normal(normal)
		tool.set_uv(Vector2(vertex.x,vertex.z) if absf(normal.y)>.5 else Vector2(vertex.z,vertex.y) if absf(normal.x)>.5 else Vector2(vertex.x,vertex.y))
		tool.add_vertex(vertex)

func quad(a: Vector3,b: Vector3,c: Vector3,d: Vector3,normal: Vector3,key: String) -> void:
	tri(a,b,c,normal,key)
	tri(a,c,d,normal,key)

func box(at: Vector3,size: Vector3,key: String) -> void:
	var h:=size*.5
	var p: Array[Vector3]=[]
	for i in 8: p.append(at+Vector3(h.x if i&1 else -h.x,h.y if i&2 else -h.y,h.z if i&4 else -h.z))
	var faces: Array=[[1,3,7,5],[4,6,2,0],[2,6,7,3],[4,0,1,5],[5,7,6,4],[0,2,3,1]]
	var normals: Array[Vector3]=[Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]
	for f in 6: quad(p[faces[f][0]],p[faces[f][1]],p[faces[f][2]],p[faces[f][3]],normals[f],key)

func profile(points: PackedVector2Array,depth: float,at: Vector3,key: String,axis := 2) -> void:
	var indices:=Geometry2D.triangulate_polygon(points)
	for side in [-1,1]:
		var normal:=Vector3(0,0,side)
		for i in range(0,indices.size(),3):
			var vertices: Array[Vector3]=[]
			for j in 3:
				var p:=points[indices[i+j]]
				vertices.append(Vector3(p.x,p.y,side*depth*.5))
			if axis==0:
				for j in 3: vertices[j]=Vector3(vertices[j].z,vertices[j].y,-vertices[j].x)
				normal=Vector3(side,0,0)
			tri(at+vertices[0],at+vertices[1],at+vertices[2],normal,key)
	for i in points.size():
		var a:=points[i]
		var b:=points[(i+1)%points.size()]
		var normal:=Vector3(b.y-a.y,a.x-b.x,0).normalized()
		var vertices: Array[Vector3]=[Vector3(a.x,a.y,-depth*.5),Vector3(b.x,b.y,-depth*.5),Vector3(b.x,b.y,depth*.5),Vector3(a.x,a.y,depth*.5)]
		if axis==0:
			for j in 4: vertices[j]=Vector3(vertices[j].z,vertices[j].y,-vertices[j].x)
			normal=Vector3(normal.z,normal.y,-normal.x)
		quad(at+vertices[0],at+vertices[1],at+vertices[2],at+vertices[3],normal,key)

static func stepped(points: PackedVector2Array,step := .0625) -> PackedVector2Array:
	var output:=PackedVector2Array()
	for i in points.size():
		var a:=points[i]
		var b:=points[(i+1)%points.size()]
		output.append(a)
		if absf(a.x-b.x)<step or absf(a.y-b.y)<step: continue
		var count:=maxi(2,int(maxf(absf(a.x-b.x),absf(a.y-b.y))/step))
		for part in range(1,count):
			var previous:=a.lerp(b,float(part-1)/count)
			var next:=a.lerp(b,float(part)/count)
			output.append(Vector2(next.x,previous.y)); output.append(next)
	return output

func cylinder(at: Vector3,radius: float,length: float,key: String,axis := 1,sides := 12) -> void:
	var points:=PackedVector2Array()
	for i in sides:
		var angle:=TAU*i/sides
		points.append(Vector2(cos(angle),sin(angle))*radius)
	if axis==0 or axis==2: profile(points,length,at,key,axis)
	else:
		# Transform a temporary Z extrusion to Y, preserving surface winding.
		var other:=WorldMeshKit.new()
		other.materials=materials
		other.profile(points,length,Vector3.ZERO,key)
		var mesh:=other.finish()
		var arrays:=mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var tool:=surface(key)
		for index in indices:
			var vertex:=vertices[index]
			var normal:=normals[index]
			tool.set_normal(Vector3(normal.x,normal.z,-normal.y))
			tool.set_uv(Vector2(vertex.x,vertex.y))
			tool.add_vertex(at+Vector3(vertex.x,vertex.z,-vertex.y))

func finish() -> ArrayMesh:
	var mesh:=ArrayMesh.new()
	for key: String in builders:
		var tool: SurfaceTool=builders[key]
		tool.index()
		tool.set_material(materials[key])
		tool.commit(mesh)
	return remove_coplanar_overdraw(mesh)

static func remove_coplanar_overdraw(source: ArrayMesh) -> ArrayMesh:
	var result:=ArrayMesh.new()
	var planes: Dictionary={}
	for surface_index in source.get_surface_count():
		var arrays:=source.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
		var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var output:=SurfaceTool.new(); output.begin(Mesh.PRIMITIVE_TRIANGLES)
		var emitted:=false
		for index in range(0,indices.size(),3):
			var a:=vertices[indices[index]]; var b:=vertices[indices[index+1]]; var c:=vertices[indices[index+2]]
			var normal:=(c-a).cross(b-a).normalized()
			var axis:=normal.abs().max_axis_index()
			var u: int=(axis+1)%3; var v: int=(axis+2)%3
			var pa:=Vector2(a[u],a[v]); var pb:=Vector2(b[u],b[v]); var pc:=Vector2(c[u],c[v])
			var triangle:=PackedVector2Array([pa,pb,pc])
			var key:=str(normal.snapped(Vector3.ONE*.0001))+":"+str(snappedf(normal.dot(a),.0001))
			var parts: Array[PackedVector2Array]=[triangle]
			if not planes.has(key): planes[key]=[]
			var bounds:=Rect2(pa,Vector2.ZERO).expand(pb).expand(pc)
			for prior in planes[key]:
				if not bounds.intersects(prior.bounds): continue
				var remaining: Array[PackedVector2Array]=[]
				for part in parts: remaining.append_array(DistrictSurfaceGeometry.subtract(part,prior.polygon))
				parts=remaining
				if parts.is_empty(): break
			planes[key].append({"bounds":bounds,"polygon":triangle})
			var determinant:=(pb-pa).cross(pc-pa)
			if absf(determinant)<.00000001: continue
			for part in parts:
				var triangulation:=Geometry2D.triangulate_polygon(part)
				for t in range(0,triangulation.size(),3):
					var corners: Array[int]=[triangulation[t],triangulation[t+1],triangulation[t+2]]
					if absf((part[corners[1]]-part[corners[0]]).cross(part[corners[2]]-part[corners[0]]))<.00003: continue
					if (part[corners[1]]-part[corners[0]]).cross(part[corners[2]]-part[corners[0]])*determinant<0: corners.reverse()
					for corner in corners:
						var point:=part[corner]
						var wb:=(point-pa).cross(pc-pa)/determinant
						var wc:=(pb-pa).cross(point-pa)/determinant
						output.set_normal(normal)
						if not uvs.is_empty(): output.set_uv(uvs[indices[index]]*(1-wb-wc)+uvs[indices[index+1]]*wb+uvs[indices[index+2]]*wc)
						if not colors.is_empty(): output.set_color(colors[indices[index]]*(1-wb-wc)+colors[indices[index+1]]*wb+colors[indices[index+2]]*wc)
						output.add_vertex(a*(1-wb-wc)+b*wb+c*wc)
						emitted=true
		if emitted:
			output.index(); output.set_material(source.surface_get_material(surface_index)); output.commit(result)
	return result
