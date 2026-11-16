class_name DistrictSceneAuthor
extends RefCounted

const TITLES := ["Medtac Research Facility","Industrial Scrapyard","Residential Block","Abandoned Warehouse","Electrical Substation","Rail Depot","Quarantine Checkpoint"]
var scene: Node3D
var nav: NavigationRegion3D
var kits: Dictionary={}
var bodies: Dictionary={}
var cache: Dictionary={}
var doors: Array[RaidDoor]=[]
var buildings: Array[Dictionary]=[]
var cover: Array[Dictionary]=[]
var serial:=0
var source_serial:=0
var pickup_serial:=0
var actor_points: Array[Vector3]=[]
var layout: DistrictLayout
var config:=DistrictGenerationConfig.new()
var paving: Array[Dictionary]=[]
var building_footprints: Array[PackedVector2Array]=[]

func world_transform(node: Node3D) -> Transform3D:
	var result:=node.transform
	var ancestor:=node.get_parent()
	while ancestor!=scene and ancestor is Node3D:
		result=(ancestor as Node3D).transform*result
		ancestor=ancestor.get_parent()
	return result

func ground_patch(parent: Node3D,at: Vector3,size: Vector3,key: String) -> void:
	var polygon:=PackedVector2Array()
	var transform:=world_transform(parent)
	for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
		var point:=transform*(at+Vector3(corner.x*size.x*.5,0,corner.y*size.z*.5))
		polygon.append(Vector2(point.x,point.z))
	paving.append({"polygon":polygon,"material":key})
var steel: MaterialDef=preload("res://resources/materials/steel.tres")
var concrete: MaterialDef=preload("res://resources/materials/concrete.tres")
var profiles: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/medtac/loot_profiles.json"))

func add(parent: Node,node: Node,title := "") -> Node:
	serial+=1
	node.name=title if not title.is_empty() else "Part%05d"%serial
	parent.add_child(node); node.owner=scene
	return node

func begin(title: String,raid := false) -> Node3D:
	scene=Node3D.new(); scene.name=title
	if raid: scene.set_script(preload("res://scripts/raid/raid_authority.gd"))
	nav=RaidNavigationRegion.new(); add(scene,nav,"NavigationRegion3D")
	var world:=WorldEnvironment.new(); world.environment=Environment.new(); add(scene,world,"WorldEnvironment")
	var sun:=DirectionalLight3D.new(); add(scene,sun,"Sun")
	var atmosphere:=DistrictAtmosphere.new()
	atmosphere.preset=WorldEnvironmentPreset.make("overcast_day")
	atmosphere.quality=WorldQualitySettings.make(1)
	add(scene,atmosphere,"Atmosphere")
	return scene

func section(title: String,at := Vector3.ZERO,parent: Node = null) -> Node3D:
	var node:=Node3D.new(); add(nav if parent==null else parent,node,title); node.position=at
	kits[node]=WorldMeshKit.new()
	return node

func collider(parent: Node3D,at: Vector3,shape: Shape3D,key: String) -> void:
	var identity:=str(parent.get_instance_id())+key
	if not bodies.has(identity):
		var body:=DecorativeProp.new(); body.material=concrete if key in ["concrete","dirt","asphalt"] else steel
		add(parent,body,"Structure"+key.capitalize()); bodies[identity]=body
	var node:=CollisionShape3D.new(); node.position=at; node.shape=shape
	add(bodies[identity],node)

func box(parent: Node3D,at: Vector3,size: Vector3,key: String,solid := true) -> void:
	if not solid and key in ["asphalt","concrete","warning"] and size.y<=.051 and at.y<.06:
		ground_patch(parent,at,size,key)
		return
	(kits[parent] as WorldMeshKit).box(at,size,key)
	if solid:
		var shape:=BoxShape3D.new(); shape.size=size
		collider(parent,at,shape,key)

func wall(parent: Node3D,at: Vector3,size: Vector3,key := "concrete") -> void:
	box(parent,at,size,key)
	if maxf(size.x,size.z)>4 and size.y>=2.5:
		var occluder:=OccluderInstance3D.new()
		var shape:=BoxOccluder3D.new(); shape.size=size*.97
		occluder.occluder=shape; occluder.position=at
		add(parent,occluder)

func asset(parent: Node3D,identity: String,at: Vector3,yaw := 0.0,district := true,solid := true) -> Node3D:
	var path: String=("res://scenes/props/district/" if district else "res://scenes/props/medtac/detail/")+identity+".tscn"
	if not cache.has(path): cache[path]=load(path)
	var node: Node3D=cache[path].instantiate()
	add(parent,node); node.position=at; node.rotation.y=yaw
	if not solid:
		for child in node.find_children("*","CollisionObject3D",true,false): child.collision_layer=0
	return node

func sign_board(parent: Node3D,identity: String,at: Vector3,width := 5.0,yaw := 0.0) -> void:
	var node:=Node3D.new(); add(parent,node,"Sign"+identity.capitalize()); node.position=at; node.rotation.y=yaw
	var mesh:=MeshInstance3D.new(); var form:=BoxMesh.new(); form.size=Vector3(width,width*.1875,.08); mesh.mesh=form
	var material:=StandardMaterial3D.new()
	material.albedo_texture=load("res://assets/district/signs/"+identity+".png")
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST; material.roughness=.85
	mesh.material_override=material; mesh.set_meta("sign_text",identity)
	add(node,mesh,"PrintedSign")
	# A Quad avoids stretching lettering around the edges of the physical panel.
	var quad:=QuadMesh.new(); quad.size=Vector2(width,width*.1875)
	mesh.mesh=quad
	var post:=section("SignPosts"+str(serial),Vector3.ZERO,node)
	for x in [-width*.4,width*.4]: box(post,Vector3(x,-at.y*.5,-.08),Vector3(.09,at.y,.09),"steel")

func lamp(parent: Node3D,at: Vector3,emergency := false) -> void:
	var fixture:=MedTacBreakable.new(); fixture.entity_id="district-fixture-%05d"%serial
	fixture.kind="light"; fixture.protected=emergency; fixture.material=steel
	add(parent,fixture,fixture.entity_id); fixture.position=at; kits[fixture]=WorldMeshKit.new()
	box(fixture,Vector3.ZERO,Vector3(1,.12,.35),"steel",false)
	box(fixture,Vector3(0,-.07,0),Vector3(.85,.035,.22),"light",false)
	var shape:=BoxShape3D.new(); shape.size=Vector3(1,.2,.35)
	var collision_node:=CollisionShape3D.new(); collision_node.shape=shape; add(fixture,collision_node,"CollisionShape3D")
	var light:=OmniLight3D.new(); light.position=-Vector3.UP*.15
	light.light_color=Color("d3be8b") if emergency else Color("b5d1c5")
	light.light_energy=1.5 if emergency else 1.0
	light.omni_range=12; light.distance_fade_enabled=true; light.distance_fade_begin=45; light.distance_fade_length=15
	add(fixture,light)

func furnishing(parent: Node3D,at: Vector3,model: String,candidate := false,guaranteed: Dictionary = {}) -> SearchableFurniture:
	var node:=SearchableFurniture.new()
	node.entity_id="district-storage-%03d"%source_serial; source_serial+=1
	node.kind="container"; node.material=steel; node.display_name=model.replace("_"," ").capitalize()
	node.keycard_candidate=candidate; node.guaranteed_items=guaranteed
	node.loot_profile="medical" if model in ["med_cabinet","medical_bag","medicine_fridge"] else "records" if model in ["filing_cabinet","desk_drawers"] else "personal" if model in ["personal_bag","staff_locker"] else "weapons" if model=="weapon_crate" else "ammo" if model=="ammo_box" else "specimen" if model=="specimen_cooler" else "technical"
	node.loot_table=LootTable.new(); node.loot_table.rolls=Vector2i(2,4)
	for entry: Array in profiles[node.loot_profile]: node.loot_table.entries.append({"id":entry[0],"weight":entry[1],"min":1,"max":entry[2]})
	add(parent,node,node.entity_id); node.position=at; node.add_to_group("raid_entities",true)
	var visual:=asset(node,model,Vector3.ZERO,0,false,false)
	var bounds: AABB=visual.get_meta("bounds")
	var shape:=CollisionShape3D.new(); var form:=BoxShape3D.new(); form.size=bounds.size; shape.shape=form; shape.position=bounds.get_center()
	add(node,shape,"CollisionShape3D"); node.interaction_offset=bounds.get_center()
	# Keep the body fixed and animate a separate door or lid around its hinge.
	visual.visible=false
	var w:=bounds.size.x; var h:=bounds.size.y; var d:=bounds.size.z
	var frame:=section("Cabinet",Vector3.ZERO,node)
	var color:="medical" if node.loot_profile in ["medical","specimen"] else "wood" if node.loot_profile=="personal" else "paint"
	for side in [-1,1]: box(frame,Vector3(side*(w*.5-.03),h*.5,0),Vector3(.06,h,d),color,false)
	box(frame,Vector3(0,h*.5,-d*.5+.03),Vector3(w,h,.06),color,false)
	box(frame,Vector3(0,.03,0),Vector3(w,.06,d),"steel",false)
	box(frame,Vector3(0,h-.03,0),Vector3(w,.06,d),color,false)
	for y in [h*.33,h*.66]: box(frame,Vector3(0,y,0),Vector3(w-.08,.035,d-.08),"steel",false)
	var moving:=section("MovingPanel",Vector3(-w*.5,h*.5,d*.5),node)
	box(moving,Vector3(w*.5,0,0),Vector3(w-.04,h-.06,.04),color,false)
	box(moving,Vector3(w*.8,0,.045),Vector3(.035,h*.2,.04),"steel",false)
	node.opening="hinge"
	return node

func pickup(parent: Node3D,at: Vector3,identity: String) -> void:
	var node:=RaidLootPickup.new(); node.entity_id="district-loose-%03d"%pickup_serial; pickup_serial+=1
	node.item_id=identity; node.material=steel; node.kind="container"; node.interaction_offset=Vector3(0,.15,0)
	add(parent,node,node.entity_id); node.position=at; node.add_to_group("raid_entities",true)
	asset(node,"pickup_"+identity,Vector3.ZERO,0,false,false)
	var shape:=CollisionShape3D.new(); var form:=BoxShape3D.new(); form.size=Vector3(.3,.3,.3); shape.shape=form; shape.position.y=.15
	add(node,shape,"CollisionShape3D")

func doorway(parent: Node3D,at: Vector3,restricted := false) -> void:
	var door:=RaidDoor.new(); door.entity_id="district-door-%03d"%doors.size(); door.material=steel; door.restricted=restricted
	door.position=at+Vector3.UP*1.2
	add(parent,door,door.entity_id)
	var visual:=MeshInstance3D.new(); var mesh:=BoxMesh.new(); mesh.size=Vector3(2,2.4,.18); visual.mesh=mesh
	var mat:=StandardMaterial3D.new(); mat.albedo_color=Color("7f8c80") if not restricted else Color("7d6346"); visual.material_override=mat
	add(door,visual,"Panel")
	var collision:=CollisionShape3D.new(); var shape:=BoxShape3D.new(); shape.size=mesh.size; collision.shape=shape
	add(door,collision,"CollisionShape3D")
	if restricted:
		var link:=NavigationLink3D.new(); link.start_position=at+Vector3(0,.15,1.5); link.end_position=at+Vector3(-1.3,.15,-2); link.enabled=false
		add(parent,link,"ResearchAccessLink"); door.traversal_link=door.get_path_to(link)
		sign_board(parent,"restricted",at+Vector3(0,2.8,.18),2.8)
	doors.append(door)

func staircase(parent: Node3D,x: float,height := 3.5) -> void:
	var length:=12.0
	var points:=PackedVector2Array([Vector2(-length*.5,0),Vector2(length*.5,0),Vector2(length*.5,height)])
	(kits[parent] as WorldMeshKit).profile(points,2.2,Vector3(x,0,0),"concrete",0)
	var shape:=ConvexPolygonShape3D.new()
	var vertices:=PackedVector3Array()
	for side in [-1,1]:
		for p in points: vertices.append(Vector3(x+side*1.1,p.y,-p.x))
	shape.points=vertices
	collider(parent,Vector3.ZERO,shape,"concrete")
	for i in 20:
		box(parent,Vector3(x,(i+1)*height/20,5.7-i*.6),Vector3(2.25,.035,.6),"steel",false)
		box(parent,Vector3(x+1.1,(i+1)*height/20+.9,5.7-i*.6),Vector3(.06,.95,.06),"steel",false)

func building(parent: Node3D,at: Vector3,purpose: String,upper := false,restricted := false,loot_slots := 8) -> Node3D:
	var index:=buildings.size()
	var node:=section("Building%02d_%s"%[index,purpose],at,parent)
	node.set_meta("building_id",index); node.set_meta("enterable",true); node.set_meta("room_purpose",purpose)
	var w:=12.0; var d:=16.0; var h:=3.5
	var footprint:=PackedVector2Array()
	for corner in [Vector2(-6,-8),Vector2(6,-8),Vector2(6,8),Vector2(-6,8)]:
		var point:=world_transform(node)*Vector3(corner.x,0,corner.y)
		footprint.append(Vector2(point.x,point.z))
	building_footprints.append(footprint)
	var wall_key:="steel" if purpose in ["warehouse","rail","scrap"] else "concrete"
	box(node,Vector3(0,-.10,0),Vector3(w,.24,d),"concrete")
	for z in [-d*.5,d*.5]:
		var has_entry: bool=z>0 or not restricted
		if has_entry:
			wall(node,Vector3(-3.5,h*.5,z),Vector3(5,h,.3),wall_key)
			wall(node,Vector3(3.5,h*.5,z),Vector3(5,h,.3),wall_key)
			box(node,Vector3(0,2.95,z),Vector3(2,1.1,.3),wall_key)
			doorway(node,Vector3(0,0,z))
		else: wall(node,Vector3(0,h*.5,z),Vector3(w,h,.3),wall_key)
	for x in [-w*.5,w*.5]:
		box(node,Vector3(x,.55,0),Vector3(.3,1.1,d),wall_key)
		box(node,Vector3(x,3.1,0),Vector3(.3,.8,d),wall_key)
		for z in [-7.8,-4,0,4,7.8]: box(node,Vector3(x,1.9,z),Vector3(.4,1.6,.45),wall_key)
		for z in [-6,-2,2,6]:
			box(node,Vector3(x,1.85,z),Vector3(.08,1.5,3.5),"glass")
			box(node,Vector3(x,1.05,z),Vector3(.55,.12,3.75),"medical",false)
			box(node,Vector3(x,1.85,z),Vector3(.14,1.5,.08),"steel",false)
		box(node,Vector3(x*.965,.2,0),Vector3(.05,.25,d),"steel",false)
		box(node,Vector3(x*.965,2.65,0),Vector3(.05,.12,d),"paint",false)
	for x in [-3.5,3.5]: wall(node,Vector3(x,1.75,-1),Vector3(5,3.5,.22),wall_key)
	box(node,Vector3(0,2.95,-1),Vector3(2,1.1,.22),wall_key)
	doorway(node,Vector3(0,0,-1),restricted)
	# Rear rooms differ by purpose; shared central corridor stays at least 2 m wide.
	wall(node,Vector3(0,1.75,-5.3),Vector3(.22,3.5,5.2),wall_key)
	if upper and purpose in ["warehouse","rail"]:
		# Storage hall with a genuine open central volume and connected mezzanines.
		for x in [-4.3,4.3]: box(node,Vector3(x,h,0),Vector3(3.5,.18,d+.25),"steel")
		box(node,Vector3(0,h,-6),Vector3(w,.18,3.5),"steel")
	else: box(node,Vector3(0,h,0),Vector3(w+.25,.18,d+.25),"concrete")
	if upper:
		staircase(node,w*.5+1.25,h+.1)
		box(node,Vector3(w*.5+.7,h,-5.8),Vector3(1.8,.18,2),"steel")
		# Upper storey, entered from the external stairs through the side arch.
		for x in [-6,6]:
			if x<0: box(node,Vector3(x,3.9,0),Vector3(.3,.8,16),wall_key)
			else:
				box(node,Vector3(x,3.9,1.6),Vector3(.3,.8,12.8),wall_key)
				box(node,Vector3(x,3.9,-7.6),Vector3(.3,.8,.8),wall_key)
			box(node,Vector3(x,6.55,0),Vector3(.3,.9,16),wall_key)
			for z in [-8,-4,0,4,8]: box(node,Vector3(x,5.25,z),Vector3(.4,2,.4),wall_key)
			for z in [-6,-2,2,6]:
				if x>0 and z==-6: continue
				box(node,Vector3(x,5.2,z),Vector3(.08,1.8,3.6),"glass")
				box(node,Vector3(x,4.25,z),Vector3(.5,.12,3.7),"medical",false)
		for z in [-8,8]: wall(node,Vector3(0,5.25,z),Vector3(12,3.5,.3),wall_key)
		box(node,Vector3(0,7,0),Vector3(12.5,.2,16.5),"steel" if purpose in ["warehouse","rail"] else "concrete")
		for x in [-6,6]: box(node,Vector3(x,7.3,0),Vector3(.2,.6,16.4),"concrete")
		if purpose=="residential":
			wall(node,Vector3(0,5.25,1),Vector3(8,3.5,.2),"concrete")
			box(node,Vector3(-3,3.85,3),Vector3(1.1,.6,2.1),"wood")
			box(node,Vector3(-3,4.2,3),Vector3(1.05,.2,2),"medical",false)
			asset(node,"break_table",Vector3(3,3.6,3),0,false)
		elif purpose=="medical":
			asset(node,"biosafety_cabinet",Vector3(-4,3.6,-4),0,false)
			asset(node,"server_rack",Vector3(4,3.6,3),0,false)
			box(node,Vector3(-2,8.5,-2),Vector3(4,3,5),"paint")
			(kits[node] as WorldMeshKit).cylinder(Vector3(-2,10.8,-2),1,1.5,"steel")
		else:
			for z in [-2,2,6]:
				asset(node,"shipping_crate",Vector3(4.4,3.6,z),0,false)
				box(node,Vector3(2.6,4.1,z),Vector3(.06,1,.06),"steel",false)
		lamp(node,Vector3(0,6.8,-5),purpose=="medical")
	var models: Array=["med_cabinet","filing_cabinet","specimen_cooler","medicine_fridge"] if purpose=="medical" else ["staff_locker","personal_bag","desk_drawers","filing_cabinet"] if purpose=="residential" else ["shipping_crate","tool_drawers","weapon_crate","ammo_box"]
	for i in loot_slots:
		var pos:=Vector3(-4.7 if i%2==0 else 4.7,0,-6.8+(i/2)*3.7)
		var storage:=furnishing(node,pos,models[i%4],i==1 and (purpose=="security" or (purpose=="medical" and not restricted)),{"research_drive":2} if restricted and i==1 else {"infection_suppressant":2} if restricted and i==0 else {})
		var item: String=["infection_suppressant","research_notes","sterile_lab_supplies","medkit"][i%4] if purpose=="medical" else ["personal_effects","food","tool","salvage"][i%4]
		var storage_shape: BoxShape3D=storage.get_node("CollisionShape3D").shape
		pickup(node,pos+Vector3(-signf(pos.x)*(storage_shape.size.x*.5+.4),.05,0),item)
	if purpose=="medical":
		asset(node,"medical_station",Vector3(-3,0,3))
		asset(node,"supply_cart",Vector3(3,0,-4),0,false)
		asset(node,"instrument_bench",Vector3(-3,0,-5),0,false)
		asset(node,"analyzer",Vector3(-3,1.46,-5),0,false,false)
		asset(node,"exam_chair",Vector3(3,0,3),0,false)
		asset(node,"privacy_screen",Vector3(1.7,0,3),0,false)
		asset(node,"wash_station",Vector3(-5,0,-2),0,false)
		asset(node,"sharps_bin",Vector3(-4,0,5),0,false)
	elif purpose=="residential":
		asset(node,"break_table",Vector3(3,0,2),0,false)
		box(node,Vector3(-3,.3,-5),Vector3(1.1,.6,2.1),"wood")
		box(node,Vector3(-3,.65,-5),Vector3(1.05,.2,2),"medical",false)
		box(node,Vector3(-3,.8,-5.7),Vector3(.7,.12,.45),"paint",false)
		box(node,Vector3(4.8,.45,-5),Vector3(1.7,.9,2.5),"wood")
		box(node,Vector3(4.8,.96,-5),Vector3(1.8,.08,2.6),"steel",false)
		for z in [-5.6,-4.6]: (kits[node] as WorldMeshKit).cylinder(Vector3(4.8,1.01,z),.22,.025,"rubber")
		asset(node,"stool",Vector3(3,0,3.7),0,false)
		asset(node,"toilet",Vector3(3,0,-6.5),0,false)
	else:
		# The legacy pallet rack is 10.1 x 7.8 m: it belongs in Labs' large
		# warehouse, not these 3.5 m rooms. Author a correctly sized shelf here.
		for x in [-3.85,-1.35]:
			for z in [-5.75,-4.85]: box(node,Vector3(x,1.3,z),Vector3(.08,2.6,.08),"steel")
		for y in [.15,.9,1.65,2.4]: box(node,Vector3(-2.6,y,-5.3),Vector3(2.5,.08,.9),"wood")
		asset(node,"industrial_press",Vector3(3,0,-5)).scale=Vector3.ONE*.75
		asset(node,"wrapped_pallet",Vector3(-3,0,3),0,false)
		asset(node,"electrical_panel",Vector3(5.6,0,2),-PI*.5,false)
	for z in [-5,3]: lamp(node,Vector3(0,3.2,z),purpose=="medical")
	buildings.append({"id":index,"at":node.position,"purpose":purpose,"upper":upper,"restricted":restricted})
	for x in [-6.9,6.9]:
		var marker:=Marker3D.new(); add(node,marker,"WallCover%d"%cover.size())
		marker.position=Vector3(x,.05,0); marker.rotation.y=0 if x<0 else PI
		marker.add_to_group("district_cover",true)
		cover.append({"asset":"building_wall","position":at,"cover_point":marker.position})
	return node

func cover_asset(parent: Node3D,identity: String,at: Vector3,yaw := 0.0) -> void:
	var prop:=asset(parent,identity,at,yaw)
	var marker:=Marker3D.new(); add(parent,marker,"Cover%03d"%cover.size())
	var bounds: AABB=prop.get_meta("bounds")
	marker.position=at+Basis(Vector3.UP,yaw)*Vector3(-bounds.size.x*.5-.7,0,0)
	marker.rotation.y=yaw
	marker.add_to_group("district_cover",true)
	cover.append({"asset":identity,"position":parent.transform*at,"cover_point":parent.transform*marker.position})
	prop.set_meta("tactical_cover",true)

func decay(parent: Node3D,at: Vector3) -> void:
	var painted: Array[PackedVector2Array]=[]
	for stage in [1,2,3]:
		var node:=section("Contamination%d_%d"%[stage,serial],at,parent)
		node.set_meta("contamination_stage",stage)
		var radius: float=1.5+stage*.6
		for i in range(stage*3):
			var angle:=i*2.4
			var center:=Vector2(cos(angle),sin(angle))*radius
			var polygon:=PackedVector2Array([center+Vector2(-.4,-.65),center+Vector2(.4,-.65),center+Vector2(.4,.65),center+Vector2(-.4,.65)])
			var pieces: Array[PackedVector2Array]=[polygon]
			for previous in painted:
				var next: Array[PackedVector2Array]=[]
				for piece in pieces: next.append_array(DistrictSurfaceGeometry.subtract(piece,previous))
				pieces=next
			for piece in pieces:
				var indices:=Geometry2D.triangulate_polygon(piece)
				for j in range(0,indices.size(),3):
					var a:=piece[indices[j]]; var b:=piece[indices[j+1]]; var c:=piece[indices[j+2]]
					(kits[node] as WorldMeshKit).tri(Vector3(a.x,.03,a.y),Vector3(b.x,.03,b.y),Vector3(c.x,.03,c.y),Vector3.UP,"contamination")
			painted.append(polygon)
		if stage>1:
			for i in range(stage*2): box(node,Vector3(.25*i,.1*i,-2),Vector3(.22,.25,.3),"contamination",false)
	var particles:=DistrictAtmosphere.emitter("contamination",24); particles.position=at+Vector3.UP*.5
	add(parent,particles)
	var volume:=FogVolume.new(); volume.position=at+Vector3.UP*.6; volume.size=Vector3(6,1.2,6)
	var fog:=FogMaterial.new(); fog.density=.07; fog.albedo=Color("667366")
	volume.material=fog; volume.set_meta("contamination_stage",2); volume.visible=false
	add(parent,volume,"LocalizedResidueFog%d"%serial)

func finish() -> void:
	# Asphalt takes precedence over courtyards. Subtract earlier patches and all
	# buildings so each exposed ground location has exactly one pavement surface.
	var priorities: Dictionary={"warning":0,"asphalt":1,"concrete":2}
	paving.sort_custom(func(a,b): return priorities[a.material]<priorities[b.material])
	var painted: Array[PackedVector2Array]=[]
	var ground:=section("UnifiedPavement")
	var ground_kit: WorldMeshKit=kits[ground]
	for patch in paving:
		var pieces: Array[PackedVector2Array]=[patch.polygon]
		for cutter in building_footprints+painted:
			var next: Array[PackedVector2Array]=[]
			for piece in pieces: next.append_array(DistrictSurfaceGeometry.subtract(piece,cutter))
			pieces=next
			if pieces.is_empty(): break
		for piece in pieces:
			var indices:=Geometry2D.triangulate_polygon(piece)
			for i in range(0,indices.size(),3):
				var a:=piece[indices[i]]; var b:=piece[indices[i+1]]; var c:=piece[indices[i+2]]
				ground_kit.tri(Vector3(a.x,.035,a.y),Vector3(b.x,.035,b.y),Vector3(c.x,.035,c.y),Vector3.UP,patch.material)
		painted.append(patch.polygon)
	for node: Node3D in kits:
		var mesh: ArrayMesh=(kits[node] as WorldMeshKit).finish()
		if mesh.get_surface_count()==0: continue
		var visual:=MeshInstance3D.new(); visual.mesh=mesh; add(node,visual,"BakedMesh")
		visual.set_meta("world_generated",true)

func terrain_height(at: Vector2) -> float:
	# Traversal and building foundations flatten terrain before meshes are authored.
	var blend:=1.0
	for point in layout.positions:
		blend=minf(blend,clampf((at.distance_to(point)-32)/8,0,1))
	for edge in layout.edges:
		var near:=Geometry2D.get_closest_point_to_segment(at,layout.positions[edge.x],layout.positions[edge.y])
		blend=minf(blend,clampf((at.distance_to(near)-8)/6,0,1))
	for site in infill_sites():
		blend=minf(blend,clampf((at.distance_to(site)-14)/6,0,1))
	if absf(at.x)>config.size_meters*.5-27 or absf(at.y)>config.size_meters*.5-27: return 0
	var ridge:=maxf(0,1.0-at.distance_to(Vector2(-35,63))/22.0)*2.5
	var embankment:=maxf(0,1.0-at.distance_to(Vector2(112,-48))/17.0)*3.0
	var channel:=-maxf(0,1.0-absf(at.x-142)/4.0)*.9
	var rolling:=(sin(at.x*.043)*cos(at.y*.051)+1)*.45
	return snappedf((ridge+embankment+channel+rolling)*blend,.125)

func terrain() -> void:
	var extent:=int(config.size_meters*.5)
	for cx in range(-extent,extent,25):
		for cz in range(-extent,extent,25):
			var node:=section("Terrain_%d_%d"%[cx,cz])
			var kit: WorldMeshKit=kits[node]
			for x in range(cx,cx+25,5):
				for z in range(cz,cz+25,5):
					var a:=Vector3(x,terrain_height(Vector2(x,z)),z)
					var nx:=mini(x+5,extent); var nz:=mini(z+5,extent)
					if x>=extent or z>=extent: continue
					var b:=Vector3(nx,terrain_height(Vector2(nx,z)),z)
					var c:=Vector3(nx,terrain_height(Vector2(nx,nz)),nz)
					var d:=Vector3(x,terrain_height(Vector2(x,nz)),nz)
					kit.tri(a,b,c,(c-a).cross(b-a).normalized(),"dirt")
					kit.tri(a,c,d,(d-a).cross(c-a).normalized(),"dirt")
			var mesh:=kit.finish()
			var visual:=MeshInstance3D.new(); visual.mesh=mesh; add(node,visual,"TerrainMesh")
			collider(node,Vector3.ZERO,mesh.create_trimesh_shape(),"dirt")
			kits.erase(node)

func roads() -> void:
	for index in layout.edges.size():
		var edge:=layout.edges[index]
		var a:=layout.positions[edge.x]; var b:=layout.positions[edge.y]
		var center:=(a+b)*.5
		var length:=a.distance_to(b)
		var road:=section("Route%02d_%s"%[index,layout.route_kinds[index]],Vector3(center.x,0,center.y))
		road.rotation.y=atan2(b.x-a.x,b.y-a.y)
		var width:=8.0 if layout.route_kinds[index]=="street" else 5.0
		box(road,Vector3(0,.015,0),Vector3(width,.03,length),"asphalt",false)
		for z in range(-int(length*.5)+8,int(length*.5)-8,8):
			if width>6: box(road,Vector3(0,.04,z),Vector3(.1,.015,3),"warning",false)
		for side in [-1,1]:
			for z in range(-int(length*.5)+12,int(length*.5)-12,12):
				if not placement_clear(road.transform*Vector3(side*(width*.5+3),0,z)): continue
				box(road,Vector3(side*(width*.5+.8),.06,z),Vector3(1.5,.12,10.5),"concrete")
				# Broken perimeter walls define alleys while leaving deliberate flank gaps.
				var height:=1.8 if index%3!=0 else 1.15
				wall(road,Vector3(side*(width*.5+3),height*.5,z),Vector3(.25,height,8),"concrete" if index%2==0 else "steel")
				for end in [-4,4]: box(road,Vector3(side*(width*.5+3),1.1,z+end),Vector3(.4,2.2,.4),"concrete")
		# Cover spacing is tied to route length, alternating flanks and combat scale.
		for i in range(1,int(length/18.0)):
			var z: float=-length*.5+i*18
			var side:=1.0 if i%2==0 else -1.0
			var identity: String="damaged_car" if i%4==0 else "industrial_truck" if i%7==0 else "concrete_barricade"
			if not placement_clear(road.transform*Vector3(side*(width*.5-1.1),0,z)): continue
			cover_asset(road,identity,Vector3(side*(width*.5-1.1),0,z),.12*side if identity!="concrete_barricade" else 0)
			if i%3==0:
				if placement_clear(road.transform*Vector3(side*(width*.5+2),0,z+4)):
					box(road,Vector3(side*(width*.5+2),.6,z+4),Vector3(3,1.2,4),"concrete")
				var dust:=DistrictAtmosphere.emitter("debris",12); dust.position=Vector3(side*width*.5,.5,z); add(road,dust)
	# Perimeter detour is longer and avoids the high-value central encounters.
	var perimeter:=section("PerimeterServiceRoad")
	var edge:=config.size_meters*.5-21
	for x in [-edge,edge]: box(perimeter,Vector3(x,.015,0),Vector3(6,.03,edge*2+2),"asphalt",false)
	for z in [-edge,edge]: box(perimeter,Vector3(0,.015,z),Vector3(edge*2+2,.03,6),"asphalt",false)
	for i in range(-int(edge)+14,int(edge)-13,20):
		cover_asset(perimeter,"concrete_barricade",Vector3(-edge+3,0,i))
		cover_asset(perimeter,"concrete_barricade",Vector3(edge-3,0,i))
		cover_asset(perimeter,"concrete_barricade",Vector3(i,0,-edge+3),PI*.5)
		cover_asset(perimeter,"concrete_barricade",Vector3(i,0,edge-3),PI*.5)

func placement_clear(at: Vector3) -> bool:
	# POI yards have their own authored cover, vehicles and utility equipment.
	# Reserve the whole yard for those assemblies, not just building centres.
	for point in layout.positions:
		if Vector2(at.x,at.z).distance_to(point)<33: return false
	var counts: Array[int]=[2,1,3,2,1,2,1]
	for i in layout.positions.size():
		for n in counts[i]:
			var center:=layout.positions[i]+Vector2(-19 if n==0 else 19 if n==1 else 0,-8 if n<2 else 24)
			# Includes the doorway approaches and the external roof stairs.
			if absf(at.x-center.x)<12 and absf(at.z-center.y)<14: return false
	for center in infill_sites():
		if absf(at.x-center.x)<12 and absf(at.z-center.y)<14: return false
	return true

func infill_sites() -> Array[Vector2]:
	var result: Array[Vector2]=[]
	for at: Vector2 in [Vector2(-118,-125),Vector2(-125,65),Vector2(120,110),Vector2(-20,78)]: result.append(at*config.size_meters/350.0)
	return result

func infill() -> void:
	var neighborhood:=section("DistrictBackstreets")
	var sites:=infill_sites()
	for i in sites.size():
		var at:=Vector3(sites[i].x,0,sites[i].y)
		var node:=building(neighborhood,at,"residential" if i<2 else "utility",i<2,false,0)
		if i<2:
			sign_board(node,"residential",Vector3(0,2.8,8.2),4)
			asset(neighborhood,"damaged_car",at+Vector3(-9,0,9),PI*.5)
		else:
			asset(neighborhood,"air_handler",at+Vector3(0,7.2 if i<2 else 3.6,0),0,false)
		box(neighborhood,at+Vector3(0,.04,11),Vector3(15,.08,5),"concrete")
		for x in [-8,8]: wall(neighborhood,at+Vector3(x,.65,-2),Vector3(.3,1.3,10))

func poi_content() -> void:
	var purposes: Array[String]=["medical","scrap","residential","warehouse","utility","rail","security"]
	var building_counts: Array[int]=[2,1,3,2,1,2,1]
	for index in layout.positions.size():
		var point:=layout.positions[index]
		var poi:=section("POI_"+DistrictLayout.POIS[index],Vector3(point.x,0,point.y))
		poi.set_meta("poi_id",DistrictLayout.POIS[index]); poi.set_meta("poi_title",TITLES[index]); poi.set_meta("poi_radius",35.0)
		box(poi,Vector3(0,.025,0),Vector3(8,.05,58),"concrete",false)
		for x in [-19,19]: box(poi,Vector3(x,.025,1),Vector3(17,.05,27),"concrete",false)
		sign_board(poi,DistrictLayout.POIS[index],Vector3(0,3.5,15),6)
		for n in building_counts[index]:
			var at:=Vector3(-19 if n==0 else 19 if n==1 else 0,0,-8 if n<2 else 24)
			building(poi,at,purposes[index],index in [0,2,3,5],index==0 and n==0)
		for n in 4:
			actor_points.append(Vector3(point.x+(-6 if n%2==0 else 6),.05,point.y+(-5 if n<2 else 7)))
		match index:
			0:
				asset(poi,"medical_station",Vector3(4,0,-16))
				sign_board(poi,"medical",Vector3(-7,2.6,2),3.5)
				decay(poi,Vector3(-20,0,-18))
				var steam:=DistrictAtmosphere.emitter("steam",24); steam.position=Vector3(-24,3.7,-10); add(poi,steam)
			1:
				for n in 4:
					cover_asset(poi,"industrial_press",Vector3(9+n%2*9,0,-20+n/2*20),PI*.5)
					asset(poi,"industrial_truck",Vector3(-4,0,-20+n*12),.2*n)
				var smoke:=DistrictAtmosphere.emitter("smoke",32); smoke.position=Vector3(18,3,-20); add(poi,smoke)
			2:
				for x in [-9,9]: cover_asset(poi,"damaged_car",Vector3(x,0,10),PI*.5)
				sign_board(poi,"evacuation",Vector3(0,2.8,-24),5)
			3:
				for z in [-24,18]:
					cover_asset(poi,"shipping_container",Vector3(8,0,z),PI*.5)
					asset(poi,"forklift",Vector3(-6,0,z),0,false)
			4:
				for z in [-18,-9,0,9,18]:
					box(poi,Vector3(15,1.5,z),Vector3(6,3,4),"steel")
					for x in [13,17]:
						(kits[poi] as WorldMeshKit).cylinder(Vector3(x,3.5,z),.3,1,"rubber")
				lamp(poi,Vector3(15,6,0),true)
			5:
				for z in [-5,5]:
					for x in range(-30,31,3): box(poi,Vector3(x,.1,z),Vector3(1.6,.15,.2),"wood",false)
					for rail_z in [z-.55,z+.55]: box(poi,Vector3(0,.22,rail_z),Vector3(65,.12,.08),"rust",false)
				for x in [-16,15]: cover_asset(poi,"shipping_container",Vector3(x,0,18),PI*.5)
			6:
				for z in [-18,18]:
					cover_asset(poi,"industrial_truck",Vector3(10,0,z),.1)
					for x in [-5,5]: cover_asset(poi,"concrete_barricade",Vector3(x,0,z),PI*.5)
				sign_board(poi,"evacuation",Vector3(12,3,0),5)
				decay(poi,Vector3(-15,0,-20))
		for x in [-9,9]: lamp(poi,Vector3(x,4.5,0),index in [0,6])
		if index in [1,3,6]:
			for x in [-7,7]:
				var voxel:=VoxelDestructible.new(); voxel.dimensions=Vector3i(12,6,2); voxel.material=concrete
				voxel.surface_color=Color("73796e"); voxel.position=Vector3(x,.75,12)
				add(poi,voxel,"DamagedCover%d"%serial)
				add(voxel,MeshInstance3D.new(),"MeshInstance3D"); add(voxel,CollisionShape3D.new(),"CollisionShape3D")
				var marker:=Marker3D.new(); marker.position=Vector3(x,.05,13.1); marker.rotation.y=PI*.5
				add(poi,marker,"VoxelCover%d"%serial); marker.add_to_group("district_cover",true)
		var rain:=DistrictAtmosphere.emitter("rain",64); rain.position=Vector3(0,10,0); add(poi,rain)

func boundary() -> void:
	var node:=section("DistrictBoundary")
	var extent:=config.size_meters*.5
	for side in [-1,1]:
		wall(node,Vector3(side*(extent-1),1.5,0),Vector3(.5,3,config.size_meters))
		wall(node,Vector3(0,1.5,side*(extent-1)),Vector3(config.size_meters,3,.5))
	# Service utility poles and dead woodland define the district's outer silhouette.
	for index in range(-int(extent)+25,int(extent)-24,25):
		for x in [-extent+10,extent-10]:
			box(node,Vector3(x,4,index),Vector3(.3,8,.3),"wood")
			box(node,Vector3(x,7.5,index),Vector3(3,.18,.18),"steel",false)
		for z in [-extent+10,extent-10]:
			var tree:=Vector3(index,0,z)
			(kits[node] as WorldMeshKit).cylinder(tree+Vector3(0,2.5,0),.3,5,"wood",1,8)
			box(node,tree+Vector3(0,4.3,0),Vector3(3,.3,.25),"wood",false)
			box(node,tree+Vector3(0,4.8,0),Vector3(.2,.25,2.7),"wood",false)

func vegetation() -> void:
	var rng:=RandomNumberGenerator.new(); rng.seed=DistrictLayout.stream(layout.seed_value,"vegetation")
	var positions: Array[Vector3]=[]
	var limit:=config.size_meters*.5-10
	var perimeter_edge:=config.size_meters*.5-21
	for attempt in 700:
		if positions.size()>=110: break
		var at:=Vector2(rng.randf_range(-limit,limit),rng.randf_range(-limit,limit))
		var allowed:=true
		for poi in layout.positions:
			if at.distance_to(poi)<37: allowed=false; break
		for site in infill_sites():
			if at.distance_to(site)<15: allowed=false; break
		if not allowed: continue
		for edge in layout.edges:
			var nearest:=Geometry2D.get_closest_point_to_segment(at,layout.positions[edge.x],layout.positions[edge.y])
			if at.distance_to(nearest)<12: allowed=false; break
		if not allowed or absf(absf(at.x)-perimeter_edge)<6 or absf(absf(at.y)-perimeter_edge)<6: continue
		positions.append(Vector3(at.x,terrain_height(at),at.y))
	var forest:=section("AbandonedWoodland")
	var kit:=WorldMeshKit.new()
	kit.cylinder(Vector3(0,2.2,0),.18,4.4,"wood",1,8)
	for i in 3:
		kit.cylinder(Vector3(0,2.5+i*.8,0),1.7-i*.45,.5,"contamination",1,8)
		kit.box(Vector3(0,2.8+i*.6,0),Vector3(2.5-i*.5,.14,.14),"wood")
	var visual:=DistrictFoliage.new()
	visual.multimesh=MultiMesh.new(); visual.multimesh.transform_format=MultiMesh.TRANSFORM_3D
	visual.multimesh.mesh=kit.finish(); visual.multimesh.instance_count=positions.size()
	for i in positions.size():
		var basis:=Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*rng.randf_range(.8,1.25))
		visual.instance_transforms.append(Transform3D(basis,positions[i]))
		var shape:=CylinderShape3D.new(); shape.radius=.2; shape.height=4
		collider(forest,positions[i]+Vector3.UP*2,shape,"wood")
	add(forest,visual,"TreeInstances")

func gameplay(map_definition: RaidMapDefinition) -> void:
	scene.set("map_definition",map_definition)
	var player: RaidPlayer=load("res://scenes/player/player.tscn").instantiate(); add(scene,player,"Player")
	player.position=Vector3(-150,.05,-140)
	var sensor: SignalDecay=load("res://scenes/rendering/signal_decay.tscn").instantiate(); sensor.manages_environment=false; add(scene,sensor,"SignalDecay")
	var impacts:=Node3D.new(); impacts.set_script(preload("res://scripts/combat/impact_presenter.gd")); add(scene,impacts,"ImpactPresenter")
	var debris:=VoxelDebrisManager.new(); add(scene,debris,"VoxelDebris")
	for node in scene.find_children("*","",true,false):
		if node is VoxelDestructible: node.debris_manager_path=node.get_path_to(debris)
	var dressing:=MedTacDressing.new(); add(scene,dressing,"Dressing")
	var debug_layer:=CanvasLayer.new(); debug_layer.layer=90; add(scene,debug_layer,"DeveloperOverlay")
	var overlay:=DistrictDebugOverlay.new(); add(debug_layer,overlay,"DistrictInspector")
	var insertions: Array[Vector2]=[Vector2(-150,-140),Vector2(150,-140),Vector2(160,0),Vector2(135,145),Vector2(0,158),Vector2(-140,145),Vector2(-160,0)]
	for i in insertions.size(): insertions[i]*=config.size_meters/350.0
	for i in insertions.size():
		var marker:=Marker3D.new(); add(scene,marker,"Insertion%02d"%i)
		marker.position=Vector3(insertions[i].x,.05,insertions[i].y); marker.rotation.y=atan2(marker.position.x,marker.position.z)
		marker.add_to_group("raid_spawns",true)
	var exits: Array[Vector2]=[Vector2(-160,-160),Vector2(160,-160),Vector2(160,160),Vector2(-160,160)]
	for i in exits.size(): exits[i]*=config.size_meters/350.0
	var ids: Array[String]=["north","east","south","west"]
	for i in exits.size():
		var zone:=ExtractionZone.new(); zone.entity_id="district-extract-"+ids[i]; zone.display_name=ids[i].capitalize()+" Service Exit"
		zone.collision_layer=0; zone.collision_mask=1; zone.position=Vector3(exits[i].x,0,exits[i].y)
		add(scene,zone,"Extraction" if i==0 else "Extraction%d"%i)
		var collider_node:=CollisionShape3D.new(); var shape:=BoxShape3D.new(); shape.size=Vector3(10,5,10); collider_node.shape=shape; collider_node.position.y=2
		add(zone,collider_node,"CollisionShape3D")
		var marker:=section("ExtractMarker%d"%i,zone.position)
		box(marker,Vector3(0,.04,0),Vector3(9,.025,9),"paint",false)
		sign_board(marker,ids[i],Vector3(0,3.5,-3),5)
		lamp(marker,Vector3(0,3.2,-3),true)
	for i in map_definition.enemy_count:
		var npc: RaidGuard=load("res://scenes/npcs/guard.tscn").instantiate()
		npc.entity_id="district-"+("infected" if i<map_definition.infected_count else "scav")+"-%02d"%i
		npc.archetype=load("res://resources/npcs/"+("zombie" if i<map_definition.infected_count else "guard")+".tres")
		npc.material=steel; npc.position=actor_points[i%actor_points.size()]
		npc.patrol_points=PackedVector3Array([npc.position,npc.position+Vector3(0,0,4),npc.position+Vector3(3,0,4)])
		add(scene,npc,"Guard" if i==0 else "Occupant%02d"%i)
