class_name CampusLoot
extends RefCounted

## Floor-tier loot for the MedTac Research Campus. Tiers only reweight existing
## items inside each container family; ItemDef values are read, never changed.
const PATH := "res://resources/campus/loot_tiers.json"
static var _data: Dictionary = {}

static func config() -> Dictionary:
	if _data.is_empty(): _data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data

static func tier_data(tier: int) -> Dictionary:
	return config().tiers[str(clampi(tier, 1, 4))]

static func table(profile: String, tier: int, items: Dictionary = {}, config_def: ContainerDef = null) -> LootTable:
	var data := tier_data(tier)
	var result := LootTable.new()
	result.rolls = Vector2i(int(data.rolls[0]), int(data.rolls[1]))
	for entry: Array in config().profiles[profile]:
		var id: String = entry[0]
		if not items.is_empty():
			if not items.has(id): continue
			if config_def != null and not allowed(items[id], config_def): continue
		var weight := float(entry[1]) * float(data.weights.get(id, 1.0))
		if weight <= 0: continue
		result.entries.append({"id": id, "weight": snappedf(weight, .001), "min": 1, "max": int(entry[2])})
	return result

static func allowed(definition: Resource, config_def: ContainerDef) -> bool:
	var kind: String = definition.get("kind") if definition.get("kind") != null else "item"
	if not config_def.allowed_categories.is_empty() and not config_def.allowed_categories.has(kind): return false
	return not config_def.prohibited_categories.has(kind)

static func item_value(items: Dictionary, id: String) -> float:
	if not items.has(id): return 0.0
	var value = items[id].get("value")
	return float(value) if value != null else 0.0

## Analytic expected value of one container's contents in ItemDef value units.
static func table_value(loot: LootTable, items: Dictionary) -> float:
	if loot == null or loot.entries.is_empty(): return 0.0
	var total := 0.0
	var each := 0.0
	for entry in loot.entries:
		total += float(entry.weight)
		each += float(entry.weight) * item_value(items, entry.id) * (int(entry.get("min", 1)) + int(entry.get("max", 1))) * .5
	return 0.0 if total <= 0 else (loot.rolls.x + loot.rolls.y) * .5 * each / total

static func container_value(entity: Node, items: Dictionary) -> float:
	if entity.get("starts_empty") == true: return 0.0
	var value := 0.0
	for id: String in entity.guaranteed_items: value += item_value(items, id) * int(entity.guaranteed_items[id])
	return value + table_value(entity.loot_table, items)

static func loose_items(tier: int) -> Array:
	return config().loose[str(clampi(tier, 1, 4))]
