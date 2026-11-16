class_name DistrictAssetAuthor
extends RefCounted

const IDS := ["damaged_car","industrial_truck","industrial_press","medical_station","concrete_barricade","shipping_container","residential_facade","warehouse_facade"]
var kit: WorldMeshKit
var components: Array[String]=[]
var solids: Array[Dictionary]=[]

func block(name: String,at: Vector3,size: Vector3,material: String,collision := false) -> void:
	kit.box(at,size,material)
	if not components.has(name): components.append(name)
	if collision: solids.append({"at":at,"size":size})

func wheel(at: Vector3,radius: float) -> void:
	kit.cylinder(at,radius,.25,"rubber",0,16)
	kit.cylinder(at+Vector3(signf(at.x)*.135,0,0),radius*.62,.04,"steel",0,12)
	kit.cylinder(at+Vector3(signf(at.x)*.16,0,0),radius*.25,.06,"rust",0,8)
	for i in 5:
		var angle:=TAU*i/5
		kit.box(at+Vector3(signf(at.x)*.17,cos(angle)*radius*.4,sin(angle)*radius*.4),Vector3(.02,.06,.06),"rubber")

func car(truck := false) -> void:
	var length:=6.8 if truck else 4.6
	var width:=2.4 if truck else 1.84
	var wheel_r:=.55 if truck else .375
	var axle:=2.15 if truck else 1.45
	for x in [-1,1]:
		for z in [-axle,axle]: wheel(Vector3(x*width*.48,wheel_r,z),wheel_r)
	components.append_array(["wheels","chassis","cab","glazing","bumper","lamps","damage"])
	block("chassis",Vector3(0,.5,0),Vector3(width*.75,.18,length-.3),"steel",true)
	if truck:
		# Cab-over-engine outline with stepped windscreen slope; the bed remains open.
		kit.profile(PackedVector2Array([Vector2(-.95,.7),Vector2(.95,.7),Vector2(.95,2.7),Vector2(.65,2.9),Vector2(-.75,2.9),Vector2(-.95,2.45)]),width,Vector3(0,0,-2.2),"paint",0)
		solids.append({"at":Vector3(0,1.7,-2.2),"size":Vector3(width,2.2,1.9)})
		block("windscreen",Vector3(0,2.25,-3.17),Vector3(width-.3,.85,.035),"glass")
		for x in [-1,1]:
			block("side_windows",Vector3(x*(width*.5+.015),2.2,-2.1),Vector3(.025,.8,1.1),"glass")
			block("handles",Vector3(x*(width*.5+.03),1.6,-1.8),Vector3(.04,.06,.22),"rubber")
			block("bed_rails",Vector3(x*(width*.5-.07),1.3,1.05),Vector3(.14,.65,4.25),"rust",true)
		block("bed",Vector3(0,.95,1.05),Vector3(width,.16,4.3),"wood",true)
		for z in [-.9,0,1,2,3]: block("bed_ribs",Vector3(0,1.05,z),Vector3(width-.15,.04,.08),"steel")
		for x in [-.5,.5]: block("windscreen_divider",Vector3(x,2.25,-3.2),Vector3(.05,.85,.035),"steel")
		block("grille",Vector3(0,1.15,-3.2),Vector3(1.4,.5,.06),"rubber")
		for y in [1.0,1.15,1.3]: block("grille_slats",Vector3(0,y,-3.24),Vector3(1.35,.035,.04),"steel")
		block("bumper",Vector3(0,.65,-3.32),Vector3(2.5,.22,.2),"rust",true)
		for x in [-.9,.9]: block("lamps",Vector3(x,1.1,-3.23),Vector3(.35,.25,.05),"light")
	else:
		# Continuous concave outline includes both wheel-arch cutouts.
		var body:=PackedVector2Array([Vector2(-2.3,.55),Vector2(-1.9,.55),Vector2(-1.85,.85),Vector2(-1.65,1),Vector2(-1.25,1),Vector2(-1.05,.8),Vector2(-1,.55),Vector2(1,.55),Vector2(1.1,.85),Vector2(1.3,1),Vector2(1.65,1),Vector2(1.85,.85),Vector2(1.9,.55),Vector2(2.3,.55),Vector2(2.3,.9),Vector2(1.9,1.04),Vector2(-1.9,1.04),Vector2(-2.3,.9)])
		kit.profile(WorldMeshKit.stepped(body),width,Vector3.ZERO,"paint",0)
		var glass:=PackedVector2Array([Vector2(-1.3,1.02),Vector2(1.22,1.02),Vector2(.65,1.62),Vector2(-.7,1.62)])
		kit.profile(glass,1.57,Vector3.ZERO,"glass",0)
		var roof:=PackedVector2Array([Vector2(-.85,1.56),Vector2(.8,1.56),Vector2(.65,1.71),Vector2(-.7,1.71)])
		kit.profile(WorldMeshKit.stepped(roof),1.76,Vector3.ZERO,"paint",0)
		for x in [-.83,.83]:
			block("b_pillar",Vector3(x,1.3,0),Vector3(.1,.5,.12),"paint")
			block("door_sill",Vector3(x,.96,0),Vector3(.1,.12,2.4),"steel")
			for z in [-.6,.6]:
				block("door_seams",Vector3(x*1.1,.77,z),Vector3(.015,.32,.025),"rubber")
				block("handles",Vector3(x*1.12,1.03,z+.25),Vector3(.045,.055,.18),"steel")
		solids.append({"at":Vector3(0,1.25,0),"size":Vector3(1.6,.8,1.6)})
		# Collision-only volumes do not cover glazing or intentional body openings.
		block("hood",Vector3(0,.92,-1.75),Vector3(1.65,.18,.8),"paint",true)
		block("bumper",Vector3(-.15,.58,-2.32),Vector3(1.6,.15,.16),"rust",true)
		block("rear_bumper",Vector3(0,.58,2.33),Vector3(1.8,.16,.14),"rubber",true)
		block("grille",Vector3(0,.76,-2.32),Vector3(.8,.2,.035),"rubber")
		for x in [-.65,.65]:
			block("lamps",Vector3(x,.82,-2.33),Vector3(.36,.18,.045),"light" if x<0 else "rubber")
			block("rear_lamps",Vector3(x,.85,2.32),Vector3(.3,.16,.04),"red")
		block("exposed_radiator",Vector3(.5,.62,-2.25),Vector3(.25,.2,.09),"steel")
		for z in [-1.95,-1.85,-1.75]: block("hood_damage",Vector3(.48,1.025,z),Vector3(.35,.02,.035),"rust")

func press() -> void:
	for x in [-1.2,1.2]:
		block("frame",Vector3(x,1.8,0),Vector3(.45,3.6,1.5),"paint",true)
		block("feet",Vector3(x,.15,0),Vector3(.8,.3,2.2),"steel",true)
	block("crosshead",Vector3(0,3.6,0),Vector3(3.2,.55,1.7),"paint",true)
	block("bed",Vector3(0,1,0),Vector3(2.4,.35,1.7),"steel",true)
	kit.cylinder(Vector3(0,2.75,0),.3,1.3,"steel")
	block("ram",Vector3(0,2,0),Vector3(1.7,.3,1.1),"rust",true)
	block("controls",Vector3(1.55,1.6,.6),Vector3(.35,.65,.4),"medical",true)
	block("power_unit",Vector3(-1.55,.8,0),Vector3(.5,1.1,.8),"steel",true)
	for x in [-.8,.8]:
		kit.cylinder(Vector3(x,2.0,0),.065,2.1,"steel")
		for z in [-.55,.55]: kit.cylinder(Vector3(x,.2,z),.07,.1,"rust")
	for x in range(-7,8,2): block("safety_marks",Vector3(x*.1,2.0,.565),Vector3(.12,.16,.025),"warning")
	for y in [1.45,1.65]: kit.cylinder(Vector3(1.55,y,.82),.055,.03,"red",2,8)
	for x in [-.7,.7]:
		kit.cylinder(Vector3(x,2.5,.87),.05,1.9,"rust")
		block("hydraulics",Vector3(x,3.45,.5),Vector3(.2,.2,.9),"steel")
	components.append_array(["hydraulics","ram","controls"])

func medical() -> void:
	block("base",Vector3(0,.2,0),Vector3(1.7,.15,.9),"steel",true)
	for x in [-.7,.7]:
		for z in [-.35,.35]: kit.cylinder(Vector3(x,.12,z),.12,.09,"rubber",0,8)
	block("pedestal",Vector3(0,.65,0),Vector3(.35,.8,.4),"medical",true)
	block("mattress",Vector3(-.15,1.15,0),Vector3(1.8,.2,.75),"paint",true)
	kit.profile(PackedVector2Array([Vector2(-.4,0),Vector2(.4,0),Vector2(.4,.65),Vector2(.28,.8),Vector2(-.28,.8),Vector2(-.4,.65)]),.12,Vector3(.7,1.3,0),"medical")
	block("monitor",Vector3(.7,1.75,-.075),Vector3(.62,.4,.025),"glass")
	for x in [.5,.6,.7,.8]: block("monitor_trace",Vector3(x,1.72+sin(x*30)*.05,-.095),Vector3(.08,.025,.01),"light")
	kit.cylinder(Vector3(-.95,1.05,-.35),.035,1.8,"steel")
	block("iv_bag",Vector3(-.95,1.75,-.3),Vector3(.2,.3,.07),"medical")
	block("iv_line",Vector3(-.95,1,-.25),Vector3(.015,1.2,.015),"rubber")
	components.append_array(["casters","iv","monitor"])

func barrier() -> void:
	kit.profile(PackedVector2Array([Vector2(-.45,0),Vector2(.45,0),Vector2(.45,.25),Vector2(.22,.8),Vector2(.18,1.4),Vector2(-.18,1.4),Vector2(-.22,.8),Vector2(-.45,.25)]),3.2,Vector3.ZERO,"concrete")
	solids.append({"at":Vector3(0,.7,0),"size":Vector3(.75,1.4,3.2)})
	for z in [-1.2,-.6,0,.6,1.2]: block("warning_stripes",Vector3(.19,1.13,z),Vector3(.025,.28,.27),"warning")
	for z in [-.9,.9]: block("lifting_slots",Vector3(0,1.405,z),Vector3(.15,.02,.16),"rubber")
	components.append_array(["tapered_body","lifting_slots"])

func container() -> void:
	block("floor",Vector3(0,.1,0),Vector3(2.5,.2,6.1),"steel",true)
	block("roof",Vector3(0,2.65,0),Vector3(2.5,.12,6.1),"paint",true)
	block("back",Vector3(0,1.35,3),Vector3(2.5,2.6,.12),"paint",true)
	for side in [-1,1]:
		block("sidewalls",Vector3(side*1.22,1.35,0),Vector3(.08,2.6,6),"paint",true)
		for z in range(-28,29,4): block("corrugation",Vector3(side*1.27,1.35,z*.1),Vector3(.06,2.4,.16),"steel")
		for z in [-3,3]: block("corner_castings",Vector3(side*1.2,.2,z),Vector3(.2,.4,.2),"rust")
	# One door is folded back; the full opening remains physically traversable.
	block("door",Vector3(1.9,1.35,-2.95),Vector3(1.2,2.5,.08),"paint",true)
	for x in [1.65,2.1]: block("locking_rods",Vector3(x,1.35,-3.02),Vector3(.035,2.3,.035),"rust")
	components.append_array(["opening","corner_castings","locking_rods"])

func facade(warehouse := false) -> void:
	var width:=12.0 if warehouse else 9.0
	var height:=6.5 if warehouse else 7.0
	block("plinth",Vector3(0,.2,0),Vector3(width,.4,.6),"concrete",true)
	for x in [-width*.5,width*.5]: block("supports",Vector3(x,height*.5,0),Vector3(.35,height,.5),"steel" if warehouse else "concrete",true)
	if warehouse:
		for x in [-4.5,4.5]: block("wall",Vector3(x,3.25,0),Vector3(3,6.5,.3),"steel",true)
		block("lintel",Vector3(0,5.6,0),Vector3(6,1.8,.3),"paint",true)
		for x in range(-5,6): block("seams",Vector3(x,4,.18),Vector3(.04,4.5,.06),"rust")
		block("roller_shutter",Vector3(0,4.55,0),Vector3(6,.3,.3),"rust",true)
		components.append("loading_door")
	else:
		for y in [.9,3.5,6.65]: block("spandrel",Vector3(0,y,0),Vector3(width,.65,.35),"concrete",true)
		for x in [-3.5,0,3.5]: block("piers",Vector3(x,3.5,0),Vector3(.6,6.5,.4),"concrete",true)
		for y in [2.1,5.0]:
			for x in [-1.75,1.75]:
				block("window_recess",Vector3(x,y,-.12),Vector3(2.6,1.8,.035),"glass")
				for side in [-1,1]: block("window_trim",Vector3(x+side*1.35,y,.15),Vector3(.1,1.95,.2),"medical")
				block("sills",Vector3(x,y-.92,.18),Vector3(2.9,.12,.35),"concrete",true)
		components.append("windows")
	block("cornice",Vector3(0,height,0),Vector3(width+.4,.25,.8),"concrete",true)
	components.append_array(["supports","trim","damage"])
	for x in [-3.7,-3.5,-3.3]: block("exposed_rebar",Vector3(x,.7,.28),Vector3(.04,1,.04),"rust")

func create(identity: String) -> Node3D:
	kit=WorldMeshKit.new()
	components=[]; solids=[]
	match identity:
		"damaged_car": car()
		"industrial_truck": car(true)
		"industrial_press": press()
		"medical_station": medical()
		"concrete_barricade": barrier()
		"shipping_container": container()
		"residential_facade": facade()
		"warehouse_facade": facade(true)
	var node:=Node3D.new()
	node.name=identity.to_pascal_case()
	node.set_meta("asset_id",identity)
	node.set_meta("components",components)
	node.set_meta("provenance","Original Last Haul / silhouette-first authored profiles")
	var visual:=MeshInstance3D.new()
	visual.name="Mesh"
	visual.mesh=kit.finish()
	visual.visibility_range_end=180 if identity.ends_with("facade") else 120
	node.add_child(visual); visual.owner=node
	var body:=DecorativeProp.new()
	body.name="Collision"
	body.material=preload("res://resources/materials/concrete.tres") if identity in ["concrete_barricade","residential_facade"] else preload("res://resources/materials/steel.tres")
	node.add_child(body); body.owner=node
	for solid in solids:
		var shape:=CollisionShape3D.new()
		var form:=BoxShape3D.new()
		form.size=solid.size
		shape.shape=form; shape.position=solid.at
		body.add_child(shape); shape.owner=node
	node.set_meta("bounds",visual.mesh.get_aabb())
	return node
