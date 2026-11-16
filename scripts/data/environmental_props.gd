class_name EnvironmentalProps
extends RefCounted

const CATALOG_PATH := "res://resources/environment_props/catalog.json"
var entries: Dictionary = {}

func load_catalog() -> String:
	entries.clear()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not parsed is Array: return "Prop catalog must be an array"
	for entry in parsed:
		if not entry is Dictionary or not entry.get("id") is String: return "Invalid prop definition"
		if entry.id.length() != 3 or not entry.id.is_valid_int() or int(entry.id) < 1 or int(entry.id) > 200 or entries.has(entry.id): return "Invalid/duplicate prop ID: " + entry.id
		if not entry.get("variants") is Array or entry.variants.is_empty() or entry.variants.size() > 4: return "Invalid variants: " + entry.id
		for index in entry.variants.size():
			var variant: Dictionary = entry.variants[index]
			if variant.get("index", -1) != index or not variant.get("scene") is String: return "Invalid variant scene: " + entry.id
		entries[entry.id] = entry
	return ""

func find_props(text := "", category := "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in entries.values():
		if not category.is_empty() and entry.category != category: continue
		if not text.is_empty() and not text.to_lower() in (entry.id + " " + entry.name).to_lower(): continue
		result.append(entry)
	return result

func select_variant(id: String, world_seed: int, placement_key: String) -> int:
	if not entries.has(id): return -1
	# SHA-256 keeps selection stable across engine versions and call order.
	var digest := ("%d:%s:%s" % [world_seed, id, placement_key]).sha256_text()
	return digest.substr(0, 8).hex_to_int() % entries[id].variants.size()

func instantiate_prop(id: String, variant := -1, world_seed := 0, placement_key := "") -> Node3D:
	if not entries.has(id): return null
	var entry: Dictionary = entries[id]
	if variant == -1: variant = select_variant(id, world_seed, placement_key)
	if variant < 0 or variant >= entry.variants.size(): return null
	# Searchable instances require a stable, unique placement identity for raid saves.
	if not entry.storage.is_empty() and placement_key.is_empty(): return null
	if not ResourceLoader.exists(entry.variants[variant].scene): return null
	var scene: PackedScene = load(entry.variants[variant].scene)
	if scene == null: return null
	var prop := scene.instantiate() as Node3D
	if prop is SearchableFurniture: prop.entity_id = "environment:" + placement_key
	return prop

func bounds(id: String, variant: int) -> AABB:
	var raw: Dictionary = entries[id].variants[variant].bounds
	return AABB(Vector3(raw.position[0], raw.position[1], raw.position[2]), Vector3(raw.size[0], raw.size[1], raw.size[2]))

func placement_error(id: String, variant: int, pose: Transform3D, context: Dictionary, occupied: Array[AABB] = [], keepouts: Array[AABB] = []) -> String:
	if not entries.has(id) or variant < 0 or variant >= entries[id].variants.size(): return "Unknown prop/variant"
	if not pose.origin.is_finite() or not pose.basis.is_finite() or not pose.basis.get_scale().is_equal_approx(Vector3.ONE): return "Invalid placement transform"
	var rule: Dictionary = entries[id].placement
	for pair in [["environment", "environments"], ["room", "rooms"], ["building", "buildings"], ["faction", "factions"], ["condition", "conditions"]]:
		if context.has(pair[0]) and not context[pair[0]] in rule[pair[1]]: return "Incompatible " + pair[0]
	if context.get("attachment", "floor") != rule.attachment: return "Incorrect attachment surface"
	if not context.get("supported", false): return "No supporting surface"
	var euler := pose.basis.get_euler()
	if absf(euler.x) > .001 or absf(euler.z) > .001: return "Unsupported tilt"
	var degrees := fposmod(rad_to_deg(euler.y), 360)
	var allowed := false
	for angle in rule.rotations:
		if absf(wrapf(degrees - float(angle), -180, 180)) < .01: allowed = true
	if not allowed: return "Unsupported rotation"
	var box := bounds(id, variant)
	var clearance: float = rule.service_clearance
	# -Z is the usable front: reserve access for drawers, loot and maintenance.
	box.position.z -= clearance
	box.size.z += clearance
	box = pose * box.grow(.08)
	for other in keepouts:
		if box.intersects(other): return "Blocks a doorway or navigation route"
	for other in occupied:
		if box.intersects(other): return "Overlaps another prop or its access clearance"
	return ""

func place(parent: Node3D, id: String, variant: int, pose: Transform3D, context: Dictionary, placement_key: String, occupied: Array[AABB], keepouts: Array[AABB]) -> Node3D:
	if not placement_error(id, variant, pose, context, occupied, keepouts).is_empty(): return null
	for child in parent.find_children("*", "", true, false):
		if child is SearchableFurniture and child.entity_id == "environment:" + placement_key: return null
	var prop := instantiate_prop(id, variant, 0, placement_key)
	if prop == null: return null
	parent.add_child(prop)
	prop.transform = pose
	var box := bounds(id, variant)
	box.position.z -= entries[id].placement.service_clearance
	box.size.z += entries[id].placement.service_clearance
	occupied.append(pose * box.grow(.08))
	return prop

func make_multimesh(id: String, variant: int, transforms: Array[Transform3D]) -> DistrictFoliage:
	if not entries.has(id) or variant < 0 or variant >= entries[id].variants.size(): return null
	if entries[id].variants[variant].collision_required or not entries[id].storage.is_empty(): return null
	var prop := instantiate_prop(id, variant)
	if prop == null: return null
	var meshes := prop.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() != 1:
		prop.free()
		return null
	var batch := DistrictFoliage.new()
	batch.multimesh = MultiMesh.new()
	batch.multimesh.mesh = meshes[0].mesh
	batch.visibility_range_end = 90
	for pose in transforms: batch.instance_transforms.append(pose * meshes[0].transform)
	prop.free()
	return batch
