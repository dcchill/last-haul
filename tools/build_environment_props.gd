extends SceneTree

const OUTPUT := "res://resources/environment_props/"
const SCENES := "res://scenes/props/environment/"
var failed := false
var palette: Dictionary = {}
var gameplay_materials: Dictionary = {}

class RecipeMesh extends WorldMeshKit:
	var part_transform := Transform3D.IDENTITY
	func tri(a: Vector3, b: Vector3, c: Vector3, normal: Vector3, key: String) -> void:
		super.tri(part_transform * a, part_transform * b, part_transform * c, part_transform.basis * normal, key)

func _initialize() -> void:
	call_deferred("build")

func vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

func save(resource: Resource, path: String) -> void:
	if ResourceSaver.save(resource, path) != OK:
		push_error("Cannot save " + path)
		failed = true

func add(parent: Node, child: Node, owner: Node) -> void:
	parent.add_child(child)
	child.owner = owner

func part_transform(part: Dictionary) -> Transform3D:
	var assembly := Basis.from_euler(vector(part.get("assembly_rotation", [0, 0, 0])))
	return Transform3D(assembly * Basis.from_euler(vector(part.rotation)), assembly * vector(part.at))

func draw(kit: RecipeMesh, part: Dictionary) -> void:
	kit.part_transform = part_transform(part)
	match part.shape:
		"box": kit.box(Vector3.ZERO, vector(part.size), part.material)
		"profile":
			var points := PackedVector2Array()
			for point in part.points: points.append(Vector2(point[0], point[1]))
			kit.profile(points, part.depth, Vector3.ZERO, part.material, int(part.axis))
		"cylinder":
			var points := PackedVector2Array()
			for index in int(part.sides):
				var angle := TAU * index / int(part.sides)
				points.append(Vector2(cos(angle), sin(angle)) * part.radius)
			var axis: int = part.axis
			if axis == 1:
				kit.part_transform *= Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3.ZERO)
			kit.profile(points, part.length, Vector3.ZERO, part.material, 0 if axis == 0 else 2)

func collision(part: Dictionary) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	shape.transform = part_transform(part)
	match part.shape:
		"box":
			var form := BoxShape3D.new()
			form.size = vector(part.size)
			shape.shape = form
		"cylinder":
			var form := CylinderShape3D.new()
			form.radius = part.radius
			form.height = part.length
			shape.shape = form
			if int(part.axis) == 0: shape.basis *= Basis(Vector3.FORWARD, PI / 2)
			if int(part.axis) == 2: shape.basis *= Basis(Vector3.RIGHT, PI / 2)
		"profile":
			var form := ConvexPolygonShape3D.new()
			var points := PackedVector3Array()
			for point in part.points:
				for side in [-1, 1]:
					var p := Vector3(point[0], point[1], side * part.depth / 2)
					points.append(Vector3(p.z, p.y, -p.x) if int(part.axis) == 0 else p)
			form.points = points
			shape.shape = form
	return shape

func prepare_materials() -> void:
	var art := WorldArtDirection.new()
	var colors: Dictionary = art.palette.duplicate()
	colors.merge({"cloth": Color("858477"), "cloth_dark": Color("4d574c"), "foliage": Color("556247"),
		"wood_light": Color("a39775"), "plastic": Color("596d73"), "cardboard": Color("958565"),
		"water": Color("557172"), "oil": Color("343e40"), "mud_water": Color("66634b")})
	for key: String in colors:
		var existing := "res://resources/district/materials/" + key + ".tres"
		var material: StandardMaterial3D
		if ResourceLoader.exists(existing): material = load(existing)
		else:
			material = StandardMaterial3D.new()
			material.resource_name = key
			material.albedo_color = colors[key]
			material.roughness = .95
			if key in ["water", "oil", "mud_water"]:
				material.roughness = .14
				material.metallic = .25
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				material.albedo_color.a = .72
			save(material, OUTPUT + "materials/" + key + ".tres")
		palette[key] = material
	var steel: MaterialDef = load("res://resources/materials/steel.tres")
	var concrete: MaterialDef = load("res://resources/materials/concrete.tres")
	for key: String in colors:
		if key in ["steel", "paint", "rust", "medical"]: gameplay_materials[key] = steel
		elif key == "concrete": gameplay_materials[key] = concrete
		else:
			var material := MaterialDef.new()
			material.id = "prop_" + key
			material.impact_color = colors[key]
			material.resistance = 350 if key in ["wood", "wood_light"] else 100
			material.thickness_meters = .06
			save(material, OUTPUT + "materials/impact_" + key + ".tres")
			gameplay_materials[key] = material

func configure_storage(entry: Dictionary, prop: SearchableFurniture) -> void:
	var storage: Dictionary = entry.storage
	var config := ContainerDef.new()
	config.id = "prop_" + entry.id
	config.display_name = entry.name
	config.dimensions = Vector2i(storage.dimensions[0], storage.dimensions[1])
	config.searchable = true
	config.progressive_discovery = true
	config.search_seconds = storage.search_seconds
	config.allowed_categories = PackedStringArray(storage.allowed_categories)
	var config_path: String = "res://resources/containers/environment/" + entry.id + ".tres"
	save(config, config_path)
	prop.container_config = ResourceLoader.load(config_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	prop.display_name = entry.name
	prop.kind = "container"
	prop.entity_id = "prop-" + entry.id
	prop.key_item = storage.key_item
	prop.loot_profile = storage.profile
	var profiles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/medtac/loot_profiles.json"))
	profiles.food = [["food", 1, 3]]
	var table := LootTable.new()
	table.rolls = Vector2i(1, 3)
	for source: Array in profiles[storage.profile]:
		table.entries.append({"id": source[0], "weight": source[1], "min": 1, "max": source[2]})
	var loot_path: String = OUTPUT + "loot/" + entry.id + ".tres"
	save(table, loot_path)
	prop.loot_table = ResourceLoader.load(loot_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	prop.add_to_group("raid_entities", true)

func bake(entry: Dictionary, variant: Dictionary) -> Dictionary:
	var kits: Dictionary = {}
	var meshes: Dictionary = {}
	var components: Array[String] = []
	for part: Dictionary in variant.parts:
		if not kits.has(part.group):
			kits[part.group] = RecipeMesh.new()
			kits[part.group].materials = palette
		draw(kits[part.group], part)
		if not components.has(part.component): components.append(part.component)
	var bounds := AABB()
	var first := true
	var key := "%s_%d" % [entry.id, variant.index]
	for group: String in kits:
		var mesh: ArrayMesh = kits[group].finish()
		if mesh.get_surface_count() == 0:
			push_error("Empty mesh: " + key + " / " + group)
			failed = true
			continue
		meshes[group] = mesh
		bounds = mesh.get_aabb() if first else bounds.merge(mesh.get_aabb())
		first = false
		save(mesh, OUTPUT + "meshes/" + key + "_" + group + ".res")
	var lift := Vector3(0, -bounds.position.y, 0)
	var root_node: Node3D = SearchableFurniture.new() if not entry.storage.is_empty() else Node3D.new()
	root_node.name = "Prop" + entry.id
	if root_node is SearchableFurniture:
		configure_storage(entry, root_node)
		root_node.locked = variant.locked
		root_node.starts_empty = variant.empty
		root_node.opening = variant.opening
		root_node.opening_direction = -1
		root_node.material = gameplay_materials.steel
	root_node.set_meta("catalog_id", entry.id)
	root_node.set_meta("variant_index", variant.index)
	root_node.set_meta("variant_name", variant.name)
	root_node.set_meta("category", entry.category)
	root_node.set_meta("classifications", entry.classifications)
	root_node.set_meta("placement", entry.placement)
	root_node.set_meta("components", components)
	var pivot := vector(variant.pivot)
	if not variant.parts.is_empty():
		pivot = Basis.from_euler(vector(variant.parts[0].get("assembly_rotation", [0, 0, 0]))) * pivot
	var groups: Dictionary = {"body": root_node}
	for group: String in meshes:
		var parent: Node3D = root_node
		if group == "panel":
			parent = Node3D.new()
			parent.name = "MovingPanel"
			parent.position = pivot + lift
			add(root_node, parent, root_node)
			groups[group] = parent
			if root_node is SearchableFurniture: root_node.panel_rest = parent.transform
		var visual := MeshInstance3D.new()
		visual.name = "LootContents" if group == "contents" else "Mesh"
		visual.mesh = ResourceLoader.load(OUTPUT + "meshes/" + key + "_" + group + ".res", "", ResourceLoader.CACHE_MODE_REPLACE)
		visual.position = -pivot if group == "panel" else lift
		visual.visibility_range_end = 65 if bounds.size.length() < 1 else 160
		visual.visibility_range_end_margin = 10
		if group == "contents": visual.visible = not variant.empty
		add(parent, visual, root_node)
	var bodies: Dictionary = {}
	for part: Dictionary in variant.parts:
		if not part.collision: continue
		var body_key: String = part.group + "_" + part.material
		if not bodies.has(body_key):
			var body := DecorativeProp.new()
			body.name = "Collision_" + body_key
			body.material = gameplay_materials[part.material]
			body.collision_layer = 1
			body.collision_mask = 0
			add(groups.get(part.group, root_node), body, root_node)
			bodies[body_key] = body
		var form := collision(part)
		form.position += -pivot if part.group == "panel" else lift
		add(bodies[body_key], form, root_node)
	if variant.initial_open and groups.has("panel"):
		var moving: Node3D = groups.panel
		if variant.opening == "drawer": moving.position.z -= .4
		elif variant.opening == "lid": moving.rotation.x = 1.35
		else: moving.rotation.y = 1.4
		if root_node is SearchableFurniture: root_node.opened = true
	# Record the actual authored pose, including extended drawers and opened lids.
	var actual := scene_bounds(root_node)
	root_node.set_meta("bounds", actual)
	if root_node is SearchableFurniture:
		root_node.interaction_offset = Vector3(actual.get_center().x, minf(1.15, actual.get_center().y), actual.position.z + .05)
	var scene_path := SCENES + key + ".tscn"
	var packed := PackedScene.new()
	if packed.pack(root_node) != OK: failed = true
	save(packed, scene_path)
	var result := {"index": variant.index, "name": variant.name, "scene": scene_path,
		"bounds": {"position": [actual.position.x, actual.position.y, actual.position.z], "size": [actual.size.x, actual.size.y, actual.size.z]},
		"collision_required": not bodies.is_empty(), "locked": variant.locked, "empty": variant.empty}
	root_node.free()
	return result

func scene_bounds(node: Node3D, transform := Transform3D.IDENTITY) -> AABB:
	var result := AABB()
	var first := true
	for child in node.get_children():
		if not child is Node3D: continue
		var next: Transform3D = transform * child.transform
		var rect := AABB()
		if child is MeshInstance3D and child.mesh != null: rect = next * child.mesh.get_aabb()
		else: rect = scene_bounds(child, next)
		if rect.size.is_zero_approx(): continue
		result = rect if first else result.merge(rect)
		first = false
	return result

func build() -> void:
	for folder in [OUTPUT + "meshes", OUTPUT + "materials", OUTPUT + "loot", SCENES, "res://resources/containers/environment"]:
		DirAccess.make_dir_recursive_absolute(folder)
	prepare_materials()
	var recipes: Array = JSON.parse_string(FileAccess.get_file_as_string(OUTPUT + "recipes.json"))
	var catalog: Array = []
	var category_filter := 0
	var args := OS.get_cmdline_user_args()
	if "--category" in args: category_filter = int(args[args.find("--category") + 1])
	if category_filter != 0 and FileAccess.file_exists(OUTPUT + "catalog.json"):
		catalog = JSON.parse_string(FileAccess.get_file_as_string(OUTPUT + "catalog.json"))
		catalog = catalog.filter(func(entry): return int(entry.category_index) != category_filter)
	var count := 0
	for source: Dictionary in recipes:
		if category_filter != 0 and int(source.category_index) != category_filter: continue
		var entry: Dictionary = source.duplicate(true)
		entry.variants = []
		for variant: Dictionary in source.variants:
			entry.variants.append(bake(source, variant))
			count += 1
		entry.erase("number")
		catalog.append(entry)
		print("BAKED %s %s (%d variants)" % [source.id, source.name, entry.variants.size()])
	catalog.sort_custom(func(a, b): return a.id < b.id)
	var file := FileAccess.open(OUTPUT + "catalog.json", FileAccess.WRITE)
	if file == null: failed = true
	else: file.store_string(JSON.stringify(catalog, "\t") + "\n")
	print("ENVIRONMENT BAKE: %d variants; %d registered IDs" % [count, catalog.size()])
	quit(1 if failed else 0)
