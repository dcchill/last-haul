extends DistrictSceneAuthor

## Fixed campus architecture. Coordinates are meters; props never scale the rooms.
const FLOOR_HEIGHT := 4.2
var rooms: Array[Dictionary]=[]
var areas: Array[Dictionary]=[]
var stairs: Array[Dictionary]=[]
var room_nodes: Array[Node3D]=[]
var building_nodes: Array[Node3D]=[]

func begin(title: String,raid := false) -> Node3D:
	# Campus-only materials keep the preserved Labs fixture's original appearance.
	for key in ["plaster","floor","concrete","dirt","rust"]:
		var mat:=StandardMaterial3D.new(); mat.roughness=.97
		mat.albedo_color={"plaster":Color("b1b5a0"),"floor":Color("737d77"),"concrete":Color("73776a"),"dirt":Color("535845"),"rust":Color("754c35")}[key]
		var texture:=Image.create(128,128,false,Image.FORMAT_RGB8)
		for y in 128:
			for x in 128:
				var grain:=float((x*73+y*151)%23)/23
				var tone:=.8+grain*.15
				if key=="floor" and (x%32<2 or y%32<2): tone=.42
				if key=="plaster":
					if (x*7+int(y/9.0)*13)%71<9: tone*=.64
					if y>87 and (x*19+int(y/7.0))%31<17: tone*=.65
				if key=="concrete" and absf(float(x)-64-sin(y*.13)*9)<1: tone=.38
				if key=="dirt": tone*=.7+float((int(x/9.0)*17+int(y/11.0)*31)%11)*.045
				texture.set_pixel(x,y,Color(tone,tone,tone))
		mat.albedo_texture=ImageTexture.create_from_image(texture); mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.set_meta("wettable",key in ["floor","concrete","rust"])
		WorldMeshKit.shared_materials[key]=mat
	return super.begin(title,raid)

func terrain_height(_at: Vector2) -> float: return 0.0
func infill_sites() -> Array[Vector2]: return []
func infill() -> void: pass

func terrain() -> void:
	var ground:=section("CampusGround")
	# Each foundation replaces the terrain: no coplanar indoor ground or stair plugs.
	var footprints: Array[Rect2]=[Rect2(-55,-60,110,100),Rect2(-45,80,90,40),Rect2(85,-45,50,80),Rect2(-130,-25,40,60)]
	foundation(ground,Rect2(-175,-175,350,350),0,footprints,"dirt")

func area_record(title: String,at: Vector3,purpose: String,adjacent: String,equipment: String,role: String) -> void:
	areas.append({"name":title,"at":[at.x,at.y,at.z],"purpose":purpose,"adjoining":adjacent,"entrances":"credential entry and free emergency egress" if title.begins_with("BasementStair") else "pedestrian/service approaches","equipment":equipment,"service_access":"maintenance via the adjoining circulation","loot":"none; storage is inside the adjoining departments","encounter":role,"corrected":"reserved walking lanes; supported props; separate pedestrian and vehicle space"})

func review_view(eye: Vector3,target: Vector3,reverse := false) -> void:
	areas[-1]["eye_reverse" if reverse else "eye"]=[eye.x,eye.y,eye.z]
	areas[-1]["target_reverse" if reverse else "target"]=[target.x,target.y,target.z]

func roads() -> void:
	var ground:=section("CampusRoutes")
	# Ring roads never run through buildings. Pedestrians use the inner loop.
	for rect in [Rect2(-150,-135,300,8),Rect2(-150,135,300,8),Rect2(-150,-127,8,262),Rect2(142,-127,8,262),Rect2(-80,-75,160,5),Rect2(-80,60,160,5),Rect2(-80,-70,5,130),Rect2(75,-70,5,130),Rect2(-142,3,67,5),Rect2(80,-8,62,6),Rect2(-4,65,8,70)]:
		box(ground,Vector3(rect.get_center().x,.015,rect.get_center().y),Vector3(rect.size.x,.03,rect.size.y),"asphalt" if rect.size.x==8 or rect.size.y==8 else "concrete",false)
	for rect in [Rect2(-142,-100,66,10),Rect2(80,-100,62,10),Rect2(-142,45,67,8),Rect2(80,48,62,8)]:
		box(ground,Vector3(rect.get_center().x,.015,rect.get_center().y),Vector3(rect.size.x,.03,rect.size.y),"asphalt",false)
	# Warehouse apron and separated visitor parking.
	box(ground,Vector3(113,.015,54),Vector3(48,.03,20),"asphalt",false)
	box(ground,Vector3(-88,.015,100),Vector3(54,.03,48),"asphalt",false)
	for i in 6:
		box(ground,Vector3(-108+i*8,.043,100),Vector3(.12,.016,12),"warning",false)
		box(ground,Vector3(92+i*7,.6,43),Vector3(.25,1.2,.25),"warning")
	for data in [["Inner campus circuit",Vector3(0,1.6,62),"walking and alternate approaches","all four buildings","curbs, drainage, benches","cross-campus travel"],["Outer service circuit",Vector3(0,1.6,-130),"freight and emergency access","perimeter and yards","road signs, wrecks, utility poles","longer bypass"],["Visitor parking",Vector3(-88,1.6,100),"public arrival","outpatient and pedestrian circuit","parking markings, abandoned cars","low-value salvage"],["Loading apron",Vector3(113,1.6,54),"truck turning and receiving","logistics and east road","dock markings, vehicle barriers","scavenger approach"],["West service yard",Vector3(-112,1.6,51),"maintenance and separated fuel/waste","facilities and west road","fuel bund, fenced waste enclosure","technical salvage"],["North perimeter",Vector3(0,1.6,-160),"boundary and insertion travel","outer service circuit","woodland and boundary wall","protected approach"],["East perimeter",Vector3(160,1.6,0),"boundary and extraction travel","freight road","woodland, service gates","protected approach"],["South perimeter",Vector3(0,1.6,160),"boundary and extraction travel","visitor access","woodland, evacuation markers","protected approach"],["West perimeter",Vector3(-160,1.6,0),"boundary and insertion travel","maintenance road","woodland, utility poles","protected approach"]]:
		area_record(data[0],data[1],data[2],data[3],data[4],data[5])

func segment(parent: Node3D,a: Vector3,b: Vector3,height := 3.6,key := "concrete") -> void:
	wall(parent,(a+b)*.5+Vector3.UP*height*.5,Vector3(maxf(.2,absf(b.x-a.x)),height,maxf(.2,absf(b.z-a.z))),key)

func gap_wall(parent: Node3D,a: Vector3,b: Vector3,gap: float,y := 0.0,height := 3.8,key := "concrete") -> void:
	var along_x:=absf(b.x-a.x)>absf(b.z-a.z)
	var center:=(a+b)*.5
	var left:=center-Vector3(gap*.5,0,0) if along_x else center-Vector3(0,0,gap*.5)
	var right:=center+Vector3(gap*.5,0,0) if along_x else center+Vector3(0,0,gap*.5)
	segment(parent,Vector3(a.x,y,a.z),Vector3(left.x,y,left.z),height,key)
	segment(parent,Vector3(right.x,y,right.z),Vector3(b.x,y,b.z),height,key)
	box(parent,Vector3(center.x,y+(2.8+height)*.5,center.z),Vector3(gap,height-2.8,.2) if along_x else Vector3(.2,height-2.8,gap),key)

func foundation(parent: Node3D,rect: Rect2,y: float,holes: Array[Rect2]=[],surface_key := "floor") -> void:
	parent=section("Slab%d"%serial,Vector3.ZERO,parent)
	parent.set_meta("campus_slab",true); parent.set_meta("surface_y",world_transform(parent).origin.y+y)
	var pieces: Array[PackedVector2Array]=[polygon(rect)]
	for hole in holes:
		var next: Array[PackedVector2Array]=[]
		for piece in pieces: next.append_array(DistrictSurfaceGeometry.subtract(piece,polygon(hole)))
		pieces=next
	for piece in pieces:
		var indices:=Geometry2D.triangulate_polygon(piece)
		var vertices:=PackedVector3Array()
		for i in range(0,indices.size(),3):
			var a:=piece[indices[i]]; var b:=piece[indices[i+1]]; var c:=piece[indices[i+2]]
			if absf((b-a).cross(c-a))<.001: continue
			(kits[parent] as WorldMeshKit).tri(Vector3(a.x,y,a.y),Vector3(b.x,y,b.y),Vector3(c.x,y,c.y),Vector3.UP,surface_key)
			vertices.append_array([Vector3(a.x,y,a.y),Vector3(b.x,y,b.y),Vector3(c.x,y,c.y)])
			if surface_key!="dirt":
				# Broken roof panels need a visible, collidable underside as well as a top.
				(kits[parent] as WorldMeshKit).tri(Vector3(a.x,y-.18,a.y),Vector3(b.x,y-.18,b.y),Vector3(c.x,y-.18,c.y),Vector3.DOWN,surface_key)
				vertices.append_array([Vector3(a.x,y-.18,a.y),Vector3(c.x,y-.18,c.y),Vector3(b.x,y-.18,b.y)])
		if not vertices.is_empty():
			var shape:=ConcavePolygonShape3D.new(); shape.set_faces(vertices)
			collider(parent,Vector3.ZERO,shape,"concrete")
	if surface_key=="concrete":
		for opening in holes:
			var outline:=polygon(opening)
			for i in 4:
				var a:=outline[i]; var b:=outline[(i+1)%4]
				box(parent,Vector3((a.x+b.x)*.5,y-.09,(a.y+b.y)*.5),Vector3(maxf(.04,absf(a.x-b.x)),.18,maxf(.04,absf(a.y-b.y))),"rust",false)

func polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])

func shell(title: String,at: Vector3,size: Vector2,height: float) -> Node3D:
	var node:=section("Building_"+title,at)
	node.set_meta("building_id",title); node.set_meta("enterable",true); node.set_meta("building_bounds",AABB(Vector3(-size.x*.5,0,-size.y*.5),Vector3(size.x,height,size.y)))
	building_nodes.append(node)
	var rect:=Rect2(-size*.5,size)
	var footprint:=PackedVector2Array()
	for p in polygon(rect): footprint.append(p+Vector2(at.x,at.z))
	building_footprints.append(footprint)
	for z in [-size.y*.5,size.y*.5]: gap_wall(node,Vector3(-size.x*.5,0,z),Vector3(size.x*.5,0,z),4,0,height)
	for x in [-size.x*.5,size.x*.5]: gap_wall(node,Vector3(x,0,-size.y*.5),Vector3(x,0,size.y*.5),4,0,height)
	buildings.append({"id":title,"at":at,"purpose":title,"upper":height>6,"restricted":false})
	return node

func equipment(parent: Node3D,model: String,at: Vector3,yaw := 0.0,supported_by := "floor") -> Node3D:
	var prop: Node3D
	if model in ["campus_rack","water_pump","fuel_tank","office_desk","office_chair"]:
		prop=section(model+str(serial),at,parent); prop.rotation.y=yaw
		match model:
			"campus_rack":
				for x in [-2,2]:
					for z in [-.7,.7]: box(prop,Vector3(x,1.6,z),Vector3(.09,3.2,.09),"rust")
				for level in [.15,1.5,3]:
					box(prop,Vector3(0,level,0),Vector3(4.1,.1,1.5),"steel")
					if level<3:
						for x in [-1,1]: box(prop,Vector3(x,level+.45,0),Vector3(1.4,.8,1),"wood")
				prop.set_meta("bounds",AABB(Vector3(-2.1,0,-.8),Vector3(4.2,3.2,1.6)))
			"water_pump":
				box(prop,Vector3(0,.15,0),Vector3(1.8,.3,1.2),"concrete")
				(kits[prop] as WorldMeshKit).cylinder(Vector3(0,.65,0),.4,.8,"steel",2,12)
				for x in [-.7,.7]:
					box(prop,Vector3(x,1.3,0),Vector3(.15,2,.15),"steel")
					box(prop,Vector3(x,1.7,.22),Vector3(.4,.06,.4),"rust",false)
				prop.set_meta("bounds",AABB(Vector3(-.9,0,-.6),Vector3(1.8,2.3,1.2)))
			"fuel_tank":
				(kits[prop] as WorldMeshKit).cylinder(Vector3(0,1.2,0),.8,1.9,"rust",1,16)
				var shape:=CylinderShape3D.new(); shape.radius=.8; shape.height=1.9; collider(prop,Vector3(0,1.2,0),shape,"steel")
				box(prop,Vector3(0,.15,0),Vector3(1.9,.3,1.9),"concrete")
				prop.set_meta("bounds",AABB(Vector3(-.95,0,-.95),Vector3(1.9,2.2,1.9)))
			"office_desk":
				box(prop,Vector3(0,.76,0),Vector3(1.8,.08,.85),"wood")
				for x in [-.7,.7]: box(prop,Vector3(x,.36,0),Vector3(.1,.72,.65),"steel")
				prop.set_meta("bounds",AABB(Vector3(-.9,0,-.425),Vector3(1.8,.8,.85)))
			"office_chair":
				box(prop,Vector3(0,.48,0),Vector3(.55,.1,.5),"rubber")
				box(prop,Vector3(0,.85,-.23),Vector3(.55,.65,.09),"rubber")
				box(prop,Vector3(0,.24,0),Vector3(.08,.45,.08),"steel")
				for x in [-1,1]:
					box(prop,Vector3(x*.18,.07,0),Vector3(.36,.05,.5),"steel",false)
					for z in [-.2,.2]: box(prop,Vector3(x*.25,.05,z),Vector3(.08,.1,.1),"rubber",false)
				prop.set_meta("bounds",AABB(Vector3(-.3,0,-.3),Vector3(.6,1.2,.6)))
	elif model=="generator":
		prop=load("res://scenes/props/generator.tscn").instantiate(); add(parent,prop); prop.position=at; prop.rotation.y=yaw
	else: prop=asset(parent,model,at,yaw,false)
	prop.set_meta("campus_equipment",model); prop.set_meta("supported_by",supported_by)
	return prop

func bench(parent: Node3D,at: Vector3,instrument: String) -> void:
	equipment(parent,"clean_workbench",at)
	equipment(parent,instrument,at+Vector3(0,.96,0),0,"clean_workbench")

func room(parent: Node3D,title: String,at: Vector3,size: Vector2,role: String,roof_hole := false) -> Node3D:
	var node:=section(title.to_pascal_case().replace("/",""),at,parent)
	var w:=size.x*.5; var d:=size.y*.5
	node.set_meta("room_purpose",title); node.set_meta("room_role",role)
	node.set_meta("room_bounds",AABB(Vector3(-w,0,-d),Vector3(size.x,3.6,size.y)))
	node.set_meta("entry_local",Vector3(0,.1,d+.8))
	node.set_meta("clearance",AABB(Vector3(-.9,0,-d+.5),Vector3(1.8,2.4,size.y+.6)))
	segment(node,Vector3(-w,0,-d),Vector3(w,0,-d),3.6,"plaster")
	segment(node,Vector3(-w,0,-d),Vector3(-w,0,d),3.6,"plaster")
	segment(node,Vector3(w,0,-d),Vector3(w,0,d),3.6,"plaster")
	gap_wall(node,Vector3(-w,0,d),Vector3(w,0,d),2,0,3.6,"plaster")
	doorway(node,Vector3(0,0,d))
	var roof:=section("RoomRoof",Vector3.ZERO,node); roof.set_meta("campus_roof",true)
	if roof_hole:
		foundation(roof,Rect2(-w,-d,size.x,size.y),3.65,[Rect2(-1,-2,3,3)],"concrete")
	else: box(roof,Vector3(0,3.7,0),Vector3(size.x,.18,size.y),"concrete")
	# Work areas flank a reserved central approach. Equipment placement is role-specific.
	var x:=-w+2.1; var z:=-d+1.7
	match role:
		"analysis":
			bench(node,Vector3(x,0,z),"centrifuge"); bench(node,Vector3(-x,0,z),"microscope")
			equipment(node,"biosafety_cabinet",Vector3(x,0,1),PI/2)
			equipment(node,"wash_station",Vector3(-x,0,-1),-PI/2)
			bench(node,Vector3(-x,0,2.5),"analyzer")
		"microscopy":
			bench(node,Vector3(x,0,z),"microscope"); bench(node,Vector3(-x,0,z),"microscope")
		"preparation":
			equipment(node,"biosafety_cabinet",Vector3(x,0,z)); bench(node,Vector3(-x,0,z),"sample_rack")
			equipment(node,"eyewash",Vector3(-x,0,1))
		"sterile":
			equipment(node,"autoclave",Vector3(x,0,z)); equipment(node,"wash_station",Vector3(-x,0,z))
			equipment(node,"supply_cart",Vector3(x,0,1)); equipment(node,"eyewash",Vector3(-x,0,1))
		"cold":
			equipment(node,"ultra_freezer",Vector3(x,0,z)); equipment(node,"lab_fridge",Vector3(-x,0,z))
		"clinical","recovery","isolation":
			equipment(node,"recovery_bed" if role=="recovery" else "exam_bed",Vector3(x,0,0))
			equipment(node,"monitor_cart",Vector3(x+1.8,0,-2)); equipment(node,"iv_stand",Vector3(x-1,0,-2))
			equipment(node,"privacy_screen",Vector3(x+2.3,0,1.6),PI/2)
			equipment(node,"wash_station",Vector3(-x,0,z))
			if size.x>14 and role!="isolation":
				equipment(node,"recovery_bed" if role=="recovery" else "exam_bed",Vector3(-x,0,0))
				equipment(node,"monitor_cart",Vector3(-x-1.8,0,-2)); equipment(node,"iv_stand",Vector3(-x+1,0,-2))
				equipment(node,"privacy_screen",Vector3(-x-2.3,0,1.6),PI/2)
		"toilet":
			for side in [-1,1]:
				equipment(node,"toilet",Vector3(side*(w-1.3),0,z))
				box(node,Vector3(side*(w-2.5),1.1,z+.4),Vector3(.08,2.2,2.5),"paint")
				box(node,Vector3(side*(w-1.3),1.1,z+1.7),Vector3(2.3,2.2,.08),"paint")
			# Stall access faces sideways, away from the corridor sightline.
			equipment(node,"wash_station",Vector3(-x,0,2),-PI/2)
		"office","control","records","meeting":
			if role=="meeting": equipment(node,"break_table",Vector3(x,0,0))
			else:
				equipment(node,"office_desk",Vector3(x,0,z)); equipment(node,"terminal",Vector3(x,.8,z),0,"office_desk")
			equipment(node,"office_chair",Vector3(x,0,z+1.5),PI)
			if role=="control": equipment(node,"monitor_cart",Vector3(-x,0,z))
		"staff":
			equipment(node,"staff_locker",Vector3(x,0,z)); equipment(node,"staff_locker",Vector3(x+1.1,0,z))
			equipment(node,"break_table",Vector3(-x,0,0)); equipment(node,"exam_chair",Vector3(-x,0,1.5),PI)
		"receiving","packing":
			equipment(node,"packing_table",Vector3(x,0,z)); equipment(node,"roll_cage",Vector3(-x,0,z))
			equipment(node,"pallet_jack",Vector3(-x,0,1),PI/2)
		"utility","generator","pump","electrical":
			equipment(node,"air_handler" if role=="utility" else "electrical_panel",Vector3(x,0,z))
			equipment(node,"work_cart",Vector3(-x,0,z))
			if role=="generator": equipment(node,"generator",Vector3(-x,0,1))
			if role=="pump": equipment(node,"water_pump",Vector3(x,0,1))
		"workshop":
			equipment(node,"instrument_bench",Vector3(x,0,z)); equipment(node,"work_cart",Vector3(-x,0,1))
		"decon":
			equipment(node,"shower",Vector3(x,0,z)); equipment(node,"wash_station",Vector3(-x,0,z))
		"containment":
			equipment(node,"recovery_bed",Vector3(x,0,z)); equipment(node,"privacy_screen",Vector3(-x,0,z),PI/2)
			equipment(node,"monitor_cart",Vector3(x,0,1))
		"waiting":
			equipment(node,"nurse_desk",Vector3(x,0,z))
			for offset in [-1.5,0,1.5]: equipment(node,"exam_chair",Vector3(-x,0,offset),PI/2)
		"security","medical","store": pass
		_: assert(false,"Unknown campus room role: "+role)
	if "toilet" in title.to_lower() and role=="staff":
		equipment(node,"toilet",Vector3(w-1.2,0,-d+1))
		box(node,Vector3(w-2.4,1.1,-d+1.2),Vector3(.08,2.2,2.4),"paint")
		box(node,Vector3(w-1.2,1.1,-d+2.4),Vector3(2.3,2.2,.08),"paint")
	if title=="IT closet": equipment(node,"server_rack",Vector3(-x,0,1))
	if "kitchenette" in title:
		equipment(node,"wash_station",Vector3(x,0,1),PI/2)
	if title in ["Human trials","Failed containment"]:
		box(node,Vector3(x,.9,0),Vector3(.6,.25,1.6),"medical",false)
		box(node,Vector3(x,1.04,-.5),Vector3(.5,.08,.3),"wood",false)
	if title in ["Trial control","Cure transfer archive"]:
		sign_board(node,"campus_cure_transfer",Vector3(0,2.4,-d+.15),3)
	if title=="Failed containment": sign_board(node,"campus_trial_notice",Vector3(0,2.4,-d+.15),3)
	# A physical printed panel is mounted above each doorway, without floating text.
	var sign:=MeshInstance3D.new(); var face:=QuadMesh.new(); face.size=Vector2(2.8,.525); sign.mesh=face
	var material:=StandardMaterial3D.new(); material.albedo_texture=load("res://assets/district/signs/campus_"+title.to_snake_case().replace("/","_").replace(" ","_")+".png")
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST; material.roughness=.95; sign.material_override=material
	sign.position=Vector3(0,2.8,d+.12); sign.set_meta("sign_text",title); add(node,sign,"RoomSign")
	# Purpose-built storage uses the same profile rules as the existing raid authority.
	var model:="med_cabinet" if role in ["clinical","recovery","medical","isolation"] else "specimen_cooler" if role in ["analysis","microscopy","preparation","cold"] else "filing_cabinet" if role in ["office","control","records","meeting","waiting"] else "staff_locker" if role=="staff" else "security_locker" if role=="security" else "tool_drawers"
	var data:={"name":title,"building":parent.get_meta("building_id"),"role":role,"at":world_transform(node).origin,"size":size,"node":node,"model":model,"sources":0,"pickups":0,"roof_hole":roof_hole}
	rooms.append(data); room_nodes.append(node)
	for side in [-1,1]:
		var marker:=Marker3D.new(); add(node,marker,"RoomCover"+str(side))
		marker.position=Vector3(side*(w-1),.1,0); marker.rotation.y=0 if side>0 else PI
		marker.add_to_group("district_cover",true)
	if role!="toilet":
		lamp(node,Vector3(0,3.4,d-1),true)
		# Cable runs visibly feed emergency fixtures from the facilities distribution.
		box(node,Vector3(0,3.52,0),Vector3(.06,.06,size.y),"rust",false)
	# Recessed peeling wall patches and rising damp have a physical cause.
	for i in 3:
		box(node,Vector3(-w+.112,.25+i*.32,-d+1+i*.7),Vector3(.015,.3,1.3),"rust" if i==2 else "contamination",false)
	if roof_hole:
		for i in 4:
			box(node,Vector3(1+i*.3,.08, -1+i*.7),Vector3(.55,.16,.45),"concrete")
		box(node,Vector3(1.2,1,-d+.2),Vector3(.12,2,1.4),"contamination",false)
	return node

func stair(parent: Node3D,x: float,z: float,base: float,up: bool,title: String) -> void:
	var node:=section(title,Vector3(x,base,z),parent)
	# 24 real 175 mm risers, 500 mm treads; smooth collision follows the same slope.
	var height:=FLOOR_HEIGHT if up else -FLOOR_HEIGHT
	var points:=PackedVector3Array()
	for side in [-1,1]:
		points.append_array([Vector3(side*1.5,-.25,6),Vector3(side*1.5,height-.25,-6),Vector3(side*1.5,height,-6),Vector3(side*1.5,0,6)])
	var shape:=ConvexPolygonShape3D.new(); shape.points=points; collider(node,Vector3.ZERO,shape,"concrete")
	for i in 24:
		var y:=height*float(i+1)/24
		box(node,Vector3(0,y-.06,5.75-i*.5),Vector3(3,.12,.5),"concrete",false)
		for side in [-1,1]:
			box(node,Vector3(side*1.55,y+.6,5.75-i*.5),Vector3(.06,1.2,.06),"rust")
			box(node,Vector3(side*1.55,y+1.2,5.75-i*.5),Vector3(.07,.07,.55),"rust",false)
	if up and title.begins_with("Administration"):
		for side in [-1,1]: box(node,Vector3(side*1.8,FLOOR_HEIGHT+.65,0),Vector3(.08,1.3,12),"rust")
		box(node,Vector3(0,FLOOR_HEIGHT+.65,6),Vector3(3.6,1.3,.08),"rust")
	stairs.append({"name":title,"start":world_transform(node)*Vector3(0,.05,7),"end":world_transform(node)*Vector3(0,height+.05,-7),"restricted":not up})
	area_record(title,world_transform(node)*Vector3(0,1,7),"vertical circulation","floor corridors","treads, rails, emergency cable","no mandatory combat bottleneck")
	var start: Vector3=stairs[-1].start+Vector3.UP*1.6
	var end: Vector3=stairs[-1].end+Vector3.UP*1.6
	review_view(start,end); review_view(end,start,true)
	if not up:
		for side in [-1,1]: segment(node,Vector3(side*1.8,-FLOOR_HEIGHT,-8),Vector3(side*1.8,-FLOOR_HEIGHT,8),8)
		box(node,Vector3(0,1.85,-8),Vector3(3.6,3.7,.2),"concrete")
		box(node,Vector3(0,-2.1,8),Vector3(3.6,4.2,.2),"concrete")
		gap_wall(node,Vector3(-1.8,0,8),Vector3(1.8,0,8),2)
		doorway(node,Vector3(0,0,8),true)
		var door:=doors[-1]
		var link:=node.get_node("ResearchAccessLink") as NavigationLink3D
		link.start_position=Vector3(0,.1,10); link.end_position=Vector3(0,-.1,6)
		door.set_meta("campus_gate",title)

func poi_content() -> void:
	var lab:=shell("research",Vector3(0,0,-10),Vector2(110,100),4)
	var holes: Array[Rect2]=[Rect2(-49.8,-6,3.6,12),Rect2(47.2,2,3.6,12)]
	foundation(lab,Rect2(-55,-50,110,100),0,holes)
	# Building-relative lab coordinates preserve a west research/clinical wing and east connector.
	var research: Array=[ ["Specimen receiving and sorting","receiving"],["Sample preparation","preparation"],["Central analysis","analysis"],["Microscopy","microscopy"],["Instrumentation","analysis"],["Cold and freezer storage","cold"],["Reagent store","cold"],["Clean supplies","store"],["Wash and sterilization","sterile"],["Research office and records","records"],["Equipment service","workshop"],["Decontamination","decon"] ]
	for i in research.size():
		var at:=Vector3(-43+(i%4)*22,0,-39+(i/4)*20)
		var size:=Vector2(18,14)
		# The wash suite shares a service wall with the separated western stairwell.
		if i==8: at.x=-39; size.x=14
		room(lab,research[i][0],at,size,research[i][1],i in [7,10])
	var clinical: Array=[["Consent and consultation","office"],["Participant examination","clinical"],["Sample collection","clinical"],["Procedure room","clinical"],["Nursing and monitored recovery","recovery"],["Clinical supplies","medical"],["Staff changing","staff"],["Labs toilets","toilet"]]
	for i in clinical.size(): room(lab,clinical[i][0],Vector3(-43+(i%4)*22,0,23+(i/4)*16),Vector2(18,12),clinical[i][1])
	room(lab,"Reception and screening",Vector3(45,0,36),Vector2(12,18),"waiting")
	stair(lab,-48,0,0,false,"BasementStairWest")
	stair(lab,49,8,0,false,"BasementStairEast")
	var basement:=section("RestrictedBasement",Vector3(0,-FLOOR_HEIGHT,0),lab)
	basement.set_meta("building_id","research")
	foundation(basement,Rect2(-55,-50,110,65),0)
	for line in [[Vector3(-55,0,-50),Vector3(55,0,-50)],[Vector3(-55,0,15),Vector3(55,0,15)],[Vector3(-55,0,-50),Vector3(-55,0,15)],[Vector3(55,0,-50),Vector3(55,0,15)]]: segment(basement,line[0],line[1],4.1)
	var restricted: Array=[["Trial control","control"],["Trial observation","control"],["Human trials","clinical"],["Failed containment","containment"],["Isolation","isolation"],["Specimen vault","cold"],["Cure transfer archive","records"],["Basement medical store","medical"],["Basement security control","security"],["Ventilation and service","utility"],["Waste holding","utility"]]
	for i in restricted.size(): room(basement,restricted[i][0],Vector3(-34+(i%4)*22,0,-39+(i/4)*20),Vector2(18,14),restricted[i][1])
	var clinic:=shell("outpatient",Vector3(0,0,100),Vector2(90,40),8.2)
	foundation(clinic,Rect2(-45,-20,90,40),0)
	foundation(clinic,Rect2(-45,-20,90,40),FLOOR_HEIGHT,[Rect2(-41.8,-6,3.6,12),Rect2(38.2,-6,3.6,12)])
	var outpatient: Array=[["Public waiting and reception","waiting"],["Triage","clinical"],["Consultation and exam one","clinical"],["Consultation and exam two","clinical"],["Treatment","clinical"],["Dispensary","medical"],["Public records and reception support","records"],["Outpatient staff room","staff"],["Public toilets","toilet"],["Staff toilets","toilet"]]
	for i in outpatient.size(): room(clinic,outpatient[i][0],Vector3(-30+(i%5)*15,0,-9+(i/5)*18),Vector2(11,12),outpatient[i][1])
	var admin: Array=[["Administration open office","office"],["Manager office","office"],["Meeting room","meeting"],["Administration archive","records"],["IT closet","control"],["Staff kitchenette and toilet","staff"]]
	for i in admin.size(): room(clinic,admin[i][0],Vector3(-24+(i%3)*24,FLOOR_HEIGHT,-9+(i/3)*18),Vector2(18,12),admin[i][1],i==3)
	for x in [-40,40]: stair(clinic,x,0,0,true,"AdministrationStairWest" if x<0 else "AdministrationStairEast")
	var logistics:=shell("logistics",Vector3(110,0,-5),Vector2(50,80),8.5)
	foundation(logistics,Rect2(-25,-40,50,80),0)
	foundation(logistics,Rect2(-25,-40,50,25),FLOOR_HEIGHT)
	room(logistics,"Receiving inspection",Vector3(-12,0,-30),Vector2(18,14),"receiving")
	room(logistics,"Cold chain storage",Vector3(12,0,-30),Vector2(18,14),"cold")
	room(logistics,"Logistics workshop",Vector3(-12,0,10),Vector2(18,14),"workshop",true)
	room(logistics,"Packing and dispatch",Vector3(12,0,10),Vector2(18,14),"packing")
	room(logistics,"Logistics staff and toilets",Vector3(-12,0,30),Vector2(18,14),"staff")
	room(logistics,"Secure equipment cage",Vector3(12,0,30),Vector2(18,14),"security")
	room(logistics,"Dispatch mezzanine office",Vector3(0,FLOOR_HEIGHT,-29),Vector2(22,14),"office")
	for x in [-21,21]: stair(logistics,x,-10,0,true,"DispatchStairWest" if x<0 else "DispatchStairEast")
	for x in [-12,-4,4,12]:
		equipment(logistics,"campus_rack",Vector3(x,0,-5))
	box(logistics,Vector3(0,FLOOR_HEIGHT+.65,-15),Vector3(38,1.3,.08),"rust")
	area_record("Bulk rack hall",Vector3(110,1.6,-12),"bulk storage with cross aisle","receiving, dispatch, apron","pallet racks with vehicle access","scavenger salvage")
	var facilities:=shell("facilities",Vector3(-110,0,5),Vector2(40,60),4)
	foundation(facilities,Rect2(-20,-30,40,60),0)
	var services: Array=[["Security desk and control","control"],["Security equipment store","security"],["Facilities changing and toilet","staff"],["Maintenance workshop","workshop"],["Electrical switchgear","electrical"],["Generator plant","generator"],["Water and pump room","pump"],["Janitor store","utility"]]
	for i in services.size(): room(facilities,services[i][0],Vector3(-10+(i%2)*20,0,-22+(i/2)*15-(2 if i>=6 else 0)),Vector2(16,10),services[i][1],i==7)
	# Fixed positions are authored before raid loot rolls, and never generated at runtime.
	populate_sources()
	grounds_detail()
	for index in layout.positions.size():
		var poi:=section("Arrival_"+DistrictLayout.POIS[index],Vector3(layout.positions[index].x,0,layout.positions[index].y))
		poi.set_meta("poi_id",DistrictLayout.POIS[index])
		sign_board(poi,["research","medical","warehouse","substation"][index],Vector3(0,3,-2),4)
	for data in rooms:
		if data.at.y<0 or data.building=="research": actor_points.append(data.at+Vector3(0,.1,2))
	for data in rooms:
		if data.at.y>=0 and data.building!="research": actor_points.append(data.at+Vector3(0,.1,2))
	scene.set_meta("campus_stairs",stairs)
	var audit: Array[Dictionary]=[]
	for data in rooms:
		var equipment_list: Array[String]=[]
		var storage_list: Array[String]=[]
		for node in data.node.get_children():
			if node.has_meta("campus_equipment"): equipment_list.append(node.get_meta("campus_equipment"))
			if node is SearchableFurniture: storage_list.append(node.display_name+" ("+node.loot_profile+")")
		var at: Vector3=data.at
		var nearby: Array[String]=[]
		for other in rooms:
			if other.name!=data.name and other.building==data.building and absf(other.at.y-at.y)<.1 and other.at.distance_to(at)<27: nearby.append(other.name)
		var entry: Vector3=world_transform(data.node)*data.node.get_meta("entry_local")
		audit.append({"name":data.name,"building":data.building,"at":[at.x,at.y,at.z],"purpose":data.role,"adjoining":data.building+" circulation","nearby_rooms":nearby,"entrances":{"width_m":2,"position":[entry.x,entry.y,entry.z]},"equipment":equipment_list,"service_access":"front equipment access and reserved 1.8 m center aisle","loot":{"searchable":data.sources,"loose_sockets":data.pickups,"containers":storage_list},"encounter":"optional room search; perimeter circulation remains open","corrected":"purpose-specific equipment; supported instruments; inward-facing storage; no generic workstation grid","roof_hole":data.roof_hole})
	for data in areas: audit.append(data)
	scene.set_meta("campus_audit",audit)
	var file:=FileAccess.open("res://.godot/district-build/campus-area-audit.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(audit,"\t"))

func populate_sources() -> void:
	var allocations:={"research":80,"outpatient":24,"logistics":16,"facilities":8}
	var loose_allocations:={"research":56,"outpatient":16,"logistics":16,"facilities":8}
	for identity: String in allocations:
		var group:=rooms.filter(func(r): return r.building==identity and r.role!="toilet")
		for index in int(allocations[identity]):
			var data: Dictionary=group[index%group.size()]
			var node: Node3D=data.node
			var n: int=data.sources
			# Dedicated back-wall storage leaves the center aisle and equipment fronts free.
			var at:=Vector3(-data.size.x*.5+2+n*1.8,0,data.size.y*.5-1.1)
			if data.size.x<=14 and n>=2: at=Vector3(-data.size.x*.5+2,0,data.size.y*.5-3.5)
			var candidate: bool=n==0 and data.name in ["Security desk and control","Staff changing","Research office and records","Dispatch mezzanine office"]
			var guarantee: Dictionary={}
			if n==0 and data.name=="Basement medical store": guarantee={"infection_suppressant":2}
			if n==0 and data.name in ["Trial control","Cure transfer archive"]: guarantee={"research_drive":1}
			var model: String=data.model
			if data.role=="security": model="weapon_crate" if n%2==0 else "ammo_box"
			var source:=furnishing(node,at,model,candidate,guarantee)
			source.rotation.y=PI
			# Room-specific containers cannot silently inherit a broader technical profile.
			source.set_meta("campus_room",data.name)
			data.sources+=1
		for index in int(loose_allocations[identity]):
			var data: Dictionary=group[index%group.size()]
			var n: int=data.pickups
			var at:=Vector3(data.size.x*.5-2.1,0,data.size.y*.5-1.5)
			if n==0: equipment(data.node,"storage_table",at)
			var item:="sterile_lab_supplies" if data.model=="specimen_cooler" else "research_notes" if data.model=="filing_cabinet" else "medkit" if data.model=="med_cabinet" else "salvage"
			pickup(data.node,at+Vector3(-.7+n*.7,1.01,0),item)
			data.pickups+=1

func grounds_detail() -> void:
	var yard:=section("ReclaimedGrounds")
	# Structural frame survives where roof panels have fallen; damage is localized.
	for node in building_nodes:
		var bounds: AABB=node.get_meta("building_bounds")
		for x in [-bounds.size.x*.5+.4,bounds.size.x*.5-.4]:
			for z in range(int(-bounds.size.z*.5)+3,int(bounds.size.z*.5),10):
				box(node,Vector3(x,bounds.size.y*.5,z),Vector3(.5,bounds.size.y,.5),"concrete")
		for z in range(int(-bounds.size.z*.5)+3,int(bounds.size.z*.5),10):
			box(node,Vector3(0,bounds.size.y-.2,z),Vector3(bounds.size.x,.3,.18),"rust",false)
			# Hanging ivy follows exposed facades, away from doors and movement lanes.
			for side in [-1,1]:
				# Dark sealed glazing and surviving frames break up the stripped facades.
				box(node,Vector3(side*(bounds.size.x*.5+.12),2.2,z),Vector3(.06,1.4,3),"glass",false)
				for edge in [-1,1]: box(node,Vector3(side*(bounds.size.x*.5+.17),2.2,z+edge*1.55),Vector3(.08,1.6,.08),"rust",false)
				box(node,Vector3(side*(bounds.size.x*.5+.17),1.5,z),Vector3(.2,.1,3.2),"concrete",false)
				for leaf in 5:
					(kits[node] as WorldMeshKit).cylinder(Vector3(side*(bounds.size.x*.5+.3),.35+leaf*.46,z+sin(leaf*2.4)*.5),.4,.6,"contamination",1,5)
				# Fallen roofing stays against its source facade, away from doorways.
				box(node,Vector3(side*(bounds.size.x*.5+2),.18,z+2),Vector3(1.4,.36,2),"concrete")
				box(node,Vector3(side*(bounds.size.x*.5+2),.4,z+2),Vector3(1.7,.08,2.4),"rust",false)
		for x in range(int(-bounds.size.x*.5)+7,int(bounds.size.x*.5)-6,8):
			if abs(x)<5: continue
			for side in [-1,1]:
				box(node,Vector3(x,2.2,side*(bounds.size.z*.5+.12)),Vector3(2.8,1.4,.06),"glass",false)
				box(node,Vector3(x,1.5,side*(bounds.size.z*.5+.17)),Vector3(3,.1,.2),"concrete",false)
		var front:=bounds.size.z*.5
		box(node,Vector3(0,3.2,front+1.2),Vector3(4.4,.15,2.6),"rust")
		for side in [-1,1]: box(node,Vector3(side*2.1,1.6,front+2.3),Vector3(.12,3.2,.12),"rust")
		for z in range(int(-bounds.size.z*.5)+6,int(bounds.size.z*.5)-5,10):
			for side in [-1,1]:
				var marker:=Marker3D.new(); add(node,marker,"FacadeCover%d"%serial)
				marker.position=Vector3(side*(bounds.size.x*.5+1.2),.1,z); marker.rotation.y=PI if side>0 else 0
				marker.add_to_group("district_cover",true)
		for x in range(int(-bounds.size.x*.5)+6,int(bounds.size.x*.5)-5,10):
			for side in [-1,1]:
				var marker:=Marker3D.new(); add(node,marker,"FacadeCover%d"%serial)
				marker.position=Vector3(x,.1,side*(bounds.size.z*.5+1.2)); marker.rotation.y=PI*.5 if side>0 else -PI*.5
				marker.add_to_group("district_cover",true)
	for side in [-1,1]:
		for i in 6:
			var at:=Vector3(side*68,0,-58+i*20)
			equipment(yard,"wrapped_pallet",at)
			var marker:=Marker3D.new(); add(yard,marker,"CampusCover%d"%serial)
			marker.position=at+Vector3(-1.7,.1,0); marker.add_to_group("district_cover",true)
	for i in 6:
		var at:=Vector3(-125+i*48,0,-115)
		cover_asset(yard,"concrete_barricade",at)
	for i in 7:
		var at:=Vector3(-122+i*40,0,128)
		cover_asset(yard,"concrete_barricade",at)
	for at in [Vector3(-103,0,90),Vector3(-84,0,110),Vector3(-70,0,88)]:
		cover_asset(yard,"damaged_car",at,.1)
	cover_asset(yard,"industrial_truck",Vector3(118,0,62),PI*.5)
	# Fuel is bunded, kept outside the generator room, and separated from waste.
	for x in [-123,-117]: equipment(yard,"fuel_tank",Vector3(x,0,48))
	for line in [[Vector3(-127,0,44),Vector3(-113,0,44)],[Vector3(-127,0,52),Vector3(-113,0,52)],[Vector3(-127,0,44),Vector3(-127,0,52)]]: segment(yard,line[0],line[1],.6)
	for i in 3: equipment(yard,"trash_bin",Vector3(-105+i*2,0,48))
	for z in [43,53]: segment(yard,Vector3(-109,0,z),Vector3(-96,0,z),2,"rust")
	segment(yard,Vector3(-96,0,43),Vector3(-96,0,53),2,"rust")
	# The surviving generator's above-ground feeder follows the service circuit.
	for x in range(-130,136,15):
		box(yard,Vector3(x,3.8,-77),Vector3(.15,7.6,.15),"rust")
		box(yard,Vector3(x+7.5,7.3,-77),Vector3(15,.05,.05),"steel",false)
	for node in building_nodes:
		var at:=node.position
		box(yard,Vector3(at.x,7.3,(at.z-77)*.5),Vector3(.05,.05,absf(at.z+77)),"steel",false)
		box(yard,Vector3(at.x,5.5,at.z),Vector3(.1,3.6,.1),"rust",false)
	for data in rooms:
		if data.roof_hole:
			area_record(data.name+" roof failure",data.at+Vector3(0,1.6,3),"water ingress and local collapse",data.name,"broken panel edges, supported rubble, exposed frame","optional search remains navigable")
			review_view(data.at+Vector3(0,1.65,data.size.y*.5-1),data.at+Vector3(.5,3.6,-.5))
	for view in [["research",Vector3(44,1.65,-35),Vector3(44,1.65,-5)],["outpatient",Vector3(0,1.65,100),Vector3(32,1.65,100)],["logistics",Vector3(110,1.65,16),Vector3(110,1.65,-18)],["facilities",Vector3(-110,1.65,5),Vector3(-110,1.65,25)],["administration upper",Vector3(0,5.85,100),Vector3(32,5.85,100)],["dispatch upper",Vector3(110,5.85,-24),Vector3(129,5.85,-24)]]:
		area_record(view[0]+" circulation",view[1],"department circulation","room doors and exterior exits","clear corridors, structural frame","alternate exits")
		review_view(view[1],view[2])

func vegetation() -> void:
	var rng:=RandomNumberGenerator.new(); rng.seed=DistrictLayout.stream(19381,"vegetation",2)
	var forest:=section("AbandonedWoodland")
	var kit:=WorldMeshKit.new()
	kit.cylinder(Vector3(0,2.5,0),.22,5,"wood",1,8)
	for i in 4: kit.cylinder(Vector3(0,3+i*.6,0),2-i*.35,.8,"contamination",1,7)
	var visual:=DistrictFoliage.new(); visual.multimesh=MultiMesh.new(); visual.multimesh.transform_format=MultiMesh.TRANSFORM_3D
	visual.multimesh.mesh=kit.finish(); visual.multimesh.instance_count=110
	var positions: Array[Vector3]=[]
	for attempt in 10000:
		if positions.size()==110: break
		var at:=Vector3(rng.randf_range(-166,166),0,rng.randf_range(-166,166))
		var clear:=true
		for node in building_nodes:
			var bounds: AABB=node.get_meta("building_bounds")
			if (node.transform*bounds).grow(4).has_point(at+Vector3.UP): clear=false; break
		if not clear: continue
		for patch in paving:
			if Geometry2D.is_point_in_polygon(Vector2(at.x,at.z),patch.polygon): clear=false; break
			for i in patch.polygon.size():
				if Geometry2D.get_closest_point_to_segment(Vector2(at.x,at.z),patch.polygon[i],patch.polygon[(i+1)%patch.polygon.size()]).distance_to(Vector2(at.x,at.z))<3: clear=false; break
			if not clear: break
		if absf(at.x)>150 or absf(at.z)>150: clear=false
		if not clear: continue
		if positions.any(func(p): return p.distance_to(at)<4): continue
		positions.append(at)
	visual.multimesh.instance_count=positions.size()
	for at in positions:
		visual.instance_transforms.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU),at))
		var shape:=CylinderShape3D.new(); shape.radius=.22; shape.height=4
		collider(forest,at+Vector3.UP*2,shape,"wood")
	add(forest,visual,"TreeInstances")

func gameplay(definition: RaidMapDefinition) -> void:
	# Explicit faction distribution: infected occupy research; scavs work salvage routes.
	var infected: Array[Vector3]=[]; var scavs: Array[Vector3]=[]
	for data in rooms:
		var at: Vector3=data.at+Vector3(0,.1,0)
		if data.role=="toilet": continue
		if data.building=="research": infected.append(at)
		elif data.at.y>=0: scavs.append(at)
	actor_points.clear()
	for i in 18: actor_points.append(infected[(i*3)%infected.size()])
	for i in 10: actor_points.append(scavs[(i*3)%scavs.size()])
	super.gameplay(definition)
