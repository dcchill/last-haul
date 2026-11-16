class_name PlateInventory
extends RefCounted

static func loaded(carrier_id: String, plate_id: String, items: Dictionary, remaining := 1.0) -> Dictionary:
	var entry := ItemInstance.create(items[carrier_id], items)
	for slot in range(entry.state.plates.size()):
		if remaining <= 0: break
		var plate := ItemInstance.create(items[plate_id], items)
		plate.state.wear = items[plate_id].definition.capacity * (1.0 - remaining)
		entry.state.plates[slot] = plate
	return entry

static func valid_carrier(state: Dictionary, definition: ArmorDef, items: Dictionary, depth: int) -> bool:
	if not state.get("plates") is Array or state.plates.size() != definition.plate_slots:
		return false
	var seen := {state.get("instance_id", ""): true}
	for plate in state.plates:
		if not plate is Dictionary: return false
		if plate.is_empty(): continue
		if not items.has(plate.get("id", "")) or not items[plate.id].definition is PlateDef:
			return false
		if not plate.get("state") is Dictionary: return false
		if plate.get("quantity") != 1 or plate.get("uid") != plate.state.get("instance_id") or plate.has("storage"):
			return false
		if not Ammunition.valid_state(plate, items, depth + 1): return false
		if seen.has(plate.uid): return false
		seen[plate.uid] = true
		if not InventoryPersistence.whole(plate.get("x")) or not InventoryPersistence.whole(plate.get("y")) or not plate.get("rotated") is bool: return false
		var condition: Variant = plate.get("condition")
		if not (condition is float or condition is int) or not is_finite(float(condition)) or condition < 0 or condition > 1: return false
		if not plate.get("metadata") is Dictionary or not InventoryPersistence.json_value(plate.metadata): return false
		if not plate.get("attachments") is Array or not plate.attachments.is_empty(): return false
	return true

static func change(request: Dictionary, source: RaidInventory, target: RaidInventory, preview := false) -> bool:
	if target == null or not source.is_accessible() or not target.is_accessible() or not target.searched:
		return false
	if not InventoryPersistence.whole(request.get("plate_slot"), 0, 2): return false
	var slot := int(request.plate_slot)
	var index := source.find_uid(str(request.get("item", "")))
	if not source.visible_item(index): return false
	var plans := {source: source.slots.duplicate(true)}
	if target != source: plans[target] = target.slots.duplicate(true)
	var src: Array[Dictionary] = plans[source]
	var dst: Array[Dictionary] = plans[target]
	if request.operation == "insert_plate":
		if not request.get("carrier_uid") is String: return false
		var carrier_index := target.find_uid(request.carrier_uid)
		if not target.visible_item(carrier_index): return false
		var definition: Resource = target.items[dst[carrier_index].id].definition
		if not definition is ArmorDef or slot >= definition.plate_slots or not source.items[src[index].id].definition is PlateDef:
			return false
		if not dst[carrier_index].state.plates[slot].is_empty(): return false
		dst[carrier_index].state.plates[slot] = src[index]
		src.remove_at(index)
	elif request.operation == "remove_plate":
		var definition: Resource = source.items[src[index].id].definition
		if not definition is ArmorDef or slot >= definition.plate_slots: return false
		var plate: Dictionary = src[index].state.plates[slot]
		if plate.is_empty(): return false
		src[index].state.plates[slot] = {}
		var at := InventoryManager._space(target, dst, plate.id, false)
		if at.x < 0: return false
		plate.x = at.x
		plate.y = at.y
		plate.rotated = false
		dst.append(plate)
	else:
		return false
	return InventoryManager._commit(plans, preview)
