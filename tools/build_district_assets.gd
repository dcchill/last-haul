extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://scenes/props/district")
	DirAccess.make_dir_recursive_absolute("res://resources/district/assets")
	DirAccess.make_dir_recursive_absolute("res://resources/district/environments")
	DirAccess.make_dir_recursive_absolute("res://resources/district/materials")
	WorldMeshKit.refresh_materials=true
	var author:=DistrictAssetAuthor.new()
	var catalog: Array[Dictionary]=[]
	var sizes: Array[Vector3]=[Vector3(2.15,1.8,4.8),Vector3(2.7,2.95,6.8),Vector3(3.5,3.9,2.2),Vector3(2.2,2.15,.9),Vector3(.9,1.42,3.2),Vector3(3.8,2.72,6.2),Vector3(9.4,7.2,.9),Vector3(12.4,6.75,.9)]
	for i in DistrictAssetAuthor.IDS.size():
		var identity: String=DistrictAssetAuthor.IDS[i]
		var node:=author.create(identity)
		for key: String in author.kit.materials:
			ResourceSaver.save(author.kit.materials[key],"res://resources/district/materials/"+key+".tres")
		var definition:=WorldAssetDefinition.new()
		definition.id=identity
		definition.scene_path="res://scenes/props/district/"+identity+".tscn"
		definition.expected_size=sizes[i]
		definition.dimension_tolerance=.4
		definition.required_components.assign(node.get_meta("components"))
		definition.source_file="res://tools/district_asset_author.gd"
		var packed:=PackedScene.new()
		if packed.pack(node)!=OK or ResourceSaver.save(packed,definition.scene_path)!=OK:
			push_error("Cannot save asset "+identity); quit(1); return
		ResourceSaver.save(definition,"res://resources/district/assets/"+identity+".tres")
		catalog.append({"id":identity,"definition":"res://resources/district/assets/"+identity+".tres","scene":definition.scene_path})
		node.free()
	for identity in ["overcast_day","contaminated_dusk","foggy_morning","emergency_night"]:
		var path: String="res://resources/district/environments/"+identity+".tres"
		if not FileAccess.file_exists(path): ResourceSaver.save(WorldEnvironmentPreset.make(identity,false),path)
	if not FileAccess.file_exists("res://resources/district/art_direction.tres"): ResourceSaver.save(WorldArtDirection.new(),"res://resources/district/art_direction.tres")
	if not FileAccess.file_exists("res://resources/district/generation.tres"): ResourceSaver.save(DistrictGenerationConfig.new(),"res://resources/district/generation.tres")
	for index in 3:
		var path:="res://resources/district/quality_"+str(index)+".tres"
		if not FileAccess.file_exists(path): ResourceSaver.save(WorldQualitySettings.make(index),path)
	var file:=FileAccess.open("res://resources/district/asset_catalog.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(catalog,"\t"))
	print("DISTRICT ASSETS: eight reference models, art rules, four atmospheres, three quality levels")
	quit()
