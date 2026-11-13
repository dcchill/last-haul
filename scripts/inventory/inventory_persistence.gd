class_name InventoryPersistence
extends RefCounted

const VERSION := 1
const MAX_DEPTH := 24

static func whole(value: Variant, minimum: int = 0, maximum: int = 2147483647) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= minimum and value <= maximum

static func json_value(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_DEPTH:
		return false
	if value == null or value is bool or value is String or value is int:
		return true
	if value is float:
		return is_finite(value)
	if value is Array:
		for child in value:
			if not json_value(child, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key in value:
			if not key is String or not json_value(value[key], depth + 1):
				return false
		return true
	return false

static func decode(data: Variant, definitions: Dictionary, seen: Dictionary = {}, depth: int = 0) -> RaidInventory:
	if depth > MAX_DEPTH or not data is Dictionary:
		return null
	if not data.get("uid") is String or data.uid.is_empty() or seen.has(data.uid):
		return null
	if not whole(data.get("width"), 1, 128) or not whole(data.get("height"), 1, 128) or not data.get("slots") is Array:
		return null
	seen[data.uid] = true
	var grid := RaidInventory.new(definitions, int(data.width), int(data.height))
	var config_path: Variant = data.get("config", "")
	if not config_path is String:
		return null
	if not config_path.is_empty():
		# Saves may only name container definitions from the project's content folder.
		if not config_path.begins_with("res://resources/containers/") or not config_path.ends_with(".tres") or ".." in config_path:
			return null
		var config: Resource = load(config_path)
		if not config is ContainerDef:
			return null
		grid.configure(config)
	grid.width = int(data.width)
	grid.height = int(data.height)
	grid.uid = data.uid
	grid.display_name = str(data.get("name", "Storage"))
	grid.equipment_slot = str(data.get("equipment_slot", ""))
	if not grid.equipment_slot.is_empty():
		grid.capacity = 1
	for key in ["accessible", "searched", "loot_generated"]:
		if not data.get(key, true) is bool:
			return null
	grid.accessible = bool(data.get("accessible", true))
	grid.searched = bool(data.get("searched", true))
	grid.loot_generated = bool(data.get("loot_generated", false))
	if not data.get("search_elapsed", 0.0) is float and not data.get("search_elapsed", 0) is int:
		return null
	grid.search_elapsed = float(data.get("search_elapsed", 0.0))
	if not is_finite(grid.search_elapsed) or grid.search_elapsed < 0 or not whole(data.get("discovered", 0), 0, data.slots.size()):
		return null
	grid.discovered = int(data.get("discovered", 0))
	for encoded in data.slots:
		var entry := decode_item(encoded, definitions, seen, depth)
		if entry.is_empty() or not grid.can_place(entry.id, int(entry.x), int(entry.y), entry.rotated):
			return null
		# Validate restrictions even for inaccessible saved containers.
		var was_accessible := grid.accessible
		grid.accessible = true
		var accepted := grid.accepts(entry)
		grid.accessible = was_accessible
		if not accepted:
			return null
		grid.slots.append(entry)
		grid._adopt(entry)
	if grid.config != null and grid.config.weight_limit > 0 and grid.total_weight() > grid.config.weight_limit + 0.00001:
		return null
	return grid

static func decode_item(encoded: Variant, definitions: Dictionary, seen: Dictionary, depth: int = 0) -> Dictionary:
	if not encoded is Dictionary or not definitions.has(encoded.get("id", "")):
		return {}
	var definition: ItemDef = definitions[encoded.id]
	if not whole(encoded.get("quantity"), 1, definition.stack_limit) or not whole(encoded.get("x")) or not whole(encoded.get("y")) or not encoded.get("rotated") is bool:
		return {}
	var entry: Dictionary = encoded.duplicate(true)
	var item_uid: Variant = entry.get("uid", ProfileStore._new_id())
	if not item_uid is String or item_uid.is_empty() or seen.has(item_uid):
		return {}
	seen[item_uid] = true
	entry.uid = item_uid
	for key in ["condition", "durability"]:
		var value: Variant = entry.get(key, 1.0 if key == "condition" else definition.max_durability)
		if not (value is float or value is int) or not is_finite(float(value)) or value < 0:
			return {}
		entry[key] = float(value)
	if entry.condition > 1.0 or entry.durability > definition.max_durability:
		return {}
	if not entry.get("attachments", []) is Array or not entry.get("metadata", {}) is Dictionary:
		return {}
	entry.attachments = entry.get("attachments", [])
	entry.metadata = entry.get("metadata", {})
	if not json_value(entry.attachments) or not json_value(entry.metadata):
		return {}
	if entry.has("storage"):
		if definition.container == null or entry.quantity != 1:
			return {}
		var storage := decode(entry.storage, definitions, seen, depth + 1)
		if storage == null:
			return {}
		entry.storage = storage
	elif definition.container != null:
		entry.storage = ItemInstance.create(definition, definitions).storage
	return entry

static func decode_entries(entries: Array, definitions: Dictionary, dimensions: Vector2i, seen: Dictionary = {}) -> RaidInventory:
	return decode({"uid": ProfileStore._new_id(), "width": dimensions.x, "height": dimensions.y, "slots": entries}, definitions, seen)

static func encode_roots(roots: Dictionary) -> Dictionary:
	var state := {"version": VERSION, "roots": {}}
	for name: String in roots:
		state.roots[name] = roots[name].serialize()
	return state

static func decode_roots(data: Variant, definitions: Dictionary) -> Dictionary:
	if not data is Dictionary or data.get("version") != VERSION or not data.get("roots") is Dictionary:
		return {}
	var roots: Dictionary = {}
	var seen: Dictionary = {}
	for name in data.roots:
		var grid := decode(data.roots[name], definitions, seen)
		if grid == null:
			return {}
		roots[name] = grid
	return roots

static func save_file(path: String, roots: Dictionary, definitions: Dictionary) -> bool:
	var state := encode_roots(roots)
	var text := JSON.stringify(state, "  ", true)
	if decode_roots(JSON.parse_string(text), definitions).size() != roots.size():
		return false
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or decode_roots(JSON.parse_string(FileAccess.get_file_as_string(path + ".tmp")), definitions).size() != roots.size():
		return false
	if FileAccess.file_exists(path) and DirAccess.copy_absolute(path, path + ".bak") != OK:
		return false
	return DirAccess.rename_absolute(path + ".tmp", path) == OK

static func load_file(path: String, definitions: Dictionary) -> Dictionary:
	if FileAccess.file_exists(path):
		var roots := decode_roots(JSON.parse_string(FileAccess.get_file_as_string(path)), definitions)
		if not roots.is_empty():
			return roots
	if FileAccess.file_exists(path + ".bak"):
		return decode_roots(JSON.parse_string(FileAccess.get_file_as_string(path + ".bak")), definitions)
	return {}

