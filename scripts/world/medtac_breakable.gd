class_name MedTacBreakable
extends StaticBody3D

@export var entity_id := ""
@export var material: MaterialDef
@export var max_health := 12.0
@export_enum("glass", "light", "barricade") var kind := "glass"
@export var navigation_link: NodePath
@export var protected := false
var health := 120.0
var broken := false
var light_enabled := true

func _ready() -> void:
	health = max_health * 10.0
	add_to_group("medtac_breakables")
	if kind=="light":
		for mesh in find_children("*","MeshInstance3D",true,false):
			if mesh.material_override!=null: mesh.material_override=mesh.material_override.duplicate()

func set_lighting(enabled: bool) -> void:
	light_enabled=enabled and not broken
	for node in find_children("*","",true,false):
		if node is Light3D: node.visible=light_enabled
		if node is MeshInstance3D and node.material_override is StandardMaterial3D:
			if node.get_parent().name=="Diffuser": node.material_override.emission_enabled=light_enabled

func damage(amount: float) -> void:
	if broken or protected or amount <= 0: return
	health = maxf(0,health-amount)
	if health > 0: return
	broken = true
	if get_parent().has_meta("wall_length"):
		get_tree().call_group("campus_breaches","mark_dirty",get_parent())
	for node in find_children("*", "", true, false):
		if node is CollisionShape3D: node.set_deferred("disabled",true)
		if node is Light3D: node.visible=false
		if node is MeshInstance3D: node.visible=false
	if kind == "light": light_enabled=false
	var link := get_node_or_null(navigation_link) as NavigationLink3D
	if link != null: link.enabled=true
	# A single merged shard effect has a fixed lifetime and bounded geometry.
	var shards := MultiMeshInstance3D.new()
	var multi := MultiMesh.new()
	multi.transform_format=MultiMesh.TRANSFORM_3D
	var mesh := BoxMesh.new()
	mesh.size=Vector3(0.07,0.02,0.12)
	multi.mesh=mesh
	multi.instance_count=8
	var rng := RandomNumberGenerator.new()
	rng.seed=hash(entity_id)
	for i in range(8):
		multi.set_instance_transform(i,Transform3D(Basis.from_euler(Vector3(rng.randf(),rng.randf(),rng.randf())*PI),Vector3(rng.randf_range(-0.6,0.6),-0.2,rng.randf_range(-0.6,0.6))))
	shards.multimesh=multi
	var paint:=StandardMaterial3D.new()
	paint.albedo_color=Color("91b7af") if kind=="glass" else Color("807b67")
	shards.material_override=paint
	add_child(shards)
	var tween:=create_tween()
	tween.tween_property(shards,"position:y",-0.7,0.3)
	get_tree().create_timer(1.5).timeout.connect(shards.queue_free)
	var audio:=AudioStreamPlayer3D.new()
	audio.stream=ArmoryAudio.make_sound("impact")
	audio.volume_db=-18
	add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)

