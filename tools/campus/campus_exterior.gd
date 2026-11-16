extends RefCounted

## Campus grounds in world metres (0.16 m per sketch pixel, sketch centre at 0,0).
const MAP := Rect2(-125, -105, 250, 210)
const NS_ROAD := Rect2(-10.4, -105, 8.3, 210)
const EW_ROAD := Rect2(-125, 8.5, 250, 8.3)
const LAB1 := Rect2(11.5, -68, 80, 64)
const LAB2 := Rect2(5.5, 30.1, 89, 31)
const HALL := Rect2(-91, -68.3, 78.4, 41.9)
const WING := Rect2(-91, -26.4, 42.7, 22.4)
const YARD := Rect2(-48.3, -26.4, 35, 34.9)
const PARKING := Rect2(-94, 20.6, 75.4, 47.7)
const BRIDGE_X := 47.5
const BRIDGE_Y := 8.4
const BLOCKADE_X := -53.6
const INSERTIONS := [Vector2(-112, -92), Vector2(40, -96), Vector2(116, -60), Vector2(112, 88), Vector2(40, 96), Vector2(-110, 92), Vector2(-115, -20)]
const EXTRACTS := [["north", "North Road", Vector2(-6.25, -99)], ["east", "East Road", Vector2(119, 12.65)], ["south", "South Road", Vector2(-6.25, 99)], ["west", "West Checkpoint", Vector2(-119, 12.65)]]

static func pave(k, parent: Node3D, r: Rect2, key := "asphalt") -> void:
	k.box(parent, Vector3(r.get_center().x, .015, r.get_center().y), Vector3(r.size.x, .03, r.size.y), key, false)

## Road paint is a thin decal over the unified pavement, not another pavement patch.
static func paint(k, parent: Node3D, at: Vector2, size: Vector2) -> void:
	k.box(parent, Vector3(at.x, .064, at.y), Vector3(size.x, .008, size.y), "warning", false)

static func build(k) -> void:
	k.building_id = "exterior"; k.floor_index = 1; k.tier = 1
	var root: Node3D = k.section("Exterior", Vector3.ZERO)
	root.set_meta("campus_floor", 1); root.set_meta("campus_building", "exterior"); root.set_meta("loot_tier", 1)
	k.split_scenes.append({"node": root, "path": "res://scenes/raid/campus/exterior.tscn"})
	var holes: Array[Rect2] = [LAB1, LAB2, HALL, WING]
	k.foundation(root, MAP, 0, holes, "grass")
	roads(k, root)
	yard(k, root)
	parking(k, root)
	blockade(k, root)
	grounds(k, root)
	boundary(k, root)
	vegetation(k, root)
	surroundings(k, root)
	skybridge(k)
	for spec: Array in [
		["scav", "exterior", Vector2(-58, 12.6), [Vector2(-58, 12.6), Vector2(-62, 10), Vector2(-58, 15.5)]],
		["scav", "exterior", Vector2(-55, 45), [Vector2(-55, 45), Vector2(-40, 45), Vector2(-55, 34)]],
		["scav", "exterior", Vector2(1.5, 38.5), [Vector2(1.5, 38.5), Vector2(-.5, 30), Vector2(1.5, 42)]],
		["infected", "exterior", Vector2(-72, 60), [Vector2(-72, 60), Vector2(-60, 62), Vector2(-80, 55)]],
		["scav", "distribution", Vector2(-30, -10), [Vector2(-30, -10), Vector2(-22, -4), Vector2(-38, -14)]],
	]:
		var patrol: Array[Vector3] = []
		for p: Vector2 in spec[3]: patrol.append(Vector3(p.x, .1, p.y))
		k.encounter_specs.append({"kind": spec[0], "building": spec[1], "floor": 1, "at": Vector3(spec[2].x, .1, spec[2].y), "patrol": patrol})

static func roads(k, root: Node3D) -> void:
	var node: Node3D = k.section("Roads", Vector3.ZERO, root)
	pave(k, node, NS_ROAD); pave(k, node, EW_ROAD)
	for z in range(-102, 103, 6):
		if absf(z - 12.6) > 7: paint(k, node, Vector2(-6.25, z), Vector2(.12, 3))
	for x in range(-122, 123, 6):
		if absf(x + 6.25) > 7: paint(k, node, Vector2(x, 12.65), Vector2(3, .12))
	for i in 6:
		paint(k, node, Vector2(-9.6 + i * 1.5, 7.2), Vector2(.7, 2.0)); paint(k, node, Vector2(-9.6 + i * 1.5, 18.1), Vector2(.7, 2.0))
		paint(k, node, Vector2(-11.7, 9.3 + i * 1.4), Vector2(2.0, .7)); paint(k, node, Vector2(-.8, 9.3 + i * 1.4), Vector2(2.0, .7))
	# Sidewalks where the roads pass the campus buildings.
	for r in [Rect2(-12.4, -105, 2, 210), Rect2(-2.1, -105, 2, 210), Rect2(-125, 6.5, 250, 2), Rect2(-125, 16.8, 250, 2)]:
		pave(k, node, r, "concrete")
	# Lab 1 forecourt, emergency and service paths.
	pave(k, node, Rect2(-.1, -42, 11.6, 12), "concrete")
	pave(k, node, Rect2(45.5, -4, 4, 10.5), "concrete")
	pave(k, node, Rect2(91.5, -21, 5, 4), "concrete")
	pave(k, node, Rect2(94, -21, 4, 27.5), "concrete")
	# Lab 2 drop-off loop, ambulance bay, south service lane and doors.
	pave(k, node, Rect2(22, 18.8, 20, 8))
	pave(k, node, Rect2(30, 26.8, 4, 3.3), "concrete")
	pave(k, node, Rect2(-.1, 34, 5.6, 9))
	pave(k, node, Rect2(-2.1, 63, 102, 5))
	pave(k, node, Rect2(52, 61.1, 4, 1.9), "concrete")
	pave(k, node, Rect2(89, 61.1, 4, 1.9), "concrete")
	pave(k, node, Rect2(94.5, 50.7, 4, 12.3), "concrete")
	k.box(node, Vector3(32, .25, 22.8), Vector3(10, .5, 2.4), "stone")
	k.place(node, "e:161:1", Vector3(2.5, 0, 38.5), PI * .5)
	k.make_source(node, "e:175:1", Vector3(1.0, 0, 41.3), 0.0)
	k.cover_marker(node, Vector3(2.5, .1, 41.5))
	# Streetlights: mostly dead; two emergency heads still run off batteries.
	var poles := [Vector2(-13.5, -90), Vector2(-13.5, -60), Vector2(-13.5, -30), Vector2(-13.5, 40), Vector2(-13.5, 80), Vector2(1, -80), Vector2(1, -15), Vector2(1, 50), Vector2(1, 90),
		Vector2(-100, 5.5), Vector2(-70, 5.5), Vector2(-30, 19.8), Vector2(20, 19.8), Vector2(60, 5.5), Vector2(100, 19.8)]
	for i in poles.size():
		var p: Vector2 = poles[i]
		k.place(node, "e:005:%d" % [2, 2, 1, 2, 3, 2, 0, 2, 2, 3, 2, 1, 2, 2, 0][i], Vector3(p.x, 0, p.y), PI * .5 if absf(p.x) < 20 else 0.0)
		if i in [6, 14]: k.light(node, Vector3(p.x, 5.4, p.y), true, 14.0)
	k.area_log.append_array([{"name": "Main campus roads", "building": "exterior", "floor": 1}, {"name": "Lab 2 ambulance bay", "building": "exterior", "floor": 1}])

static func yard(k, root: Node3D) -> void:
	var node: Node3D = k.section("TruckYard", Vector3.ZERO, root)
	pave(k, node, YARD)
	pave(k, node, Rect2(-13.3, -10, 2.9, 8))
	for x in [-45.0, -27.0, -15.0]: paint(k, node, Vector2(x, -18), Vector2(.15, 14))
	k.place(node, "d:industrial_truck", Vector3(-45, 0, -21.5), 0.0)
	k.place(node, "e:160:1", Vector3(-27, 0, -22), 0.0)
	k.place(node, "e:160:2", Vector3(-38.5, 0, -14), .25)
	k.place(node, "e:170:1", Vector3(-20, 0, -8), 1.3)
	for z in [-2.0, 4.0]: k.place(node, "d:shipping_container", Vector3(-44, 0, z), PI * .5)
	k.place(node, "e:167:2", Vector3(-31, 0, -9), 2.4)
	for at in [Vector2(-34, -2), Vector2(-26, 2), Vector2(-17, -16)]:
		k.place(node, "m:wrapped_pallet", Vector3(at.x, 0, at.y), .4)
	k.make_source(node, "e:113:2", Vector3(-16.2, 0, 5.4), PI)
	k.make_source(node, "e:172:2", Vector3(-36, 0, 3.2), .2)
	k.make_source(node, "e:178:3", Vector3(-22.5, 0, -4.5), 1.0)
	for at in [Vector2(-45, -15), Vector2(-27, -13), Vector2(-38.5, -6), Vector2(-20, -3), Vector2(-40.5, -2)]:
		k.cover_marker(node, Vector3(at.x, .1, at.y))
	k.area_log.append({"name": "Truck loading yard", "building": "exterior", "floor": 1})

static func parking(k, root: Node3D) -> void:
	var node: Node3D = k.section("ParkingLot", Vector3.ZERO, root)
	pave(k, node, PARKING)
	pave(k, node, Rect2(-43, 16.8, 3.3, 3.8))
	pave(k, node, Rect2(-18.6, 44.3, 8.2, 4.5))
	# Four bays of 2.6 m stalls; aisles run east-west.
	var rows := [24.0, 36.0, 41.0, 53.0, 58.0, 65.0]
	for z: float in rows:
		for i in 27:
			var x := -92.5 + i * 2.6
			if x > -21: break
			paint(k, node, Vector2(x, z), Vector2(.1, 4.6))
	var vehicles := ["e:156:0", "e:157:1", "e:156:3", "e:158:2", "e:159:2", "e:157:2", "e:156:1", "e:169:0", "e:158:0", "e:157:0", "e:156:2", "e:159:3", "e:165:1", "e:157:1", "e:156:0", "e:166:2", "e:158:1", "e:156:1"]
	var slots := [Vector2(-90, 24), Vector2(-82, 24), Vector2(-71, 24), Vector2(-58, 24), Vector2(-33, 24), Vector2(-86, 36), Vector2(-64, 41), Vector2(-48, 36), Vector2(-27, 41), Vector2(-78, 53), Vector2(-61, 58), Vector2(-44, 53), Vector2(-36, 58), Vector2(-88, 65), Vector2(-70, 65), Vector2(-52, 65), Vector2(-24, 53), Vector2(-56, 31)]
	for i in vehicles.size():
		var at: Vector2 = slots[i]
		var yaw: float = (PI if i % 2 == 0 else 0.0) + k.rng.randf_range(-.25, .25)
		if at.y == 31.0: yaw = PI * .5 + .4
		k.place(node, vehicles[i], Vector3(at.x, 0, at.y), yaw)
		k.cover_marker(node, Vector3(at.x + 1.8, .1, at.y))
	k.place(node, "e:164:1", Vector3(-30, 0, 47.5), PI * .5 + .05)
	k.cover_marker(node, Vector3(-30, .1, 49.5))
	# The failed evacuation staging point: tents, cots and an abandoned queue.
	k.dresser.story(k, node, ["camp", Vector2(-78, 46), .5])
	k.place(node, "e:128:2", Vector3(-84, 0, 45), .2)
	k.place(node, "e:127:3", Vector3(-72, 0, 47), -.3)
	k.place(node, "e:138:2", Vector3(-66, 0, 44), PI)
	k.printed_sign(node, "evacuation", Vector3(-66, 2.6, 43.3), PI, 3.0)
	for i in 3: k.dresser.story(k, node, ["body", Vector2(-75 + i * 4, 50 + i), i * .9])
	for i in 6:
		var spec: String = ["e:180:2", "e:181:1", "e:182:0", "e:180:0", "e:181:3", "e:182:1"][i]
		k.make_source(node, spec, Vector3([-80.5, -68.0, -60.0, -46.0, -30.5, -86.0][i], 0, [48.6, 50.0, 26.6, 38.6, 55.6, 62.6][i]), k.rng.randf() * TAU)
	for at in [Vector2(-75, 30), Vector2(-50, 47.5), Vector2(-75, 60), Vector2(-40, 30)]:
		k.place(node, "e:142:%d" % (k.rng.randi() % 3), Vector3(at.x, 0, at.y), k.rng.randf() * TAU)
		k.place(node, "e:155:3", Vector3(at.x + 1.5, 0, at.y + .8), k.rng.randf() * TAU, false)
	for at in [Vector2(-92, 32), Vector2(-60, 32), Vector2(-28, 32), Vector2(-92, 62), Vector2(-60, 62), Vector2(-28, 62)]:
		k.place(node, "e:005:%d" % (2 if k.rng.randf() < .6 else 3), Vector3(at.x, 0, at.y), 0.0)
	k.area_log.append({"name": "Visitor parking lot", "building": "exterior", "floor": 1})

static func blockade(k, root: Node3D) -> void:
	var node: Node3D = k.section("QuarantineBlockade", Vector3.ZERO, root)
	# Barrier line across the western road leaves one narrow pedestrian squeeze.
	for i in 3:
		var z := 9.4 + i * 2.85
		k.place(node, "e:112:%d" % (i % 2), Vector3(BLOCKADE_X, 0, z), PI * .5)
	k.place(node, "e:121:1", Vector3(BLOCKADE_X - 2.2, 0, 11), PI * .5)
	k.place(node, "e:111:1", Vector3(BLOCKADE_X + 1.6, 0, 10.5), PI * .5)
	k.place(node, "e:111:2", Vector3(BLOCKADE_X + 1.6, 0, 13.2), PI * .5)
	k.cover_marker(node, Vector3(BLOCKADE_X + 2.6, .1, 12))
	k.cover_marker(node, Vector3(BLOCKADE_X - 3.2, .1, 13), PI)
	# Fence along the north verge from the map edge to the checkpoint.
	var x := -123.5
	var gap := -80.0
	while x < BLOCKADE_X - 1:
		if absf(x - gap) > 2.5: k.place(node, "e:036:%d" % (1 if k.rng.randf() < .7 else 3), Vector3(x + 1.65, 0, 7.4), 0.0)
		else: k.place(node, "e:036:2", Vector3(x + 1.65, .05, 6.2), 0.0, false)
		x += 3.3
	k.make_source(node, "e:113:1", Vector3(BLOCKADE_X + 5, 0, 5.2), PI)
	k.place(node, "e:163:2", Vector3(BLOCKADE_X + 9, 0, 11), PI * .5 + .1)
	k.place(node, "e:162:1", Vector3(BLOCKADE_X - 8, 0, 14.5), PI * .5 - .3)
	for z in [5.0, 19.5]: k.place(node, "e:119:%d" % (0 if z < 10 else 2), Vector3(BLOCKADE_X + 3, 0, z), PI * .5)
	k.light(node, Vector3(BLOCKADE_X + 3, 2.4, 5.0), true, 12.0)
	k.make_source(node, "e:173:2", Vector3(BLOCKADE_X + 4.2, 0, 19.2), 0.0)
	k.make_source(node, "e:174:2", Vector3(BLOCKADE_X + 6.5, 0, 19.4), 0.0)
	k.place(node, "e:125:1", Vector3(BLOCKADE_X + 5, 0, 7.3), 0.0)
	k.printed_sign(node, "checkpoint", Vector3(BLOCKADE_X - .6, 2.8, 12.6), -PI * .5, 4.0)
	# Abandoned queue of vehicles stopped at the checkpoint.
	var jam := ["e:156:1", "e:159:0", "e:157:2", "e:158:3", "e:156:2", "e:162:2", "e:157:0", "e:159:3"]
	for i in jam.size():
		var at := Vector3(BLOCKADE_X - 12 - i * 8.5, 0, 10.6 if i % 2 == 0 else 14.6)
		k.place(node, jam[i], at, -PI * .5 + k.rng.randf_range(-.3, .3))
		k.cover_marker(node, at + Vector3(0, .1, -2.0 if i % 2 == 0 else 2.0))
	for i in 3: k.make_source(node, ["e:182:2", "e:180:1", "e:181:0"][i], Vector3(BLOCKADE_X - 16 - i * 17, 0, 12.6), k.rng.randf() * TAU)
	k.area_log.append({"name": "Western quarantine blockade", "building": "exterior", "floor": 1})

static func grounds(k, root: Node3D) -> void:
	var node: Node3D = k.section("LabGrounds", Vector3.ZERO, root)
	# Overgrown planters, benches and sculptural planting between the labs.
	var benches := [Vector3(5, 0, -48), Vector3(5, 0, -24), Vector3(30, 0, 0), Vector3(66, 0, 0), Vector3(66, 0, 24), Vector3(30, 0, 24), Vector3(98, 0, 30)]
	for at: Vector3 in benches:
		var bench: Node3D = k.section("Bench%d" % k.serial, at, node)
		k.box(bench, Vector3(0, .45, 0), Vector3(1.8, .08, .45), "wood")
		for s in [-1, 1]: k.box(bench, Vector3(s * .75, .22, 0), Vector3(.08, .44, .4), "steel")
	for at in [Vector3(26, 0, 2.5), Vector3(70, 0, 2.5), Vector3(26, 0, 23), Vector3(70, 0, 23), Vector3(5.5, 0, -55), Vector3(5.5, 0, -18)]:
		var planter: Node3D = k.section("Planter%d" % k.serial, at, node)
		k.box(planter, Vector3(0, .3, 0), Vector3(4, .6, 2.2), "stone")
		k.box(planter, Vector3(0, .61, 0), Vector3(3.6, .02, 1.8), "grass", false)
		k.place(planter, "e:143:%d" % (k.rng.randi() % 4), Vector3(0, .6, 0), k.rng.randf() * TAU, false)
		k.cover_marker(node, at + Vector3(0, .1, 1.8))
	# Curving garden walk between the labs, after the reference courtyard.
	var walk := [Vector2(-.1, 23), Vector2(10, 21), Vector2(20, 23.5), Vector2(32, 21.5), Vector2(44, 24), Vector2(58, 21), Vector2(72, 24), Vector2(86, 21), Vector2(98, 22)]
	for i in range(1, walk.size()):
		var a: Vector2 = walk[i - 1]; var b: Vector2 = walk[i]
		var holder: Node3D = k.section("Walk%d" % k.serial, Vector3((a.x + b.x) * .5, 0, (a.y + b.y) * .5), node)
		holder.rotation.y = atan2(b.x - a.x, b.y - a.y)
		k.box(holder, Vector3(0, .02, 0), Vector3(2.2, .03, a.distance_to(b) + .6), "concrete", false)
	for i in 70:
		var at := Vector3(k.rng.randf_range(-120, 120), 0, k.rng.randf_range(-100, 100))
		if not clear(k, Vector2(at.x, at.z), 2.5): continue
		k.place(node, "e:%s:%d" % [["143", "144", "153", "154", "148", "150"][i % 6], i % 3], at, k.rng.randf() * TAU, false)
	for at in [Vector2(100, -30), Vector2(105, 70), Vector2(-110, -40), Vector2(-20, 80), Vector2(60, -85)]:
		k.place(node, "e:149:%d" % (k.rng.randi() % 3), Vector3(at.x, 0, at.y), k.rng.randf() * TAU)
		k.cover_marker(node, Vector3(at.x + 1.2, .1, at.y))
	k.area_log.append({"name": "Overgrown lab grounds", "building": "exterior", "floor": 1})

static func clear(k, at: Vector2, margin: float) -> bool:
	for r in [LAB1, LAB2, HALL, WING]:
		if (r as Rect2).grow(margin).has_point(at): return false
	for patch: Dictionary in k.paving:
		if Geometry2D.is_point_in_polygon(at, patch.polygon): return false
		var poly: PackedVector2Array = patch.polygon
		for i in poly.size():
			if Geometry2D.get_closest_point_to_segment(at, poly[i], poly[(i + 1) % poly.size()]).distance_to(at) < margin: return false
	if absf(at.x - BRIDGE_X) < 5 and at.y > -6 and at.y < 32: return false
	for p: Vector2 in INSERTIONS:
		if p.distance_to(at) < 6: return false
	for e: Array in EXTRACTS:
		if (e[2] as Vector2).distance_to(at) < 9: return false
	return MAP.grow(-3).has_point(at)

static func boundary(k, root: Node3D) -> void:
	var node: Node3D = k.section("Boundary", Vector3.ZERO, root)
	for side in [[Vector3(MAP.position.x, 3, 0), Vector3(.5, 6, MAP.size.y)], [Vector3(MAP.end.x, 3, 0), Vector3(.5, 6, MAP.size.y)], [Vector3(0, 3, MAP.position.y), Vector3(MAP.size.x, 6, .5)], [Vector3(0, 3, MAP.end.y), Vector3(MAP.size.x, 6, .5)]]:
		var shape := BoxShape3D.new(); shape.size = side[1]
		k.collider(node, side[0], shape, "concrete")
	# A broken perimeter fence; gaps sit where the roads leave the map.
	for i in 30:
		var t := (i + .5) / 30.0
		for edge in 4:
			var at: Vector3
			var yaw := 0.0
			match edge:
				0: at = Vector3(lerpf(MAP.position.x + 4, MAP.end.x - 4, t), 0, MAP.position.y + 4)
				1: at = Vector3(lerpf(MAP.position.x + 4, MAP.end.x - 4, t), 0, MAP.end.y - 4)
				2: at = Vector3(MAP.position.x + 4, 0, lerpf(MAP.position.y + 4, MAP.end.y - 4, t)); yaw = PI * .5
				3: at = Vector3(MAP.end.x - 4, 0, lerpf(MAP.position.y + 4, MAP.end.y - 4, t)); yaw = PI * .5
			if NS_ROAD.grow(4).has_point(Vector2(at.x, at.z)) or EW_ROAD.grow(4).has_point(Vector2(at.x, at.z)): continue
			if (i + edge) % 4 == 0: continue
			k.place(node, "e:036:%d" % (0 if (i + edge) % 3 else 2), at, yaw, (i + edge) % 3 != 0)

## Visual-only woodland and ground beyond the boundary so the map edge reads as forest.
static func surroundings(k, root: Node3D) -> void:
	var node: Node3D = k.section("Surroundings", Vector3.ZERO, root)
	var outer := Rect2(-420, -400, 840, 800)
	var kit: WorldMeshKit = k.kits[node]
	var pieces: Array[PackedVector2Array] = DistrictSurfaceGeometry.subtract(k.polygon(outer), k.polygon(MAP))
	for piece in pieces:
		var indices := Geometry2D.triangulate_polygon(piece)
		for i in range(0, indices.size(), 3):
			var a := piece[indices[i]]; var b := piece[indices[i + 1]]; var c := piece[indices[i + 2]]
			kit.tri(Vector3(a.x, -.02, a.y), Vector3(b.x, -.02, b.y), Vector3(c.x, -.02, c.y), Vector3.UP, "grass")
	var tree := WorldMeshKit.new()
	tree.cylinder(Vector3(0, 3.2, 0), .3, 6.4, "wood", 1, 6)
	for i in 4: tree.cylinder(Vector3(0, 4.2 + i * .8, 0), 2.8 - i * .5, 1.1, "contamination", 1, 6)
	var visual := DistrictFoliage.new(); visual.multimesh = MultiMesh.new(); visual.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	visual.multimesh.mesh = tree.finish()
	var rng: RandomNumberGenerator = k.rng
	for i in 1400:
		var at := Vector2(rng.randf_range(-190, 190), rng.randf_range(-170, 170))
		if MAP.grow(1.5).has_point(at): continue
		if absf(at.x + 6.25) < 6 and absf(at.y) > 100: continue
		if absf(at.y - 12.65) < 6 and absf(at.x) > 120: continue
		visual.instance_transforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(.8, 1.5)), Vector3(at.x, 0, at.y)))
	visual.multimesh.instance_count = visual.instance_transforms.size()
	k.add(node, visual, "OuterWoodland")
	# Roads continue out of sight beyond the extracts.
	for r in [Rect2(-10.4, -400, 8.3, 295), Rect2(-10.4, 105, 8.3, 295), Rect2(-420, 8.5, 295, 8.3), Rect2(125, 8.5, 295, 8.3)]:
		k.box(node, Vector3(r.get_center().x, -.005, r.get_center().y), Vector3(r.size.x, .02, r.size.y), "asphalt", false)

static func vegetation(k, root: Node3D) -> void:
	var forest: Node3D = k.section("Woodland", Vector3.ZERO, root)
	var tree := WorldMeshKit.new()
	tree.cylinder(Vector3(0, 2.6, 0), .24, 5.2, "wood", 1, 8)
	for i in 4: tree.cylinder(Vector3(0, 3.4 + i * .65, 0), 2.3 - i * .4, .9, "contamination", 1, 7)
	var tuft := WorldMeshKit.new()
	for i in 3:
		var holder := Basis(Vector3.UP, i * PI / 3)
		var a := holder * Vector3(-.45, 0, 0); var b := holder * Vector3(.45, 0, 0)
		tuft.quad(a, b, b + Vector3(0, .7, 0), a + Vector3(0, .7, 0), holder * Vector3.BACK, "grass")
		tuft.quad(b, a, a + Vector3(0, .7, 0), b + Vector3(0, .7, 0), holder * Vector3.FORWARD, "grass")
	var rng: RandomNumberGenerator = k.rng
	for kind in [["TreeInstances", tree, 230, 4.0, true], ["GrassTufts", tuft, 1600, .8, false]]:
		var positions: Array[Vector3] = []
		for attempt in 30000:
			if positions.size() >= kind[2]: break
			var at := Vector2(rng.randf_range(MAP.position.x + 2, MAP.end.x - 2), rng.randf_range(MAP.position.y + 2, MAP.end.y - 2))
			# Woodland thickens towards the map edge; lawns keep sightlines open.
			var edge := minf(minf(at.x - MAP.position.x, MAP.end.x - at.x), minf(at.y - MAP.position.y, MAP.end.y - at.y))
			if kind[4] and edge > 22 and rng.randf() < .8: continue
			if not clear(k, at, 3.0 if kind[4] else 1.0): continue
			if kind[4] and positions.any(func(p): return Vector2(p.x, p.z).distance_to(at) < kind[3]): continue
			positions.append(Vector3(at.x, 0, at.y))
		var visual := DistrictFoliage.new(); visual.multimesh = MultiMesh.new(); visual.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		visual.multimesh.mesh = (kind[1] as WorldMeshKit).finish(); visual.multimesh.instance_count = positions.size()
		for at in positions:
			var scale := rng.randf_range(.75, 1.3)
			visual.instance_transforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale), at))
			if kind[4]:
				var shape := CylinderShape3D.new(); shape.radius = .24; shape.height = 4
				k.collider(forest, at + Vector3.UP * 2, shape, "wood")
		if not kind[4]: visual.visibility_range_end = 60
		k.add(forest, visual, kind[0])

static func skybridge(k) -> void:
	k.building_id = "skybridge"; k.floor_index = 3; k.tier = 3
	var length := LAB2.position.y - LAB1.end.y
	var center := Vector3(BRIDGE_X, BRIDGE_Y, (LAB1.end.y + LAB2.position.y) * .5)
	var node: Node3D = k.section("Skybridge", center)
	node.set_meta("campus_floor", 3); node.set_meta("campus_building", "skybridge"); node.set_meta("loot_tier", 3)
	node.set_meta("bridge_bounds", AABB(Vector3(-3, -.4, -length * .5), Vector3(6, 3.6, length)))
	k.split_scenes.append({"node": node, "path": "res://scenes/raid/campus/skybridge.tscn"})
	k.box(node, Vector3(0, -.15, 0), Vector3(6, .3, length), "lab_floor")
	k.box(node, Vector3(0, -.45, 0), Vector3(5.2, .3, length - .4), "steel", false)
	k.box(node, Vector3(0, 3.35, 0), Vector3(6.2, .25, length + .2), "panel")
	for s in [-1, 1]:
		k.box(node, Vector3(s * 2.95, .45, 0), Vector3(.12, .9, length), "panel")
		var broken_from := 6.0 if s < 0 else -12.0
		for i in int(length / 2.0):
			var z := -length * .5 + 1 + i * 2.0
			k.box(node, Vector3(s * 2.95, 2.1, z - 1), Vector3(.14, 2.4, .1), "steel", false)
			if s < 0 and z > broken_from and z < broken_from + 4: continue
			k.box(node, Vector3(s * 2.97, 2.1, z), Vector3(.04, 2.4, 1.9), "glass", false)
		var shape := BoxShape3D.new(); shape.size = Vector3(.12, 2.4, length)
		k.collider(node, Vector3(s * 2.95, 2.1, 0), shape, "glass")
	# Piers stand on the verges either side of the road.
	for z in [LAB1.end.y + 6, LAB2.position.y - 6]:
		for x in [-3.3, 3.3]:
			k.box(node, Vector3(x, -center.y * .5 - .3, z - center.z), Vector3(.9, center.y - .6, .9), "concrete")
		k.box(node, Vector3(0, -.75, z - center.z), Vector3(7.4, .6, .9), "concrete")
	k.place(node, "e:111:1", Vector3(-1.4, 0, 4), PI * .5)
	k.place(node, "e:122:2", Vector3(1.8, 0, 5.5), .3)
	k.place(node, "e:097:2", Vector3(1.6, 0, -6), .2, false)
	k.make_source(node, "e:114:2", Vector3(-1.9, 0, 9), PI * .5, {"profile": "records"})
	k.dresser.story(k, node, ["body", Vector2(.6, -2), 1.2])
	k.papers(node, Vector3.ZERO, Vector2(2, 10), 20)
	k.stain(node, Vector3(-.5, 0, -1), 1.2)
	for z in [-10.0, 0.0, 10.0]: k.light(node, Vector3(0, 3.1, z), z == 0.0, 8.0)
	k.cover_marker(node, Vector3(-1.4, .1, 5.2)); k.cover_marker(node, Vector3(1.8, .1, 6.6))
	k.printed_sign(node, "skybridge", Vector3(0, 2.7, -length * .5 + .3), 0.0, 2.6)
	k.printed_sign(node, "skybridge_research", Vector3(0, 2.7, length * .5 - .3), PI, 2.6)
	k.area_log.append({"name": "Third-floor skybridge", "building": "skybridge", "floor": 3})
