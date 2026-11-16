extends RefCounted

## MedTac pharmaceutical distribution building. The 78 x 42 m high-bay hall is
## authored in world coordinates; the two-storey L-wing (offices and staff
## facilities) uses the shared floor machinery with its north wall as a party
## wall that the hall builds, including the wing's connecting doors.
const HALL := Rect2(-91, -68.3, 78.4, 41.9)
const HALL_HEIGHT := 10.0
const DOCKS := [-45.0, -39.0, -33.0, -27.0, -21.0, -15.0]
const OPEN_DOCKS := [-45.0, -27.0, -15.0]

static func R(title: String, x0: float, z0: float, x1: float, z1: float, role: String, doors: Array, extra := {}) -> Dictionary:
	var result := {"name": title, "rect": Rect2(x0, z0, x1 - x0, z1 - z0), "role": role, "doors": doors}
	result.merge(extra)
	return result

## Wing-local coordinates are world + (70, 0, 15).
static func wing() -> Dictionary:
	return {
		"id": "distribution_wing", "title": "Distribution offices", "origin": Vector3(-70, 0, -15), "bounds": Rect2(-21, -11.4, 42.7, 22.4), "style": "office", "party": ["n"],
		"cores": [{"kind": "stair", "id": "WingStair", "rect": Rect2(14, -11.4, 4.4, 9), "landing": "s", "top": 2}],
		"corridors": [{"points": PackedVector2Array([Vector2(-20.4, -.9), Vector2(21.1, -.9)]), "width": 3.0, "check": 1.2}],
		"levels": [
			{"floor": 1, "tier": 1, "title": "Dispatch and Staff Facilities", "floor_key": "concrete", "rooms": [
				R("Cold-chain storage", -21, -11.4, -8, -2.4, "dist_cold", ["s:-14:door", "n:-14:door"]),
				R("Maintenance workshop", -8, -11.4, 4, -2.4, "workshop", ["s:-2:door", "n:-2:open:3"]),
				R("Forklift charging bay", 4, -11.4, 14, -2.4, "charging", ["s:9:door", "n:9:open:3"]),
				R("Dock supervisor", 18.4, -11.4, 21.7, -2.4, "office", ["s:20:door"]),
				R("Reception and dispatch", -21, .6, -8, 11, "dispatch_reception", ["n:-14:open:3", "s:-14:extdoor"]),
				R("Staff lockers", -8, .6, 0, 11, "changing", ["n:-4:door"]),
				R("Warehouse restrooms", 0, .6, 6, 11, "restroom", ["n:3:door"]),
				R("Warehouse break room", 6, .6, 16, 11, "breakroom", ["n:11:door"], {"fire": true}),
				R("Warehouse first aid", 16, .6, 21.7, 11, "firstaid", ["n:19:door"]),
			], "facade_doors": [{"side": "w", "pos": -.9, "kind": "extdoor", "width": 2.0}, {"side": "e", "pos": -.9, "kind": "extdoor", "width": 2.0}],
			"story": [["papers", Vector2(-14, 4), 10], ["stain", Vector2(5, -.9), 1.0]],
			"encounters": []},
			{"floor": 2, "tier": 2, "title": "Warehouse Offices and Security", "floor_key": "carpet", "rooms": [
				R("Warehouse offices", -21, -11.4, -5, -2.4, "openoffice", ["s:-13:door"]),
				R("Shipping records", -5, -11.4, 4, -2.4, "records", ["s:0:door"]),
				R("IT and server room", 4, -11.4, 14, -2.4, "server", ["s:9:door"]),
				R("Upper electrical cupboard", 18.4, -11.4, 21.7, -2.4, "riser", ["s:20:door"]),
				R("Security monitoring", -21, .6, -10, 11, "security_monitor", ["n:-15.5:door"]),
				R("Logistics manager", -10, .6, 0, 11, "office", ["n:-5:door"]),
				R("Training room", 0, .6, 12, 11, "meeting", ["n:6:door"]),
				R("Kitchenette", 12, .6, 21.7, 11, "kitchen", ["n:17:door"]),
			], "story": [["papers", Vector2(-8, -.9), 12], ["camp", Vector2(6, 6), PI]],
			"encounters": [["scav", Vector2(-15.5, 5), [Vector2(-15.5, 5), Vector2(-15.5, -.9), Vector2(0, -.9)]]]},
		],
	}

static func build_hall(k) -> void:
	k.building_id = "distribution"; k.floor_index = 1; k.tier = 1
	k.lines.clear(); k.facade_cuts.clear(); k.floor_rooms.clear()
	k.plan = {"id": "distribution", "bounds": HALL}
	var node: Node3D = k.section("Building_distribution", Vector3.ZERO)
	node.set_meta("building_id", "distribution"); node.set_meta("enterable", true)
	node.set_meta("building_bounds", AABB(Vector3(HALL.position.x, 0, HALL.position.y), Vector3(HALL.size.x, HALL_HEIGHT, HALL.size.y)))
	node.set_meta("building_title", "Distribution hall")
	node.set_meta("campus_floor", 1); node.set_meta("loot_tier", 1); node.set_meta("campus_building", "distribution")
	k.building_nodes.append(node)
	var footprint := PackedVector2Array()
	for p in k.polygon(HALL): footprint.append(p)
	k.building_footprints.append(footprint)
	k.split_scenes.append({"node": node, "path": "res://scenes/raid/campus/distribution/hall.tscn"})
	var solid_floor: Array[Rect2] = []
	k.foundation(node, HALL, 0, solid_floor, "concrete")
	# Interior enclosed rooms are 4 m boxes inside the high bay.
	for spec: Dictionary in [
		R("Walk-in cold store", -91, -68.3, -75, -56.3, "dist_cold", ["s:-77.5:door"]),
		R("Equipment and charging cage", -75, -68.3, -63, -58.3, "charging", ["s:-69:open:3"]),
		R("Warehouse security office", -24, -68.3, -12.6, -58.3, "security_monitor", ["w:-63:door", "s:-18:door"], {"tier": 2}),
		R("Hazardous goods store", -91, -56.3, -80, -46.3, "chemstore", ["e:-51:door"]),
		R("Goods-in inspection", -91, -46.3, -80, -38, "receipt", ["e:-42:door"]),
	]:
		var room: Node3D = k.plan_room(node, spec)
		var r: Rect2 = spec.rect
		k.box(room, Vector3(0, 4.02 + .08, 0), Vector3(r.size.x + .2, .16, r.size.y + .2), "concrete")
	var walls: Node3D = k.section("InteriorWalls", Vector3.ZERO, node)
	k.build_walls(walls, HALL, "panel")
	perimeter(k, node)
	racks(k, node)
	receiving(k, node)
	roof(k, node)
	k.area_log.append_array([
		{"name": "Pallet storage aisles", "building": "distribution", "floor": 1},
		{"name": "Receiving and loading docks", "building": "distribution", "floor": 1},
		{"name": "Shipping preparation", "building": "distribution", "floor": 1},
		{"name": "Scavenger camp", "building": "distribution", "floor": 1},
	])
	for spec: Array in [["scav", Vector2(-29, -63), [Vector2(-29, -63), Vector2(-33, -57), Vector2(-26, -56)]], ["scav", Vector2(-32, -33), [Vector2(-32, -33), Vector2(-20, -33), Vector2(-40, -36)]], ["infected", Vector2(-83, -62), [Vector2(-83, -62), Vector2(-80, -60), Vector2(-86, -60)]]]:
		var patrol: Array[Vector3] = []
		for p: Vector2 in spec[2]: patrol.append(Vector3(p.x, .1, p.y))
		k.encounter_specs.append({"kind": spec[0], "building": "distribution", "floor": 1, "at": Vector3(spec[1].x, .1, spec[1].y), "patrol": patrol})

static func perimeter(k, node: Node3D) -> void:
	var shell: Node3D = k.section("HallShell", Vector3.ZERO, node)
	var west := HALL.position.x; var east := HALL.end.x; var north := HALL.position.y; var south := HALL.end.y
	# Hall side cuts: [center, width, kind, height].
	var sides := {
		"n": {"h": true, "c": north, "a": west, "b": east, "cuts": [[-70.0, 2.0, "extdoor"], [-30.0, 2.0, "extdoor"]], "out": Vector3.FORWARD},
		"e": {"h": false, "c": east, "a": north, "b": south, "cuts": [[-40.0, 2.0, "extdoor"]], "out": Vector3.RIGHT},
		"w": {"h": false, "c": west, "a": north, "b": south, "cuts": [], "out": Vector3.LEFT},
		"s": {"h": true, "c": south, "a": west, "b": east, "cuts": [], "out": Vector3.BACK},
	}
	for x: float in DOCKS: sides.s.cuts.append([x, 3.2, "dock"])
	# Wing doors on the shared wall come from the wing's ground-floor plan.
	for cut: Dictionary in k.party_cuts:
		if cut.building == "distribution_wing" and cut.floor == 1: sides.s.cuts.append([cut.world, cut.width, "open" if cut.kind == "open" else "door"])
	for id: String in sides:
		var side: Dictionary = sides[id]
		var openings: Array = []
		for cut: Array in side.cuts: openings.append(Vector2(cut[0] - cut[1] * .5, cut[0] + cut[1] * .5))
		for piece: Vector2 in k.subtract([Vector2(side.a, side.b)], openings):
			k.wall_box(shell, side.h, side.c, piece.x, piece.y, 0, HALL_HEIGHT, "corrugated", .3)
		for cut: Array in side.cuts:
			var head := 3.0 if cut[2] == "dock" else 2.4
			k.wall_box(shell, side.h, side.c, cut[0] - cut[1] * .5, cut[0] + cut[1] * .5, head, HALL_HEIGHT, "corrugated", .3)
			var at := Vector3(cut[0], 0, side.c) if side.h else Vector3(side.c, 0, cut[0])
			match cut[2]:
				"extdoor", "door": k.make_door(shell, at, side.h, cut[1], "extdoor" if cut[2] == "extdoor" else "door", -side.out)
				"dock":
					k.box(shell, at - side.out * 1.2 + Vector3.UP * .064, Vector3(3.0, .008, 2.2), "warning", false)
					for s in [-1, 1]: k.box(shell, at + side.out * .6 + Vector3(s * 1.8, .5, 0), Vector3(.25, 1.0, .25), "warning")
					if not cut[0] in OPEN_DOCKS:
						var shape := BoxShape3D.new(); shape.size = Vector3(3.2, 3.0, .3)
						k.collider(shell, at + Vector3.UP * 1.5, shape, "steel")
						k.place(shell, "e:023:%d" % (0 if int(cut[0]) % 2 == 0 else 1), at + side.out * .02, k.front_yaw("e:x", side.out), false)
					else:
						k.box(shell, at + Vector3.UP * 2.75, Vector3(3.0, .45, .32), "steel", false)
		# Clerestory glazing and ivy keep the long corrugated walls readable.
		var length: float = side.b - side.a
		for i in int(length / 8.0):
			var mid: float = side.a + 4 + i * 8
			var at := Vector3(mid, 7.8, side.c) if side.h else Vector3(side.c, 7.8, mid)
			k.box(shell, at + side.out * .17, Vector3(5.2, 1.1, .05) if side.h else Vector3(.05, 1.1, 5.2), "glass", false)
			if k.rng.randf() < .35: k.box(shell, Vector3(at.x, k.rng.randf_range(1.5, 3.5), at.z) + side.out * .2, Vector3(1.0, k.rng.randf_range(3, 7), .08) if side.h else Vector3(.08, k.rng.randf_range(3, 7), 1.0), "ivy", false)
	# Upper wing offices overlook the hall through the shared wall.
	for span in [Vector2(-90, -76), Vector2(-74, -67)]:
		k.box(shell, Vector3((span.x + span.y) * .5, 5.9, south - .17), Vector3(span.y - span.x, 1.4, .05), "glass", false)
	k.printed_sign(shell, "distribution_sign", Vector3(-30, 6.2, south + .2), 0.0, 8.0)

static func racks(k, node: Node3D) -> void:
	var hall: Node3D = k.section("RackAisles", Vector3.ZERO, node)
	var rows := [[-52.5, [-71.5, -61.0, -45.0, -34.5, -24.0]], [-44.0, [-71.5, -61.0, -45.0, -34.5, -24.0]], [-61.5, [-50.7, -40.1]]]
	for row: Array in rows:
		for x: float in row[1]:
			k.place(hall, "m:pallet_rack", Vector3(x, 0, row[0]), 0.0)
			k.cover_marker(hall, Vector3(x + 5.6, .1, row[0]), PI * .5)
	# Floor-level cargo in the aisles: medical shipments, tools and electronics.
	var sources := [["m:shipping_crate", Vector2(-66, -48.3)], ["e:175:0", Vector2(-56, -48.4)], ["m:cold_chain_crate", Vector2(-40, -48.2)], ["e:172:1", Vector2(-29, -48.3)],
		["e:188:1", Vector2(-66, -57.2)], ["m:shipping_crate", Vector2(-45, -57.4)], ["e:171:1", Vector2(-56, -40.0)], ["e:179:0", Vector2(-20, -40.0)],
		["e:191:0", Vector2(-70, -40.2)], ["e:175:2", Vector2(-38, -40.2)]]
	for item: Array in sources:
		k.make_source(hall, item[0], Vector3(item[1].x, 0, item[1].y), 0.0)
	for at: Vector2 in [Vector2(-77.5, -48), Vector2(-50, -48.6), Vector2(-60, -56.8), Vector2(-24, -56.6), Vector2(-33, -40.4)]:
		k.place(hall, "m:wrapped_pallet", Vector3(at.x, 0, at.y), k.rng.randf() * .3)
	k.place(hall, "e:167:1", Vector3(-53.5, 0, -48), PI * .5)
	k.place(hall, "m:pallet_jack", Vector3(-38.0, 0, -57.2), .3)
	for i in 6: k.flat(hall, Vector3(-80 + i * 11, .064, -48.3), Vector3(.15, .01, 3.0) if i % 2 == 0 else Vector3(9.5, .01, .15), "warning")
	# Scavenger camp tucked between the north racks and the security office.
	k.dresser.story(k, hall, ["camp", Vector2(-29, -64.5), 0.0])
	k.make_source(hall, "e:132:1", Vector3(-31.5, 0, -60.2), PI)
	k.make_source(hall, "e:140:2", Vector3(-26.5, 0, -60.4), PI)
	k.place(hall, "e:127:1", Vector3(-33, 0, -65.5), .4)
	k.place(hall, "e:131:2", Vector3(-28.5, 0, -61.8), 0.0, false)
	k.place(hall, "e:129:0", Vector3(-35.5, 0, -58.8), PI * .5)
	k.place(hall, "e:136:0", Vector3(-25.5, 0, -65.8), PI)

static func receiving(k, node: Node3D) -> void:
	var zone: Node3D = k.section("ReceivingDocks", Vector3.ZERO, node)
	for i in 3:
		var table: Node3D = k.place(zone, "m:packing_table", Vector3(-62 + i * 7, 0, -34), 0.0)
		var top: AABB = table.get_meta("bounds")
		k.tier = 1
		k.loose(zone, table.transform * Vector3(0, top.end.y + .01, 0))
		k.place(zone, "m:roll_cage", Vector3(-62 + i * 7, 0, -36.2), 0.0)
	for x in [-52.0, -46.0]: k.place(zone, "m:conveyor", Vector3(x, 0, -31.5), 0.0)
	for at: Vector2 in [Vector2(-45, -29.5), Vector2(-33, -30), Vector2(-21, -29.4)]:
		k.place(zone, "m:wrapped_pallet", Vector3(at.x, 0, at.y), 0.0)
		k.cover_marker(zone, Vector3(at.x + 1.4, .1, at.y))
	k.place(zone, "m:forklift", Vector3(-27, 0, -35), .7)
	k.place(zone, "m:pallet_jack", Vector3(-17, 0, -33), -.4)
	k.make_source(zone, "m:shipping_crate", Vector3(-70, 0, -30), 0.0)
	k.make_source(zone, "e:172:0", Vector3(-15.5, 0, -36), PI * .5)
	k.dresser.story(k, zone, ["body", Vector2(-40, -30), 1.2])
	k.papers(zone, Vector3(-55, 0, -33), Vector2(4, 2), 16)
	for i in 4:
		var at := Vector3(-80 + i * 18, 9.2, -47)
		k.light(zone, at, i % 2 == 0, 16.0)
		k.light(zone, at + Vector3(0, 0, 14), false, 16.0)

static func roof(k, node: Node3D) -> void:
	var top: Node3D = k.section("HallRoof", Vector3(0, HALL_HEIGHT, 0), node)
	top.set_meta("campus_roof", true)
	var holes: Array[Rect2] = [Rect2(-60, -52, 4, 6), Rect2(-33, -45, 5, 4)]
	k.foundation(top, HALL, 0, holes, "corrugated")
	for hole in holes:
		var below := Vector3(hole.get_center().x, -HALL_HEIGHT, hole.get_center().y)
		k.box(top, below + Vector3(0, .25, 0), Vector3(hole.size.x * .8, .5, hole.size.y * .6), "concrete")
		k.flat(top, below + Vector3(.6, .53, .2), Vector3(2.4, .05, 1.6), "corrugated", .4)
		var rain := DistrictAtmosphere.emitter("rain", 24); rain.position = Vector3(hole.get_center().x, 2, hole.get_center().y); k.add(top, rain)
	for i in range(0, int(HALL.size.x), 6):
		k.box(top, Vector3(HALL.position.x + 3 + i, -.6, HALL.get_center().y), Vector3(.25, .9, HALL.size.y - .4), "steel", false)
	for side in [-1, 1]: k.box(top, Vector3(HALL.get_center().x, .5, HALL.get_center().y + side * HALL.size.y * .5), Vector3(HALL.size.x, 1.0, .25), "corrugated")
