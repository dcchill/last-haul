extends SceneTree

const OUT := "res://scenes/raid/district/"
var config: DistrictGenerationConfig=preload("res://resources/district/generation.tres")

func _initialize() -> void: call_deferred("run")

func write_json(path: String,value: Variant) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"\t"))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	DirAccess.make_dir_recursive_absolute("res://.godot/district-build")
	DirAccess.make_dir_recursive_absolute("res://resources/district/reports")
	var definition:=RaidMapDefinition.new()
	definition.id="medtac_quarantine_district"; definition.display_name="Medtac Quarantine District"
	if config.curated_seeds.is_empty(): push_error("Configure at least one curated seed"); quit(1); return
	definition.scene_path=OUT+"district_%d.tscn"%config.curated_seeds[0]
	definition.infection_seconds=1500; definition.enemy_count=28; definition.infected_count=18; definition.active_loose_loot=48
	for seed_number in config.curated_seeds: definition.approved_layouts.append(OUT+"district_%d.tscn"%seed_number)
	# Existing approved data is not touched unless every staged layout passes.
	var reports: Array[Dictionary]=[]
	if config.size_meters!=350 or config.curated_seeds!=[19381]:
		push_error("The authored campus requires 350 meters and the sole approved seed 19381"); quit(1); return
	for seed_number in config.curated_seeds:
		var layout:=DistrictLayout.generate(seed_number,config)
		if not layout.validate(config).is_empty():
			push_error("Invalid traversal graph: "+str(layout.report())); quit(1); return
		var scene: Node3D=load(OUT+"district_19381.tscn").instantiate()
		var author:=DistrictSceneAuthor.new(); author.scene=scene; author.layout=layout; author.config=config
		author.nav=scene.get_node("NavigationRegion3D")
		for node in scene.find_children("*","StaticBody3D",true,false):
			if node is RaidDoor: author.doors.append(node)
		scene.set_meta("layout_seed",seed_number); scene.set_meta("generator_version",config.generator_version)
		scene.set_meta("layout_report",layout.report())
		var plan_errors:=CampusValidator.plan_errors(scene)
		if not plan_errors.is_empty(): push_error(str(plan_errors)); scene.free(); quit(1); return
		var mesh:=NavigationMesh.new()
		mesh.geometry_parsed_geometry_type=NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		mesh.cell_size=.5; mesh.cell_height=.25; mesh.agent_height=2; mesh.agent_radius=.5; mesh.agent_max_climb=.5
		mesh.agent_max_slope=40; mesh.filter_baking_aabb=AABB(Vector3(-config.size_meters*.5,-6,-config.size_meters*.5),Vector3(config.size_meters,22,config.size_meters))
		author.nav.navigation_mesh=mesh
		root.add_child(scene)
		scene.set_physics_process(false); scene.get_node("Player").set_physics_process(false)
		for door in author.doors:
			if not door.restricted: door.open=true; door.refresh()
		var bake_map:=NavigationServer3D.map_create()
		NavigationServer3D.map_set_active(bake_map,true)
		NavigationServer3D.map_set_use_async_iterations(bake_map,false)
		NavigationServer3D.map_set_merge_rasterizer_cell_scale(bake_map,.01)
		author.nav.set_navigation_map(bake_map)
		for frame in 3: await physics_frame
		print("DISTRICT BUILD ",seed_number,": baking ",author.serial," nodes")
		var geometry:=NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(mesh,geometry,author.nav)
		# Furniture tops are not stairs; project existing bounds through their usable height.
		for prop in scene.find_children("*","Node3D",true,false):
			var bounds:=AABB()
			if prop is SearchableFurniture:
				var collision: CollisionShape3D=prop.get_node("CollisionShape3D")
				bounds=AABB(collision.position-collision.shape.size*.5,collision.shape.size)
			elif prop.has_meta("bounds") and prop.visible: bounds=prop.get_meta("bounds")
			else: continue
			bounds=prop.global_transform*bounds
			var corners:=PackedVector3Array([Vector3(bounds.position.x,0,bounds.position.z),Vector3(bounds.end.x,0,bounds.position.z),Vector3(bounds.end.x,0,bounds.end.z),Vector3(bounds.position.x,0,bounds.end.z)])
			geometry.add_projected_obstruction(corners,bounds.position.y,maxf(2.25,bounds.size.y+.3),false)
		NavigationServer3D.bake_from_source_geometry_data(mesh,geometry)
		var baked:=author.nav.navigation_mesh.duplicate(true) as NavigationMesh
		author.nav.navigation_mesh=null; author.nav.navigation_mesh=baked
		NavigationServer3D.map_force_update(bake_map)
		for frame in 6: await physics_frame
		var report:=DistrictValidator.inspect(scene,layout)
		report.room_audit=CampusValidator.inspect(scene)
		report.errors.append_array(report.room_audit.errors)
		scene.set_meta("architecture_errors",report.room_audit.errors)
		var tactics:=DistrictTactics.analyze(scene,layout,bake_map,config)
		report.tactics=tactics
		report.errors.append_array(tactics.errors)
		scene.set_meta("tactical_report",tactics)
		report.graph=layout.report()
		write_json("res://.godot/district-build/%d-validation.json"%seed_number,report)
		if not report.errors.is_empty():
			push_error("District rejected: "+str(report.errors)); scene.free(); NavigationServer3D.free_rid(bake_map); quit(1); return
		for door in author.doors: door.open=false; door.refresh()
		# Restore prefab instances after the bake so runtime hands/visuals aren't baked.
		for title in ["Player","SignalDecay"]:
			var node:=scene.get_node(title)
			var replacement: Node=load(node.scene_file_path).instantiate()
			var transform: Transform3D=node.transform if node is Node3D else Transform3D.IDENTITY
			scene.remove_child(node); node.free(); author.add(scene,replacement,title)
			if replacement is Node3D: replacement.transform=transform
			if replacement is SignalDecay: replacement.manages_environment=false
		var packed:=PackedScene.new()
		if packed.pack(scene)!=OK or ResourceSaver.save(packed,"res://.godot/district-build/district_%d.tscn"%seed_number)!=OK:
			push_error("Cannot stage district"); quit(1); return
		reports.append(report)
		scene.free(); NavigationServer3D.free_rid(bake_map)
		print("DISTRICT VALIDATED ",seed_number,": ",report.navigation_polygons," nav polygons / ",report.cover_positions," cover anchors")
	for seed_number in config.curated_seeds:
		if DirAccess.copy_absolute("res://.godot/district-build/district_%d.tscn"%seed_number,OUT+"district_%d.tscn"%seed_number)!=OK:
			push_error("Cannot publish validated district"); quit(1); return
	ResourceSaver.save(definition,"res://resources/maps/medtac_quarantine_district.tres")
	# Architecture and building scenes are editor-owned; only baked root data is published.
	for report in reports: write_json("res://resources/district/reports/layout_%d.json"%report.seed,report)
	print("DISTRICT BUILD COMPLETE: one validated static MedTac campus; building scenes preserved")
	quit()
