class_name ProfileStore
extends RefCounted

signal problem(message: String)
const VERSION := 4
var path: String
var catalog: Catalog
var profile: Dictionary = {}
var load_error := ""
var writable := true

func _init(data: Catalog, save_path: String = "user://profile.json") -> void:
	catalog = data
	path = save_path
	profile = _empty_profile()

func _empty_profile() -> Dictionary:
	return {"version": VERSION, "player_id": "player-" + _new_id(), "stash": [], "last_result": {}, "committed_raids": [], "starter_seeded": false}

static func _new_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

func _header_valid(value: Variant) -> bool:
	if not value is Dictionary or not value.get("player_id") is String or value.player_id.is_empty():
		return false
	if not value.get("stash") is Array or not value.get("last_result") is Dictionary or not value.get("committed_raids") is Array:
		return false
	for raid in value.committed_raids:
		if not raid is String:
			return false
	var result: Dictionary = value.last_result
	return result.is_empty() or (result.get("raid_id") is String and result.get("success") is bool and result.get("reason") is String)

func valid(value: Variant) -> bool:
	if not _header_valid(value) or value.get("version") != VERSION or not value.get("starter_seeded") is bool:
		return false
	var stash := RaidInventory.new(catalog.items, 10, 18)
	var seen: Dictionary = {}
	var decoded := InventoryPersistence.decode_entries(value.stash, catalog.items, Vector2i(10, 18))
	if decoded == null:
		return false
	for entry in value.stash:
		if not entry is Dictionary or not catalog.items.has(entry.get("id", "")):
			return false
		if not ArmoryInstance.whole(entry.get("quantity")) or entry.quantity < 1 or entry.quantity > catalog.items[entry.id].stack_limit:
			return false
		if not ArmoryInstance.whole(entry.get("x")) or not ArmoryInstance.whole(entry.get("y")) or not entry.get("rotated") is bool:
			return false
		if not stash.can_place(entry.id, int(entry.x), int(entry.y), entry.rotated) or not ArmoryInstance.valid(entry.id, entry.get("state"), catalog):
			return false
		for instance_id in ArmoryInstance.ids(entry.state):
			if seen.has(instance_id):
				return false
			seen[instance_id] = true
		stash.slots.append(entry.duplicate(true))
	for entry in decoded.slots:
		if entry.has("storage") and not _valid_armory_grid(entry.storage, seen):
			return false
	return true

func _valid_armory_grid(grid: RaidInventory, seen: Dictionary) -> bool:
	for entry in grid.slots:
		if not ArmoryInstance.valid(entry.id, entry.get("state"), catalog):
			return false
		for identity in ArmoryInstance.ids(entry.state):
			if seen.has(identity):
				return false
			seen[identity] = true
		if entry.has("storage") and not _valid_armory_grid(entry.storage, seen):
			return false
	return true

func _valid_legacy(value: Variant) -> bool:
	if not _header_valid(value) or (value.get("version") != 1 and value.get("version") != 2 and value.get("version") != 3):
		return false
	var legacy_items := catalog.items.duplicate()
	# Validate historical footprints without registering removed items for play.
	for tier in ArmoryContent.REMOVED_ARMOR_TIERS:
		for slot in ["helmet", "chestplate", "leggings", "boots"]:
			var item := ItemDef.new()
			item.id = tier + "_" + slot
			item.stack_limit = 1
			item.width = 2
			item.height = 3 if slot == "chestplate" else 2
			legacy_items[item.id] = item
	var stash := RaidInventory.new(legacy_items, 10, 18)
	for entry in value.stash:
		if not entry is Dictionary or not legacy_items.has(entry.get("id", "")) or not ArmoryInstance.whole(entry.get("quantity")) or entry.quantity < 1:
			return false
		if entry.quantity > legacy_items[entry.id].stack_limit:
			return false
		if value.version >= 2:
			if not ArmoryInstance.whole(entry.get("x")) or not ArmoryInstance.whole(entry.get("y")) or not entry.get("rotated") is bool:
				return false
			if not stash.can_place(entry.id, int(entry.x), int(entry.y), entry.rotated):
				return false
			stash.slots.append(entry.duplicate(true))
	return true

func _read(file_path: String) -> Variant:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return null
	var json := JSON.new()
	return json.data if json.parse(file.get_as_text()) == OK else null

func load_profile(_starter_loadout: String = "standard") -> bool:
	writable = true
	load_error = ""
	var value: Variant = _read(path)
	if valid(value):
		profile = value
		return true
	if _valid_legacy(value):
		return _migrate(value)
	var backup: Variant = _read(path + ".bak")
	if valid(backup) or _valid_legacy(backup):
		if FileAccess.file_exists(path) and DirAccess.copy_absolute(path, path + ".corrupt-" + _new_id()) != OK:
			return _fail("Could not preserve the corrupt save; saving is disabled.")
		if _valid_legacy(backup):
			return _migrate(backup)
		profile = backup
		load_error = "Recovered stash from backup; original saved as .corrupt."
		problem.emit(load_error)
		return true
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"):
		var inventory := RaidInventory.new(catalog.items, 10, 18)
		inventory.add("m_four", 1)
		inventory.add("patrol", 1)
		inventory.add("five_five_six", 60)
		for rounds in [30, 30]:
			var state := ArmoryInstance.fresh("stanag_magazine", catalog.items)
			state.rounds = rounds
			inventory.add("stanag_magazine", 1, state)
		profile = _empty_profile()
		profile.stash = inventory.snapshot()
		profile.starter_seeded = true
		if _write(profile):
			return true
		return _fail("Could not save starter stash; deployment is disabled.")
	return _fail("Stash is unreadable or unsupported. Original files preserved; deployment is disabled.")

func _migrate(value: Dictionary) -> bool:
	if FileAccess.file_exists(path):
		var backup_path := path + ".v%d-%s.bak" % [int(value.version), _new_id()]
		if DirAccess.copy_absolute(path, backup_path) != OK:
			return _fail("Could not back up the original profile for migration.")
	var inventory := RaidInventory.new(catalog.items, 10, 18)
	for old in value.stash:
		var encoded := _migrate_entry(old)
		if encoded.is_empty():
			return _fail("Invalid nested legacy item; original preserved.")
		var entry := InventoryPersistence.decode_item(encoded, catalog.items, {})
		if entry.is_empty():
			return _fail("Invalid legacy item metadata; original preserved.")
		var placed := inventory.insert_instance(entry, Vector2i(encoded.x, encoded.y)) if value.version >= 2 else false
		if not placed and not inventory.add_entry(entry):
			return _fail("Migrated stash cannot fit; original save preserved.")
	var candidate := {"version": VERSION, "player_id": value.player_id, "stash": inventory.snapshot(), "last_result": value.last_result.duplicate(true), "committed_raids": value.committed_raids.duplicate(), "starter_seeded": true}
	if not _write(candidate):
		return _fail("Profile migration could not be saved; original retained.")
	load_error = "Stash upgraded to the current equipment catalog; original backed up."
	return true

func _migrate_entry(old: Dictionary, depth: int = 0) -> Dictionary:
	if depth > InventoryPersistence.MAX_DEPTH:
		return {}
	var id: String = ArmoryContent.MIGRATIONS.get(old.get("id", ""), old.get("id", ""))
	var replacement := ArmoryContent.removed_armor_replacement(id)
	if not replacement.is_empty():
		id = replacement
	if not catalog.items.has(id):
		return {}
	var encoded := old.duplicate(true)
	encoded.id = id
	encoded.state = old.get("state", ArmoryInstance.fresh(id, catalog.items)).duplicate(true)
	if not replacement.is_empty():
		var identity: String = encoded.state.get("instance_id", _new_id())
		encoded.state = ArmoryInstance.fresh(id, catalog.items)
		encoded.state.instance_id = identity
		var armor: ArmorDef = catalog.definitions[id]
		encoded.state.wear = mini(armor.max_durability, int(old.get("state", {}).get("wear", 0)))
	encoded.x = int(old.get("x", 0))
	encoded.y = int(old.get("y", 0))
	encoded.rotated = bool(old.get("rotated", false))
	if encoded.has("storage"):
		if not encoded.storage is Dictionary or not encoded.storage.get("slots") is Array:
			return {}
		var children: Array[Dictionary] = []
		for child in encoded.storage.slots:
			if not child is Dictionary:
				return {}
			var migrated := _migrate_entry(child, depth + 1)
			if migrated.is_empty():
				return {}
			children.append(migrated)
		encoded.storage.slots = children
	return encoded

func _fail(message: String) -> bool:
	writable = false
	load_error = message
	problem.emit(message)
	return false

func _write(candidate: Dictionary) -> bool:
	if not writable or not valid(candidate):
		problem.emit("Save rejected: profile unavailable or invalid.")
		return false
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		problem.emit("Could not write stash; retry saving.")
		return false
	file.store_string(JSON.stringify(candidate, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or not valid(_read(path + ".tmp")):
		return false
	var previous: Variant = _read(path)
	if (valid(previous) or _valid_legacy(previous)) and DirAccess.copy_absolute(path, path + ".bak") != OK:
		return false
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		problem.emit("Could not replace stash; previous save retained.")
		return false
	profile = candidate.duplicate(true)
	return true

func save_profile() -> bool:
	return _write(profile.duplicate(true))

func save_stash_layout(stash: Array[Dictionary]) -> bool:
	var candidate := profile.duplicate(true)
	candidate.stash = stash.duplicate(true)
	return _write(candidate)

func debit_loadout(entries: Array[Dictionary]) -> bool:
	var inventory := RaidInventory.new(catalog.items, 10, 18)
	for entry in profile.stash:
		inventory.slots.append(entry.duplicate(true))
	for entry in entries:
		if not inventory.remove_entry(entry):
			return false
	return save_stash_layout(inventory.snapshot())

func commit_result(result: Dictionary, loot: Array[Dictionary], equipment: Array[Dictionary] = []) -> bool:
	if result.get("practice", false):
		return false
	if profile.committed_raids.has(result.raid_id):
		return true
	var candidate := profile.duplicate(true)
	if result.success:
		var stash := RaidInventory.new(catalog.items, 10, 18)
		for entry in candidate.stash:
			stash.slots.append(entry.duplicate(true))
		for entry in equipment + loot:
			var placed := false
			if entry.has("x") and entry.has("y"):
				placed = stash.add_at(entry.id, int(entry.quantity), int(entry.x), int(entry.y), bool(entry.get("rotated", false)), entry.get("state", {}))
			if not placed and not stash.add_entry(entry):
				problem.emit("Stash is full; result retained for retry.")
				return false
		candidate.stash = stash.snapshot()
	candidate.last_result = result.duplicate(true)
	candidate.committed_raids.append(result.raid_id)
	return _write(candidate)
