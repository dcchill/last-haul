class_name ProfileStore
extends RefCounted

signal problem(message: String)
const VERSION := 1
var path: String
var catalog: Catalog
var profile: Dictionary = {}
var load_error: String = ""
var writable: bool = true

func _init(data: Catalog, save_path: String = "user://profile.json") -> void:
	catalog = data
	path = save_path
	profile = {"version": VERSION, "player_id": "player-" + _new_id(), "stash": [], "last_result": {}, "committed_raids": []}

static func _new_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != VERSION:
		return false
	if not value.get("player_id") is String or value.player_id.is_empty():
		return false
	if not value.get("stash") is Array or not value.get("last_result") is Dictionary or not value.get("committed_raids") is Array:
		return false
	for raid in value.committed_raids:
		if not raid is String:
			return false
	for slot in value.stash:
		if not slot is Dictionary or not slot.get("id") is String or not catalog.items.has(slot.id):
			return false
		if not _positive_integer(slot.get("quantity")) or slot.quantity > catalog.items[slot.id].stack_limit:
			return false
	var result: Dictionary = value.last_result
	if not result.is_empty():
		if not result.get("raid_id") is String or not result.get("success") is bool or not result.get("reason") is String:
			return false
	return true

func _positive_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value > 0

func _read(file_path: String) -> Variant:
	if not FileAccess.file_exists(file_path):
		return null
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return null
	var json := JSON.new()
	return json.data if json.parse(file.get_as_text()) == OK else null

func load_profile() -> bool:
	load_error = ""
	writable = true
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"):
		return true
	var value: Variant = _read(path)
	if valid(value):
		profile = value
		return true
	var backup: Variant = _read(path + ".bak")
	if valid(backup):
		profile = backup
		load_error = "Recovered stash from backup; the unreadable save was preserved."
		if not _preserve_unreadable():
			writable = false
			load_error += " Could not preserve the original; saving is disabled."
		problem.emit(load_error)
		return writable

	writable = false
	load_error = "Stash save is unreadable. Original files preserved; deployment is disabled until the save is repaired or moved."
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
	# Only a validated main file may replace the known-good backup.
	if valid(_read(path)) and DirAccess.copy_absolute(path, path + ".bak") != OK:
		problem.emit("Could not back up stash; previous save retained.")
		return false
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		problem.emit("Could not replace stash; previous save retained. Retry saving.")
		return false
	profile = candidate
	return true

func save_profile() -> bool:
	return _write(profile.duplicate(true))

func commit_result(result: Dictionary, loot: Array[Dictionary]) -> bool:
	if profile.committed_raids.has(result.raid_id):
		return true
	var candidate := profile.duplicate(true)
	if result.success:
		var stash := RaidInventory.new(catalog.items, 10000)
		for slot in candidate.stash:
			if not stash.add(slot.id, int(slot.quantity)):
				return false
		for slot in loot:
			if not stash.add(slot.id, int(slot.quantity)):
				return false
		candidate.stash = stash.snapshot()
	candidate.last_result = result.duplicate(true)
	# shortcut: outcome IDs grow with raid count, compact the ledger before production use.
	candidate.committed_raids.append(result.raid_id)
	return _write(candidate)
