class_name ArmorPlates
extends RefCounted

# Name retained for scene compatibility; all gameplay now uses Minecraft equipment.
var definition: ArmorDef
var entries: Dictionary = {}
var definitions: Dictionary = {}
var durability: Dictionary = {"front": 0, "rear": 0, "left": 0, "right": 0}

func _init(armor: ArmorDef = null) -> void:
	definition = armor
	if armor != null and armor.max_durability > 0:
		definitions[armor.id] = armor
		entries[armor.slot] = {"id": armor.id, "state": {"wear": 0}}

func points() -> float:
	var total := 0.0
	for entry in entries.values():
		var armor: ArmorDef = definitions[entry.id]
		if armor.max_durability == 0 or int(entry.state.wear) < armor.max_durability:
			total += armor.points
	return total

func toughness() -> float:
	var total := 0.0
	for entry in entries.values():
		var armor: ArmorDef = definitions[entry.id]
		if armor.max_durability > int(entry.state.wear):
			total += armor.toughness
	return total

func knockback_multiplier() -> float:
	var resistance := 0.0
	for entry in entries.values():
		var armor: ArmorDef = definitions[entry.id]
		if armor.max_durability > int(entry.state.wear):
			resistance += armor.knockback_resistance
	return 1.0 - clampf(resistance, 0.0, 1.0)

static func reduce(damage: float, armor: float, tough: float) -> float:
	var effective := clampf(armor - damage / (2.0 + tough / 4.0), armor * 0.2, 20.0)
	return maxf(0.0, damage * (1.0 - effective / 25.0))

func absorb(damage: float, wear: bool = true) -> float:
	# Vanilla damages equipment before calculating remaining protection.
	if wear:
		for entry in entries.values():
			var armor: ArmorDef = definitions[entry.id]
			if armor.max_durability > 0:
				entry.state.wear = mini(armor.max_durability, int(entry.state.wear) + maxi(1, int(damage / 4.0)))
	return reduce(damage, points(), toughness())

func movement_multiplier() -> float:
	return 1.0

func total_weight() -> float:
	return 0.0

func impact(_actor: Node3D, _incoming: Vector3, _normal: Vector3, _ammo: AmmoDef, damage: float, _rng: RandomNumberGenerator) -> Dictionary:
	return {"outcome": "armored", "damage": absorb(damage), "continues": false, "energy": 0.0}
