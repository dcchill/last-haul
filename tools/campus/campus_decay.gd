extends RefCounted

## Decay, grime and trash for the MedTac Research Campus.
## Scavengers stripped the lower storeys and left their rubbish; contamination
## kept them off the upper storeys, which stay tidier, dustier and more infested.
const DECAL_DIR := "res://assets/campus/decals/"
const DECAL_BUDGET := 260
const GUARD_LAYER := 2

## Per storey: scav (looting / scav marks), trash, wet (water damage), cont
## (contamination growth), dust, broken / boarded window shares.
const PROFILES := {
	1: {"scav": .9, "trash": .9, "wet": .7, "cont": .15, "dust": .1, "broken": .3, "boarded": .15},
	2: {"scav": .55, "trash": .55, "wet": .45, "cont": .4, "dust": .25, "broken": .22, "boarded": .08},
	3: {"scav": .15, "trash": .2, "wet": .3, "cont": .75, "dust": .55, "broken": .12, "boarded": .03},
	4: {"scav": .05, "trash": .08, "wet": .45, "cont": .95, "dust": .7, "broken": .08, "boarded": 0.0},
}
const INWARD := {"n": Vector3.BACK, "s": Vector3.FORWARD, "w": Vector3.RIGHT, "e": Vector3.LEFT}
const SECURE_ROLES := ["vault_samples", "vault_data", "vault_pharma", "medvault", "dispensary", "archive", "server"]

var textures: Dictionary = {}
var decal_count: Dictionary = {}
var decay_budget: Dictionary = {}
var litter: Dictionary = {}

static func profile(building: String, level: int) -> Dictionary:
	if building in ["exterior", "distribution", "skybridge"]: return PROFILES[1] if building != "skybridge" else PROFILES[3]
	return PROFILES[clampi(level, 1, 4)]

func p(k) -> Dictionary: return profile(k.building_id, k.floor_index)

func key(k) -> String: return "%s/%d" % [k.building_id, k.floor_index]

# ---------------------------------------------------------------- decals

func texture(kind: String) -> Texture2D:
	if not textures.has(kind): textures[kind] = load(DECAL_DIR + kind + ".png")
	return textures[kind]

## Projects `kind` onto the surface whose outward normal is `normal`.
func grime(k, parent: Node3D, at: Vector3, normal: Vector3, kind: String, size: Vector2, spin := 0.0, depth := .5) -> Decal:
	var id := key(k)
	if int(decal_count.get(id, 0)) >= DECAL_BUDGET: return null
	decal_count[id] = int(decal_count.get(id, 0)) + 1
	var decal := Decal.new()
	var y := normal.normalized()
	var x := Vector3.UP.cross(y).normalized() if absf(y.y) < .9 else Vector3.RIGHT.rotated(Vector3.UP, spin)
	var z := x.cross(y).normalized()
	decal.transform = Transform3D(Basis(x, y, z), at)
	decal.size = Vector3(size.x, depth, size.y)
	decal.texture_albedo = texture(kind)
	decal.albedo_mix = .92
	decal.normal_fade = .35
	decal.upper_fade = .15; decal.lower_fade = .15
	decal.distance_fade_enabled = true; decal.distance_fade_begin = 20; decal.distance_fade_length = 8
	decal.modulate = Color(1, 1, 1, k.rng.randf_range(.7, 1.0))
	k.add(parent, decal, "Grime%d" % k.serial)
	decal.set_meta("campus_decal", kind)
	return decal

func wall_point(rc: Dictionary, wall: String, t: float, height: float) -> Array:
	var inward: Vector3 = INWARD[wall]
	var along_x: bool = wall in ["n", "s"]
	var half: float = rc.hw if along_x else rc.hd
	var a: float = lerpf(-half + .5, half - .5, t)
	var face: float = (rc.hd if along_x else rc.hw) + .14
	var at := Vector3(a, height, -inward.z * face) if along_x else Vector3(-inward.x * face, height, a)
	return [at, inward]

# ---------------------------------------------------------------- rooms

func room(k, rc: Dictionary) -> void:
	var profile_data := p(k)
	var node: Node3D = rc.node
	var rng: RandomNumberGenerator = k.rng
	var area: float = rc.hw * rc.hd * 4
	var walls := ["n", "s", "e", "w"]
	var fire: bool = rc.spec.get("fire", false)
	if profile_data.dust > .4 and rc.role not in ["restroom", "riser"]:
		grime(k, node, Vector3(0, .15, 0), Vector3.UP, "dust", Vector2(rc.hw * 1.8, rc.hd * 1.8), rng.randf() * TAU, .6)
	for i in int(area / 30.0 * (.3 + profile_data.trash)):
		grime(k, node, Vector3(rng.randf_range(-rc.hw * .8, rc.hw * .8), .15, rng.randf_range(-rc.hd * .8, rc.hd * .8)), Vector3.UP, "floor_grime", Vector2.ONE * rng.randf_range(1.4, 3.0), rng.randf() * TAU)
	if rng.randf() < .45: grime(k, node, Vector3(rng.randf_range(-rc.hw * .5, rc.hw * .5), .15, rng.randf_range(-rc.hd * .5, rc.hd * .5)), Vector3.UP, "tile_cracks", Vector2(2.2, 2.2), rng.randf() * TAU)
	var entrances: Array = node.get_meta("entrance_points", [])
	if profile_data.scav > .5 and not entrances.is_empty():
		var door: Vector3 = entrances[0]
		var inward := -Vector3(door.x, 0, door.z).normalized()
		grime(k, node, door + inward * 1.6 + Vector3.UP * .15, Vector3.UP, "bootprints", Vector2(3.0, 1.2), atan2(inward.x, inward.z) - PI * .5)
	for i in roundi(profile_data.wet * 2.5):
		var spot := wall_point(rc, walls[rng.randi() % 4], rng.randf(), .75)
		grime(k, node, spot[0], spot[1], "water_stain", Vector2(rng.randf_range(1.2, 2.2), 1.5))
	for i in roundi(profile_data.cont * 2.2):
		var spot := wall_point(rc, walls[rng.randi() % 4], rng.randf_range(0, .15) if rng.randf() < .5 else rng.randf_range(.85, 1), rng.randf_range(1.6, 2.8))
		grime(k, node, spot[0], spot[1], "mould", Vector2.ONE * rng.randf_range(1.0, 2.0))
	if profile_data.cont > .6 and rc.role in ["icu", "isolation", "experimental", "containment", "ward", "makeshift", "controlled_obs", "holding", "regenesis", "dissection", "patient"] and rng.randf() < .55:
		grime(k, node, Vector3(rng.randf_range(-1, 1), .15, rng.randf_range(-1, 1)), Vector3.UP, "blood_smear", Vector2(2.2, 1.4), rng.randf() * TAU)
	# Rubbish: scavengers dumped it downstairs; upstairs it is tipped equipment instead.
	var trash_specs := ["e:012:0", "e:012:1", "e:013:0", "e:013:1", "e:013:2", "m:cardboard_box", "e:020:1", "e:012:3"]
	for i in int(area / 40.0 * profile_data.trash + rng.randf() * profile_data.trash):
		for attempt in 5:
			var item: Node3D = k.free_item(rc, trash_specs[rng.randi() % trash_specs.size()], Vector2(rng.randf_range(-rc.hw + .6, rc.hw - .6), rng.randf_range(-rc.hd + .6, rc.hd - .6)), Vector3(rng.randf_range(-1, 1), 0, 1).normalized(), false)
			if item != null: break
	add_litter(k, node, rc, int(area * .3 * profile_data.trash))
	k.papers(node, Vector3.ZERO, Vector2(rc.hw * .7, rc.hd * .7), rng.randi_range(0, int(2 + profile_data.scav * 6)) if rc.role not in ["restroom", "riser"] else 0)
	if profile_data.cont > .6 and rc.role not in ["restroom", "riser"]:
		for i in rng.randi_range(1, 2):
			k.wall_item(rc, walls[rng.randi() % 4], rng.randf(), "e:147:%d" % (rng.randi() % 4), false)
		if rng.randf() < profile_data.cont * .6: k.wall_item(rc, walls[rng.randi() % 4], rng.randf(), "e:153:%d" % (rng.randi() % 3), false)
		if rng.randf() < .4: k.wall_item(rc, walls[rng.randi() % 4], rng.randf(), "e:145:%d" % (rng.randi() % 3), false)
		var id := key(k)
		if profile_data.cont > .8 and int(decay_budget.get(id, 3)) > 0 and rng.randf() < .2:
			decay_budget[id] = int(decay_budget.get(id, 3)) - 1
			k.decay(node, Vector3(rng.randf_range(-rc.hw * .4, rc.hw * .4), 0, rng.randf_range(-rc.hd * .4, rc.hd * .4)))
	if fire: burn(k, rc)

func burn(k, rc: Dictionary) -> void:
	var node: Node3D = rc.node
	var rng: RandomNumberGenerator = k.rng
	for wall in ["n", "s", "e", "w"]:
		for i in 2:
			var spot := wall_point(rc, wall, rng.randf_range(.1, .9), 2.2)
			grime(k, node, spot[0], spot[1], "soot", Vector2(rng.randf_range(2.0, 3.5), 2.8))
	grime(k, node, Vector3(0, 3.2, 0), Vector3.DOWN, "soot", Vector2(rc.hw * 1.6, rc.hd * 1.6), 0.0, .4)
	grime(k, node, Vector3(0, .15, 0), Vector3.UP, "soot", Vector2(rc.hw * 1.5, rc.hd * 1.5), rng.randf() * TAU)
	k.free_item(rc, "e:090:3", Vector2(rng.randf_range(-.5, .5), rng.randf_range(-.5, .5)))
	for i in 6: k.flat(node, Vector3(rng.randf_range(-rc.hw * .7, rc.hw * .7), .015, rng.randf_range(-rc.hd * .7, rc.hd * .7)), Vector3(rng.randf_range(.4, 1.2), .03, rng.randf_range(.3, .9)), "rubber", rng.randf() * TAU)
	k.area_log.append({"name": rc.title + " fire damage", "building": k.building_id, "floor": k.floor_index})

## Searched-out containers stand open with their contents strewn about.
func ransacked(k, source: Node3D, parent: Node3D) -> void:
	source.set_meta("ransacked", true)
	var profile_data := p(k)
	var front: Vector3 = (source.transform.basis.z if not str(source.get_meta("campus_equipment", "")).begins_with("e:") else -source.transform.basis.z).normalized()
	k.papers(parent, source.position + front * .7, Vector2(.6, .5), k.rng.randi_range(4, 9))
	add_litter(k, parent, {}, 4, source.position + front * .8)
	if profile_data.scav > .4 and k.rng.randf() < .55:
		grime(k, parent, source.position - front * .2 + Vector3.UP * 1.75, front, "graffiti_tally" if k.rng.randf() < .65 else "graffiti_stripped", Vector2(1.0, 1.0), 0.0, .7)

# ---------------------------------------------------------------- litter

func add_litter(k, parent: Node3D, rc: Dictionary, count: int, center := Vector3.INF) -> void:
	var id := key(k)
	if not litter.has(id): litter[id] = []
	var floor_frame: Transform3D = k.world_transform(parent)
	for i in count:
		var local := center if center != Vector3.INF else Vector3.ZERO
		local += Vector3(k.rng.randf_range(-.6, .6), 0, k.rng.randf_range(-.6, .6)) if center != Vector3.INF else Vector3(k.rng.randf_range(-rc.hw + .3, rc.hw - .3), 0, k.rng.randf_range(-rc.hd + .3, rc.hd - .3))
		litter[id].append(Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU).scaled(Vector3.ONE * k.rng.randf_range(.7, 1.3)), floor_frame * local + Vector3.UP * .005))

static func litter_mesh() -> ArrayMesh:
	var kit := WorldMeshKit.new()
	kit.cylinder(Vector3(.2, .05, 0), .035, .12, "rust", 0, 6)
	kit.cylinder(Vector3(-.15, .04, .18), .04, .2, "glass", 2, 6)
	kit.box(Vector3(0, .006, -.2), Vector3(.25, .012, .18), "paper")
	kit.box(Vector3(-.25, .01, -.05), Vector3(.3, .02, .22), "wood")
	kit.box(Vector3(.12, .008, .22), Vector3(.14, .016, .1), "medical")
	return kit.finish()

## One non-solid litter MultiMesh per storey, culled beyond 40 m.
func flush_litter(k, parent: Node3D) -> void:
	var id := key(k)
	var transforms: Array = litter.get(id, [])
	if transforms.is_empty(): return
	var origin: Transform3D = k.world_transform(parent).affine_inverse()
	var visual := DistrictFoliage.new(); visual.multimesh = MultiMesh.new(); visual.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	visual.multimesh.mesh = litter_mesh(); visual.multimesh.instance_count = transforms.size()
	for t: Transform3D in transforms: visual.instance_transforms.append(origin * t)
	visual.visibility_range_end = 40
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	k.add(parent, visual, "Litter")
	visual.set_meta("campus_litter", transforms.size())
	litter.erase(id)

# ---------------------------------------------------------------- circulation

func corridor(k, node: Node3D, a: Vector2, b: Vector2, width: float) -> void:
	var profile_data := p(k)
	var length := a.distance_to(b)
	var along := (b - a).normalized()
	var spin := atan2(along.x, along.y) - PI * .5
	for i in int(length / 6.0):
		var at := a.lerp(b, (i + .5) / int(length / 6.0))
		var roll: float = k.rng.randf()
		if profile_data.scav > .5 and roll < .7: grime(k, node, Vector3(at.x, .15, at.y), Vector3.UP, "mud_tracks", Vector2(4.5, width * .7), spin)
		elif profile_data.dust > .4 and roll < .5: grime(k, node, Vector3(at.x, .15, at.y), Vector3.UP, "dust", Vector2(5.0, width * .9), spin)
		elif profile_data.cont > .6 and roll < .65: grime(k, node, Vector3(at.x, .15, at.y), Vector3.UP, "blood_smear", Vector2(3.0, 1.0), spin)
		if profile_data.wet > .4 and k.rng.randf() < .2: k.place(node, "e:152:%d" % (k.rng.randi() % 4), Vector3(at.x + k.rng.randf_range(-.5, .5), 0, at.y + k.rng.randf_range(-.5, .5)), k.rng.randf() * TAU, false)
	var lane := {"hw": absf(b.x - a.x) * .5 + .1 if absf(along.x) > .5 else width * .4, "hd": absf(b.y - a.y) * .5 + .1 if absf(along.y) > .5 else width * .4}
	var mid := (a + b) * .5
	var holder: Node3D = k.section("CorridorLitter%d" % k.serial, Vector3(mid.x, 0, mid.y), node)
	add_litter(k, holder, lane, int(length * 1.2 * profile_data.trash))

# ---------------------------------------------------------------- windows

func guard(k, parent: Node3D, at: Vector3, size: Vector3) -> void:
	## Window safety guards block actors (layer 2) but not bullets (layer 1).
	var body: StaticBody3D = parent.get_node_or_null("WindowGuards")
	if body == null:
		body = StaticBody3D.new(); k.add(parent, body, "WindowGuards")
		body.collision_layer = 1 << (GUARD_LAYER - 1); body.collision_mask = 0
	var shape := BoxShape3D.new(); shape.size = size
	var node := CollisionShape3D.new(); node.shape = shape; node.position = at
	k.add(body, node)

func window(k, node: Node3D, h: bool, c: float, a: float, b: float, sill: float, head: float, outward: Vector3, role: String) -> String:
	var profile_data := p(k)
	var rng: RandomNumberGenerator = k.rng
	var mid := (a + b) * .5
	var center := (Vector3(mid, (sill + head) * .5, c) if h else Vector3(c, (sill + head) * .5, mid))
	var opening := Vector3(b - a, head - sill, .1) if h else Vector3(.1, head - sill, b - a)
	var state := "intact"
	var roll := rng.randf()
	if role in SECURE_ROLES: state = "barred"
	elif roll < profile_data.broken: state = "shattered"
	elif roll < profile_data.broken + profile_data.boarded: state = "boarded"
	guard(k, node, center, opening)
	match state:
		"intact", "barred":
			k.glass_panel(node, h, c, a + .04, b - .04, sill, head)
			var pane: Node3D = node.get_child(node.get_child_count() - 1)
			pane.set_meta("exterior_pane", true)
			if state == "barred": k.place(node, "e:025:3", center + outward * .2 - Vector3.UP * .65, k.front_yaw("e:x", outward), false)
		"shattered", "boarded":
			# Jagged shards stay in the frame; glass and leaves blow inside.
			for i in 3:
				var t := rng.randf_range(.1, .9)
				var edge := sill if i % 2 == 0 else head - .25
				var piece := Vector3(lerpf(a, b, t), edge + .12, c) if h else Vector3(c, edge + .12, lerpf(a, b, t))
				k.box(node, piece, Vector3(rng.randf_range(.2, .5), rng.randf_range(.15, .35), .03) if h else Vector3(.03, rng.randf_range(.15, .35), rng.randf_range(.2, .5)), "glass", false)
			var inside := (Vector3(mid, 0, c) if h else Vector3(c, 0, mid)) - outward * rng.randf_range(.6, 1.3)
			for i in 4: k.flat(node, inside + Vector3(rng.randf_range(-.6, .6), .015, rng.randf_range(-.6, .6)), Vector3(.18, .01, .12), "glass", rng.randf() * TAU)
			if k.floor_index <= 2 and rng.randf() < .5: k.place(node, "e:154:%d" % (rng.randi() % 3), inside, rng.randf() * TAU, false)
			grime(k, node, (Vector3(mid, .6, c) if h else Vector3(c, .6, mid)) - outward * .17, -outward, "water_stain", Vector2(b - a + .4, 1.3))
			if state == "boarded": k.place(node, "e:039:%d" % (0 if rng.randf() < .6 else 1), center + outward * .22 - Vector3.UP * .65, k.front_yaw("e:x", outward), false)
	if rng.randf() < .35:
		grime(k, node, (Vector3(mid, sill - .8, c) if h else Vector3(c, sill - .8, mid)) + outward * .17, outward, "drips", Vector2(b - a, 1.6))
	return state

## Rubble, leaves and broken drainpipes along the ground-floor façade.
func facade_base(k, node: Node3D, h: bool, c: float, a: float, b: float, outward: Vector3) -> void:
	if k.floor_index != 1 or k.rng.randf() > .25: return
	var mid: float = k.rng.randf_range(a, b)
	var at: Vector3 = (Vector3(mid, 0, c) if h else Vector3(c, 0, mid)) + outward * k.rng.randf_range(.6, 1.4)
	k.place(node, ["e:014:%d", "e:154:%d", "e:155:%d"][k.rng.randi() % 3] % (k.rng.randi() % 3), at, k.rng.randf() * TAU, false)
