extends RefCounted

func run(suite: SceneTree) -> bool:
	var raid: RaidAuthority = load("res://scenes/raid/test_yard.tscn").instantiate()
	suite.root.add_child(raid)
	raid.deploy("hybrid-player", suite.catalog, SettingsStore.new(), {"practice": true})
	raid.set_physics_process(false)
	raid.player.set_physics_process(false)
	raid.player.accepts_local_input = false
	var origin := Vector3(0, 60, 0)
	var target := RaidEntity.new()
	target.entity_id = "hybrid-target"
	target.material = suite.catalog.definitions.steel
	var shape := BoxShape3D.new()
	shape.size = Vector3(2, 2, 0.2)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	target.add_child(collision)
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	mesh.mesh = BoxMesh.new()
	target.add_child(mesh)
	raid.add_child(target)
	for distance in [10.0, 20.0, 20.2, 35.0]:
		target.global_position = origin + Vector3.FORWARD * (distance + 0.1)
		await suite.physics_frame
		await suite.physics_frame
		raid.projectiles.clear()
		target.health = 1000
		var bullet := raid._spawn_projectile(origin, Vector3.FORWARD, 9, 0, 25, 1.5, raid.player.get_rid(), "bullet", "five_five_six")
		if distance <= 20.0:
			suite.check(target.health == 975 and raid.projectiles.is_empty(), "instant hit at %s meters applies once" % distance)
		else:
			suite.check(target.health == 1000 and raid.projectiles.size() == 1, "distant hit waits for travel at %s meters" % distance)
			suite.check(bullet.position.is_equal_approx(origin + Vector3.FORWARD * 20) and bullet.ammo_id == "five_five_six" and bullet.source_entity_id == "hybrid-player", "continuation retains boundary and shot metadata")
			for tick in range(5):
				if not raid._step_projectile(bullet): break
			suite.check(target.health == 975, "projectile contact damages exactly once")
			suite.check(bullet.position.z > target.global_position.z, "projectile ends on near face of thin cover")
	# The same sweep must choose cover before the inflated humanoid bounds.
	target.global_position = origin + Vector3.FORWARD * 5
	raid.player.global_position = origin + Vector3.FORWARD * 10 - Vector3.UP
	await suite.physics_frame
	await suite.physics_frame
	var health: float = raid.participants["hybrid-player"].health
	raid._spawn_projectile(origin, Vector3.FORWARD, 9, 0, 25, 1.5, RID())
	suite.check(raid.participants["hybrid-player"].health == health, "near cover blocks humanoid hits")
	target.global_position.x += 10
	await suite.physics_frame
	await suite.physics_frame
	raid._spawn_projectile(origin, Vector3.FORWARD, 9, 0, 25, 1.5, RID())
	suite.check(raid.participants["hybrid-player"].health < health, "unobstructed hitscan damages humanoid")
	var state: RaidParticipant = raid.participants["hybrid-player"]
	state.equipment.slots.body_armor.slots.assign([PlateInventory.loaded("carrier_single", "plate_steel", suite.catalog.items)])
	state.refresh_armor(suite.catalog)
	state.health = 200
	var head_origin := Vector3(0, raid.player.eye_position().y, 0)
	raid._spawn_projectile(head_origin, Vector3.FORWARD, 9, 0, 10, 2, RID(), "bullet", "five_five_six")
	suite.check(state.health == 180 and state.armor.active_plate().state.wear == 0, "instant headshot applies multiplier and bypasses armor")
	state.health = 200
	var torso_origin := Vector3(0, raid.player.global_position.y + 1.0, 0)
	raid._spawn_projectile(torso_origin, Vector3.FORWARD, 9, 0, 100, 2, RID(), "bullet", "five_five_six_ap")
	suite.check(is_equal_approx(state.health, 136) and is_equal_approx(state.armor.active_plate().state.wear, 36), "instant torso hit retains ammunition bypass and armor wear")
	var friendly: RaidGuard = load("res://scenes/npcs/guard.tscn").instantiate()
	friendly.entity_id = "hybrid-friendly"
	raid.add_child(friendly)
	raid.npcs.append(friendly)
	raid.entities[friendly.entity_id] = friendly
	friendly.global_position = Vector3(30, 60, -10)
	await suite.physics_frame
	await suite.physics_frame
	health = friendly.health
	var blocked := raid._spawn_projectile(Vector3(30, 61, 0), Vector3.FORWARD, 9, 0, 25, 2, raid.guard.get_rid())
	suite.check(friendly.health == health and not raid.projectiles.has(blocked), "friendly NPC blocks instant bullet without taking damage")
	raid.projectiles.clear()
	var inherited := Vector3(0.2, 0, 0)
	var moving := raid._spawn_projectile(origin, Vector3.FORWARD, 9, 0, 25, 1.5, raid.player.get_rid(), "bullet", "five_five_six", inherited)
	suite.check(moving.velocity == Vector3.FORWARD * 9 + inherited and moving.position.is_equal_approx(origin + moving.velocity.normalized() * 20), "inherited movement finalized before hitscan")
	var rocket := raid._spawn_projectile(origin, Vector3.FORWARD, 4, 0, 25, 1, raid.player.get_rid(), "rocket")
	suite.check(rocket.position == origin and rocket.age == 0, "rockets retain original projectile launch")
	suite.check(Ballistics.tracer_opacity(19) == 0 and Ballistics.tracer_opacity(20) == 0 and is_equal_approx(Ballistics.tracer_opacity(22.5), 0.35) and is_equal_approx(Ballistics.tracer_opacity(25), 0.7), "tracer fades in only over meters 20 to 25")
	var steel: MaterialDef = suite.catalog.definitions.steel
	suite.check(Ballistics.can_ricochet(steel, Vector3.UP, Vector3(1, -0.1, 0)) and not Ballistics.can_ricochet(steel, Vector3.UP, Vector3.DOWN) and not Ballistics.can_ricochet(null, Vector3.UP, Vector3.RIGHT), "ricochet requires known hard surface and grazing angle")
	var presenter: Node3D = raid.get_node("ImpactPresenter")
	var rng_state: int = moving.rng.state
	var count := presenter.get_child_count()
	presenter.muzzle_flash(origin, Vector3.FORWARD, true)
	suite.check(presenter.get_child_count() == count, "suppression hides muzzle flash and light")
	presenter.muzzle_flash(origin, Vector3.FORWARD, false)
	suite.check(presenter.get_child_count() == count + 1, "discharge creates one flash group")
	var serial := raid.projectile_serial
	health = target.health
	presenter.ricochet(origin, Vector3.UP, Vector3(1, -0.1, 0).normalized())
	suite.check(raid.projectile_serial == serial and target.health == health, "ricochet effects cannot spawn damaging bullets")
	suite.check(moving.rng.state == rng_state, "presentation leaves gameplay RNG unchanged")
	presenter.present(origin, Vector3.UP, "unknown", "")
	await suite.create_timer(0.5).timeout
	suite.check(presenter.get_child_count() == 0, "muzzle and impact effects clean up")
	raid.free()
	return true
