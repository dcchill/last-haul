class_name Ammunition
extends RefCounted

static func default_ammo(id: String, items: Dictionary) -> String:
	var feed := ArmoryContent.magazine_feed(id)
	if not feed.is_empty():
		return str(feed.ammo)
	if items.has(id) and items[id].definition is WeaponDef:
		return items[id].definition.ammo.id
	return ""

static func sequence(state: Dictionary, ammo: String) -> Array:
	if not state.has("ammo"):
		state.ammo = []
		for i in range(int(state.get("rounds", 0))):
			state.ammo.append(ammo)
	return state.ammo

static func valid_state(entry: Dictionary, items: Dictionary, depth := 0) -> bool:
	if depth > 24 or not entry.get("id") is String or not items.has(entry.id) or not entry.get("state", {}) is Dictionary:
		return false
	var state: Dictionary = entry.get("state", {})
	var item: ItemDef = items[entry.id]
	if item.stack_limit != 1: return state.is_empty()
	if not state.get("instance_id") is String or state.instance_id.is_empty(): return false
	if item.kind == "magazine" or (item.kind == "weapon" and item.definition is WeaponDef):
		var feed := ArmoryContent.magazine_feed(entry.id)
		var capacity: int = int(feed.get("capacity", 0)) if item.kind == "magazine" else item.definition.magazine_size
		if not InventoryPersistence.whole(state.get("rounds"), 0, capacity): return false
		if state.has("ammo"):
			if not state.ammo is Array or state.ammo.size() != int(state.rounds): return false
			var expected := default_ammo(entry.id, items)
			for ammo in state.ammo:
				if not ammo is String or caliber(ammo, items).is_empty() or caliber(ammo, items) != caliber(expected, items): return false
	if item.kind == "weapon" and item.definition is WeaponDef:
		if not state.get("magazine") is Dictionary or not state.get("attachments") is Dictionary or not state.get("chamber", "") is String: return false
		if not item.definition.magazine_id.is_empty() and int(state.rounds) != 0: return false
		if not state.get("chamber", "").is_empty() and (caliber(state.chamber, items).is_empty() or caliber(state.chamber, items) != item.definition.ammo.caliber): return false
		if not state.magazine.is_empty():
			if state.magazine.get("id") != item.definition.magazine_id or not valid_state(state.magazine, items, depth + 1): return false
		for slot in state.attachments:
			var attached: Variant = state.attachments[slot]
			if not attached is Dictionary or not valid_state(attached, items, depth + 1): return false
			var definition: Resource = items[attached.id].definition
			if not definition is AttachmentDef or definition.slot != slot or not definition.supports(item.definition): return false
	if item.kind == "armor" and item.definition is ArmorDef:
		if not InventoryPersistence.whole(state.get("wear"), 0, item.definition.max_durability): return false
	return true

static func normalize(entry: Dictionary, items: Dictionary) -> void:
	if not entry.has("uid"): entry.uid = ProfileStore._new_id()
	var defaults := {"quantity": 1, "x": 0, "y": 0, "rotated": false, "condition": 1.0, "durability": items[entry.id].max_durability, "attachments": [], "metadata": {}}
	for key in defaults:
		if not entry.has(key): entry[key] = defaults[key]
	var state: Dictionary = entry.get("state", {})
	if state.has("instance_id"):
		entry.uid = state.instance_id
	if items[entry.id].kind == "armor": entry.erase("durability")
	if state.has("rounds"):
		sequence(state, default_ammo(entry.id, items))
	if items[entry.id].kind == "weapon":
		state.chamber = state.get("chamber", "")
	if not state.get("magazine", {}).is_empty():
		normalize(state.magazine, items)
	for attachment in state.get("attachments", {}).values():
		normalize(attachment, items)

static func caliber(id: String, items: Dictionary) -> String:
	if not items.has(id):
		return ""
	var definition: Resource = items[id].definition
	return definition.caliber if definition is AmmoDef else ""

static func load(grid: RaidInventory, index: int, ammo_id: String, unload := false, preview := false) -> bool:
	if not grid.visible_item(index):
		return false
	var entry: Dictionary = grid.slots[index]
	var feed := ArmoryContent.magazine_feed(entry.id)
	if feed.is_empty():
		return false
	var candidate := grid.slots.duplicate(true)
	var state: Dictionary = candidate[index].state
	var rounds := sequence(state, str(feed.ammo))
	if unload:
		if rounds.is_empty():
			return false
		var trial := RaidInventory.new(grid.items, grid.width, grid.height)
		trial.draft = true
		trial.config = grid.config
		trial.slots = candidate
		var counts: Dictionary = {}
		for id in rounds:
			counts[id] = int(counts.get(id, 0)) + 1
		state.ammo = []
		state.rounds = 0
		for id in counts:
			if not trial.add(id, counts[id]):
				return false
		return InventoryManager._commit({grid: trial.slots}, preview)
	if ammo_id.is_empty():
		ammo_id = str(feed.ammo)
	if caliber(ammo_id, grid.items).is_empty() or caliber(ammo_id, grid.items) != caliber(str(feed.ammo), grid.items):
		return false
	var remaining := int(feed.capacity) - rounds.size()
	var loaded := 0
	for i in range(candidate.size() - 1, -1, -1):
		if candidate[i].id != ammo_id:
			continue
		var amount := mini(remaining, int(candidate[i].quantity))
		for n in range(amount):
			rounds.push_front(ammo_id)
		candidate[i].quantity -= amount
		remaining -= amount
		loaded += amount
		if candidate[i].quantity == 0:
			candidate.remove_at(i)
	state.rounds = rounds.size()
	return loaded > 0 and InventoryManager._commit({grid: candidate}, preview)
