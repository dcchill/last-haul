extends Node3D

var catalog: Catalog
var effects_rng := RandomNumberGenerator.new()
var ricochet_sound: AudioStreamWAV

func _ready() -> void:
	effects_rng.randomize()
	ricochet_sound = ArmoryAudio.make_sound("ricochet")

func present(position: Vector3, _normal: Vector3, material_id: String, _entity_id: String) -> void:
	var marker := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	marker.mesh = mesh
	var surface := StandardMaterial3D.new()
	var data: MaterialDef = catalog.definitions.get(material_id)
	surface.albedo_color = data.impact_color if data != null else Color(0.65, 0.65, 0.6)
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = surface
	add_child(marker)
	marker.global_position = position
	marker.reset_physics_interpolation()
	get_tree().create_timer(0.25).timeout.connect(marker.queue_free)

func muzzle_flash(position: Vector3, direction: Vector3, suppressed: bool, view: Node3D = null) -> void:
	if suppressed: return
	var flash := Node3D.new()
	flash.name = "MuzzleFlash"
	add_child(flash)
	flash.global_position = position
	var reused: bool = view != null and view.muzzle_flash()
	if not reused:
		_streak(flash, Vector3.ZERO, direction.normalized() * 0.22, 0.075, 0.055)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.65, 0.3)
	light.light_energy = 2.0
	light.omni_range = 3.0
	light.shadow_enabled = false
	flash.add_child(light)
	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.055)
	tween.tween_callback(flash.queue_free)
	flash.reset_physics_interpolation()

func ricochet(position: Vector3, normal: Vector3, incoming: Vector3) -> void:
	var burst := Node3D.new()
	burst.name = "Ricochet"
	add_child(burst)
	burst.global_position = position + normal * 0.015
	var reflected := incoming.bounce(normal).normalized()
	_streak(burst, Vector3.ZERO, reflected * 0.9, 0.012, 0.12)
	for index in range(5):
		var scatter := Vector3(effects_rng.randf_range(-0.3, 0.3), effects_rng.randf_range(-0.3, 0.3), effects_rng.randf_range(-0.3, 0.3))
		var direction := (reflected + normal * 0.4 + scatter).normalized()
		_streak(burst, Vector3.ZERO, direction * effects_rng.randf_range(0.15, 0.5), 0.008, 0.12)
	var audio := AudioStreamPlayer3D.new()
	audio.stream = ricochet_sound
	audio.volume_db = -10.0
	audio.max_distance = 45.0
	burst.add_child(audio)
	audio.play()
	get_tree().create_timer(0.3).timeout.connect(burst.queue_free)
	burst.reset_physics_interpolation()

func _streak(parent: Node3D, start: Vector3, end: Vector3, width: float, seconds: float) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, width, start.distance_to(end))
	mesh.mesh = box
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1, 0.75, 0.35, 1)
	material.emission_enabled = true
	material.emission = Color(1, 0.55, 0.15)
	material.emission_energy_multiplier = 3.0
	mesh.material_override = material
	parent.add_child(mesh)
	mesh.position = (start + end) * 0.5
	var direction := (end - start).normalized()
	mesh.basis = Basis.looking_at(direction, Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.999 else Vector3.UP)
	var tween := create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, seconds)
	tween.tween_callback(mesh.queue_free)
