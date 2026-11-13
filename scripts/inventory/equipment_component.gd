class_name EquipmentComponent
extends RefCounted

signal changed
const DEFAULT_SLOTS := ["headgear", "face", "eyewear", "body_armor", "rig", "backpack", "primary", "secondary", "holster", "melee", "leggings", "boots"]
var slots: Dictionary = {}

func _init(definitions: Dictionary, names: Array = DEFAULT_SLOTS) -> void:
	for slot_name: String in names:
		var grid := RaidInventory.new(definitions, 16, 16)
		grid.capacity = 1
		grid.equipment_slot = slot_name
		grid.display_name = slot_name.replace("_", " ").capitalize()
		grid.changed.connect(_changed)
		slots[slot_name] = grid

func storages() -> Array[RaidInventory]:
	var result: Array[RaidInventory] = []
	for grid: RaidInventory in slots.values():
		for entry in grid.slots:
			if entry.has("storage"):
				result.append(entry.storage)
	return result

func roots() -> Array[RaidInventory]:
	var result: Array[RaidInventory] = []
	for grid: RaidInventory in slots.values():
		result.append(grid)
	return result

func total_weight() -> float:
	var total := 0.0
	for grid: RaidInventory in slots.values():
		total += grid.total_weight()
	return total

func serialize() -> Dictionary:
	var result: Dictionary = {}
	for name: String in slots:
		result[name] = slots[name].serialize()
	return result

func owner_of(identity: String) -> RaidInventory:
	for root in roots():
		var owner := root.owner_of(identity)
		if owner != null:
			return owner
	return null

func restore(data: Dictionary, definitions: Dictionary, seen: Dictionary = {}) -> bool:
	for name in data:
		if not slots.has(name):
			return false
		var grid := InventoryPersistence.decode(data[name], definitions, seen)
		if grid == null or grid.equipment_slot != name:
			return false
		slots[name] = grid
		grid.changed.connect(_changed)
	return true

func _changed() -> void:
	changed.emit()
