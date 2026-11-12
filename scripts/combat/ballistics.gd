class_name Ballistics
extends RefCounted

signal impact(position: Vector3, normal: Vector3, material_id: String, entity_id: String)

func trace(world: World3D, origin: Vector3, direction: Vector3, distance: float, exclude: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * distance, 1, exclude)
	return world.direct_space_state.intersect_ray(query)

func damage(base: float, material: MaterialDef, armor: ArmorDef) -> float:
	var multiplier := material.damage_multiplier if material != null else 1.0
	var reduction := armor.damage_reduction if armor != null else 0.0
	return maxf(0.0, base * multiplier * (1.0 - clampf(reduction, 0.0, 1.0)))
