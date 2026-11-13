class_name ArmoryInstance
extends RefCounted

static func fresh(id: String, items: Dictionary) -> Dictionary:
	if not items.has(id) or items[id].stack_limit != 1:
		return {}
	var state := {"instance_id": ProfileStore._new_id()}
	match items[id].kind:
		"weapon": state.merge({"rounds": 0, "magazine": {}, "attachments": {}})
		"magazine": state.rounds = 0
		"armor": state.wear = 0
	return state

static func whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and float(value) == floorf(float(value))

static func valid(id: String, state: Variant, catalog: Catalog) -> bool:
	if not state is Dictionary or not catalog.items.has(id):
		return false
	var item: ItemDef = catalog.items[id]
	if item.stack_limit != 1:
		return state.is_empty()
	if not state.get("instance_id") is String or state.instance_id.is_empty():
		return false
	if state.has("ammo"):
		if not state.ammo is Array or state.ammo.size() != int(state.get("rounds", -1)):
			return false
		var expected := Ammunition.default_ammo(id, catalog.items)
		for ammo in state.ammo:
			if not ammo is String or Ammunition.caliber(ammo, catalog.items).is_empty() or Ammunition.caliber(ammo, catalog.items) != Ammunition.caliber(expected, catalog.items):
				return false
	if state.has("chamber") and state.chamber != "":
		if not state.chamber is String or not catalog.definitions.get(id) is WeaponDef:
			return false
		if Ammunition.caliber(state.chamber, catalog.items) != catalog.definitions[id].ammo.caliber:
			return false
	match item.kind:
		"weapon":
			if not catalog.definitions[id] is WeaponDef:
				return true
			var gun: WeaponDef = catalog.definitions[id]
			if not whole(state.get("rounds")) or state.rounds > gun.magazine_size or not state.get("magazine") is Dictionary or not state.get("attachments") is Dictionary:
				return false
			if not gun.magazine_id.is_empty() and state.rounds != 0:
				return false
			if not state.magazine.is_empty():
				if state.magazine.get("id") != gun.magazine_id or not valid(gun.magazine_id, state.magazine.get("state"), catalog):
					return false
			for slot in state.attachments:
				var entry: Variant = state.attachments[slot]
				if not entry is Dictionary or not catalog.definitions.get(entry.get("id", "")) is AttachmentDef:
					return false
				var attachment: AttachmentDef = catalog.definitions[entry.id]
				if slot != attachment.slot or not attachment.supports(gun) or not valid(entry.id, entry.get("state"), catalog):
					return false
		"magazine":
			var feed := ArmoryContent.magazine_feed(id)
			if not feed.is_empty() and (not whole(state.get("rounds")) or state.rounds > int(feed.capacity)):
				return false
		"armor":
			if not whole(state.get("wear")) or state.wear > catalog.definitions[id].max_durability:
				return false
	return true

static func ids(state: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if state.has("instance_id"):
		result.append(state.instance_id)
	if state.has("magazine") and not state.magazine.is_empty():
		result.append_array(ids(state.magazine.state))
	for entry in state.get("attachments", {}).values():
		result.append_array(ids(entry.state))
	return result
