class_name ArmorPlates
extends RefCounted

var definition: ArmorDef
var entries: Dictionary = {}
var definitions: Dictionary = {}

func _init(armor: ArmorDef = null) -> void:
	definition = armor
	if armor != null:
		definitions[armor.id] = armor
		var state := {"plates": []}
		for slot in range(armor.plate_slots): state.plates.append({})
		entries[armor.slot] = {"id": armor.id, "state": state}

func active_plate() -> Dictionary:
	for entry in entries.values():
		for plate in entry.state.get("plates", []):
			if not plate.is_empty(): return plate
	return {}

func protection() -> float:
	var plate := active_plate()
	return definitions[plate.id].reduction if not plate.is_empty() else 0.0

func knockback_multiplier() -> float:
	return 1.0

func absorb(damage: float, wear := true, bypass := 0.0) -> float:
	var eligible := maxf(0.0, damage) * (1.0 - clampf(bypass, 0.0, 1.0))
	for entry in entries.values():
		var plates: Array = entry.state.get("plates", [])
		for slot in range(plates.size()):
			var plate: Dictionary = plates[slot]
			if plate.is_empty(): continue
			var material: PlateDef = definitions[plate.id]
			var blocked := minf(eligible * material.reduction, material.capacity - float(plate.state.wear))
			if wear:
				plate.state.wear += blocked
				if plate.state.wear >= material.capacity: plates[slot] = {}
			return maxf(0.0, damage - blocked)
	return maxf(0.0, damage)

func movement_multiplier() -> float:
	var cost := 0.0
	for entry in entries.values():
		for plate in entry.state.get("plates", []):
			if not plate.is_empty(): cost += definitions[plate.id].movement_cost
	return 1.0 - minf(0.09, cost)

func total_weight() -> float:
	var total := 0.0
	for entry in entries.values():
		var armor: ArmorDef = definitions[entry.id]
		total += armor.carrier_weight if armor.plate_slots > 0 else 0.0
		for plate in entry.state.get("plates", []):
			if not plate.is_empty(): total += definitions[plate.id].weight
	return total

func summary() -> String:
	var count := 0
	var slots := 0
	for entry in entries.values():
		for plate in entry.state.get("plates", []):
			slots += 1
			if not plate.is_empty(): count += 1
	return "%d/%d plates, %.0f%% protection" % [count, slots, protection() * 100]

func impact(_actor: Node3D, _incoming: Vector3, _normal: Vector3, ammo: AmmoDef, damage: float, _rng: RandomNumberGenerator) -> Dictionary:
	return {"outcome": "armored", "damage": absorb(damage, true, ammo.bypass if ammo != null else 0.0), "continues": false, "energy": 0.0}
