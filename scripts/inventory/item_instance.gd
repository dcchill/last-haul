class_name ItemInstance
extends RefCounted

# Runtime dictionaries preserve the existing stash API; storage is serialized separately.
static func create(definition: ItemDef, definitions: Dictionary, quantity: int = 1) -> Dictionary:
	var entry := {"id": definition.id, "uid": ProfileStore._new_id(), "quantity": quantity,
		"x": 0, "y": 0, "rotated": false, "condition": 1.0,
		"durability": definition.max_durability, "attachments": [], "metadata": {}}
	entry.state = ArmoryInstance.fresh(definition.id, definitions)
	if definition.container != null:
		var config: ContainerDef = definition.container
		entry.storage = RaidInventory.new(definitions, config.dimensions.x, config.dimensions.y)
		entry.storage.configure(config)
	return entry

static func compatible(a: Dictionary, b: Dictionary) -> bool:
	return a.id == b.id and not a.has("storage") and not b.has("storage") \
		and a.get("condition", 1.0) == b.get("condition", 1.0) \
		and a.get("durability", 100.0) == b.get("durability", 100.0) \
		and a.get("attachments", []) == b.get("attachments", []) \
		and a.get("metadata", {}) == b.get("metadata", {}) \
		and a.get("state", {}) == b.get("state", {})

static func weight(entry: Dictionary, definitions: Dictionary) -> float:
	var total: float = definitions[entry.id].weight * int(entry.quantity)
	if entry.has("storage"):
		total += entry.storage.total_weight()
	for attachment in entry.get("attachments", []):
		if attachment is Dictionary and definitions.has(attachment.get("id", "")):
			total += weight(attachment, definitions)
	return total

static func contains(entry: Dictionary, target: RaidInventory) -> bool:
	if not entry.has("storage"):
		return false
	if entry.storage == target:
		return true
	for child in entry.storage.slots:
		if contains(child, target):
			return true
	return false
