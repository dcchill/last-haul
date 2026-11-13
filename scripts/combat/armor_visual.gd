class_name ArmorVisual
extends RefCounted

static func create(armor: ArmorDef) -> Node3D:
	var root := Node3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = armor.color
	material.roughness = 0.8
	var parts: Array = []
	match armor.slot:
		"helmet":
			parts = [[Vector3(0, 1.82, 0), Vector3(0.5, 0.08, 0.5)], [Vector3(-0.22, 1.62, 0), Vector3(0.06, 0.38, 0.5)], [Vector3(0.22, 1.62, 0), Vector3(0.06, 0.38, 0.5)], [Vector3(0, 1.62, 0.22), Vector3(0.5, 0.38, 0.06)]]
		"chestplate":
			parts = [[Vector3(0, 1.12, 0), Vector3(0.56, 0.65, 0.32)], [Vector3(-0.37, 1.3, 0), Vector3(0.18, 0.28, 0.34)], [Vector3(0.37, 1.3, 0), Vector3(0.18, 0.28, 0.34)]]
		"leggings":
			parts = [[Vector3(0, 0.77, 0), Vector3(0.56, 0.15, 0.33)], [Vector3(-0.15, 0.48, 0), Vector3(0.26, 0.52, 0.32)], [Vector3(0.15, 0.48, 0), Vector3(0.26, 0.52, 0.32)]]
		"boots":
			parts = [[Vector3(-0.15, 0.14, -0.035), Vector3(0.28, 0.28, 0.39)], [Vector3(0.15, 0.14, -0.035), Vector3(0.28, 0.28, 0.39)]]
	for part in parts:
		var visual := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = part[1]
		visual.mesh = mesh
		visual.position = part[0]
		visual.material_override = material
		root.add_child(visual)
	return root
