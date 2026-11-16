class_name MedTacCampusValidator
extends RefCounted

## Physical validation of the MedTac Research Campus. Rooms reuse the campus
## clearance/overlap rules; every room must be reachable from its building's
## ground-floor entrance, which proves the stair cores connect every storey.
const SECURITY_ROLES := ["security", "security_ops", "security_monitor", "security_desk", "checkpoint", "bridge_security"]

static func rooms(scene: Node) -> Array[Node]:
	return scene.find_children("*", "Node3D", true, false).filter(func(n): return n.has_meta("room_bounds"))

static func set_vault_links(scene: Node, enabled: bool) -> void:
	for door in scene.find_children("*", "StaticBody3D", true, false):
		if door is RaidDoor and door.restricted:
			var link := door.get_node_or_null(door.traversal_link) as NavigationLink3D
			if link != null: link.enabled = enabled or door.open or door.unlocked

static func on_nav(map: RID, at: Vector3, tolerance := .8) -> bool:
	return NavigationServer3D.map_get_closest_point(map, at).distance_to(at) < tolerance

static func inspect(scene: Node3D) -> Dictionary:
	var errors: Array[String] = []
	var nav: NavigationRegion3D = scene.get_node("NavigationRegion3D")
	var map := nav.get_navigation_map()
	var space := scene.get_world_3d().direct_space_state
	var excluded: Array[RID] = []
	for actor in scene.find_children("*", "CharacterBody3D", true, false): excluded.append(actor.get_rid())
	var door_excluded: Array[RID] = excluded.duplicate()
	for door in scene.find_children("*", "StaticBody3D", true, false):
		if door is RaidDoor: door_excluded.append(door.get_rid())
	var anchors: Dictionary = scene.get_meta("campus_anchors", {})
	var ids: Dictionary = {}
	var checked := 0
	for node in scene.find_children("*", "", true, false):
		if node is Label3D: errors.append("floating text in playable world: " + str(node.get_path()))
		if node is RaidEntity or node is RaidDoor or node is RaidGuard or node is ExtractionZone or node is MedTacBreakable:
			if node.entity_id.is_empty() or ids.has(node.entity_id): errors.append("missing/duplicate entity ID: " + node.entity_id)
			ids[node.entity_id] = true
	set_vault_links(scene, true)
	NavigationServer3D.map_force_update(map)
	for room in rooms(scene):
		checked += 1
		var title: String = room.get_meta("room_purpose")
		var where := "%s %s/%d" % [title, room.get_meta("campus_building"), room.get_meta("campus_floor")]
		var bounds: AABB = room.get_meta("room_bounds")
		if minf(bounds.size.x, bounds.size.z) < 2.5 or bounds.size.x * bounds.size.z < 8: errors.append(where + ": implausible room dimensions")
		var entrances: Array = room.get_meta("entrance_points", [])
		if entrances.is_empty(): errors.append(where + ": no declared entrance"); continue
		var props: Array[Dictionary] = []
		for prop in room.get_children():
			if not prop is Node3D or not prop.has_meta("bounds") or not prop.has_meta("campus_equipment"): continue
			if prop.get_meta("nonsolid", false) or prop.get_meta("supported_by", "floor") != "floor": continue
			var box: AABB = prop.transform * (prop.get_meta("bounds") as AABB)
			if not bounds.grow(.2).encloses(AABB(box.position, Vector3(box.size.x, minf(box.size.y, 3), box.size.z))): errors.append(where + ": equipment outside room: " + str(prop.name))
			for previous: Dictionary in props:
				var overlap := box.intersection(previous.bounds)
				if overlap.size.x > .1 and overlap.size.y > .1 and overlap.size.z > .1: errors.append(where + ": overlapping equipment: " + str(prop.name) + " / " + str(previous.node.name))
			props.append({"node": prop, "bounds": box})
		var center: Vector3 = room.to_global(Vector3(0, .1, 0))
		for opening: Vector3 in entrances:
			var along_x := absf(absf(opening.z) - bounds.size.z * .5) < .6
			var query := PhysicsShapeQueryParameters3D.new(); var shape := BoxShape3D.new()
			shape.size = Vector3(1.1, 2.0, .3); query.shape = shape
			query.transform = room.global_transform * Transform3D(Basis(Vector3.UP, 0.0 if along_x else PI * .5), opening + Vector3.UP * 1.1)
			query.collision_mask = 1; query.exclude = door_excluded
			var blockers := space.intersect_shape(query, 1)
			if not blockers.is_empty(): errors.append(where + ": doorway blocked at " + str(opening) + " by " + str(blockers[0].collider.get_path()))
		# A room is accessible when the route from its entrance (and from the
		# building's ground-floor entrance) ends inside the room on its storey.
		var inside := func(p: Vector3) -> bool: return AABB(bounds.position - Vector3(0, .6, 0), bounds.size + Vector3(0, 1.2, 0)).grow(.1).has_point(room.to_local(p))
		var entry: Vector3 = room.to_global(room.get_meta("entry_local"))
		var route := RaidNavigation.path(map, entry, center)
		if route.is_empty() or not inside.call(route[-1]): errors.append(where + ": entry cannot reach working area")
		var building: String = room.get_meta("campus_building")
		if anchors.has(building):
			var approach := RaidNavigation.path(map, anchors[building], center)
			if approach.is_empty() or not inside.call(approach[-1]): errors.append(where + ": not reachable from the ground-floor entrance")
		# Every searchable container needs a reachable standing point within 1.8 m.
		for source in room.get_children():
			if not source is SearchableFurniture: continue
			var front: Vector3 = source.to_global(source.interaction_offset)
			var stand := RaidNavigation.path(map, entry, front)
			if stand.is_empty() or Vector2(stand[-1].x - front.x, stand[-1].z - front.z).length() > 1.8 or absf(stand[-1].y - front.y) > 2.0: errors.append(where + ": storage cannot be reached: " + source.entity_id)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(center + Vector3.UP * .4, center - Vector3.UP * .4, 1, excluded))
		if hit.is_empty(): errors.append(where + ": unsupported floor")
	for marker in scene.find_children("*", "Marker3D", true, false):
		if not marker.has_meta("route_points"): continue
		var points: PackedVector3Array = marker.get_meta("route_points")
		for i in range(1, points.size()):
			var a: Vector3 = marker.to_global(points[i - 1]); var b: Vector3 = marker.to_global(points[i])
			if not DistrictValidator.reaches(map, a, b, 1.0): errors.append(str(marker.get_path()) + ": broken circulation " + str(a) + " -> " + str(b))
			var delta := b - a
			var samples := maxi(1, ceili(Vector2(delta.x, delta.z).length() / .8))
			for sample in range(samples + 1):
				var query := PhysicsShapeQueryParameters3D.new(); var shape := BoxShape3D.new()
				shape.size = Vector3(float(marker.get_meta("route_width")), 2.0, .2); query.shape = shape
				query.transform = Transform3D(Basis(Vector3.UP, atan2(-delta.x, -delta.z)), a.lerp(b, float(sample) / samples) + Vector3.UP * 1.12)
				query.collision_mask = 1; query.exclude = door_excluded
				var hits := space.intersect_shape(query, 1)
				if not hits.is_empty():
					errors.append(str(marker.get_path()) + ": corridor obstructed at " + str(query.transform.origin) + " by " + str(hits[0].collider.get_path()))
					break
	for stair: Dictionary in scene.get_meta("campus_stairs", []):
		var points: Array = stair.points
		if not DistrictValidator.reaches(map, points[0], points[-1], 1.0):
			var detail := ""
			for i in range(1, points.size()):
				if not DistrictValidator.reaches(map, points[i - 1], points[i], 1.0):
					detail = " (breaks between %s and %s; nav near start %s)" % [points[i - 1], points[i], NavigationServer3D.map_get_closest_point(map, points[i - 1])]
					break
			errors.append("stair %s/%s %d->%d not navigable%s" % [stair.building, stair.core, stair.from, stair.to, detail])
		var overhead := space.intersect_ray(PhysicsRayQueryParameters3D.create(points[-1] + Vector3.UP * .3, points[-1] + Vector3.UP * 2.0, 1, excluded))
		if not overhead.is_empty(): errors.append("stair %s/%s ends under a ceiling at level %d" % [stair.building, stair.core, stair.to])
	var bridge := scene.find_child("Skybridge", true, false) as Node3D
	var bridge_box := AABB()
	if bridge == null: errors.append("skybridge missing")
	else:
		bridge_box = bridge.global_transform * (bridge.get_meta("bridge_bounds") as AABB)
		var ends: Array[Vector3] = [bridge.to_global(Vector3(0, .1, -bridge_box.size.z * .5 - 2.5)), bridge.to_global(Vector3(0, .1, bridge_box.size.z * .5 + 2.5))]
		if not DistrictValidator.reaches(map, ends[0], ends[1], 1.0): errors.append("skybridge does not connect Lab 1 and Lab 2 floor three")
		var under := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(bridge.global_position.x, .2, 12.6), Vector3(bridge.global_position.x, 5.2, 12.6), 1, excluded))
		if not under.is_empty(): errors.append("road clearance under the skybridge is below 5 m")
		for room in rooms(scene):
			if room.get_meta("room_role") not in ["bridge_access", "bridge_security"]: continue
			var path := RaidNavigation.path(map, anchors[room.get_meta("campus_building")], room.to_global(Vector3(0, .1, 0)))
			for p in path:
				if bridge_box.grow(.5).has_point(p): errors.append(str(room.get_meta("campus_building")) + " floor three only reachable over the skybridge"); break
	var starts: Array[Marker3D] = []
	var exits: Array[ExtractionZone] = []
	for node in scene.find_children("*", "", true, false):
		if node is Marker3D and node.is_in_group("raid_spawns"): starts.append(node)
		if node is ExtractionZone: exits.append(node)
	if starts.size() != 7 or exits.size() != 4: errors.append("campus needs 7 insertions and 4 extracts")
	var longest := 0.0
	for start in starts:
		var distances: Array[Dictionary] = []
		for exit in exits:
			var path := RaidNavigation.path(map, start.global_position, exit.global_position)
			if path.is_empty() or path[-1].distance_to(exit.global_position) > 1.5: errors.append("unreachable extract: " + str(start.name) + " -> " + exit.entity_id)
			var length := DistrictValidator.path_length(path); longest = maxf(longest, length)
			distances.append({"id": exit.entity_id, "distance": length})
		distances.sort_custom(func(a, b): return a.distance > b.distance)
		if distances.size() >= 2:
			start.set_meta("assigned_extracts", [distances[0].id, distances[1].id])
			start.set_meta("route_distances", distances)
	for npc in scene.get_children():
		if not npc is RaidGuard: continue
		if not on_nav(map, npc.global_position): errors.append(npc.entity_id + ": spawn is off navigation")
		for p in npc.patrol_points:
			if not DistrictValidator.reaches(map, npc.global_position, p, 1.0): errors.append(npc.entity_id + ": unreachable patrol point " + str(p))
			elif absf(p.y - npc.global_position.y) > 1.0: errors.append(npc.entity_id + ": patrol leaves its floor")
	for entity in scene.find_children("*", "", true, false):
		if entity is SearchableFurniture:
			var room := entity.get_parent()
			var role: String = room.get_meta("room_role", "")
			if entity.loot_profile in ["weapons", "ammo"] and role not in SECURITY_ROLES and entity.get_meta("campus_building", "") != "exterior": errors.append(entity.entity_id + ": weapons outside security storage")
		if entity is RaidLootPickup:
			var parent_y: float = (entity.get_parent() as Node3D).global_position.y
			if entity.global_position.y - parent_y < .5: errors.append(entity.entity_id + ": loose loot on the floor")
	set_vault_links(scene, false)
	NavigationServer3D.map_force_update(map)
	return {"errors": errors, "rooms_checked": checked, "longest_extraction_route_m": longest, "entities": ids.size()}

## Expected loot value per building/floor, in ItemDef value units.
static func loot_report(scene: Node, items: Dictionary, active_fraction: float) -> Dictionary:
	var floors: Dictionary = {}
	for entity in scene.find_children("*", "", true, false):
		if not entity is RaidEntity or not entity.has_meta("loot_tier"): continue
		var key := "%s/%d" % [entity.get_meta("campus_building", "?"), int(entity.get_meta("campus_floor", 1))]
		if not floors.has(key): floors[key] = {"containers": 0, "locked": 0, "empty": 0, "loose": 0, "baseline": 0.0, "locked_bonus": 0.0, "loose_value": 0.0}
		var record: Dictionary = floors[key]
		if entity is SearchableFurniture:
			var value := CampusLoot.container_value(entity, items)
			if entity.locked: record.locked += 1; record.locked_bonus += value; continue
			record.containers += 1
			if entity.starts_empty: record.empty += 1
			record.baseline += value
		elif entity is RaidLootPickup:
			record.loose += 1
			record.loose_value += CampusLoot.item_value(items, entity.item_id) * active_fraction
	var labs: Dictionary = {}
	for level in range(1, 5):
		var total := 0.0
		for building in ["lab1", "lab2"]:
			var key := "%s/%d" % [building, level]
			if floors.has(key): total += floors[key].baseline + floors[key].loose_value
		labs[str(level)] = total
	var base: float = maxf(labs["1"], .001)
	var ratios: Dictionary = {}
	for level: String in labs: ratios[level] = snappedf(labs[level] / base, .01)
	var zero_value: Array[String] = []
	for id: String in items:
		if CampusLoot.item_value(items, id) <= 0 and items[id].get("kind") in ["medical", "food", "tool", "item"]: zero_value.append(id)
	return {"floors": floors, "lab_floor_value": labs, "lab_floor_ratio": ratios, "targets": CampusLoot.config().targets, "zero_value_items": zero_value}
