extends SceneTree

var registry := preload("res://scripts/data/environmental_props.gd").new()
var failed := false

func _initialize() -> void:
	call_deferred("build")

func own(root_node: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = root_node

func solid(root_node: Node3D, at: Vector3, size: Vector3, material: String) -> void:
	var body := DecorativeProp.new()
	body.material = load("res://resources/materials/concrete.tres")
	body.position = at
	own(root_node, root_node, body)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = load("res://resources/district/materials/" + material + ".tres")
	own(root_node, body, visual)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	own(root_node, body, collision)

func example(interior: bool) -> void:
	var node := Node3D.new()
	node.name = "InteriorExample" if interior else "ExteriorExample"
	root.add_child(node)
	solid(node, Vector3(0, -.15, 0), Vector3(24, .3, 24), "concrete")
	if interior:
		solid(node, Vector3(-12, 1.5, 0), Vector3(.3, 3, 24), "medical")
		solid(node, Vector3(0, 1.5, 12), Vector3(24, 3, .3), "medical")
		# The front and east side stay open for inspection and a continuous aisle.
		solid(node, Vector3(0, .08, 0), Vector3(2, .02, 22), "paint")
	var layout: Array
	if interior:
		layout = [["041", 1, -5, 0, 7], ["042", 0, -5, 0, 8.2], ["043", 1, -8, 0, 8],
			["044", 1, -9, 0, 10.5], ["058", 0, -5, 0, 3], ["096", 1, 5, 0, 7],
			["096", 2, 8, 0, 7], ["098", 1, 4, 0, 6], ["099", 0, 5, 0, 3],
			["107", 0, 7, 0, 4], ["104", 0, 10, 0, 10], ["175", 2, 5, .925, 3],
			["061", 1, -5, 0, -5], ["062", 0, -8, 0, -5], ["064", 1, -5, 0, -9],
			["179", 1, -9, 0, -9], ["190", 1, 5, 0, -7], ["199", 0, 8, .76, -7],
			["046", 0, 8, 0, -7], ["110", 0, 5, 0, -3]]
	else:
		layout = [["001", 1, -4, 0, 8], ["003", 0, 3, 0, 8], ["002", 1, -6, 0, 6],
			["002", 0, -5, 0, 6], ["004", 2, -9, 0, 4], ["008", 1, -7, 0, -3],
			["005", 0, -10, 0, -6], ["156", 1, 4, 0, 1], ["159", 2, 8, 0, -4],
			["011", 3, 3, 0, -6], ["171", 2, 4, 0, -8], ["195", 2, 8, 0, -9],
			["111", 2, -4, 0, -8], ["127", 2, -7, 0, -9], ["131", 0, -4, 0, -10],
			["142", 1, 9, 0, 8], ["143", 1, 7, 0, 9], ["148", 3, 9, 0, 4],
			["144", 1, 4, 0, 10], ["155", 3, -8, 0, 9]]
	var reserved: Array[AABB] = []
	var keepouts: Array[AABB] = [AABB(Vector3(-1, 0, -12), Vector3(2, 3, 24))]
	for index in layout.size():
		var slot: Array = layout[index]
		var id: String = slot[0]
		var definition: Dictionary = registry.entries[id]
		var context := {"attachment": definition.placement.attachment, "supported": true}
		var pose := Transform3D(Basis.IDENTITY, Vector3(slot[2], slot[3], slot[4]))
		# Small cases are supported by the authored table/cart below them.
		var local_occupied: Array[AABB] = []
		if float(slot[3]) <= .1: local_occupied = reserved
		var prop := registry.place(node, id, slot[1], pose, context, "example-%s-%d" % [node.name, index], local_occupied, keepouts)
		if prop == null:
			push_error("Example placement rejected: " + id + " " + registry.placement_error(id, slot[1], pose, context, local_occupied, keepouts))
			failed = true
			continue
		prop.owner = node
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("354348")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b3c5c1")
	environment.ambient_light_energy = .65
	world.environment = environment
	own(node, node, world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -35, 0)
	light.light_color = Color("e6decb")
	light.light_energy = 1.5
	light.shadow_enabled = true
	own(node, node, light)
	var camera := Camera3D.new()
	camera.position = Vector3(20, 20, -25)
	if not interior: camera.position = Vector3(23, 18, -25)
	own(node, node, camera)
	camera.look_at(Vector3(0, 1, 0))
	camera.current = true
	camera.set_script(load("res://scripts/world/prop_preview_camera.gd"))
	camera.preview_title = "LAST HAUL / " + ("INTERIOR" if interior else "EXTERIOR") + " PROP EXAMPLE"
	var packed := PackedScene.new()
	if packed.pack(node) != OK or ResourceSaver.save(packed, "res://scenes/review/environment_" + ("interior" if interior else "exterior") + ".tscn") != OK: failed = true
	node.free()

func build() -> void:
	if not registry.load_catalog().is_empty(): quit(1); return
	example(true)
	example(false)
	quit(1 if failed else 0)
