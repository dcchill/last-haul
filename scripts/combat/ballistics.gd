class_name Ballistics
extends RefCounted

signal impact(position: Vector3, normal: Vector3, material_id: String, entity_id: String)

static func shoot(direction: Vector3, speed: float, spread: float, rng: RandomNumberGenerator) -> Vector3:
	var deviation := 0.0172275 * spread
	return (direction.normalized() + Vector3((rng.randf() - rng.randf()) * deviation, (rng.randf() - rng.randf()) * deviation, (rng.randf() - rng.randf()) * deviation)) * speed

func make_bullet(origin: Vector3, direction: Vector3, speed: float, spread: float, damage: float, head_multiplier: float, seed_value: int, exclude: Array[RID], kind: String = "bullet") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return {"position": origin, "previous": origin, "velocity": shoot(direction, speed, spread, rng), "damage": damage,
		"head_multiplier": head_multiplier, "age": 0, "exclude": exclude.duplicate(), "kind": kind, "rng": rng}

static func advance(projectile: Dictionary) -> void:
	projectile.previous = projectile.position
	projectile.position += projectile.velocity
	projectile.age += 1
	projectile.velocity = projectile.velocity * (0.999 if projectile.kind == "bullet" else 0.99) + Vector3.DOWN * (0.015 if projectile.kind == "bullet" else 0.05)

func trace(world: World3D, origin: Vector3, direction: Vector3, distance: float, exclude: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * distance, 1, exclude)
	query.hit_from_inside = true
	return world.direct_space_state.intersect_ray(query)

static func headshot(target: Node3D, point: Vector3) -> bool:
	var eye: float = target.eye_position().y if target is RaidPlayer else target.global_position.y + 1.62
	return point.y >= eye - 0.18
