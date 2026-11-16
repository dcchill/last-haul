extends SceneTree

var stage: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var world: WorldEnvironment
var output := "res://.godot/asset-review"

func _initialize() -> void: call_deferred("run")

func settle() -> void:
	for frame in 3: await process_frame
	if DisplayServer.get_name()!="headless": await RenderingServer.frame_post_draw

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	stage=Node3D.new(); root.add_child(stage)
	world=WorldEnvironment.new(); world.environment=Environment.new()
	world.environment.background_mode=Environment.BG_COLOR
	world.environment.background_color=Color("535e60")
	world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color=Color("c1c9c7")
	world.environment.ambient_light_energy=.6
	stage.add_child(world)
	sun=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-45,-30,0); sun.light_energy=1.2; sun.shadow_enabled=true
	stage.add_child(sun)
	camera=Camera3D.new(); camera.current=true; camera.fov=40; camera.near=.05
	stage.add_child(camera)
	var ground:=MeshInstance3D.new()
	var plane:=PlaneMesh.new(); plane.size=Vector2(40,40)
	ground.mesh=plane
	var floor_mat:=StandardMaterial3D.new(); floor_mat.albedo_color=Color("4b514d"); floor_mat.roughness=1
	ground.material_override=floor_mat
	stage.add_child(ground)
	var reports: Array[Dictionary]=[]
	var catalog: Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/district/asset_catalog.json"))
	var args:=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--definition":
		var selected:=load(args[1]) as WorldAssetDefinition
		if selected==null: push_error("Invalid asset definition"); quit(1); return
		catalog=[{"id":selected.id,"definition":args[1],"scene":selected.scene_path}]
	var sheet:=Image.create(2048,1024,false,Image.FORMAT_RGB8)
	var failures:=0
	for index in catalog.size():
		var entry: Dictionary=catalog[index]
		var definition: WorldAssetDefinition=load(entry.definition)
		var asset: Node3D=load(entry.scene).instantiate()
		stage.add_child(asset)
		var report:=WorldAssetValidator.inspect(asset,definition)
		reports.append(report)
		failures+=report.errors.size()
		print("ASSET ",entry.id,": ",report.triangles," triangles / ",report.errors)
		if DisplayServer.get_name()!="headless":
			DirAccess.make_dir_recursive_absolute(output+"/"+entry.id)
			var bounds: AABB=asset.get_meta("bounds")
			var center:=bounds.get_center()
			var distance:=maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z))*1.8
			var views: Dictionary={"front":Vector3(0,.15,-1),"side":Vector3(1,.15,0),"top":Vector3(.001,1,0),"three_quarter":Vector3(1,.65,-1),"neutral":Vector3(1,.65,-1),"gameplay":Vector3(1,.65,-1)}
			for title: String in views:
				world.environment.ambient_light_energy=.6 if title!="gameplay" else .45
				sun.light_color=Color.WHITE if title!="gameplay" else Color("cad6cb")
				camera.position=center+(views[title] as Vector3).normalized()*distance
				camera.look_at(center)
				await settle()
				var frame:=root.get_texture().get_image()
				frame.save_png(output+"/"+entry.id+"/"+title+".png")
				if title=="three_quarter":
					frame.resize(512,512,Image.INTERPOLATE_LANCZOS)
					frame.convert(sheet.get_format())
					sheet.blit_rect(frame,Rect2i(0,0,512,512),Vector2i(index%4*512,index/4*512))
		asset.free()
	if DisplayServer.get_name()!="headless": sheet.save_png(output+"/contact-sheet.png")
	var file:=FileAccess.open(output+"/validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(reports,"\t"))
	stage.free()
	print("ASSET REVIEW: ",reports.size()," assets, ",failures," technical failures; visual review separate")
	quit(1 if failures else 0)
