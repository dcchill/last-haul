class_name RaidInventory
extends RefCounted

signal changed

const CELL_SIZE := 18
var slots: Array[Dictionary] = []
var width: int
var height: int
var items: Dictionary

func _init(item_definitions: Dictionary = {}, grid_width: int = 10, grid_height: int = 6) -> void:
	items = item_definitions
	width = grid_width
	height = grid_height

func count(item_id: String) -> int:
	var total := 0
	for slot in slots:
		if slot.id == item_id:
			total += int(slot.quantity)
	return total

func can_place(item_id: String, x: int, y: int, rotated: bool = false, ignore_slot: int = -1) -> bool:
	if not items.has(item_id):
		return false
	var item: ItemDef = items[item_id]
	var item_width := item.height if rotated else item.width
	var item_height := item.width if rotated else item.height
	if x < 0 or y < 0 or x + item_width > width or y + item_height > height:
		return false
	for index in range(slots.size()):
		if index == ignore_slot:
			continue
		var slot: Dictionary = slots[index]
		var other: ItemDef = items[slot.id]
		var other_width := other.height if bool(slot.get("rotated", false)) else other.width
		var other_height := other.width if bool(slot.get("rotated", false)) else other.height
		if x < int(slot.x) + other_width and x + item_width > int(slot.x) and y < int(slot.y) + other_height and y + item_height > int(slot.y):
			return false
	return true

func add(item_id: String, quantity: int) -> bool:
	if not items.has(item_id) or quantity <= 0:
		return false
	var candidate := slots.duplicate(true)
	var limit: int = items[item_id].stack_limit
	var remaining := quantity
	for slot in candidate:
		if slot.id == item_id and int(slot.quantity) < limit:
			var moved: int = mini(remaining, limit - int(slot.quantity))
			slot.quantity += moved
			remaining -= moved
			if remaining == 0:
				slots = candidate
				changed.emit()
				return true
	while remaining > 0:
		var position := _first_space(item_id, candidate)
		if position.x < 0:
			return false
		var moved: int = mini(remaining, limit)
		candidate.append({"id": item_id, "quantity": moved, "x": position.x, "y": position.y, "rotated": false})
		remaining -= moved
	slots = candidate
	changed.emit()
	return true

func add_at(item_id: String, quantity: int, x: int, y: int, rotated: bool = false) -> bool:
	if not items.has(item_id) or quantity <= 0 or quantity > items[item_id].stack_limit:
		return false
	var index := _slot_at(x, y)
	if index >= 0 and slots[index].id == item_id:
		if int(slots[index].quantity) + quantity > items[item_id].stack_limit:
			return false
		slots[index].quantity += quantity
	else:
		if not can_place(item_id, x, y, rotated):
			return false
		slots.append({"id": item_id, "quantity": quantity, "x": x, "y": y, "rotated": rotated})
	changed.emit()
	return true

func remove(item_id: String, quantity: int) -> bool:
	if quantity <= 0 or count(item_id) < quantity:
		return false
	var remaining := quantity
	for index in range(slots.size() - 1, -1, -1):
		if slots[index].id != item_id:
			continue
		var moved := mini(remaining, int(slots[index].quantity))
		slots[index].quantity -= moved
		remaining -= moved
		if slots[index].quantity == 0:
			slots.remove_at(index)
		if remaining == 0:
			break
	changed.emit()
	return true

func transfer_to(index: int, target: RaidInventory, x: int, y: int, rotated: bool = false) -> bool:
	if index < 0 or index >= slots.size() or target == self:
		return false
	var slot: Dictionary = slots[index]
	var target_index := target._slot_at(x, y)
	if target_index >= 0 and target.slots[target_index].id == slot.id:
		var limit: int = target.items[slot.id].stack_limit
		if int(target.slots[target_index].quantity) + int(slot.quantity) > limit:
			return false
		target.slots[target_index].quantity += int(slot.quantity)
	else:
		if not target.can_place(slot.id, x, y, rotated):
			return false
		target.slots.append({"id": slot.id, "quantity": int(slot.quantity), "x": x, "y": y, "rotated": rotated})
	slots.remove_at(index)
	target.changed.emit()
	changed.emit()
	return true

func move(index: int, x: int, y: int, rotated: bool = false) -> bool:
	if index < 0 or index >= slots.size():
		return false
	var slot: Dictionary = slots[index]
	if not can_place(slot.id, x, y, rotated, index):
		return false
	slot.x = x
	slot.y = y
	slot.rotated = rotated
	changed.emit()
	return true

func sort() -> bool:
	var ordered := slots.duplicate(true)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary):
		var item_a: ItemDef = items[a.id]
		var item_b: ItemDef = items[b.id]
		if item_a.width * item_a.height != item_b.width * item_b.height:
			return item_a.width * item_a.height > item_b.width * item_b.height
		return a.id < b.id
	)
	var sorted := RaidInventory.new(items, width, height)
	for slot in ordered:
		if sorted.add(slot.id, int(slot.quantity)):
			continue
		var item: ItemDef = items[slot.id]
		var placed := false
		if item.width != item.height:
			for y in range(height):
				for x in range(width):
					if sorted.can_place(slot.id, x, y, true) and sorted.add_at(slot.id, int(slot.quantity), x, y, true):
						placed = true
						break
				if placed:
					break
		if not placed:
			return false
	slots = sorted.slots
	changed.emit()
	return true

func _first_space(item_id: String, candidate: Array[Dictionary]) -> Vector2i:
	for y in range(height):
		for x in range(width):
			if _can_place_in(candidate, item_id, x, y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func _can_place_in(candidate: Array[Dictionary], item_id: String, x: int, y: int) -> bool:
	var item: ItemDef = items[item_id]
	if x + item.width > width or y + item.height > height:
		return false
	for slot in candidate:
		var other: ItemDef = items[slot.id]
		var other_width := other.height if bool(slot.get("rotated", false)) else other.width
		var other_height := other.width if bool(slot.get("rotated", false)) else other.height
		if x < int(slot.x) + other_width and x + item.width > int(slot.x) and y < int(slot.y) + other_height and y + item.height > int(slot.y):
			return false
	return true

func _slot_at(x: int, y: int) -> int:
	for index in range(slots.size()):
		var slot: Dictionary = slots[index]
		var item: ItemDef = items[slot.id]
		var item_width := item.height if bool(slot.get("rotated", false)) else item.width
		var item_height := item.width if bool(slot.get("rotated", false)) else item.height
		if x >= int(slot.x) and x < int(slot.x) + item_width and y >= int(slot.y) and y < int(slot.y) + item_height:
			return index
	return -1

func snapshot() -> Array[Dictionary]:
	return slots.duplicate(true)
