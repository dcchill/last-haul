extends SceneTree

## Authoring tool: generates editable department scenes and baked navigation.
## Run explicitly; runtime only loads the resulting PackedScenes.
const SCALE := 0.625
var site: Node3D
var nav: NavigationRegion3D
var serial := 0
var paints: Dictionary = {}
var shapes: Dictionary = {}
var meshes: Dictionary = {}
var prop_cache: Dictionary = {}
var steel: MaterialDef = preload("res://resources/materials/steel.tres")
var concrete: MaterialDef = preload("res://resources/materials/concrete.tres")
var rng := RandomNumberGenerator.new()
var ordinary_doors: Array[RaidDoor] = []
var departments: Array[Node3D] = []
var detail
var root_scene := "res://scenes/raid/medtac_labs.tscn"

func _initialize() -> void:
	call_deferred("build")

func point(x: float, z: float, y := 0.0) -> Vector3:
	return Vector3((x - 512) * SCALE, y, (z - 512) * SCALE)

func add(parent: Node, node: Node, title := "") -> Node:
	serial += 1
	node.name = title if not title.is_empty() else "Detail%d" % serial
	parent.add_child(node)
	node.owner = site
	return node

func paint(color: String, emission := false) -> StandardMaterial3D:
	if detail != null and not emission: return detail.textured(color)
	var key := color + str(emission)
	if not paints.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(color)
		mat.roughness = 0.92
		if emission:
			mat.emission_enabled = true
			mat.emission = Color(color)
			mat.emission_energy_multiplier = 0.8
		paints[key] = mat
	return paints[key]

func box(parent: Node3D, at: Vector3, size: Vector3, color: String, solid := true, title := "", glow := false) -> Node3D:
	var body: Node3D
	if solid:
		body = StaticBody3D.new()
		body.set_script(preload("res://scripts/world/decorative_prop.gd"))
		body.set("material", concrete if color in ["61645b", "343a35", "444b45"] else steel)
	else:
		body = Node3D.new()
	add(parent, body, title)
	body.position = at
	var key := str(size)
	if not meshes.has(key):
		var mesh := BoxMesh.new()
		mesh.size = size
		meshes[key] = mesh
	var visual := MeshInstance3D.new()
	visual.mesh = meshes[key]
	visual.material_override = paint(color, glow)
	add(body, visual, "Mesh")
	if solid:
		if not shapes.has(key):
			var shape := BoxShape3D.new()
			shape.size = size
			shapes[key] = shape
		var collision := CollisionShape3D.new()
		collision.shape = shapes[key]
		add(body, collision, "CollisionShape3D")
	return body

func slab(parent: Node3D, x1: float, z1: float, x2: float, z2: float, y: float, color: String, solid := true) -> Node3D:
	return box(parent, Vector3((x1 + x2) * 0.5, y - 0.15, (z1 + z2) * 0.5), Vector3(x2 - x1, 0.3, z2 - z1), color, solid)

func wall(parent: Node3D, x1: float, z1: float, x2: float, z2: float, y := 0.0, height := 5.0, color := "8b9589") -> void:
	var size:=Vector3(maxf(absf(x2-x1),.5),height,maxf(absf(z2-z1),.5))
	var body:=box(parent,Vector3((x1+x2)*.5,y+height*.5,(z1+z2)*.5),size,color)
	if height>=2.5 and maxf(size.x,size.z)>4:
		var occluder:=OccluderInstance3D.new()
		var form:=BoxOccluder3D.new()
		form.size=size*.98
		occluder.occluder=form
		add(body,occluder,"WallOccluder")

func sign_text(parent: Node3D, text: String, at: Vector3, yaw := 0.0, size := 48, color := Color("d5ddc4")) -> void:
	detail.physical_sign(parent,text,at,yaw,size,color)

func light(parent: Node3D, at: Vector3, color := Color("a5c9bf"), range_m := 16.0) -> void:
	detail.fixture(parent,at,false,color.r>color.b)

func section(title: String) -> Node3D:
	var node := Node3D.new()
	add(nav, node, title)
	departments.append(node)
	return node

func prop(parent: Node3D, id: String, at: Vector3, yaw := 0.0) -> Node3D:
	var path := "res://scenes/props/" + id + ".tscn"
	if not prop_cache.has(path): prop_cache[path] = load(path)
	var node: Node3D = prop_cache[path].instantiate()
	add(parent, node)
	node.position = at
	node.rotation.y = yaw
	return node

func table(entries: Array, rolls := Vector2i(2, 4)) -> LootTable:
	var resource := LootTable.new()
	resource.rolls = rolls
	for entry in entries:
		resource.entries.append({"id": entry[0], "weight": entry[1], "min": 1, "max": entry[2]})
	return resource

func container(parent: Node3D, id: String, at: Vector3, kind := "industrial", candidate := false, guaranteed: Dictionary = {}) -> void:
	detail.source(parent,id,at,"medical_bag" if kind=="medical" else "shipping_crate",kind,candidate,guaranteed)

func door(parent: Node3D, id: String, at: Vector3, yaw := 0.0, restricted := false, width := 3.0, height := 3.5) -> RaidDoor:
	var node := RaidDoor.new()
	node.entity_id = id
	node.restricted = restricted
	node.material = steel
	add(parent, node, id)
	node.position = at + Vector3.UP * height * .5
	node.rotation.y = yaw
	var shape := CollisionShape3D.new()
	var form := BoxShape3D.new()
	form.size = Vector3(width, height, 0.25)
	shape.shape = form
	add(node, shape, "CollisionShape3D")
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = form.size
	visual.mesh = mesh
	visual.material_override = paint("56675e" if restricted else "727b70")
	add(node, visual, "Panel")
	box(node, Vector3(width * 0.5 - 0.25, 0, 0.18), Vector3(0.12, 0.25, 0.10), "e2a05a" if restricted else "b3c3a6", false, "Reader", true)
	if restricted: sign_text(parent, "RESEARCH / SINGLE-USE CREDENTIAL", at + Vector3(0, height + .35, 0.3), yaw, 23)
	if restricted:
		var link := NavigationLink3D.new()
		add(parent, link, id + "-link")
		link.start_position = at + Vector3(0, 0.3, 3)
		link.end_position = at + Vector3(0, -0.1, -3)
		link.enabled = false
		node.traversal_link = NodePath("../" + str(link.name))
	else:
		ordinary_doors.append(node)
	return node

func horizontal_door_wall(parent: Node3D, x1: float, x2: float, z: float, gaps: Array, y := 0.0, height := 5.0) -> void:
	var cursor := x1
	for gap in gaps:
		wall(parent, cursor, z, float(gap) - 1.5, z, y, height)
		door(parent, "passage-%d" % serial, Vector3(float(gap), y, z))
		wall(parent, float(gap) - 1.5, z, float(gap) + 1.5, z, y + 3.5, height - 3.5)
		cursor = float(gap) + 1.5
	wall(parent, cursor, z, x2, z, y, height)

func vertical_door_wall(parent: Node3D, x: float, z1: float, z2: float, gaps: Array, y := 0.0, height := 5.0) -> void:
	var cursor := z1
	for gap in gaps:
		wall(parent, x, cursor, x, float(gap) - 1.5, y, height)
		door(parent, "passage-%d" % serial, Vector3(x, y, float(gap)), PI / 2)
		wall(parent, x, float(gap)-1.5, x, float(gap)+1.5, y+3.5, height-3.5)
		cursor = float(gap) + 1.5
	wall(parent, x, cursor, x, z2, y, height)

func lab_bench(parent: Node3D, at: Vector3, variant := 0) -> void:
	var packed: PackedScene = prop_cache["lab_bench_%d" % (variant%3)]
	var instance: Node3D = packed.instantiate()
	add(parent,instance)
	instance.position=at

func author_lab_bench(parent: Node3D, at: Vector3, variant := 0) -> void:
	box(parent, at + Vector3(0, 0.85, 0), Vector3(3.6, 0.12, 1.3), "c1c7b6")
	box(parent, at + Vector3(0, 0.4, 0.25), Vector3(3.2, 0.8, 0.65), "697970")
	for x in [-1.25, 0, 1.25]:
		box(parent, at + Vector3(x, 0.6, -0.22), Vector3(0.9, 0.025, 0.08), "303e39", false)
	if variant % 3 == 0:
		box(parent, at + Vector3(0.8, 1.2, 0.1), Vector3(0.65, 0.6, 0.55), "889a8b")
		box(parent, at + Vector3(0.8, 1.28, -0.19), Vector3(0.4, 0.25, 0.02), "4c8878", false, "", true)
	elif variant % 3 == 1:
		box(parent, at + Vector3(-0.6, 1.1, 0), Vector3(0.3, 0.4, 0.3), "969f88")
		box(parent, at + Vector3(-0.6, 1.35, -0.1), Vector3(0.1, 0.2, 0.4), "394c45")
	for x in [-1.1, -0.8, -0.5]:
		box(parent, at + Vector3(x, 1, -0.1), Vector3(0.08, 0.18, 0.08), "a3b797", false)

func bake_prop_mesh(node: Node3D, transform: Transform3D, builder: SurfaceTool) -> void:
	var local_transform := transform * node.transform
	if node is MeshInstance3D:
		var arrays: Array=node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		for index in indices:
			builder.set_normal((local_transform.basis*normals[index]).normalized())
			builder.set_color(node.material_override.albedo_color)
			builder.add_vertex(local_transform*vertices[index])
	for child in node.get_children():
		if child is Node3D: bake_prop_mesh(child,local_transform,builder)

func build_lab_props() -> void:
	DirAccess.make_dir_recursive_absolute("res://scenes/props/medtac")
	for variant in range(3):
		var bench:=Node3D.new()
		add(site,bench,"MedTacLabBench")
		author_lab_bench(bench,Vector3.ZERO,variant)
		var builder:=SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		bake_prop_mesh(bench,Transform3D.IDENTITY,builder)
		for node in bench.find_children("*","MeshInstance3D",true,false): node.free()
		var combined:=MeshInstance3D.new()
		combined.mesh=builder.commit()
		var material:=StandardMaterial3D.new()
		material.vertex_color_use_as_albedo=true
		material.roughness=0.9
		combined.material_override=material
		add(bench,combined,"BakedMesh")
		for node in bench.find_children("*","",true,false):
			if node.owner==site: node.owner=bench
		var path:="res://scenes/props/medtac/lab_bench_%d.tscn"%variant
		pack_to(bench,path)
		prop_cache["lab_bench_%d"%variant]=load(path)
		bench.free()

func covered_body(parent: Node3D, at: Vector3) -> void:
	box(parent, at + Vector3(0, 0.22, 0), Vector3(0.65, 0.4, 1.9), "8c9282", false)
	box(parent, at + Vector3(0.4, 0.008, 0), Vector3(0.9, 0.015, 1.4), "513f36", false)

func weak_partition(parent: Node3D, at: Vector3) -> void:
	var body: VoxelDestructible = preload("res://scripts/world/breachable_partition.gd").new()
	body.dimensions = Vector3i(12, 14, 2)
	body.material = preload("res://resources/materials/medical_partition.tres")
	body.surface_color = Color("9a8e68")
	add(parent, body, "WeakPartition%d" % serial)
	body.position = at + Vector3.UP * 1.75
	body.debris_manager_path = NodePath("../../../VoxelDebris")
	add(body, CollisionShape3D.new(), "CollisionShape3D")
	add(body, MeshInstance3D.new(), "MeshInstance3D")
	sign_text(parent, "DAMAGED PARTITION", at + Vector3(0, 3.8, 0.4), 0, 22)
	# This alcove is excluded from the bake until the partition has fully cleared.
	var link := NavigationLink3D.new()
	add(parent, link, "BreachLink%d" % serial)
	link.start_position = at + Vector3(0, 0.3, 2)
	link.end_position = at + Vector3(0, 0.3, -2)
	link.enabled = false
	body.set("link_path", NodePath("../" + str(link.name)))

func build_grounds() -> void:
	var area := section("Grounds")
	# Ground slabs contain real stairwell openings; no hidden ground collision beneath them.
	var xs := [-320.0, -36.0, -28.0, 50.0, 58.0, 320.0]
	var zs := [-320.0, -85.0, -45.0, 320.0]
	for xi in range(xs.size()-1):
		for zi in range(zs.size()-1):
			if zi == 1 and xi in [1,3]: continue
			slab(area, xs[xi], zs[zi], xs[xi+1], zs[zi+1], 0, "333f30")
	# Roads follow the sketch, including its southern junction and long yellow marking.
	for rect in [Rect2(-265,-320,92,94), Rect2(-265,-244,574,44), Rect2(-265,-244,23,338), Rect2(-265,72,336,22), Rect2(276,-244,33,305), Rect2(49,-43,260,115), Rect2(-16,94,41,150), Rect2(167,61,106,183), Rect2(-320,244,640,76)]:
		slab(area, rect.position.x, rect.position.y, rect.end.x, rect.end.y, 0.025, "444b45", false)
	for x in range(-290, 290, 70): box(area, Vector3(x, 0.045, 290), Vector3(48,0.025,0.4), "d7b947", false)
	box(area, Vector3(220,0.045,150), Vector3(0.4,0.025,170), "d7b947", false)
	box(area, Vector3(244,0.045,150), Vector3(0.4,0.025,170), "d7b947", false)
	for x in range(-220, -30, 12):
		box(area, Vector3(x,0.045,120), Vector3(0.2,0.02,16), "a0a38b", false)
		if x % 3 != 0: prop(area, ["burned_sedan","sedan","panel_van","hatchback"][posmod(x,4)], Vector3(x+4,0.04,118), PI)
	for x in [65,95,125,155,185,215,245]:
		prop(area, "flatbed_truck", Vector3(x,0.04,12), PI)
		prop(area, "loaded_pallet", Vector3(x+6,0.04,14))
	for at in [Vector3(-250,0,-210),Vector3(-100,0,-220),Vector3(270,0,-210),Vector3(285,0,45),Vector3(180,0,240),Vector3(-250,0,245)]:
		prop(area,"concrete_barrier",at)
		prop(area,"road_sign",at+Vector3(4,0,2))
	prop(area,"guard_booth",Vector3(165,0,200))
	for id in ["generator","transformer","fuel_tank","electrical_cabinet"]:
		prop(area,id,Vector3(-215+serial%5*7,0,-216))
	for i in range(130):
		var at := Vector3(rng.randf_range(-310,310),0,rng.randf_range(-310,310))
		if at.x > -270 and at.x < 310 and at.z > -250 and at.z < 100: continue
		if at.z > 240 or (at.x > -20 and at.x < 30) or (at.x > 160 and at.x < 280): continue
		# Sparse broken woodland and scrub with simple opaque block silhouettes.
		box(area,at+Vector3(0,3,0),Vector3(0.6,6,0.6),"4d4938")
		box(area,at+Vector3(0,6,0),Vector3(4,4,4),"344936",false)
		box(area,at+Vector3(1,3,1),Vector3(3,1.8,3),"40533a",false)
	for x in range(-310,311,10):
		for z in [-310,310]:
			if (z < 0 and x > -255 and x < -175) or (z > 0 and (x < -290 or x > 290)): continue
			prop(area,"fence_panel",Vector3(x,0,z))
	for z in range(-300,301,10):
		for x in [-310,310]:
			if x > 0 and z < -180 and z > -250: continue
			prop(area,"fence_panel",Vector3(x,0,z),PI/2)
	# Physical boundary prevents walking around extraction gates into the void.
	for line in [[-320,-320,320,-320],[-320,320,320,320],[-320,-320,-320,320],[320,-320,320,320]]:
		wall(area,line[0],line[1],line[2],line[3],0,6,"343a35")
	for i in range(8):
		container(area,"grounds-supply-%02d"%i,Vector3(-220+i*55,0,90 if i%2==0 else -216))

func build_shell() -> void:
	var shell := section("Shell")
	# Original reference footprint in world meters.
	vertical_door_wall(shell,-242,-200,72,[-120,-20])
	horizontal_door_wall(shell,-242,49,72,[-150])
	horizontal_door_wall(shell,-242,276,-200,[-150,180])
	vertical_door_wall(shell,276,-200,-43,[-100],0,10)
	horizontal_door_wall(shell,49,276,-43,[90,180,240],0,10)
	vertical_door_wall(shell,49,-43,72,[35])
	# Ground floor slabs and ceilings preserve the stair openings.
	for rect in [Rect2(-242,-200,206,272),Rect2(-28,-200,78,115),Rect2(-28,-45,77,117),Rect2(58,-200,218,157)]:
		slab(shell,rect.position.x,rect.position.y,rect.end.x,rect.end.y,0.03,"737c70",false)
	box(shell,Vector3(-96.5,5.4,-64),Vector3(291,0.4,272),"535e55",true,"LabRoof")
	box(shell,Vector3(162.5,10.4,-121.5),Vector3(227,0.4,157),"45534b",true,"WarehouseRoof")
	vertical_door_wall(shell,10,-200,-30,[-140,-70])
	vertical_door_wall(shell,49,-200,-43,[-140,-70],0,5)
	horizontal_door_wall(shell,-242,49,-30,[-205,-75,30])
	vertical_door_wall(shell,-96,-200,-30,[-165,-75])
	horizontal_door_wall(shell,-242,10,-113,[-205,-130,-60])
	# Keep service routes legible despite the broad industrial halls.
	for at in [Vector3(29,4,-165),Vector3(29,4,-80),Vector3(-150,4,65)]:
		sign_text(shell,"MEDTAC LABS\nRESEARCH • DIAGNOSTICS • DISTRIBUTION",at,0,70)

func build_reception() -> void:
	var area := section("Reception")
	sign_text(area,"MEDTAC",Vector3(-150,4.2,72.8),0,60)
	sign_text(area,"A HEALTHIER TOMORROW",Vector3(-150,2.8,77),0,22)
	# Exterior facade rhythm, failed visitor lighting, and surviving entrance power.
	for x in range(-230,40,18):
		box(area,Vector3(x,2,72.4),Vector3(7,1.5,0.15),"526a62",false)
		box(area,Vector3(x+5,2.5,72.4),Vector3(0.3,5,0.7),"687568")
	for x in [-155,-145]: light(area,Vector3(x,3.7,74),Color("c0a77b"),12)
	prop(area,"awning",Vector3(-150,0,75))
	prop(area,"plastic_barricade",Vector3(-156,0,82),0.2)
	prop(area,"traffic_cone",Vector3(-143,0,81))
	box(area,Vector3(-160,0.9,-17),Vector3(70,1.8,2.2),"425f58")
	sign_text(area,"CHECK IN / VISITOR SCREENING",Vector3(-160,2.6,-15.7),0,45)
	for x in [-220,-212,-204,-196,-188]:
		prop(area,"bench",Vector3(x,0,32),PI/2)
		prop(area,"bench",Vector3(x,0,43),PI/2)
	# Human-sized staff rooms line the east edge of the lobby.
	for index in range(4):
		var z := -9.0 + index*18
		horizontal_door_wall(area,-22,49,z,[0])
	vertical_door_wall(area,-22,-27,65,[0,36])
	for row in [["SECURITY / STAFF ACCESS",0],["STAFF LOCKERS",18],["WASHROOMS",36],["BREAK ROOM",54]]:
		sign_text(area,row[0],Vector3(-21.6,2.7,float(row[1])),PI/2,24)
	container(area,"security-office-cabinet",Vector3(-9,0,-4),"security",true)
	container(area,"staff-locker",Vector3(32,0,18),"medical",true)
	container(area,"reception-medical",Vector3(-132,0,-12),"medical")
	container(area,"reception-supplies",Vector3(-210,0,9))
	for x in [-12,0,12,24]: prop(area,"locker_bank",Vector3(x,0,24))
	prop(area,"industrial_sink",Vector3(35,0,40))
	prop(area,"bench",Vector3(12,0,60))
	covered_body(area,Vector3(-157,0,61))
	covered_body(area,Vector3(-163,0,60))
	for at in [Vector3(-150,4,40),Vector3(-200,4,-10),Vector3(8,4,15)]: light(area,at)
	sign_text(area,"EVACUATION SUSPENDED\nDO NOT WAIT FOR COMPANY TRANSPORT",Vector3(-146,1.7,69),0,24,Color("caae7a"))

func build_labs() -> void:
	var area := section("Laboratories")
	var rooms := [["SAMPLE INTAKE",-222,-177],["DIAGNOSTICS",-175,-177],["SPECIMEN PREPARATION",-132,-177],["COLD STORAGE",-73,-177],["TRIAL RECORDS",-222,-91],["STAFF LABORATORY",-160,-91],["DECONTAMINATION",-60,-91]]
	for room in rooms:
		var at := Vector3(float(room[1]),0,float(room[2]))
		# Each original colored department contains a recognizable enclosed lab suite.
		horizontal_door_wall(area,at.x-9,at.x+22,at.z+25,[at.x+6],0,3.8)
		wall(area,at.x-9,at.z-14,at.x+22,at.z-14,0,3.8)
		for edge_x in [at.x-9,at.x+22]:
			wall(area,edge_x,at.z-14,edge_x,at.z+25,0,1.2,"697970")
			wall(area,edge_x,at.z-14,edge_x,at.z+25,3,0.8,"697970")
			# Opaque observation glazing keeps the voxel palette and blocks sightlines.
			box(area,Vector3(edge_x,2.1,at.z+5),Vector3(0.15,1.8,37),"56756b")
		sign_text(area,room[0],at+Vector3(6,3.05,25.3),0,29)
		for col in range(3):
			prop(area,"locker_bank",at+Vector3(col*5,0,-10))
		box(area,at+Vector3(17,2.5,10),Vector3(0.18,0.3,26),"495a50",false)
		for row in range(3):
			for col in range(3): lab_bench(area,at+Vector3(col*7,0,row*9),row+col)
		light(area,at+Vector3(7,4.4,10))
		container(area,str(room[0]).to_lower().replace(" ","-")+"-supply",at+Vector3(-5,0,2),"medical",room[0]=="TRIAL RECORDS")
	# Glazed observation alcoves and shelving break up long cross-room sightlines.
	for x in [-228,-190,-150,-78,-40]:
		prop(area,"shelving_unit",Vector3(x,0,-123),PI/2)
		box(area,Vector3(x,1.6,-140),Vector3(9,3.2,0.3),"526a62")
		box(area,Vector3(x,2,-139.8),Vector3(7,1.6,0.04),"8ca99d",false)
	for x in [-75,-68,-61,-54]:
		box(area,Vector3(x,1.4,-194),Vector3(3.8,2.8,2),"a6b7aa")
		box(area,Vector3(x,1.5,-192.96),Vector3(3.2,2.1,0.04),"536b62",false)
	# A deliberately weak shortcut joins two otherwise connected lab areas.
	wall(area,-190,-66,-181.5,-66)
	wall(area,-178.5,-66,-170,-66)
	weak_partition(area,Vector3(-180,0,-66))
	covered_body(area,Vector3(-215,0,-157))
	sign_text(area,"ALL CURE LOTS TRANSFERRED TO CENTRAL LOGISTICS\nNO LOCAL DISPENSING AUTHORIZED",Vector3(-220,2.4,-114),0,23)
	sign_text(area,"RESTRICTED RESEARCH ↓\nSTAFF CREDENTIAL REQUIRED",Vector3(-32,3,-39),0,30,Color("d5a461"))

func build_warehouse() -> void:
	var area := section("Warehouse")
	sign_text(area,"MEDTAC LOGISTICS\nGARAGE / LOADING BAY",Vector3(160,8,-199.5),0,110)
	for x in [85,115,145,175,205,235]:
		for z in [-178,-165,-152,-125,-112,-99]:
			prop(area,"shelving_unit",Vector3(x,0,z))
			prop(area,"loaded_pallet",Vector3(x+4,0,z))
			if z in [-178,-112]: prop(area,"cargo_case",Vector3(x-3,0,z+4))
	for x in [92,122,152,182,212,242]:
		prop(area,"workbench",Vector3(x,0,-57))
		container(area,"packing-station-%d"%x,Vector3(x+3,0,-54))
		box(area,Vector3(x,0.04,-46),Vector3(20,0.02,0.25),"d7b947",false)
	for at in [Vector3(78,8,-170),Vector3(158,8,-135),Vector3(238,8,-90)]: light(area,at,Color("d1ac76"),24)
	# Dispatch and maintenance sit beside the main connecting corridor.
	vertical_door_wall(area,73,-194,-150,[-172])
	horizontal_door_wall(area,49,73,-150,[61])
	sign_text(area,"DISPATCH / SHIPPING",Vector3(61,3,-194),0,27)
	container(area,"dispatch-office-safe",Vector3(55,0,-184),"security",true)
	sign_text(area,"MAINTENANCE / RESEARCH ACCESS ↓",Vector3(58,3,-40),0,28,Color("d5a461"))
	for id in ["tool_cabinet","air_compressor","welding_cart","generator"]:
		prop(area,id,Vector3(80+serial%4*5,0,-76))
	sign_text(area,"PRIORITY: CURE LOTS 001–019 EVACUATED\nREGIONAL ORDERS CANCELLED / NO REPLACEMENT STOCK",Vector3(260,3,-199),0,28)

func staircase(parent: Node3D, x: float, identity: String) -> void:
	# Both stairs descend north; 40 quarter-meter steps over a 40-meter run.
	for i in range(40):
		var step_y := -float(i+1)*0.25
		box(parent,Vector3(x,step_y-0.25,-45.5-i),Vector3(8,0.5,1),"61645b")
		# Smooth collision ramp alongside matching visible tread geometry.
	var ramp := StaticBody3D.new()
	add(parent,ramp)
	var shape := CollisionShape3D.new()
	var prism := ConvexPolygonShape3D.new()
	prism.points = PackedVector3Array([Vector3(-4,-0.3,0),Vector3(4,-0.3,0),Vector3(-4,-10.3,-40),Vector3(4,-10.3,-40),Vector3(-4,0,0),Vector3(4,0,0),Vector3(-4,-10,-40),Vector3(4,-10,-40)])
	shape.shape = prism
	add(ramp,shape)
	ramp.position = Vector3(x,0,-45)
	wall(parent,x-4.25,-85,x-4.25,-45,-10,14,"61645b")
	wall(parent,x+4.25,-85,x+4.25,-45,-10,14,"61645b")
	# Northern end remains closed at ground level, but is open at basement level.
	wall(parent,x-4.25,-85.5,x+4.25,-85.5,-6.2,10.2,"61645b")
	wall(parent,x-4.25,-44,x-1.5,-44,-0.3,4.3,"61645b")
	wall(parent,x+1.5,-44,x+4.25,-44,-0.3,4.3,"61645b")
	wall(parent,x-1.5,-44,x+1.5,-44,3.5,0.5,"61645b")
	door(parent,identity,Vector3(x,0,-44),0,true)
	light(parent,Vector3(x,-0.5,-62),Color("d1a05f"),12)

func build_basement() -> void:
	var area := section("Basement")
	slab(area,-220,-185,105,-38,-10,"444b45")
	for edge in [[-220,-185,105,-185],[-220,-38,105,-38],[-220,-185,-220,-38],[105,-185,105,-38]]:
		wall(area,edge[0],edge[1],edge[2],edge[3],-10,9.7,"61645b")
	# Basement circulation is a loop with cross-passages, never a single dead-end escape.
	horizontal_door_wall(area,-220,105,-120,[-190,-110,0,80],-10,4.5)
	vertical_door_wall(area,-140,-185,-38,[-160,-95,-55],-10,4.5)
	vertical_door_wall(area,-55,-185,-90,[-160],-10,4.5)
	vertical_door_wall(area,30,-185,-90,[-160],-10,4.5)
	staircase(area,-32,"research-lab-entrance")
	staircase(area,54,"research-maintenance-entrance")
	var rooms := [["OBSERVATION / TRIAL CONTROL",-195,-155],["HUMAN TRIALS / AUTHORIZED ONLY",-112,-155],["CONTAINMENT / LOCKDOWN FAILED",-25,-155],["ARCHIVE / CURE TRANSFERS",65,-155],["SPECIMEN STORAGE",-195,-75],["UTILITIES / AIR HANDLING",-115,-65]]
	for i in range(rooms.size()):
		var room: Array = rooms[i]
		var at := Vector3(float(room[1]),-10,float(room[2]))
		sign_text(area,room[0],at+Vector3(0,3.2,-11),0,30,Color("c8b58b"))
		lab_bench(area,at)
		light(area,at+Vector3(0,3.8,0),Color("c59060") if i==2 else Color("789d91"),17)
		var guarantee := {"infection_suppressant":1,"research_drive":1} if i in [0,3] else {}
		container(area,"basement-research-%d"%i,at+Vector3(6,0,1),"research",false,guarantee)
	for x in [-110,-100,-90]:
		box(area,Vector3(x,-9.2,-170),Vector3(1.1,0.25,2.4),"8f9e8f")
		box(area,Vector3(x,-8.98,-170),Vector3(1.15,0.08,0.3),"5b5144",false)
		covered_body(area,Vector3(x,-9.1,-170))
	# Broken containment has a physical opening, scattered frames, and no live gas hazard.
	for x in [-35,-20,-5]:
		wall(area,x-5,-180,x-5,-168,-10,3.5,"536c62")
		box(area,Vector3(x,-8.4,-176),Vector3(7,2.6,0.12),"6b8476",false)
		box(area,Vector3(x,-9.96,-166),Vector3(2.5,0.035,2),"54705c",false)
	covered_body(area,Vector3(-13,-10,-147))
	sign_text(area,"TRIAL 19: PATHOGEN RELEASE APPROVED\nREVENUE MODEL: EXCLUSIVE CURE DISTRIBUTION\nDOMESTIC CONTAINMENT PROJECTIONS EXCEEDED",Vector3(-194,-7.8,-184.6),0,22)
	sign_text(area,"CURE EFFICACY CONFIRMED\nALL VIABLE STOCK EVACUATED / LOCAL INVENTORY: ZERO\nDO NOT CONFUSE SUPPRESSANTS WITH CURE",Vector3(67,-7.8,-184.6),0,22)
	for at in [Vector3(-175,-10,-43),Vector3(0,-10,-100),Vector3(90,-10,-43)]:
		sign_text(area,"EMERGENCY EXIT ↑\nLAB STAIRS ← / MAINTENANCE STAIRS →",at+Vector3.UP*2.5,0,23)

func add_extracts_and_spawns() -> void:
	var areas := [["north-service","North Service Gate",160,12],["east-logistics","East Logistics Gate",1008,169],["southwest-roadblock","Southwest Roadblock",8,967],["southeast-evacuation","Southeast Evacuation Gate",1013,967]]
	for i in range(areas.size()):
		var data: Array = areas[i]
		var zone := ExtractionZone.new()
		zone.entity_id = data[0]
		zone.display_name = data[1]
		zone.collision_mask = 1
		zone.collision_layer = 0
		add(site,zone,"Extraction" if i==0 else "Extraction%d"%i)
		zone.position = point(data[2],data[3])
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(9,5,12)
		collision.shape = shape
		collision.position.y = 2
		add(zone,collision,"CollisionShape3D")
		box(zone,Vector3(0,0.07,0),Vector3(9,0.05,12),"466f44",false)
		for x in [-4.0,4.0]:
			box(zone,Vector3(x,1.4,0),Vector3(0.16,2.8,0.16),"99d663",false,"",true)
		sign_text(zone,data[1].to_upper()+"\nEXTRACTION / 15 SECONDS",Vector3(0,3,0),0,36,Color("b8e88c"))
	var coords := [Vector2(32,138),Vector2(800,57),Vector2(1006,655),Vector2(209,775),Vector2(721,806),Vector2(88,927),Vector2(931,998)]
	for i in range(coords.size()):
		var marker := Marker3D.new()
		add(site,marker,"Insertion%02d"%i)
		marker.position = point(coords[i].x,coords[i].y,0.04)
		marker.rotation.y = atan2(marker.position.x,marker.position.z)
		marker.add_to_group("raid_spawns",true)

func add_enemies() -> void:
	var positions := [Vector3(-200,0,110),Vector3(-80,0,150),Vector3(100,0,155),Vector3(270,0,20),Vector3(-245,0,-150),Vector3(-218,0,-160),Vector3(-180,0,-180),Vector3(-135,0,-145),Vector3(-70,0,-160),Vector3(-160,0,-80),Vector3(-65,0,-60),Vector3(-195,-10,-155),Vector3(-105,-10,-155),Vector3(-20,-10,-155),Vector3(75,-10,-155),Vector3(-180,-10,-75),Vector3(210,0,160),Vector3(-200,0,-220),Vector3(90,0,-168),Vector3(135,0,-110),Vector3(190,0,-158),Vector3(245,0,-75)]
	for i in range(positions.size()):
		var npc: RaidGuard = preload("res://scenes/npcs/guard.tscn").instantiate()
		npc.entity_id = "medtac-infected-%02d"%i if i<16 else "medtac-scav-%02d"%i
		npc.archetype = preload("res://resources/npcs/zombie.tres") if i<16 else preload("res://resources/npcs/guard.tres")
		npc.material = steel
		add(site,npc,"Guard" if i==0 else "Occupant%02d"%i)
		npc.position = positions[i]+Vector3.UP*0.03
		# Keep authored patrols inside their encounter sector and out of spawn pockets.
		npc.patrol_points = PackedVector3Array([positions[i],positions[i]+Vector3(5,0,0),positions[i]+Vector3(5,0,6)])
		npc.cover_points = PackedVector3Array([positions[i]+Vector3(3,0,0)]) if i>=16 else PackedVector3Array()

func pack_to(node: Node, path: String) -> Error:
	var packed := PackedScene.new()
	var error := packed.pack(node)
	return ResourceSaver.save(packed,path) if error==OK else error

func build() -> void:
	detail=preload("res://tools/medtac_detail.gd").new()
	detail.b=self
	rng.seed = 19381
	DirAccess.make_dir_recursive_absolute("res://scenes/raid/medtac")
	site = Node3D.new()
	site.name = "MedTacLabs"
	site.set_script(preload("res://scripts/raid/raid_authority.gd"))
	site.set("map_definition",preload("res://resources/maps/medtac_labs.tres"))
	nav = preload("res://scripts/world/raid_navigation_region.gd").new()
	add(site,nav,"NavigationRegion3D")
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	mesh.agent_height = 2.0
	mesh.agent_radius = 0.5
	mesh.agent_max_climb = 0.5
	mesh.filter_baking_aabb = AABB(Vector3(-318,-12,-318),Vector3(636,30,636))
	nav.navigation_mesh = mesh
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("545564")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("9aa6ac")
	world.environment.ambient_light_energy = 0.65
	add(site,world,"WorldEnvironment")
	var sun := DirectionalLight3D.new()
	add(site,sun,"DuskSun")
	sun.rotation_degrees = Vector3(-12,-50,0)
	sun.light_color = Color("d3a076")
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160
	var player := preload("res://scenes/player/player.tscn").instantiate()
	add(site,player,"Player")
	player.position = Vector3(-150,0.04,95)
	var decay := preload("res://scenes/rendering/signal_decay.tscn").instantiate()
	add(site,decay,"SignalDecay")
	decay.haze_start = 90
	decay.haze_end = 290
	decay.haze_density = 0.28
	decay.haze_color = Color("555c5c")
	var impact := Node3D.new()
	impact.set_script(preload("res://scripts/combat/impact_presenter.gd"))
	add(site,impact,"ImpactPresenter")
	var debris := Node3D.new()
	debris.set_script(preload("res://scripts/world/voxel_debris_manager.gd"))
	add(site,debris,"VoxelDebris")
	build_grounds()
	await detail.build_variants()
	detail.build_shell()
	detail.build_reception()
	detail.build_labs()
	detail.build_warehouse()
	detail.build_basement()
	detail.finish_geometry()
	add_extracts_and_spawns()
	add_enemies()
	detail.finish_signs()
	# Bake with ordinary doors open. Restricted gates remain closed and use disabled links.
	root.add_child(site)
	var bake_map:=NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(bake_map,true)
	NavigationServer3D.map_set_use_async_iterations(bake_map,false)
	NavigationServer3D.map_force_update(bake_map)
	nav.set_navigation_map(bake_map)
	site.set_physics_process(false)
	player.set_physics_process(false)
	for node in ordinary_doors:
		node.open = true
		node.refresh()
	await physics_frame
	await physics_frame
	nav.bake_navigation_mesh(false)
	detail.remove_bake_proxies()
	await physics_frame
	await physics_frame
	NavigationServer3D.set_active(true)
	NavigationServer3D.map_set_use_async_iterations(nav.get_navigation_map(),false)
	NavigationServer3D.map_set_active(nav.get_navigation_map(),true)
	NavigationServer3D.region_set_navigation_mesh(nav.get_rid(),nav.navigation_mesh)
	# Reassign the baked resource so the region updates its cached polygon data.
	var baked_mesh := nav.navigation_mesh.duplicate(true) as NavigationMesh
	baked_mesh.emit_changed()
	nav.navigation_mesh = null
	nav.navigation_mesh = baked_mesh
	NavigationServer3D.map_force_update(nav.get_navigation_map())
	for frame in range(6): await physics_frame
	NavigationServer3D.map_force_update(nav.get_navigation_map())
	print("NAV BUILD: polygons ",nav.navigation_mesh.get_polygon_count()," / regions ",NavigationServer3D.map_get_regions(nav.get_navigation_map()).size()," / iteration ",NavigationServer3D.map_get_iteration_id(nav.get_navigation_map()))
	if nav.navigation_mesh.get_polygon_count()==0:
		push_error("MedTac navigation is empty")
		quit(1)
		return
	# Assign extracts by actual routes, excluding the restricted basement.
	for marker in site.find_children("Insertion*","Marker3D",false,false):
		var distances: Array[Dictionary] = []
		for zone in site.get_children():
			if not zone is ExtractionZone: continue
			var path := preload("res://scripts/world/raid_navigation.gd").path(nav.get_navigation_map(),marker.global_position,zone.global_position)
			var length := 0.0
			for i in range(1,path.size()): length += path[i-1].distance_to(path[i])
			if path.is_empty() or path[-1].distance_to(zone.global_position)>3:
				push_error("Unreachable extract %s from %s / end: %s"%[zone.entity_id,marker.name,path[-1] if not path.is_empty() else Vector3.ZERO])
				quit(1)
				return
			distances.append({"id":zone.entity_id,"distance":length})
		distances.sort_custom(func(a,b): return a.distance>b.distance)
		marker.set_meta("assigned_extracts",[distances[0].id,distances[1].id])
		marker.set_meta("route_distances",distances)
	for node in ordinary_doors:
		node.open = false
		node.refresh()
	# Remove runtime-only player/hands/sensor children by recreating packed prefab instances.
	for node in [player,decay]:
		var prefab: PackedScene = load(node.scene_file_path)
		var replacement := prefab.instantiate()
		var title := str(node.name)
		var transform: Transform3D = node.transform if node is Node3D else Transform3D.IDENTITY
		site.remove_child(node)
		node.free()
		add(site,replacement,title)
		if replacement is Node3D: replacement.transform = transform
		if replacement is SignalDecay:
			replacement.haze_start=90
			replacement.haze_end=290
			replacement.haze_density=0.28
			replacement.haze_color=Color("555c5c")
	# Clear voxel runtime meshes and save departments as independently editable scenes.
	for node in site.find_children("*","",true,false):
		if node is VoxelDestructible:
			node.get_node("CollisionShape3D").shape=null
			node.get_node("MeshInstance3D").mesh=null
			node.get_node("MeshInstance3D").material_override=null
	for department in departments:
		var path := "res://scenes/raid/medtac/"+str(department.name).to_snake_case()+".tscn"
		for node in department.find_children("*","",true,false):
			if node.owner==site: node.owner=department
		if pack_to(department,path)!=OK:
			push_error("Cannot save "+path)
			quit(1)
			return
		var instance: Node3D = load(path).instantiate()
		var title := str(department.name)
		nav.remove_child(department)
		department.free()
		add(nav,instance,title)
	var error := pack_to(site,root_scene)
	print("MEDTAC BUILD: ",error_string(error)," / navigation polygons: ",nav.navigation_mesh.get_polygon_count()," / authored nodes: ",serial)
	site.free()
	NavigationServer3D.free_rid(bake_map)
	quit(0 if error==OK else 1)
