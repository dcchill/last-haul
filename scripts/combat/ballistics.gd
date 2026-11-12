class_name Ballistics
extends RefCounted

signal impact(position: Vector3, normal: Vector3, material_id: String, entity_id: String)

func make_projectile(origin: Vector3, direction: Vector3, ammo: AmmoDef, velocity: float, spread: float, max_range: float, seed: int, exclude: Array[RID]) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var right := direction.normalized().cross(Vector3.UP).normalized()
	if right.is_zero_approx():
		right = Vector3.RIGHT
	var up := right.cross(direction.normalized()).normalized()
	var shot_direction := (direction.normalized() + right * rng.randf_range(-spread, spread) + up * rng.randf_range(-spread, spread)).normalized()
	var shot_velocity := shot_direction * velocity
	return {"position": origin, "velocity": shot_velocity, "energy": energy(ammo.mass_kg, velocity),
		"initial_energy": energy(ammo.mass_kg, velocity), "ammo": ammo, "range": max_range,
		"traveled": 0.0, "rng": rng, "exclude": exclude.duplicate(), "ricochets": 0}

func energy(mass: float, speed: float) -> float:
	return 0.5 * mass * speed * speed

func speed_for_energy(mass: float, joules: float) -> float:
	return sqrt(2.0 * maxf(0.0, joules) / mass)

func velocity_after_forces(velocity: Vector3, ammo: AmmoDef, delta: float) -> Vector3:
	var speed := velocity.length()
	return velocity / (1.0 + ammo.drag * speed * delta) + Vector3.DOWN * 9.81 * ammo.gravity * delta

func projectile_damage(projectile: Dictionary, material: MaterialDef) -> float:
	var ammo: AmmoDef = projectile.ammo
	var retained := sqrt(clampf(projectile.energy / projectile.initial_energy, 0.0, 1.0))
	return maxf(0.0, ammo.damage * retained * (material.damage_multiplier if material != null else 1.0))

func trace(world: World3D, origin: Vector3, direction: Vector3, distance: float, exclude: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * distance, 1, exclude)
	return world.direct_space_state.intersect_ray(query)
