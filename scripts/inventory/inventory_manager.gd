class_name InventoryManager
extends RefCounted

# All requests preflight complete candidate states. Signals fire only after commit.
# A future server can invoke this same API after validating actor/root ownership.
static func _copies(grid: RaidInventory) -> Array[Dictionary]:
	return grid.slots.duplicate(true)

static func _weight(entries: Array[Dictionary], definitions: Dictionary) -> float:
	var total := 0.0
	for entry in entries:
		total += ItemInstance.weight(entry, definitions)
	return total

static func _commit(plans: Dictionary, dry_run: bool = false) -> bool:
	var deltas: Dictionary = {}
	for grid: RaidInventory in plans:
		var entries: Array[Dictionary] = plans[grid]
		if not grid.is_accessible():
			return false
		for i in range(entries.size()):
			var entry := entries[i]
			if not grid.items.has(entry.get("id", "")): return false
			if not Ammunition.valid_state(entry, grid.items): return false
			Ammunition.normalize(entry, grid.items)
			if not grid.accepts(entry) or int(entry.quantity) < 1 or int(entry.quantity) > grid.items[entry.id].stack_limit:
				return false
			if not grid._can_place_in(entries, entry.id, int(entry.x), int(entry.y), bool(entry.rotated), i):
				return false
		if grid.capacity >= 0 and entries.size() > grid.capacity:
			return false
		if grid.config != null and grid.config.item_limit > 0 and entries.size() > grid.config.item_limit:
			return false
		var delta := _weight(entries, grid.items) - grid.total_weight()
		var ancestor: RaidInventory = grid
		while ancestor != null:
			deltas[ancestor] = float(deltas.get(ancestor, 0.0)) + delta
			ancestor = ancestor.parent_inventory.get_ref() if ancestor.parent_inventory != null else null
	for grid: RaidInventory in deltas:
		if grid.config != null and grid.config.weight_limit > 0 and grid.total_weight() + deltas[grid] > grid.config.weight_limit + 0.00001:
			return false
	if dry_run:
		return true
	for grid: RaidInventory in plans:
		grid.slots = plans[grid]
		if not grid.draft:
			for entry in grid.slots:
				grid._adopt(entry)
	for grid: RaidInventory in plans:
		if not grid.draft: grid._notify()
	return true

static func _space(grid: RaidInventory, entries: Array[Dictionary], id: String, rotated: bool) -> Vector2i:
	for y in range(grid.height):
		for x in range(grid.width):
			if grid._can_place_in(entries, id, x, y, rotated):
				return Vector2i(x, y)
	return Vector2i(-1, -1)

static func add_new(grid: RaidInventory, id: String, quantity: int, at: Vector2i = Vector2i(-1, -1), rotated: bool = false) -> bool:
	if not grid.items.has(id) or quantity <= 0:
		return false
	var candidate := _copies(grid)
	var definition: ItemDef = grid.items[id]
	var prototype := ItemInstance.create(definition, grid.items)
	var remaining := quantity
	if at.x >= 0:
		if quantity > definition.stack_limit:
			return false
		var target_index := grid._slot_at(at.x, at.y)
		if target_index >= 0 and ItemInstance.compatible(candidate[target_index], prototype):
			candidate[target_index].quantity += quantity
		else:
			prototype.quantity = quantity
			prototype.x = at.x
			prototype.y = at.y
			prototype.rotated = rotated
			candidate.append(prototype)
	else:
		for entry in candidate:
			if ItemInstance.compatible(entry, prototype):
				var amount := mini(remaining, definition.stack_limit - int(entry.quantity))
				entry.quantity += amount
				remaining -= amount
		while remaining > 0:
			var position := _space(grid, candidate, id, false)
			var rotation := false
			if position.x < 0:
				position = _space(grid, candidate, id, true)
				rotation = true
			if position.x < 0:
				return false
			var entry := ItemInstance.create(definition, grid.items, mini(remaining, definition.stack_limit))
			entry.x = position.x
			entry.y = position.y
			entry.rotated = rotation
			candidate.append(entry)
			remaining -= int(entry.quantity)
	return _commit({grid: candidate})

static func insert(grid: RaidInventory, entry: Dictionary, at: Vector2i = Vector2i(-1, -1)) -> bool:
	if not grid.items.has(entry.get("id", "")):
		return false
	var instance := entry.duplicate(true)
	if not instance.has("uid"):
		var defaults := ItemInstance.create(grid.items[instance.id], grid.items, int(instance.quantity))
		defaults.merge(instance, true)
		instance = defaults
	if instance.get("storage") is Dictionary:
		var decoded: RaidInventory = InventoryPersistence.decode(instance.storage, grid.items)
		if decoded == null:
			return false
		instance.storage = decoded
	if grid.find_uid(instance.uid) >= 0 or ItemInstance.contains(instance, grid):
		return false
	var candidate := _copies(grid)
	var limit: int = grid.items[instance.id].stack_limit
	if at.x < 0 and limit > 1:
		for target in candidate:
			if ItemInstance.compatible(target, instance):
				var amount := mini(limit - int(target.quantity), int(instance.quantity))
				target.quantity += amount
				instance.quantity -= amount
				if instance.quantity == 0:
					return _commit({grid: candidate})
	var position := at
	if position.x < 0:
		position = _space(grid, candidate, instance.id, bool(instance.get("rotated", false)))
		if position.x < 0:
			instance.rotated = not bool(instance.get("rotated", false))
			position = _space(grid, candidate, instance.id, instance.rotated)
	if position.x < 0:
		return false
	instance.x = position.x
	instance.y = position.y
	instance.rotated = bool(instance.get("rotated", false))
	candidate.append(instance)
	return _commit({grid: candidate})

static func move(source: RaidInventory, index: int, target: RaidInventory, at: Vector2i = Vector2i(-1, -1), rotated: bool = false, quantity: int = -1, dry_run: bool = false) -> bool:
	if source == null or target == null or not source.visible_item(index) or not source.is_accessible() or not target.searched:
		return false
	var entry := source.slots[index].duplicate(true)
	if not target.accepts(entry):
		return false
	var amount := int(entry.quantity) if quantity < 0 else quantity
	if amount <= 0 or amount > int(entry.quantity) or (entry.has("storage") and amount != int(entry.quantity)):
		return false
	var original: Vector2i = Vector2i(int(entry.x), int(entry.y))
	var plans := {source: _copies(source)}
	if source != target:
		plans[target] = _copies(target)
	var src: Array[Dictionary] = plans[source]
	var dst: Array[Dictionary] = plans[target]
	var position := at
	var occupant := -1
	if position.x >= 0:
		occupant = target._slot_at(position.x, position.y)
	else:
		for i in range(dst.size()):
			if (source != target or i != index) and ItemInstance.compatible(entry, dst[i]) and int(dst[i].quantity) < target.items[entry.id].stack_limit:
				occupant = i
				break
	if occupant >= 0 and (source != target or occupant != index) and ItemInstance.compatible(entry, dst[occupant]):
		var free: int = target.items[entry.id].stack_limit - int(dst[occupant].quantity)
		if free <= 0:
			return false
		amount = mini(amount, free)
		dst[occupant].quantity += amount
		src[index].quantity -= amount
		if src[index].quantity == 0:
			src.remove_at(index)
		return _commit(plans, dry_run)
	if amount < int(entry.quantity):
		src[index].quantity -= amount
		entry.uid = ProfileStore._new_id()
		entry.quantity = amount
	else:
		src.remove_at(index)
	if position.x < 0:
		position = _space(target, dst, entry.id, rotated)
		if position.x < 0:
			rotated = not rotated
			position = _space(target, dst, entry.id, rotated)
	if position.x < 0:
		return false
	# A swap is all-or-nothing, including compatibility, cycles and both footprints.
	if occupant >= 0 and (source != target or occupant != index):
		if amount != int(source.slots[index].quantity):
			return false
		var other := target.slots[occupant].duplicate(true)
		if not source.visible_item(index) or not target.visible_item(occupant) or not source.accepts(other):
			return false
		for i in range(dst.size()):
			if dst[i].get("uid") == other.get("uid"):
				dst.remove_at(i)
				break
		other.x = original.x
		other.y = original.y
		src.append(other)
	entry.x = position.x
	entry.y = position.y
	entry.rotated = rotated
	dst.append(entry)
	return _commit(plans, dry_run)

static func sort_grid(grid: RaidInventory, dry_run: bool = false) -> bool:
	if not grid.searched:
		return false
	var ordered := _copies(grid)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary):
		var aa := grid.dimensions(a.id)
		var bb := grid.dimensions(b.id)
		return aa.x * aa.y > bb.x * bb.y if aa.x * aa.y != bb.x * bb.y else str(a.get("uid", a.id)) < str(b.get("uid", b.id))
	)
	var candidate: Array[Dictionary] = []
	for entry in ordered:
		for placed in candidate:
			if ItemInstance.compatible(placed, entry):
				var amount := mini(int(entry.quantity), grid.items[entry.id].stack_limit - int(placed.quantity))
				placed.quantity += amount
				entry.quantity -= amount
		if entry.quantity == 0:
			continue
		var at := _space(grid, candidate, entry.id, bool(entry.rotated))
		if at.x < 0:
			entry.rotated = not bool(entry.rotated)
			at = _space(grid, candidate, entry.id, entry.rotated)
		if at.x < 0:
			return false
		entry.x = at.x
		entry.y = at.y
		candidate.append(entry)
	return _commit({grid: candidate}, dry_run)

static func resize(grid: RaidInventory, dimensions: Vector2i) -> bool:
	if dimensions.x < 1 or dimensions.y < 1:
		return false
	for entry in grid.slots:
		var end := Vector2i(int(entry.x), int(entry.y)) + grid.dimensions(entry.id, bool(entry.rotated))
		if end.x > dimensions.x or end.y > dimensions.y:
			return false
	grid.width = dimensions.x
	grid.height = dimensions.y
	grid._notify()
	return true
