extends Node3D

var catalog: Catalog

func present(position: Vector3, _normal: Vector3, material_id: String, _entity_id: String) -> void:
	var marker := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	marker.mesh = mesh
	var surface := StandardMaterial3D.new()
	var data: MaterialDef = catalog.definitions[material_id]
	surface.albedo_color = data.impact_color
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = surface
	add_child(marker)
	marker.global_position = position
	get_tree().create_timer(0.25).timeout.connect(marker.queue_free)
