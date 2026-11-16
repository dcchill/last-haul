class_name ProfileStore
extends RefCounted

signal problem(message: String)
const VERSION := 7
const VESTS := {"patrol": ["carrier_single", "plate_steel"], "vest": ["carrier_single", "plate_ceramic"], "sentinel": ["carrier_dual", "plate_steel"], "bastion": ["carrier_dual", "plate_ceramic"], "juggernaut": ["carrier_triple", "plate_composite"]}
const STASH_DEF: ContainerDef = preload("res://resources/containers/stash.tres")
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
	return {"version": VERSION, "player_id": "player-" + _new_id(), "stash": [], "last_result": {}, "committed_raids": [], "starter_seeded": false, "stash_width": STASH_DEF.dimensions.x, "stash_height": STASH_DEF.dimensions.y, "staged": {}, "pending_result": {}}

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
	if not InventoryPersistence.whole(value.get("stash_width"), 1, 128) or not InventoryPersistence.whole(value.get("stash_height"), 1, 128):
		return false
	if not value.get("staged") is Dictionary or not value.get("pending_result") is Dictionary:
		return false
	var seen: Dictionary = {}
	var stash := InventoryPersistence.decode_entries(value.stash, catalog.items, Vector2i(int(value.stash_width), int(value.stash_height)), seen)
	if stash == null or not _valid_armory_grid(stash, {}):
		return false
	for name in value.staged:
		if name not in ["pack", "pockets"] + EquipmentComponent.DEFAULT_SLOTS: return false
		var grid := InventoryPersistence.decode(value.staged[name], catalog.items, seen)
		if grid == null or grid.equipment_slot != (name if name in EquipmentComponent.DEFAULT_SLOTS else "") or not _valid_armory_grid(grid, {}):
			return false
	var pending: Dictionary = value.pending_result
	if not pending.is_empty():
		if not pending.get("result") is Dictionary or not pending.result.get("raid_id") is String or not pending.result.get("success") is bool or not pending.get("items") is Array:
			return false
		for encoded in pending.items:
			var entry := InventoryPersistence.decode_item(encoded, catalog.items, seen)
			if entry.is_empty() or not ArmoryInstance.valid(entry.id, entry.state, catalog):
				return false
	return true

func _valid_v4(value: Variant) -> bool:
	if not _header_valid(value) or value.get("version") != 4 or not value.get("starter_seeded") is bool:
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
	var historical := ProfileStore.new(_historical_catalog(), path)
	if value is Dictionary and (value.get("version") == 5 or value.get("version") == 6):
		var candidate: Dictionary = value.duplicate(true)
		candidate.version = VERSION
		return historical.valid(candidate)
	if historical._valid_v4(value): return true
	if not _header_valid(value) or (value.get("version") != 1 and value.get("version") != 2 and value.get("version") != 3):
		return false
	var legacy_items := historical.catalog.items.duplicate()
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
		if _write(_starter_profile()):
			return true
		return _fail("Could not save starter stash; deployment is disabled.")
	return _fail("Stash is unreadable or unsupported. Original files preserved; deployment is disabled.")

func _starter_profile() -> Dictionary:
	var inventory := RaidInventory.new(catalog.items, STASH_DEF.dimensions.x, STASH_DEF.dimensions.y)
	inventory.add("m_four", 1)
	inventory.insert_instance(PlateInventory.loaded("carrier_single", "plate_steel", catalog.items))
	inventory.add("five_five_six", 60)
	for rounds in [30, 30]:
		var state := ArmoryInstance.fresh("stanag_magazine", catalog.items)
		state.rounds = rounds
		inventory.add("stanag_magazine", 1, state)
	var candidate := _empty_profile()
	candidate.stash = inventory.snapshot()
	candidate.starter_seeded = true
	return candidate

func reset_character() -> bool:
	if not _write(_starter_profile()): return false
	load_error = ""
	return true

func _migrate(value: Dictionary) -> bool:
	if FileAccess.file_exists(path):
		var backup_path := path + ".v%d-%s.bak" % [int(value.version), _new_id()]
		if DirAccess.copy_absolute(path, backup_path) != OK:
			return _fail("Could not back up the original profile for migration.")
	if value.version == 5 or value.version == 6:
		# Version 5 already has the complete nested layout and pending-result journal.
		# Never send it through the older stash-only migration.
		var upgraded: Dictionary = value.duplicate(true)
		upgraded.version = VERSION
		_convert_supplies(upgraded)
		_convert_armor(upgraded)
		if not _repair_armor_layout(upgraded) or not _write(upgraded): return _fail("Could not migrate armor; original retained.")
		return true
	var inventory := RaidInventory.new(catalog.items, 10, 18)
	var converted_entries: Array[Dictionary] = []
	for old in value.stash:
		var encoded := _migrate_entry(old)
		if encoded.is_empty():
			return _fail("Invalid nested legacy item; original preserved.")
		converted_entries.append(encoded)
		_rehome_item(encoded, converted_entries)
	for encoded in converted_entries:
		var entry := InventoryPersistence.decode_item(encoded, catalog.items, {})
		if entry.is_empty():
			return _fail("Invalid legacy item metadata; original preserved.")
		var placed := inventory.insert_instance(entry, Vector2i(encoded.x, encoded.y)) if value.version >= 2 else false
		if not placed and not inventory.add_entry(entry):
			var fitted := false
			while inventory.height < 128:
				inventory.height += 1
				if inventory.add_entry(entry):
					fitted = true
					break
			if not fitted:
				return _fail("Migrated stash cannot fit; original save preserved.")
	var candidate := {"version": VERSION, "player_id": value.player_id, "stash": inventory.snapshot(), "last_result": value.last_result.duplicate(true), "committed_raids": value.committed_raids.duplicate(), "starter_seeded": true, "stash_width": inventory.width, "stash_height": inventory.height, "staged": {}, "pending_result": {}}
	_convert_supplies(candidate)
	if not _write(candidate):
		return _fail("Profile migration could not be saved; original retained.")
	load_error = "Stash upgraded to the current equipment catalog; original backed up."
	return true

func _convert_supplies(value: Variant) -> void:
	if value is Dictionary:
		if value.get("id", "") == "battery_cell": value.id = "infection_suppressant"
		for child in value.values(): _convert_supplies(child)
	elif value is Array:
		for child in value: _convert_supplies(child)

func _migrate_entry(old: Dictionary, depth: int = 0) -> Dictionary:
	if depth > InventoryPersistence.MAX_DEPTH:
		return {}
	var id: String = ArmoryContent.MIGRATIONS.get(old.get("id", ""), old.get("id", ""))
	var replacement := ArmoryContent.removed_armor_replacement(id)
	if not replacement.is_empty():
		id = replacement
	var historical := _historical_catalog()
	if not historical.items.has(id):
		return {}
	var encoded := old.duplicate(true)
	encoded.id = id
	encoded.state = old.get("state", ArmoryInstance.fresh(id, historical.items)).duplicate(true)
	if not replacement.is_empty():
		var identity: String = encoded.state.get("instance_id", _new_id())
		encoded.state = ArmoryInstance.fresh(id, historical.items)
		encoded.state.instance_id = identity
		var armor: ArmorDef = historical.definitions[id]
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
	_convert_armor(encoded)
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

func stash_grid() -> RaidInventory:
	return InventoryPersistence.decode_entries(profile.stash, catalog.items, Vector2i(int(profile.stash_width), int(profile.stash_height)))

func save_stash_layout(stash: Array[Dictionary]) -> bool:
	var candidate := profile.duplicate(true)
	candidate.stash = stash.duplicate(true)
	return _write(candidate)

func save_layout(stash: RaidInventory, roots: Dictionary) -> bool:
	var candidate := profile.duplicate(true)
	candidate.stash = stash.snapshot()
	candidate.stash_width = stash.width
	candidate.stash_height = stash.height
	candidate.staged = {}
	for name in roots:
		candidate.staged[name] = roots[name].serialize()
	return _write(candidate)

func debit_loadout() -> bool:
	var candidate := profile.duplicate(true)
	candidate.staged = {}
	return _write(candidate)

func stage_result(result: Dictionary, loot: Array[Dictionary]) -> bool:
	if profile.committed_raids.has(result.raid_id):
		return true
	if not profile.pending_result.is_empty():
		return profile.pending_result.result.raid_id == result.raid_id
	var normalized: Array[Dictionary] = []
	if result.get("success", false):
		for item in loot:
			if not Ammunition.valid_state(item, catalog.items): return false
			var encoded := item.duplicate(true)
			Ammunition.normalize(encoded, catalog.items)
			normalized.append(encoded)
	var candidate := profile.duplicate(true)
	candidate.pending_result = {"result": result.duplicate(true), "items": normalized}
	return _write(candidate)

func commit_result(result: Dictionary, loot: Array[Dictionary], equipment: Array[Dictionary] = []) -> bool:
	if result.get("practice", false):
		return false
	if profile.committed_raids.has(result.raid_id):
		return true
	if profile.pending_result.is_empty() and not stage_result(result, equipment + loot):
		return false
	var pending: Dictionary = profile.pending_result
	if pending.result.raid_id != result.raid_id:
		return false
	var stash := stash_grid()
	for encoded in pending.items:
		var entry := InventoryPersistence.decode_item(encoded, catalog.items, {})
		if entry.is_empty() or not stash.add_entry(entry):
			problem.emit("Stash is full; arrange storage and retry the retained result.")
			return false
	var candidate := profile.duplicate(true)
	candidate.stash = stash.snapshot()
	candidate.last_result = pending.result.duplicate(true)
	candidate.committed_raids.append(result.raid_id)
	candidate.pending_result = {}
	return _write(candidate)

func _historical_catalog() -> Catalog:
	var historical := Catalog.new()
	historical.items = catalog.items.duplicate()
	historical.definitions = catalog.definitions.duplicate()
	for id in VESTS:
		var armor: ArmorDef = load("res://resources/armor/" + id + ".tres")
		historical.definitions[id] = armor
		var item := historical._inventory_item(armor, 1, 2, 3, "armor")
		item.equipment_slots = PackedStringArray(["body_armor"])
		item.weight = 2.0
		historical.items[id] = item
	return historical

func _convert_armor(value: Variant) -> void:
	if value is Dictionary:
		if VESTS.has(value.get("id", "")):
			var old: ArmorDef = load("res://resources/armor/" + str(value.id) + ".tres")
			var ratio := 1.0 - float(value.get("state", {}).get("wear", 0)) / old.max_durability
			var mapping: Array = VESTS[value.id]
			var loaded := PlateInventory.loaded(mapping[0], mapping[1], catalog.items, ratio)
			var identity: String = value.get("state", {}).get("instance_id", value.get("uid", _new_id()))
			value.id = mapping[0]
			value.uid = identity
			value.state = loaded.state
			value.state.instance_id = identity
			value.erase("durability")
		for key in value:
			if key != "metadata": _convert_armor(value[key])
	elif value is Array:
		for child in value: _convert_armor(child)

func _encoded_weight(entry: Dictionary) -> float:
	var total: float = catalog.items[entry.id].weight * int(entry.get("quantity", 1))
	if entry.has("storage"):
		for child in entry.storage.slots: total += _encoded_weight(child)
	var state: Dictionary = entry.get("state", {})
	for child in [state.get("magazine", {})] + state.get("attachments", {}).values() + state.get("plates", []):
		if not child.is_empty(): total += _encoded_weight(child)
	for id in state.get("ammo", []): total += catalog.items[id].weight
	if catalog.items.has(state.get("chamber", "")): total += catalog.items[state.chamber].weight
	return total

func _rehome_item(entry: Dictionary, overflow: Array[Dictionary]) -> void:
	if entry.has("storage"): _rehome_grid(entry.storage, overflow)

func _rehome_grid(encoded: Dictionary, overflow: Array[Dictionary]) -> void:
	for entry in encoded.slots: _rehome_item(entry, overflow)
	var config_path: String = encoded.get("config", "")
	if config_path.is_empty(): return
	var config: ContainerDef = load(config_path)
	if config.weight_limit <= 0: return
	var weight := 0.0
	for entry in encoded.slots: weight += _encoded_weight(entry)
	while weight > config.weight_limit + 0.00001 and not encoded.slots.is_empty():
		var entry: Dictionary = encoded.slots.pop_back()
		weight -= _encoded_weight(entry)
		overflow.append(entry)
		if encoded.has("search_order"): encoded.search_order.erase(entry.get("uid", entry.get("state", {}).get("instance_id", "")))
		encoded.discovered = mini(int(encoded.get("discovered", 0)), encoded.slots.size())

func _repair_armor_layout(candidate: Dictionary) -> bool:
	var overflow: Array[Dictionary] = []
	for entry in candidate.stash: _rehome_item(entry, overflow)
	for grid in candidate.staged.values(): _rehome_grid(grid, overflow)
	if not candidate.pending_result.is_empty():
		var pending_overflow: Array[Dictionary] = []
		for entry in candidate.pending_result.items: _rehome_item(entry, pending_overflow)
		candidate.pending_result.items.append_array(pending_overflow)
	var stash := InventoryPersistence.decode_entries(candidate.stash, catalog.items, Vector2i(int(candidate.stash_width), int(candidate.stash_height)))
	if stash == null: return false
	for encoded in overflow:
		var entry := InventoryPersistence.decode_item(encoded, catalog.items, {})
		if entry.is_empty(): return false
		while not stash.add_entry(entry):
			if stash.height >= 128: return false
			stash.height += 1
	candidate.stash = stash.snapshot()
	candidate.stash_height = stash.height
	return true
