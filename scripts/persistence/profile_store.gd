class_name ProfileStore
extends RefCounted

signal problem(message: String)
const VERSION := 2
var path: String
var catalog: Catalog
var profile: Dictionary = {}
var load_error: String = ""
var writable: bool = true

func _init(data: Catalog, save_path: String = "user://profile.json") -> void:
	catalog = data
	path = save_path
	profile = _empty_profile()

func _empty_profile() -> Dictionary:
	return {"version": VERSION, "player_id": "player-" + _new_id(), "stash": [], "last_result": {}, "committed_raids": [], "starter_seeded": false}

static func _new_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != VERSION:
		return false
	if not value.get("player_id") is String or value.player_id.is_empty() or not value.get("starter_seeded") is bool:
		return false
	if not value.get("stash") is Array or not value.get("last_result") is Dictionary or not value.get("committed_raids") is Array:
		return false
	for raid in value.committed_raids:
		if not raid is String:
			return false
	var stash := RaidInventory.new(catalog.items, 10, 18)
	for slot in value.stash:
		if not slot is Dictionary or not slot.get("id") is String or not catalog.items.has(slot.id):
			return false
		if not _whole_number(slot.get("quantity")) or slot.quantity <= 0 or slot.quantity > catalog.items[slot.id].stack_limit:
			return false
		if not _whole_number(slot.get("x")):
			return false
		if not _whole_number(slot.get("y")):
			return false
		if not slot.get("rotated") is bool or not stash.can_place(slot.id, int(slot.x), int(slot.y), slot.rotated):
			return false
		stash.slots.append(slot.duplicate(true))
	var result: Dictionary = value.last_result
	if not result.is_empty() and (not result.get("raid_id") is String or not result.get("success") is bool or not result.get("reason") is String):
		return false
	return true

func _valid_legacy(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1 or not value.get("player_id") is String or value.player_id.is_empty():
		return false
	if not value.get("stash") is Array or not value.get("last_result") is Dictionary or not value.get("committed_raids") is Array:
		return false
	for raid in value.committed_raids:
		if not raid is String:
			return false
	for slot in value.stash:
		if not slot is Dictionary or not slot.get("id") is String or not catalog.items.has(slot.id):
			return false
		if not _whole_number(slot.get("quantity")) or slot.quantity <= 0 or slot.quantity > catalog.items[slot.id].stack_limit:
			return false
	var result: Dictionary = value.last_result
	return result.is_empty() or (result.get("raid_id") is String and result.get("success") is bool and result.get("reason") is String)

func _whole_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= 0

func _read(file_path: String) -> Variant:
	if not FileAccess.file_exists(file_path):
		return null
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return null
	var json := JSON.new()
	return json.data if json.parse(file.get_as_text()) == OK else null

func load_profile(starter_loadout: String = "standard") -> bool:
	load_error = ""
	writable = true
	var value: Variant = _read(path)
	if valid(value):
		profile = value
		if not bool(profile.starter_seeded):
			return _seed_and_write(starter_loadout)
		return true
	if _valid_legacy(value):
		profile = {"version": VERSION, "player_id": value.player_id, "stash": [], "last_result": value.last_result, "committed_raids": value.committed_raids, "starter_seeded": false}
		var old_stash: Array = value.stash
		var legacy_inventory := RaidInventory.new(catalog.items, 10, 18)
		for old_slot in old_stash:
			if not legacy_inventory.add(old_slot.id, int(old_slot.quantity)):
				writable = false
				load_error = "Stash migration exceeded grid capacity; the original save was preserved."
				return false
		profile.stash = legacy_inventory.snapshot()
		return _seed_and_write(starter_loadout)
	var backup: Variant = _read(path + ".bak")
	if valid(backup) or _valid_legacy(backup):
		var backup_legacy := _valid_legacy(backup)
		if valid(backup):
			profile = backup
		else:
			profile = {"version": VERSION, "player_id": backup.player_id, "stash": [], "last_result": backup.last_result, "committed_raids": backup.committed_raids, "starter_seeded": false}
			var legacy_inventory := RaidInventory.new(catalog.items, 10, 18)
			for slot in backup.stash:
				if not legacy_inventory.add(slot.id, int(slot.quantity)):
					writable = false
					return false
			profile.stash = legacy_inventory.snapshot()
		load_error = "Recovered stash from backup; the unreadable save was preserved."
		if not _preserve_unreadable():
			writable = false
			load_error += " Could not preserve the original; saving is disabled."
			problem.emit(load_error)
			return false
		problem.emit(load_error)
		if backup_legacy or not bool(profile.starter_seeded):
			return _seed_and_write(starter_loadout)
		return true
	if value == null and not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"):
		profile = _empty_profile()
		return _seed_and_write(starter_loadout)
	writable = false
	load_error = "Stash save is unreadable. Original files preserved; deployment is disabled until the save is repaired or moved."
	problem.emit(load_error)
	return false

func _seed_and_write(starter_loadout: String) -> bool:
	if not WeaponState.LOADOUTS.has(starter_loadout):
		starter_loadout = "standard"
	var inventory := RaidInventory.new(catalog.items, 10, 18)
	for slot in profile.stash:
		inventory.slots.append(slot.duplicate(true))
	for item in [{"id": "rifle", "quantity": 1}, {"id": "rifle_round", "quantity": 60}, {"id": "patrol", "quantity": 1}]:
		if not inventory.add(item.id, item.quantity):
			return false
	for id in ["reflex_sight", "balanced_compensator", "precision_stock", "heavy_barrel"]:
		if not inventory.add(id, 1):
			return false
	profile.stash = inventory.snapshot()
	profile.starter_seeded = true
	if _write(profile.duplicate(true)):
		return true
	writable = false
	load_error = "Could not save the migrated starter stash; deployment is disabled."
	problem.emit(load_error)
	return false

func _preserve_unreadable() -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.copy_absolute(path, path + ".corrupt-" + _new_id()) == OK

func _write(candidate: Dictionary) -> bool:
	if not writable or not valid(candidate):
		problem.emit("Save rejected: profile unavailable or invalid.")
		return false
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		problem.emit("Could not write stash. Check disk space and permissions, then retry.")
		return false
	file.store_string(JSON.stringify(candidate, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or not valid(_read(path + ".tmp")):
		problem.emit("Stash verification failed; previous save retained.")
		return false
	var old_value: Variant = _read(path)
	if (valid(old_value) or _valid_legacy(old_value)) and DirAccess.copy_absolute(path, path + ".bak") != OK:
		problem.emit("Could not back up stash; previous save retained.")
		return false
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		problem.emit("Could not replace stash; previous save retained. Retry saving.")
		return false
	profile = candidate
	return true

func save_profile() -> bool:
	return _write(profile.duplicate(true))

func save_stash_layout(stash: Array[Dictionary]) -> bool:
	var candidate := profile.duplicate(true)
	candidate.stash = stash.duplicate(true)
	return _write(candidate)

func debit_loadout(entries: Array[Dictionary]) -> bool:
	var candidate := profile.duplicate(true)
	var inventory := RaidInventory.new(catalog.items, 10, 18)
	for slot in candidate.stash:
		inventory.slots.append(slot.duplicate(true))
	for entry in entries:
		if not entry is Dictionary or not entry.get("id") is String or not catalog.items.has(entry.id) or not _whole_number(entry.get("quantity")) or entry.quantity <= 0:
			return false
		var remaining: int = int(entry.quantity)
		for index in range(inventory.slots.size() - 1, -1, -1):
			var slot: Dictionary = inventory.slots[index]
			if slot.id != entry.id:
				continue
			var moved := mini(remaining, int(slot.quantity))
			slot.quantity -= moved
			remaining -= moved
			if slot.quantity == 0:
				inventory.slots.remove_at(index)
			if remaining == 0:
				break
		if remaining > 0:
			return false
	candidate.stash = inventory.snapshot()
	return _write(candidate)

func commit_result(result: Dictionary, loot: Array[Dictionary], equipment: Array[Dictionary] = []) -> bool:
	if profile.committed_raids.has(result.raid_id):
		return true
	var candidate := profile.duplicate(true)
	if result.success:
		var stash := RaidInventory.new(catalog.items, 10, 18)
		for slot in candidate.stash:
			stash.slots.append(slot.duplicate(true))
		for slot in equipment + loot:
			var placed := false
			if slot.has("x") and slot.has("y"):
				placed = stash.add_at(slot.id, int(slot.quantity), int(slot.x), int(slot.y), bool(slot.get("rotated", false)))
			if not placed and not stash.add(slot.id, int(slot.quantity)):
				problem.emit("Stash is full; raid result is retained for retry.")
				return false
		candidate.stash = stash.snapshot()
	candidate.last_result = result.duplicate(true)
	candidate.committed_raids.append(result.raid_id)
	return _write(candidate)
