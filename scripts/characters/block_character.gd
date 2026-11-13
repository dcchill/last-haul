extends Node3D

# Both rigs share paint rather than allocating a material per rivet.
static var paints: Dictionary = {}

func part(parent: Node3D, size: Vector3, at: Vector3, color: String, glow := false) -> MeshInstance3D:
	var key := color + ("_lit" if glow else "")
	if not paints.has(key):
		var paint := StandardMaterial3D.new()
		paint.albedo_color = Color(color)
		paint.roughness = 0.88
		if glow:
			paint.emission_enabled = true
			paint.emission = Color(color)
			paint.emission_energy_multiplier = 0.7
		paints[key] = paint
	var visual := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	visual.mesh = box
	visual.material_override = paints[key]
	visual.position = at
	parent.add_child(visual)
	return visual

func pivot(parent: Node3D, title: String, at: Vector3) -> Node3D:
	var joint := Node3D.new()
	joint.name = title
	joint.position = at
	parent.add_child(joint)
	return joint

func shadow_only(node: Node3D, enabled: bool) -> void:
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for child in node.get_children():
		if child is Node3D: shadow_only(child, enabled)
