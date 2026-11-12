class_name RaidInventory
extends RefCounted

signal changed
var slots: Array[Dictionary] = []
var capacity: int
var items: Dictionary

func _init(item_definitions: Dictionary = {}, slot_capacity: int = 8) -> void:
	items = item_definitions
	capacity = slot_capacity

func count(item_id: String) -> int:
	var total := 0
	for slot in slots:
		if slot.id == item_id:
			total += slot.quantity
	return total

func add(item_id: String, quantity: int) -> bool:
	if not items.has(item_id) or quantity <= 0:
		return false
	var limit: int = items[item_id].stack_limit
	var room: int = (capacity - slots.size()) * limit
	for slot in slots:
		if slot.id == item_id:
			room += limit - int(slot.quantity)
	if quantity > room:
		return false
	var remaining := quantity
	for slot in slots:
		if slot.id == item_id:
			var moved: int = mini(remaining, limit - int(slot.quantity))
			slot.quantity += moved
			remaining -= moved
	while remaining > 0:
		var moved: int = mini(remaining, limit)
		slots.append({"id": item_id, "quantity": moved})
		remaining -= moved
	changed.emit()
	return true

func snapshot() -> Array[Dictionary]:
	return slots.duplicate(true)
