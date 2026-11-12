class_name ArmorPlates
extends RefCounted

const REGIONS := ["front", "rear", "left", "right"]
const CONDITION_FLOOR := 0.65
const CURVE_WIDTH := 7.0

var definition: ArmorDef
var durability: Dictionary = {}

func _init(armor: ArmorDef) -> void:
	definition = armor
	for region in REGIONS:
		durability[region] = armor.plate_durability if armor.side_plates or region == "front" or region == "rear" else 0.0

func region_for_hit(actor: Node3D, incoming: Vector3) -> String:
	var basis := actor.global_basis if actor.is_inside_tree() else actor.basis
	var local := basis.inverse() * incoming.normalized()
	if local.z < -0.5:
		return "front"
	if local.z > 0.5:
		return "rear"
	return "left" if local.x > 0.0 else "right"

func total_weight() -> float:
	var count := 4 if definition.side_plates else 2
	return definition.carrier_weight + definition.plate_weight * count

func movement_multiplier() -> float:
	return 1.0 - minf(0.4, total_weight() * 0.02)

func impact(actor: Node3D, incoming: Vector3, normal: Vector3, ammo: AmmoDef, damage: float, rng: RandomNumberGenerator) -> Dictionary:
	var region := region_for_hit(actor, incoming)
	if (region == "left" or region == "right") and not definition.side_plates:
		return {"outcome": "unprotected", "damage": damage, "continues": true, "energy": 1.0, "region": region}
	var remaining: float = durability[region]
	if remaining <= 0.0:
		return {"outcome": "unprotected", "damage": damage, "continues": true, "energy": 1.0, "region": region}
	var condition := clampf(remaining / definition.plate_durability, 0.0, 1.0)
	var cosine := clampf(absf(-incoming.normalized().dot(normal.normalized())), 0.5, 1.0)
	var resistance := definition.resistance * (CONDITION_FLOOR + (1.0 - CONDITION_FLOOR) * condition) / cosine
	resistance = minf(resistance, definition.resistance * 2.0)
	var probability := clampf(1.0 / (1.0 + exp((resistance - ammo.penetration) / CURVE_WIDTH)), 0.005, 0.995)
	var outcome := "penetrated"
	var transferred := minf(0.95, 0.75 + 0.25 * ammo.bypass)
	var continues := true
	var energy_fraction := 1.0
	var grazing := absf(incoming.normalized().dot(normal.normalized()))
	var ricochet_chance := definition.ricochet * pow(maxf(0.0, 1.0 - grazing / 0.65), 2.0) * (1.0 - probability)
	if rng.randf() < ricochet_chance:
		outcome = "ricochet"
		transferred = ammo.stopped_damage * 0.2
		energy_fraction = 0.5
	elif rng.randf() >= probability:
		if rng.randf() < 0.2 * 4.0 * probability * pow(1.0 - probability, 2.0):
			outcome = "partial"
			transferred = 0.35
			energy_fraction = 0.35 * 0.35
		else:
			outcome = "stopped"
			transferred = minf(0.08, ammo.stopped_damage)
			continues = false
			energy_fraction = 0.0
	var wear := maxf(0.5, damage * ammo.armor_damage * definition.durability_loss)
	durability[region] = maxf(0.0, remaining - minf(remaining, wear))
	return {"outcome": outcome, "damage": damage * transferred, "continues": continues,
		"energy": energy_fraction, "region": region, "condition": condition, "probability": probability}
