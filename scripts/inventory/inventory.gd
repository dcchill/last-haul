class_name RaidInventory
extends RefCounted

signal changed
const CELL_SIZE := 18
var uid: String = ProfileStore._new_id()
var revision := 0
# Detached transaction drafts must not adopt shared child inventories.
var draft := false
var slots: Array[Dictionary] = []
var width: int
var height: int
var items: Dictionary
var display_name: String = "Storage"
var config: ContainerDef
var capacity: int = -1
var equipment_slot: String = ""
var parent_inventory: WeakRef
var accessible: bool = true
var searched: bool = true
var searching: bool = false
var search_elapsed: float = 0.0
var discovered: int = 0
var search_order: Array[String] = []
var loot_generated: bool = false
var is_open: bool = false

func _init(definitions: Dictionary = {}, grid_width: int = 10, grid_height: int = 6) -> void:
	items = definitions
	width = grid_width
	height = grid_height

func configure(value: ContainerDef) -> void:
	config = value
	width = value.dimensions.x
	height = value.dimensions.y
	display_name = value.display_name
	accessible = value.accessible
	searched = not value.searchable

func count(item_id: String) -> int:
	var total := 0
	for entry in slots:
		if entry.id == item_id:
			total += int(entry.quantity)
	return total

func find_uid(item_uid: String) -> int:
	for i in range(slots.size()):
		if slots[i].get("uid", "") == item_uid:
			return i
	return -1

func dimensions(item_id: String, rotated: bool = false) -> Vector2i:
	var definition: ItemDef = items[item_id]
	return Vector2i(definition.height, definition.width) if rotated else Vector2i(definition.width, definition.height)

func accepts(entry: Dictionary) -> bool:
	if not items.has(entry.id) or not is_accessible():
		return false
	var definition: ItemDef = items[entry.id]
	if not equipment_slot.is_empty() and not definition.equipment_slots.has(equipment_slot):
		return false
	if config != null:
		if entry.has("storage") and not config.allow_containers:
			return false
		var depth := ItemInstance.depth(entry)
		var ancestor: RaidInventory = self
		while ancestor != null:
			if ancestor.config != null and depth > ancestor.config.max_nesting_depth:
				return false
			ancestor = ancestor.parent_inventory.get_ref() if ancestor.parent_inventory != null else null
			depth += 1
		if not config.allowed_categories.is_empty() and not config.allowed_categories.has(definition.kind):
			return false
		if config.prohibited_categories.has(definition.kind):
			return false
	return not ItemInstance.contains(entry, self)

func is_accessible() -> bool:
	if not accessible:
		return false
	var ancestor: RaidInventory = parent_inventory.get_ref() if parent_inventory != null else null
	return ancestor == null or ancestor.is_accessible()

func visible_item(index: int) -> bool:
	return index >= 0 and index < slots.size() and (searched or (config != null and config.progressive_discovery and slots[index].uid in search_order.slice(0, discovered)))

func can_place(item_id: String, x: int, y: int, rotated: bool = false, ignore_slot: int = -1) -> bool:
	return _can_place_in(slots, item_id, x, y, rotated, ignore_slot)

func _can_place_in(entries: Array[Dictionary], item_id: String, x: int, y: int, rotated: bool = false, ignore: int = -1) -> bool:
	if not items.has(item_id) or capacity == 0:
		return false
	var footprint := dimensions(item_id, rotated)
	if x < 0 or y < 0 or x + footprint.x > width or y + footprint.y > height:
		return false
	if ignore < 0 and ((capacity > 0 and entries.size() >= capacity) or (config != null and config.item_limit > 0 and entries.size() >= config.item_limit)):
		return false
	var rect := Rect2i(Vector2i(x, y), footprint)
	for i in range(entries.size()):
		if i == ignore:
			continue
		var other: Dictionary = entries[i]
		if rect.intersects(Rect2i(Vector2i(int(other.x), int(other.y)), dimensions(other.id, bool(other.get("rotated", false))))):
			return false
	return true

func first_space(item_id: String, rotated: bool = false, ignore: int = -1) -> Vector2i:
	for y in range(height):
		for x in range(width):
			if can_place(item_id, x, y, rotated, ignore):
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func _slot_at(x: int, y: int) -> int:
	for i in range(slots.size()):
		var entry := slots[i]
		if Rect2i(Vector2i(int(entry.x), int(entry.y)), dimensions(entry.id, bool(entry.get("rotated", false)))).has_point(Vector2i(x, y)):
			return i
	return -1

func add(item_id: String, quantity: int, state: Dictionary = {}) -> bool:
	if not state.is_empty():
		if quantity != 1 or not items.has(item_id):
			return false
		var entry := ItemInstance.create(items[item_id], items)
		entry.state = state.duplicate(true)
		Ammunition.normalize(entry, items)
		return insert_instance(entry)
	return InventoryManager.add_new(self, item_id, quantity)

func add_at(item_id: String, quantity: int, x: int, y: int, rotated: bool = false, state: Dictionary = {}) -> bool:
	if not state.is_empty():
		if quantity != 1 or not items.has(item_id):
			return false
		var entry := ItemInstance.create(items[item_id], items)
		entry.state = state.duplicate(true)
		Ammunition.normalize(entry, items)
		entry.rotated = rotated
		return insert_instance(entry, Vector2i(x, y))
	return InventoryManager.add_new(self, item_id, quantity, Vector2i(x, y), rotated)

func find_instance(instance_id: String) -> int:
	for index in range(slots.size()):
		if slots[index].get("state", {}).get("instance_id", slots[index].get("uid", "")) == instance_id:
			return index
	return -1

func add_entry(entry: Dictionary) -> bool:
	return insert_instance(entry)

func remove_entry(entry: Dictionary) -> bool:
	var instance_id: String = entry.get("state", {}).get("instance_id", "")
	if instance_id.is_empty():
		return remove(entry.id, int(entry.quantity))
	var index := find_instance(instance_id)
	if index < 0 or slots[index].id != entry.id:
		return false
	slots.remove_at(index)
	_notify()
	return true

func insert_instance(entry: Dictionary, at: Vector2i = Vector2i(-1, -1)) -> bool:
	return InventoryManager.insert(self, entry, at)

func remove(item_id: String, quantity: int) -> bool:
	if quantity <= 0 or count(item_id) < quantity:
		return false
	for entry in slots:
		if entry.id == item_id and entry.has("storage") and not entry.storage.slots.is_empty():
			return false
	var remaining := quantity
	for i in range(slots.size() - 1, -1, -1):
		if slots[i].id == item_id:
			var amount := mini(remaining, int(slots[i].quantity))
			slots[i].quantity -= amount
			remaining -= amount
			if slots[i].quantity == 0:
				slots.remove_at(i)
			if remaining == 0:
				break
	_notify()
	return true

func transfer_to(index: int, target: RaidInventory, x: int, y: int, rotated: bool = false) -> bool:
	return InventoryManager.move(self, index, target, Vector2i(x, y), rotated)

func move(index: int, x: int, y: int, rotated: bool = false) -> bool:
	return InventoryManager.move(self, index, self, Vector2i(x, y), rotated)

func sort() -> bool:
	return InventoryManager.sort_grid(self)

func total_weight() -> float:
	var total := 0.0
	for entry in slots:
		total += ItemInstance.weight(entry, items)
	return total

func _notify() -> void:
	revision += 1
	changed.emit()
	var ancestor: RaidInventory = parent_inventory.get_ref() if parent_inventory != null else null
	if ancestor != null:
		ancestor._notify()

func _adopt(entry: Dictionary) -> void:
	if entry.has("storage"):
		entry.storage.parent_inventory = weakref(self)

func begin_search() -> bool:
	if not is_accessible():
		return false
	is_open = true
	if search_order.is_empty():
		for entry in slots: search_order.append(entry.uid)
	searching = not searched
	if config == null or config.search_seconds <= 0:
		searched = true
		searching = false
	_notify()
	return true

func tick_search(delta: float) -> void:
	if not searching or config == null:
		return
	search_elapsed = minf(config.search_seconds, search_elapsed + maxf(0, delta))
	discovered = floori(search_order.size() * search_elapsed / maxf(0.001, config.search_seconds))
	if search_elapsed >= config.search_seconds:
		searched = true
		searching = false
	_notify()

func search_state() -> String:
	if not is_open:
		return "Closed"
	if searching:
		return "Searching"
	if not searched:
		return "Unsearched"
	return "Empty" if slots.is_empty() else "Searched"

func snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in slots:
		var encoded := entry.duplicate(true)
		if entry.has("storage"):
			encoded.storage = entry.storage.serialize()
		result.append(encoded)
	return result

func serialize() -> Dictionary:
	return {"uid": uid, "width": width, "height": height, "name": display_name,
		"config": config.resource_path if config != null else "", "equipment_slot": equipment_slot,
		"accessible": accessible, "searched": searched, "search_elapsed": search_elapsed,
		"discovered": discovered, "search_order": search_order.duplicate(), "loot_generated": loot_generated, "slots": snapshot()}

func all_grids() -> Array[RaidInventory]:
	var result: Array[RaidInventory] = [self]
	for entry in slots:
		if entry.has("storage"):
			result.append_array(entry.storage.all_grids())
	return result

func owner_of(identity: String) -> RaidInventory:
	for grid in all_grids():
		if grid.find_uid(identity) >= 0 or grid.find_instance(identity) >= 0:
			return grid
	return null
