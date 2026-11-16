extends RefCounted

var b
var signs: Dictionary={}
var sign_nodes: Dictionary={}
var rooms: Array[Dictionary]=[]
var sources: Array[RaidEntity]=[]
var pickups: Array[RaidLootPickup]=[]
var bake_proxies: Array[Node]=[]
var fixture_serial:=0
var route_serial:=0
var slot_serial:=0
var cache: Dictionary={}
var surface_cache: Dictionary={}
var tile_textures: Dictionary={}
var loot_profiles: Dictionary={}

func profile_for_model(model: String) -> String:
	if model in ["medical_bag","med_cabinet","medicine_fridge"]: return "medical"
	if model in ["specimen_cooler","lab_fridge","ultra_freezer"]: return "specimen"
	if model in ["filing_cabinet","desk_drawers"]: return "records"
	if model in ["staff_locker","personal_bag"]: return "personal"
	if model=="security_locker": return "security_gear"
	if model in ["weapon_box","weapon_crate"]: return "weapons"
	if model=="ammo_box": return "ammo"
	return "technical"

func room_model(data: Dictionary) -> String:
	if data.role in ["medical_store","clinical","recovery"]: return "med_cabinet"
	if data.role=="cold": return "lab_fridge"
	if "SECURITY" in data.title: return "security_locker"
	if data.role in ["office","records"]: return "filing_cabinet"
	if data.role in ["staff","washroom"]: return "staff_locker"
	if data.role=="laboratory": return "specimen_cooler"
	return "tool_drawers"

func textured(color: String) -> StandardMaterial3D:
	if surface_cache.has(color): return surface_cache[color]
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color(color).lightened(0.15)
	var tile:=4 if color in ["333f30","444b45","61645b","343a35"] else 0
	if not tile_textures.has(tile):
		var atlas:=Image.new()
		atlas.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/medtac/materials.png"))
		var image:=atlas.get_region(Rect2i((tile%8)*128,(tile/8)*128,128,128))
		# Neutral roughness/wear modulates paint; furniture branding stays on equipment.
		for iy in range(128):
			for ix in range(128):
				var level:=clampf(image.get_pixel(ix,iy).r+.35,.55,1)
				image.set_pixel(ix,iy,Color(level,level,level))
		var path:="res://assets/medtac/surface_%d.png"%tile
		image.save_png(path)
		var texture:=ImageTexture.create_from_image(image)
		texture.take_over_path(path)
		tile_textures[tile]=texture
	material.albedo_texture=tile_textures[tile]
	material.uv1_triplanar=true
	material.uv1_scale=Vector3.ONE*.22
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness=.9
	surface_cache[color]=material
	return material

func physical_sign(parent: Node3D, text: String, at: Vector3, yaw: float, size: int, _color: Color) -> void:
	var cleaned:=text.replace("[E] ","").replace("passage-","ACCESS ")
	var key:=cleaned.sha256_text().substr(0,16)
	signs[key]=cleaned
	var width:=clampf(float(size)*.045,1.0,4.5)
	var height:=maxf(.35,width*.22*cleaned.split("\n").size())
	var root:=Node3D.new()
	b.add(parent,root,"MountedSign%d"%b.serial)
	root.position=at
	root.rotation.y=yaw
	b.box(root,Vector3.ZERO,Vector3(width+.08,height+.08,.08),"343a35",false)
	var quad:=MeshInstance3D.new()
	var mesh:=QuadMesh.new()
	mesh.size=Vector2(width,height)
	quad.mesh=mesh
	quad.position.z=.046
	var material:=StandardMaterial3D.new()
	material.roughness=.9
	quad.material_override=material
	b.add(root,quad,"PrintedFace")
	quad.set_meta("sign_text",cleaned)
	if not sign_nodes.has(key): sign_nodes[key]=[]
	sign_nodes[key].append(quad)
	# Physical brackets suspend each panel from a ceiling or carry it on posts outdoors.
	var floor_y:=-10.0 if at.y<0 else 0.0
	var indoors:=at.z<-25 and at.x>-240 and at.x<275
	if indoors:
		var ceiling:=5.1 if at.y>=0 else -5.6
		var length:=maxf(.15,ceiling-at.y-height*.5)
		for x in [-width*.35,width*.35]: b.box(root,Vector3(x,height*.5+length*.5,0),Vector3(.035,length,.035),"444b45",false)
	else:
		var length:=maxf(.15,at.y-floor_y)
		for x in [-width*.42,width*.42]: b.box(root,Vector3(x,-length*.5,0),Vector3(.06,length,.06),"444b45",false)

func finish_signs() -> void:
	var file:=FileAccess.open("res://.godot/medtac-signs.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(signs))
	file.close()
	var output: Array=[]
	if OS.execute("python",[ProjectSettings.globalize_path("res://tools/build_medtac_textures.py")],output,true)!=0: push_error(str(output))
	for key: String in sign_nodes:
		var image:=Image.new()
		image.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/medtac/signs/"+key+".png"))
		var texture:=ImageTexture.create_from_image(image)
		texture.take_over_path("res://assets/medtac/signs/"+key+".png")
		for node: MeshInstance3D in sign_nodes[key]:
			node.material_override.albedo_texture=texture
			node.material_override.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST

func equipment_label(parent: Node3D, text: String, at: Vector3, size: Vector2, flat:=false) -> void:
	var key:=text.sha256_text().substr(0,16)
	signs[key]=text
	var face:=MeshInstance3D.new()
	var quad:=QuadMesh.new()
	quad.size=size
	face.mesh=quad
	face.material_override=StandardMaterial3D.new()
	b.add(parent,face,"PrintedContainerLabel")
	face.position=at
	if flat: face.rotation.x=-PI/2
	face.set_meta("sign_text",text)
	if not sign_nodes.has(key): sign_nodes[key]=[]
	sign_nodes[key].append(face)

func prop(parent: Node3D, identity: String, at: Vector3, yaw:=0.0, collision:=true) -> Node3D:
	var path:="res://scenes/props/medtac/detail/"+identity+".tscn"
	if not cache.has(path): cache[path]=load(path)
	var node: Node3D=cache[path].instantiate()
	b.add(parent,node)
	node.position=at
	node.rotation.y=yaw
	if not collision:
		for child in node.find_children("*","CollisionObject3D",true,false): child.collision_layer=0
	return node

func source(parent: Node3D, identity: String, at: Vector3, model: String, category: String, candidate:=false, guaranteed: Dictionary={}) -> SearchableFurniture:
	var node:=SearchableFurniture.new()
	node.entity_id=identity
	node.display_name=model.replace("_"," ").capitalize()
	node.kind="container"
	node.material=b.steel
	node.keycard_candidate=candidate
	node.guaranteed_items=guaranteed
	node.opening="drawer" if model in ["desk_drawers","tool_drawers","filing_cabinet"] else "lid" if model in ["personal_bag","medical_bag","specimen_cooler","shipping_crate","cold_chain_crate","weapon_box","weapon_crate","ammo_box"] else "hinge"
	node.loot_profile=profile_for_model(model)
	if loot_profiles.is_empty(): loot_profiles=JSON.parse_string(FileAccess.get_file_as_string("res://resources/medtac/loot_profiles.json"))
	node.loot_table=b.table(loot_profiles[node.loot_profile])
	b.add(parent,node,identity)
	node.position=at
	node.add_to_group("raid_entities",true)
	var visual:=prop(node,model,Vector3.ZERO,0,false)
	var bounds: AABB=visual.get_meta("bounds")
	var shape:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=bounds.size
	shape.shape=box
	shape.position=bounds.get_center()
	b.add(node,shape,"CollisionShape3D")
	node.interaction_offset=bounds.get_center()+Vector3(0,0,.05)
	if model=="medical_bag": equipment_label(node,"MEDICAL",Vector3(0,.24,.215),Vector2(.48,.14))
	if model!="supply_cart":
		# Separate hollow cabinet/case and moving door, rather than opening a panel over a solid box.
		visual.visible=false
		var w:=bounds.size.x
		var h:=bounds.size.y
		var d:=bounds.size.z
		var case_paint:="455c49" if node.loot_profile=="weapons" else "766b3e" if node.loot_profile=="ammo" else "c1c7b6" if node.loot_profile=="medical" else "728c86" if node.loot_profile=="specimen" else "697970"
		if model=="personal_bag": case_paint="75644b"
		for side in [-1,1]: b.box(node,Vector3(side*w*.48,h*.5,0),Vector3(.06,h,d),case_paint,false)
		b.box(node,Vector3(0,h*.5,-d*.48),Vector3(w,h,.06),"444b45",false)
		b.box(node,Vector3(0,.035,0),Vector3(w,.07,d),"697970",false)
		if node.opening!="lid":
			b.box(node,Vector3(0,h-.035,0),Vector3(w,.07,d),"697970",false)
			for shelf_y in [h*.33,h*.66]: b.box(node,Vector3(0,shelf_y,0),Vector3(w-.08,.035,d-.05),"444b45",false)
		else: b.box(node,Vector3(0,h*.5,d*.48),Vector3(w,h,.06),"697970",false)
		var pivot:=Node3D.new()
		b.add(node,pivot,"MovingPanel")
		if node.opening=="lid":
			pivot.position=Vector3(0,h,-d*.5)
			b.box(pivot,Vector3(0,0,d*.5),Vector3(w,.05,d),case_paint,false)
			if model in ["personal_bag","medical_bag"]: b.box(pivot,Vector3(0,.08,d*.5),Vector3(.24,.1,.09),"444b45",false)
			equipment_label(pivot,node.loot_profile.to_upper(),Vector3(0,.031,d*.5),Vector2(w*.75,d*.55),true)
		else:
			pivot.position=Vector3(-w*.45,h*.5,d*.5+.015)
			b.box(pivot,Vector3(w*.45,0,0),Vector3(w*.9,h*.8,.04),case_paint,false)
			equipment_label(pivot,node.loot_profile.to_upper(),Vector3(w*.45,h*.15,.026),Vector2(w*.72,minf(.2,h*.3)))
	sources.append(node)
	return node

func pickup(parent: Node3D, at: Vector3, category: String) -> void:
	var items: Array=["medkit","infection_suppressant"] if category=="medical" else ["research_notes","research_drive"] if category=="records" else ["sealed_specimen","sterile_lab_supplies"] if category=="specimen" else ["food","personal_effects"] if category=="personal" else ["tool","salvage","lab_electronics"]
	var identity: String=items[pickups.size()%items.size()]
	var node:=RaidLootPickup.new()
	node.entity_id="loose-%02d"%pickups.size()
	node.item_id=identity
	node.amount=18 if identity=="five_five_six" else 1
	node.material=b.steel
	node.kind="container"
	node.interaction_offset=Vector3(0,.12,0)
	b.add(parent,node,node.entity_id)
	node.position=at
	node.add_to_group("raid_entities",true)
	prop(node,"pickup_"+identity,Vector3.ZERO,0,false)
	var shape:=CollisionShape3D.new()
	var form:=BoxShape3D.new()
	form.size=Vector3(.35,.3,.3)
	shape.shape=form
	shape.position.y=.12
	b.add(node,shape,"CollisionShape3D")
	pickups.append(node)

func fixture(parent: Node3D, at: Vector3, emergency:=false, warm:=false) -> void:
	var node:=MedTacBreakable.new()
	node.entity_id="fixture-%03d"%fixture_serial
	fixture_serial+=1
	node.kind="light"
	node.protected=emergency
	node.material=b.steel
	b.add(parent,node,node.entity_id)
	node.position=at
	if at.x>-242 and at.x<276 and at.z>-200 and at.z<72:
		var ceiling: float=parent.get_meta("ceiling_height",-5.5 if at.y<-2 else 10.15 if at.x>49 and at.z<-43 else 5.25)
		var suspension:=ceiling-at.y-.1
		if suspension>.15: b.box(node,Vector3(0,suspension*.5+.1,0),Vector3(.035,suspension,.035),"444b45",false)
	b.box(node,Vector3.ZERO,Vector3(1.2,.16,.45),"444b45",false)
	b.box(node,Vector3(0,-.09,0),Vector3(1.05,.045,.32),"e4d5b0" if warm else "b5dbd1",false,"Diffuser",true)
	var shape:=CollisionShape3D.new()
	var form:=BoxShape3D.new()
	form.size=Vector3(1.2,.22,.45)
	shape.shape=form
	b.add(node,shape,"CollisionShape3D")
	var lamp:=OmniLight3D.new()
	lamp.light_color=Color("e6c59a") if warm else Color("b8d3cf")
	lamp.light_energy=2.4 if emergency else 1.8
	lamp.omni_range=13 if emergency else 11
	if at.x>75 and at.z<-43 and at.y>6:
		lamp.omni_range=23
		lamp.light_energy=3.2
	lamp.distance_fade_enabled=true
	lamp.distance_fade_begin=35
	lamp.distance_fade_length=12
	b.add(node,lamp,"Light")
	lamp.position.y=-.3

func glass(parent: Node3D, at: Vector3, width:=2.5, height:=1.2) -> MedTacBreakable:
	var node:=MedTacBreakable.new()
	node.entity_id="window-%d"%b.serial
	node.kind="glass"
	node.material=b.steel
	b.add(parent,node)
	node.position=at
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color(.42,.64,.61,.22)
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness=.15
	var visual:=MeshInstance3D.new()
	var mesh:=BoxMesh.new()
	mesh.size=Vector3(width,height,.06)
	visual.mesh=mesh
	visual.material_override=material
	b.add(node,visual,"Glass")
	var shape:=CollisionShape3D.new()
	var form:=BoxShape3D.new()
	form.size=mesh.size
	shape.shape=form
	b.add(node,shape,"CollisionShape3D")
	return node

func build_facade(shell: Node3D) -> void:
	# Glazed public frontage, with solid piers, real sills and framed openings.
	var cursor:=-242.0
	for x in [-230,-212,-194,-176,-124,-106,-88,-70,-52,-34,-16,2,20,38]:
		var left: float=x-5
		var right: float=x+5
		if cursor<-151.5 and left>-148.5:
			b.wall(shell,cursor,72,-151.5,72)
			b.wall(shell,-151.5,72,-148.5,72,3.5,1.5)
			b.door(shell,"public-entrance",Vector3(-150,0,72))
			cursor=-148.5
		b.wall(shell,cursor,72,left,72)
		b.wall(shell,left,72,right,72,0,.6)
		b.wall(shell,left,72,right,72,3.8,1.2)
		var pane:=glass(shell,Vector3(x,2.2,72),9.7,3.1)
		for edge in [-4.95,0,4.95]: b.box(shell,Vector3(x+edge,2.2,72),Vector3(.12,3.2,.2),"444b45",true)
		for y in [.62,3.78]: b.box(shell,Vector3(x,y,72),Vector3(10,.12,.25),"444b45",true)
		var link:=NavigationLink3D.new()
		b.add(shell,link,"BrokenFrontageLink%d"%b.serial)
		link.start_position=Vector3(x+2,.1,75)
		link.end_position=Vector3(x+2,.1,69)
		link.enabled=false
		pane.navigation_link=pane.get_path_to(link)
		cursor=right
	b.wall(shell,cursor,72,49,72)
	# A supported canopy, protected arrival lane, seating and fixed branding.
	b.box(shell,Vector3(-150,3.9,76),Vector3(20,.3,8.5),"444b45")
	for x in [-159,-141]: b.box(shell,Vector3(x,1.9,79.5),Vector3(.3,3.8,.3),"61645b")
	b.box(shell,Vector3(-150,4.6,80.4),Vector3(8.2,1.2,.18),"343a35",false)
	equipment_label(shell,"MEDTAC LABS\nCLINICAL RESEARCH AND LOGISTICS",Vector3(-150,4.6,80.51),Vector2(8,1.1))
	for x in [-164,-158,-142,-136]:
		b.box(shell,Vector3(x,.55,82.5),Vector3(.28,1.1,.28),"cfb762")
	for x in [-169,-131]:
		for offset in [-1,0,1]: prop(shell,"exam_chair",Vector3(x+offset,0,77),PI)
		b.box(shell,Vector3(x,0.35,81),Vector3(3,.7,1.1),"61645b")
		b.box(shell,Vector3(x,.72,81),Vector3(2.7,.1,.85),"333f30",false)
	fixture(shell,Vector3(-155,3.6,76),true,true)
	fixture(shell,Vector3(-145,3.6,76),true,true)

func room(parent: Node3D, title: String, center: Vector3, size: Vector2, role: String, category: String, secondary:=false) -> void:
	if title in ["CLINICAL STORES","MEDICAL STORE"]: role="medical_store"
	elif title=="NURSING STATION" or ("OBSERVATION" in title and category=="research"): role="office"
	var area:=Node3D.new()
	b.add(parent,area,title.to_pascal_case().replace("/",""))
	area.set_meta("room_purpose",title)
	area.set_meta("ceiling_height",center.y+3.6)
	var x:=center.x
	var y:=center.y
	var z:=center.z
	var left:=x-size.x*.5
	var right:=x+size.x*.5
	var back:=z-size.y*.5
	var front:=z+size.y*.5
	# Floors and ceilings are room-sized so local lighting and culling stay useful.
	b.slab(area,left,back,right,front,y+.025,"8b9589" if category=="medical" else "61645b",false)
	b.wall(area,left,back,left,front,y,3.6)
	b.wall(area,right,back,right,front,y,3.6)
	b.box(area,Vector3(x,y+3.65,z),Vector3(size.x,.1,size.y),"535e55",true,"RoomCeiling%d"%b.serial)
	for offset in [[left,left+.6],[left+3.4,x-1],[x+1,right]]: b.wall(area,offset[0],front,offset[1],front,y,3.6)
	b.wall(area,left+.6,front,left+3.4,front,y,1.3)
	b.wall(area,left+.6,front,left+3.4,front,y+2.5,1.1)
	b.wall(area,x-1,front,x+1,front,y+2.5,1.1)
	b.door(area,"door-"+str(b.serial),Vector3(x,y,front),0,false,2,2.5)
	if secondary:
		for offset in [[left,x-1],[x+1,right]]: b.wall(area,offset[0],back,offset[1],back,y,3.6)
		b.wall(area,x-1,back,x+1,back,y+2.5,1.1)
		route(area,Vector3(x,y,back))
	else: b.wall(area,left,back,right,back,y,3.6)
	physical_sign(area,title,Vector3(x,y+2.9,front+.3),0,40,Color.WHITE)
	# High observation windows have real frames and breakable panes, away from security.
	for edge in [-1.35,1.35]: b.box(area,Vector3(left+2+edge,y+1.9,front),Vector3(.12,1.4,.16),"444b45",false)
	glass(area,Vector3(left+2,y+1.9,front))
	fixture(area,Vector3(x,y+3.35,z),false,role in ["staff","office","recovery"])
	if size.x>18: fixture(area,Vector3(x+size.x*.25,y+3.35,z-size.y*.22))
	# Services run into actual room fixtures rather than stopping in empty space.
	b.box(area,Vector3(x,y+3.1,back+.4),Vector3(size.x-.8,.16,.22),"444b45",false)
	prop(area,"electrical_panel",Vector3(right-.7,y,back+1),PI/2)
	var models: Array[String]
	match role:
		"clinical": models=["exam_bed","monitor_cart","exam_chair","privacy_screen","wash_station","iv_stand"]
		"recovery": models=["recovery_bed","monitor_cart","recovery_bed","privacy_screen","iv_stand","nurse_desk"]
		"laboratory": models=["instrument_bench","analyzer","biosafety_cabinet","centrifuge","wash_station","sample_rack"]
		"cold": models=["lab_fridge","ultra_freezer","lab_fridge","specimen_cooler","instrument_bench","sample_rack"]
		"records": models=["filing_cabinet","nurse_desk","filing_cabinet","server_rack","terminal","cardboard_box"]
		"staff": models=["break_table","staff_locker","staff_locker","trash_bin","shower","wash_station"]
		"utility": models=["air_handler","electrical_panel","work_cart","mop_bucket","trash_bin","extinguisher"]
		"washroom": models=["toilet","toilet","wash_station","shower","trash_bin","mop_bucket"]
		"warehouse": models=["packing_table","roll_cage","cold_chain_crate","pallet_jack","work_cart","wrapped_pallet"]
		"medical_store": models=["med_cabinet","medicine_fridge","med_cabinet","supply_cart","med_cabinet","wash_station"]
		_: models=["nurse_desk","terminal","filing_cabinet","exam_chair","wall_clock","trash_bin"]
	if "MICROSCOP" in title: models=["instrument_bench","microscope","microscope","sample_rack","wash_station","supply_cart"]
	elif "RECEIV" in title or "SORTING" in title: models=["packing_table","specimen_cooler","roll_cage","sample_rack","instrument_bench","supply_cart"]
	elif "STERIL" in title or "WASH AND" in title: models=["autoclave","wash_station","autoclave","eyewash","supply_cart","mop_bucket"]
	elif "REAGENT" in title or "CLEAN SUPPL" in title: models=["lab_fridge","wall_cabinet","med_cabinet","supply_cart","instrument_bench","sample_rack"]
	elif "CONTROL" in title or "COORDIN" in title: models=["nurse_desk","monitor_cart","server_rack","terminal","filing_cabinet","exam_chair"]
	elif "MEETING" in title: models=["break_table","exam_chair","exam_chair","terminal","filing_cabinet","wall_clock"]
	elif "SECURITY" in title: models=["nurse_desk","monitor_cart","staff_locker","electrical_panel","personal_bag","filing_cabinet"]
	elif "OBSERVATION" in title or title=="NURSING STATION": models=["nurse_desk","monitor_cart","server_rack","terminal","supply_cart","filing_cabinet"]
	elif "PROCEDURE" in title: models=["exam_bed","monitor_cart","instrument_bench","iv_stand","sharps_bin","privacy_screen"]
	var placements: Array[Vector3]=[Vector3(-size.x*.27,0,-size.y*.28),Vector3(size.x*.22,0,-size.y*.3),Vector3(-size.x*.27,0,0),Vector3(size.x*.25,0,0),Vector3(-size.x*.3,0,size.y*.24),Vector3(size.x*.3,0,size.y*.24)]
	for i in range(models.size()):
		var position:=center+placements[i]
		if models[i] in ["analyzer","centrifuge","sample_rack","terminal","clipboard","microscope"]:
			prop(area,"instrument_bench",position)
			position.y+=.96
		prop(area,models[i],position,0,models[i] not in ["sample_rack","wall_clock","terminal"])
	# A staffed bench, forms, bins and a stool give each workstation a human scale.
	prop(area,"stool",center+Vector3(-size.x*.27,0,-size.y*.28+1.6))
	prop(area,"clipboard",center+Vector3(-size.x*.27,1,-size.y*.28),0,false)
	prop(area,"sharps_bin" if category=="medical" else "cardboard_box",center+Vector3(size.x*.35,0,-size.y*.35))
	# Furnish complete work areas, with aisles between them, rather than isolated display props.
	if role=="laboratory":
		for station in range(9):
			var at:=center+Vector3(-4+(station%3)*4,0,-5+(station/3)*5)
			prop(area,"clean_workbench",at)
			prop(area,["microscope","centrifuge","sample_rack"][station%3],at+Vector3(-.45,.96,0),0,false)
			prop(area,"clipboard",at+Vector3(.55,.96,.1),.12,false)
			prop(area,"stool",at+Vector3(0,0,1.35))
	elif role in ["clinical","recovery"] and not "SCREENING" in title and not "CONSULTATION" in title:
		for station in range(4):
			var at:=center+Vector3(-3.2 if station%2==0 else 3.2,0,-3.8 if station<2 else 3.8)
			prop(area,"recovery_bed" if role=="recovery" else "exam_bed",at,.035*(station-1))
			prop(area,"monitor_cart",at+Vector3(1,0,-.7))
			prop(area,"iv_stand",at+Vector3(-.85,0,-.5))
			if station in [1,3]: prop(area,"privacy_screen",at+Vector3(-1.7,0,0),PI/2)
	elif role=="medical_store":
		for index in range(5): prop(area,"medicine_fridge" if index%2==0 else "med_cabinet",center+Vector3(-size.x*.36+index*size.x*.18,0,-size.y*.4))
		for offset in [-3,0,3]: prop(area,"med_cabinet",center+Vector3(-size.x*.4,0,offset),PI/2)
		prop(area,"supply_cart",center+Vector3(0,0,1))
	elif role=="cold":
		for index in range(7): prop(area,"ultra_freezer" if index%3==0 else "lab_fridge",center+Vector3(-9+index*3,0,-size.y*.4))
		for offset in [-6,-2,2]: prop(area,"lab_fridge",center+Vector3(-size.x*.4,0,offset),PI/2)
	elif role in ["office","records"]:
		for index in range(4):
			var at:=center+Vector3(-2 if index%2==0 else 2,0,-2 if index<2 else 2)
			prop(area,"nurse_desk",at)
			prop(area,"exam_chair",at+Vector3(0,0,1.3),PI)
			prop(area,"clipboard",at+Vector3(.5,1,.1),0,false)
		for index in range(4): prop(area,"filing_cabinet",center+Vector3(-size.x*.3+index*1.7,0,-size.y*.4))
	elif role=="staff":
		if "BREAK" in title or "MEETING" in title:
			for x_offset in [-2.5,2.5]:
				prop(area,"break_table",center+Vector3(x_offset,0,1.5))
				prop(area,"exam_chair",center+Vector3(x_offset,0,3),PI)
		else:
			for index in range(6): prop(area,"staff_locker",center+Vector3(-size.x*.35+index*1.1,0,-size.y*.4))
	elif role=="utility":
		for index in range(4): prop(area,"air_handler",center+Vector3(-size.x*.3+index*2.5,0,-size.y*.4))
	rooms.append({"node":area,"center":center,"size":size,"category":category,"role":role,"title":title})

func route(parent: Node3D, at: Vector3) -> void:
	var node:=MedTacRouteBlock.new()
	node.route_id="secondary-%d"%route_serial
	node.entity_id=node.route_id
	node.kind="barricade"
	node.max_health=45
	node.material=b.steel
	route_serial+=1
	b.add(parent,node,node.entity_id)
	node.position=at+Vector3.UP*1.2
	b.box(node,Vector3.ZERO,Vector3(1.9,2.4,.4),"807454",false)
	var shape:=CollisionShape3D.new()
	var form:=BoxShape3D.new()
	form.size=Vector3(1.9,2.4,.4)
	shape.shape=form
	b.add(node,shape,"CollisionShape3D")
	var link:=NavigationLink3D.new()
	b.add(parent,link,"SecondaryLink%d"%route_serial)
	link.start_position=at+Vector3(0,.5,1.8)
	link.end_position=at+Vector3(0,.5,-1.8)
	link.enabled=false
	node.navigation_link=NodePath("../"+str(link.name))
	physical_sign(parent,"SERVICE ACCESS",at+Vector3(0,2.9,.3),0,26,Color.WHITE)

func build_shell() -> void:
	var shell: Node3D=b.section("Shell")
	b.vertical_door_wall(shell,-242,-200,72,[-120,-20])
	build_facade(shell)
	b.horizontal_door_wall(shell,-242,276,-200,[-150,180])
	b.vertical_door_wall(shell,276,-200,-43,[-100],0,10)
	b.horizontal_door_wall(shell,49,276,-43,[90,180,240],0,10)
	b.vertical_door_wall(shell,49,-43,72,[35])
	b.vertical_door_wall(shell,10,-200,-30,[-170,-120,-70])
	b.vertical_door_wall(shell,49,-200,-43,[-170,-120,-70])
	# Large roofs are segmented for lighting and visibility instead of one campus-sized mesh.
	for x in range(-242,49,24):
		for z in range(-200,72,24): b.box(shell,Vector3(x+minf(24,49-x)*.5,5.4,z+minf(24,72-z)*.5),Vector3(minf(24,49-x),.3,minf(24,72-z)),"535e55",true,"LabRoof%d"%b.serial)
	for x in range(49,276,24):
		for z in range(-200,-43,24): b.box(shell,Vector3(x+minf(24,276-x)*.5,10.3,z+minf(24,-43-z)*.5),Vector3(minf(24,276-x),.3,minf(24,-43-z)),"45534b",true,"WarehouseRoof%d"%b.serial)
	for z in [-180,-140,-100,-50,15,55]:
		fixture(shell,Vector3(29,4.6,z),true)
		physical_sign(shell,"CLINICAL < / LOGISTICS >\nRESEARCH - STAFF ONLY",Vector3(29,3,z),0,36,Color.WHITE)

func build_reception() -> void:
	var area: Node3D=b.section("Reception")
	prop(area,"nurse_desk",Vector3(-150,0,42))
	prop(area,"nurse_desk",Vector3(-147.7,0,42))
	for x in [-185,-175,-110,-100]:
		for z in [50,58]: prop(area,"exam_chair",Vector3(x,0,z),PI)
		prop(area,"break_table",Vector3(x,0,64))
	for z in [4,48,64]: fixture(area,Vector3(-150,4.4,z),true,true)
	var titles: Array[String]=["VISITOR SCREENING","CONSULTATION 01","CONSULTATION 02","EXAM SUITE A","SAMPLE COLLECTION","PROCEDURE SUITE","NURSING STATION","MONITORED RECOVERY","OBSERVATION WARD","CLINICAL STORES"]
	for i in range(10):
		room(area,titles[i],Vector3(-225+i*20,0,-12),Vector2(16,20),"recovery" if i in [7,8] else "clinical","medical",i<2)
	for i in [0,1,2,7,8,9]: room(area,"PARTICIPANT EXAM %02d"%i,Vector3(-225+i*20,0,27),Vector2(16,20),"clinical","medical")
	var staff: Array[String]=["SECURITY OFFICE","STAFF LOCKERS","WASHROOMS","CLINICAL RECORDS","TRIAL COORDINATION","STAFF BREAK ROOM","CONSENT OFFICE","CHANGING AND SHOWERS","SUPPLY OFFICE"]
	for i in range(9): room(area,staff[i],Vector3(-8+(i%3)*22,0,-13+(i/3)*27),Vector2(16,20),"washroom" if i==2 else "staff" if i in [1,5,7] else "records" if i==3 else "office","security" if i==0 else "medical")
	for at in [Vector3(-156,0,67),Vector3(-164,0,64)]: b.covered_body(area,at)
	physical_sign(area,"EVACUATION SUSPENDED\nDO NOT WAIT FOR COMPANY TRANSPORT",Vector3(-146,2,66),0,36,Color.WHITE)

func build_labs() -> void:
	var area: Node3D=b.section("Laboratories")
	var names: Array[String]=["SPECIMEN RECEIVING","SAMPLE SORTING","PREPARATION","CENTRAL ANALYSIS","MICROSCOPY","INSTRUMENTATION","COLD STORAGE","FREEZER STORE","CLINICAL ASSAYS","QUALITY REVIEW","CLEAN SUPPLIES","WASH AND STERILIZE","REAGENT STORE","TRIAL RECORDS","TRIAL LABORATORY","RESEARCH OFFICE","LABORATORY A","LABORATORY B","EQUIPMENT SERVICE","INSTRUMENT STORE","SPECIMEN ARCHIVE","TECHNICAL RECORDS","ELECTRONICS LAB","RESEARCH MEETING","STAFF CHANGING","MATERIALS RECEIVING","CLEANING STORE","STAFF SUPPORT","DECONTAMINATION","AIR HANDLING"]
	var index:=0
	for row in range(4):
		for col in range(8):
			if row==3 and col>=6: continue
			var title: String=names[index]
			var role:="cold" if "COLD" in title or "FREEZER" in title else "records" if "RECORD" in title or "OFFICE" in title else "utility" if "SERVICE" in title or "CLEANING" in title or "AIR" in title else "staff" if "STAFF" in title else "laboratory"
			room(area,title,Vector3(-225+col*30,0,-181+row*38),Vector2(24,28),role,"medical",index in [3,12,22])
			index+=1
	for z in [-162,-124,-86,-40]:
		for x in [-225,-195,-165,-135,-105,-75,-45,-15]: fixture(area,Vector3(x,4.5,z),true)
	physical_sign(area,"RESTRICTED RESEARCH\nSINGLE USE CREDENTIAL REQUIRED",Vector3(-32,3,-39),0,40,Color.WHITE)
	# Keep the authored destructible shortcut in a separate service alcove.
	b.wall(area,-190,-42,-181.5,-42)
	b.wall(area,-178.5,-42,-170,-42)
	b.weak_partition(area,Vector3(-180,0,-42))

func build_warehouse() -> void:
	var area: Node3D=b.section("Warehouse")
	for x in range(90,260,18):
		for z in [-180,-170,-160,-130,-120,-110]:
			prop(area,"pallet_rack",Vector3(x,0,z))
		# Rack-end plates and a clear vehicle aisle connect receiving to dispatch.
		physical_sign(area,"AISLE %02d\nMEDTAC LOGISTICS"%((x-90)/18+1),Vector3(x,3,-157.8),0,36,Color.WHITE)
	for z in [-151,-137,-103,-97]: b.box(area,Vector3(170,.012,z),Vector3(180,.02,.12),"cfb762",false)
	for x in [110,145,180,215,250]:
		prop(area,"conveyor",Vector3(x,0,-64),PI/2)
		prop(area,"packing_table",Vector3(x+4,0,-67))
		prop(area,"roll_cage",Vector3(x-3,0,-59))
		prop(area,"forklift",Vector3(x+5,0,-85),.2)
	for x in [100,130,160,190,220,250]:
		for z in [-185,-155,-125,-95,-55]: fixture(area,Vector3(x,8.5,z),z==-55,true)
	room(area,"DISPATCH AND SHIPPING",Vector3(64,0,-185),Vector2(18,20),"records","security",true)
	room(area,"RECEIVING INSPECTION",Vector3(64,0,-155),Vector2(18,20),"warehouse","industrial")
	room(area,"COLD CHAIN STAGING",Vector3(64,0,-125),Vector2(18,20),"cold","medical")
	room(area,"MAINTENANCE WORKSHOP",Vector3(93,0,-64),Vector2(24,24),"warehouse","industrial")
	physical_sign(area,"MEDTAC LOGISTICS\nRECEIVING / PACKING / DISPATCH",Vector3(160,6,-199.5),0,75,Color.WHITE)
	physical_sign(area,"CURE LOTS EVACUATED\nREGIONAL ORDERS CANCELLED",Vector3(260,3,-195),0,44,Color.WHITE)

func build_basement() -> void:
	var area: Node3D=b.section("Basement")
	b.slab(area,-220,-185,105,-38,-10,"444b45")
	for line in [[-220,-185,105,-185],[-220,-38,105,-38],[-220,-185,-220,-38],[105,-185,105,-38]]: b.wall(area,line[0],line[1],line[2],line[3],-10,9.7,"61645b")
	b.staircase(area,-32,"research-lab-entrance")
	b.staircase(area,54,"research-maintenance-entrance")
	var names: Array[String]=["TRIAL CONTROL","OBSERVATION A","HUMAN TRIALS A","HUMAN TRIALS B","FAILED CONTAINMENT","OBSERVATION B","SPECIMEN VAULT","CURE TRANSFER ARCHIVE","TRIAL RECORDS","MEDICAL STORE","EXPERIMENT SUPPORT","ISOLATION A","ISOLATION B","SECURITY CONTROL","ARCHIVE ANNEX","COLD SPECIMENS"]
	for i in range(16):
		var x:=-201.0+(i%8)*38.0
		if i%8==7: x=83
		var role:="office" if i==13 else "recovery" if i in [2,3,11,12] else "cold" if i in [6,15] else "records" if i in [0,7,8,14] else "laboratory"
		room(area,names[i],Vector3(x,-10,-160+(i/8)*45),Vector2(28,26),role,"research")
	for i in range(4): room(area,["VENTILATION PLANT","WASTE HOLDING","TECHNICAL SERVICE","EMERGENCY STORES"][i],Vector3(-201+i*40,-10,-65),Vector2(28,26),"utility","research")
	for x in [-185,-145,-105,-65,0,80]: fixture(area,Vector3(x,-6,-92),true)
	physical_sign(area,"CURE EFFICACY CONFIRMED\nALL VIABLE STOCK REMOVED\nSUPPRESSANTS ARE NOT A CURE",Vector3(80,-7,-180),0,45,Color.WHITE)
	physical_sign(area,"TRIAL 19 - PATHOGEN RELEASE APPROVED\nEXCLUSIVE CURE DISTRIBUTION\nCONTAINMENT PROJECTIONS EXCEEDED",Vector3(-200,-7,-180),0,45,Color.WHITE)
	b.covered_body(area,Vector3(-48,-10,-146))
	# The containment centerpiece is physically different from an ordinary instrument lab.
	prop(area,"recovery_bed",Vector3(-55,-10,-165))
	prop(area,"monitor_cart",Vector3(-52,-10,-165))
	b.covered_body(area,Vector3(-55,-9.2,-165))
	for x in [-58,-52]: b.box(area,Vector3(x,-8.4,-167),Vector3(.12,3.2,.12),"444b45")
	b.box(area,Vector3(-55,-6.8,-167),Vector3(6,.15,.2),"444b45")
	for x in [-57,-56,-54]: b.box(area,Vector3(x,-9.96,-166),Vector3(.5,.03,.3),"8ca99d",false)
	for x in [-185,-105,0,80]: physical_sign(area,"EMERGENCY EGRESS\nLAB STAIRS < / MAINTENANCE >",Vector3(x,-7.5,-43),0,34,Color.WHITE)

func populate_loot() -> void:
	# Four stable keycard candidates, independent from the richer ordinary loot budget.
	var stable: Array=[["security-office-cabinet","SECURITY OFFICE","security",true],["staff-locker","STAFF LOCKERS","medical",true],["trial-records-supply","TRIAL RECORDS","medical",true],["dispatch-office-safe","DISPATCH AND SHIPPING","security",true]]
	for entry: Array in stable:
		for room_data in rooms:
			if room_data.title==entry[1] and room_data.center.y>=0:
				source(room_data.node,entry[0],room_data.center+Vector3(-room_data.size.x*.37,0,room_data.size.y*.33),"staff_locker" if entry[0]=="staff-locker" else "filing_cabinet",entry[2],true)
				break
	for i in range(rooms.size()):
		var data: Dictionary=rooms[i]
		var id:="room-source-%03d"%i
		var guarantee: Dictionary={}
		if data.center.y<0:
			id="basement-research-%d"%(i-59)
			if data.title in ["TRIAL CONTROL","CURE TRANSFER ARCHIVE"]: guarantee={"research_drive":1}
			if data.title=="MEDICAL STORE": guarantee={"infection_suppressant":2}
		source(data.node,id,data.center+Vector3(data.size.x*.37,0,data.size.y*.33),room_model(data),data.category,false,guarantee)
	# Dedicated weapon and ammunition cases; these item types never roll in ordinary storage.
	var warehouse: Node3D=b.nav.get_node("Warehouse")
	for i in range(8):
		var at:=Vector3(110+i*18,0,-49)
		var owner_node:=warehouse
		if i==7:
			for data in rooms:
				if data.title=="SECURITY CONTROL": at=data.center+Vector3(3,0,8.5); owner_node=data.node
		prop(owner_node,"storage_table",at)
		source(owner_node,"weapon-case-%02d"%i,at+Vector3.UP*1.01,"weapon_box" if i%2==0 else "weapon_crate","security")
	for i in range(12):
		var at:=Vector3(100+i*14,0,-94)
		var owner_node:=warehouse
		if i==11:
			for data in rooms:
				if data.title=="SECURITY CONTROL": at=data.center+Vector3(-3,0,8.5); owner_node=data.node
		prop(owner_node,"storage_table",at)
		source(owner_node,"ammo-case-%02d"%i,at+Vector3.UP*1.01,"ammo_box","security")
	for i in range(128-sources.size()):
		var data: Dictionary=rooms[(i*7)%rooms.size()]
		var model:="medical_bag" if data.role in ["clinical","recovery"] else "personal_bag" if data.role in ["staff","office"] else "tool_drawers" if data.role in ["utility","warehouse"] else "filing_cabinet"
		source(data.node,"supplemental-%03d"%i,data.center+Vector3(-data.size.x*.37,0,0),model,data.category)
	for i in range(64):
		var data: Dictionary=rooms[i%rooms.size()]
		var at: Vector3=data.center+Vector3(-data.size.x*.15,0,data.size.y*.3)
		prop(data.node,"clean_workbench" if data.category in ["medical","research"] else "storage_table",at)
		pickup(data.node,at+Vector3(0,1.03,0),profile_for_model(room_model(data)))

func build_variants() -> void:
	DirAccess.make_dir_recursive_absolute("res://scenes/raid/medtac/variants")
	var main_site: Node3D=b.site
	for theme: String in ["exterior","clinical","laboratory","warehouse","basement"]:
		for variant in range(3):
			var root:=Node3D.new()
			root.name="CoverArrangement"
			b.site=root
			var region: NavigationRegion3D=preload("res://scripts/world/raid_navigation_region.gd").new()
			b.add(root,region,"NavigationRegion3D")
			var mesh:=NavigationMesh.new()
			mesh.geometry_parsed_geometry_type=NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
			mesh.cell_size=.25
			mesh.cell_height=.25
			mesh.agent_radius=.5
			mesh.agent_height=2
			mesh.agent_max_climb=.5
			region.navigation_mesh=mesh
			b.box(region,Vector3(0,-.15,0),Vector3(9,.3,9),"61645b")
			var selected: Array=["work_cart","wrapped_pallet","roll_cage"] if theme in ["warehouse","exterior"] else ["supply_cart","privacy_screen","recovery_bed"] if theme=="clinical" else ["instrument_bench","specimen_cooler","work_cart"]
			for corner in range(4):
				if corner==variant: continue
				var at:=Vector3(-2.6 if corner%2==0 else 2.6,0,-2.6 if corner<2 else 2.6)
				prop(region,selected[(corner+variant)%3],at,PI/2 if variant==1 else 0)
				var marker:=Marker3D.new()
				b.add(root,marker,"Cover%d"%corner)
				marker.position=at+Vector3(0,0,1.1)
			b.root.add_child(root)
			NavigationServer3D.map_set_use_async_iterations(region.get_navigation_map(),false)
			NavigationServer3D.map_force_update(region.get_navigation_map())
			await b.physics_frame
			await b.physics_frame
			region.bake_navigation_mesh(false)
			if region.navigation_mesh.get_polygon_count()==0: push_error("Empty cover variant: "+theme)
			b.pack_to(root,"res://scenes/raid/medtac/variants/"+theme+"_%d.tscn"%variant)
			b.root.remove_child(root)
			root.free()
	b.site=main_site

func add_slot(parent: Node3D, at: Vector3, theme: String) -> void:
	var slot:=MedTacVariantSlot.new()
	slot.slot_id="slot-%02d"%slot_serial
	slot_serial+=1
	for variant in range(3): slot.variants.append(load("res://scenes/raid/medtac/variants/"+theme+"_%d.tscn"%variant))
	b.add(parent,slot,slot.slot_id)
	slot.position=at
	if theme!="exterior": fixture(parent,at+Vector3.UP*(7 if theme=="warehouse" else 4.25),true,theme=="warehouse")
	# A bake-only solid reserves this footprint in the fixed navigation mesh.
	var proxy: Node3D=b.box(parent,at+Vector3.UP*1.7,Vector3(9,3.4,9),"61645b")
	bake_proxies.append(proxy)
	for offset in [Vector3(1,0,0),Vector3(-1,0,0),Vector3(0,0,1),Vector3(0,0,-1)]:
		var link:=NavigationLink3D.new()
		b.add(parent,link,"CoverPortal%d"%b.serial)
		link.start_position=at+offset*6+Vector3.UP*.5
		link.end_position=at+offset*3+Vector3.UP*.5

func finish_geometry() -> void:
	var node: Node3D=b.section("RaidVariation")
	for at in [Vector3(-150,0,130),Vector3(-70,0,150),Vector3(100,0,155),Vector3(255,0,140)]: add_slot(node,at,"exterior")
	for x in [-220,-180,-100,-60]: add_slot(node,Vector3(x,0,8),"clinical")
	for z in [-124,-86]:
		for x in [-210,-150,-90]: add_slot(node,Vector3(x,0,z),"laboratory")
	for at in [Vector3(100,0,-145),Vector3(140,0,-145),Vector3(180,0,-145),Vector3(220,0,-145),Vector3(150,0,-83)]: add_slot(node,at,"warehouse")
	for at in [Vector3(-182,-10,-92),Vector3(-144,-10,-92),Vector3(-106,-10,-92),Vector3(-68,-10,-92),Vector3(15,-10,-60)]: add_slot(node,at,"basement")
	var controller:=MedTacDressing.new()
	b.add(b.site,controller,"Dressing")
	populate_loot()
	var grounds: Node3D=b.nav.get_node("Grounds")
	for at in [Vector3(-250,0,-220),Vector3(-150,0,-220),Vector3(0,0,-220),Vector3(150,0,-220),Vector3(285,0,-160),Vector3(285,0,-70),Vector3(220,0,80),Vector3(220,0,190),Vector3(-250,0,90),Vector3(-100,0,90),Vector3(-250,0,270),Vector3(-100,0,270),Vector3(80,0,270),Vector3(260,0,270)]:
		b.box(grounds,at+Vector3.UP*3,Vector3(.15,6,.15),"444b45")
		fixture(grounds,at+Vector3.UP*6,true,true)
	for data in rooms:
		# Cables, ventilation and a few displaced personal objects distinguish occupation.
		var center: Vector3=data.center
		var size: Vector2=data.size
		prop(data.node,"trash_bin",center+Vector3(size.x*.4,0,-size.y*.4))
		prop(data.node,"cardboard_box",center+Vector3(-size.x*.38,0,size.y*.32),.18)
		prop(data.node,"clipboard",center+Vector3(-size.x*.2,.03,size.y*.32),.55,false)

func remove_bake_proxies() -> void:
	for node in bake_proxies: node.free()
	bake_proxies.clear()

