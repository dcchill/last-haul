extends "res://tools/campus_scene_author.gd"

## MedTac Research Campus authoring kit. Building-local metres, north is -Z.
## Rooms share wall lines: interior walls, façades, slabs, ceilings and stair
## openings are all derived from the room plan, so every window belongs to a
## real room and every stair lands on a real floor.
const FH := 4.2
const WALL_H := 4.02
const CEIL := 3.3
const DOOR_H := 2.4
const ENV_DIR := "res://scenes/props/environment/"
const SIGN_DIR := "res://assets/campus/signs/"
const PATTERNS := {
	"plaster": ["b3b6a5", "plaster"], "floor": ["737d77", "floor"], "concrete": ["7a7d72", "concrete"],
	"dirt": ["535845", "dirt"], "rust": ["754c35", "rust"], "tile": ["c4c9c0", "tile"], "lino": ["6c8281", "lino"],
	"carpet": ["4f5a5e", "carpet"], "ceiling": ["bfc1b4", "ceiling"], "panel": ["cfd2c9", "panel"],
	"stone": ["b5a990", "stone"], "grass": ["4d6136", "grass"], "ivy": ["3a5529", "ivy"], "paper": ["d6d2c1", "paper"],
	"corrugated": ["86908b", "corrugated"], "lab_floor": ["9aa6a2", "tile"]}
const WINDOWED := ["office","openoffice","exec","exec_reception","exec_lounge","conference","meeting","secure_conference","waiting","lobby","breakroom","cafeteria","exhibit","pharmalab","chemlab","biolab","prep","workstations","calibration","receipt","pressroom","mixing","balance","imaging","labsupport","animal","regenesis","control","prototype","datacentre","ward","dissection","kitchen","interview","dispensary","coatroom","firstaid","it","supplies","mail","security","security_desk","security_ops","service_entry","patient","icu","experimental","trial_lab","diagnostic","consent","trial_treatment","controlled_obs","holding","dayroom","er","triage","reception","exam","treatment","resus","procedure","nurse_station","monitoring","oncall","makeshift","records","dispatch","dispatch_reception","security_monitor","observation","observation_clinical","obs_control","bridge_access","bridge_security","checkpoint","laundry","transfer","changing","gowning","glasswash"]

var env: Dictionary = {}
var item_defs: Dictionary = {}
var usage: Dictionary = {}
var rng := RandomNumberGenerator.new()
var dresser: RefCounted
var decayer: RefCounted
var window_states: Dictionary = {}
var door_serial := 0
var glass_serial := 0
var light_serial := 0
var loose_total := 0
var room_log: Array[Dictionary] = []
var area_log: Array[Dictionary] = []
var encounter_specs: Array[Dictionary] = []
var split_scenes: Array[Dictionary] = []
var stair_log: Array[Dictionary] = []
var anchors: Dictionary = {}
var lines: Dictionary = {}
var facade_cuts: Array[Dictionary] = []
var party_cuts: Array[Dictionary] = []
var floor_rooms: Array[Dictionary] = []
var bounds_cache: Dictionary = {}
var building_id := ""
var floor_index := 1
var tier := 1
var building_node: Node3D
var floor_node: Node3D
var plan: Dictionary = {}
var prof: Dictionary = {}

func lap(name: String, since: int) -> int:
	var now := Time.get_ticks_usec()
	prof[name] = int(prof.get(name, 0)) + now - since
	return now

func setup() -> void:
	rng.seed = 19381
	for entry: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://resources/environment_props/catalog.json")): env[entry.id] = entry
	var catalog := Catalog.new()
	catalog.load_all()
	item_defs = catalog.items
	dresser = load("res://tools/campus/campus_dressing.gd").new()
	decayer = load("res://tools/campus/campus_decay.gd").new()

func begin(title: String, raid := false) -> Node3D:
	var result := super.begin(title, raid)
	DirAccess.make_dir_recursive_absolute("res://resources/campus/materials")
	for key: String in PATTERNS:
		var path := "res://resources/campus/materials/%s.tres" % key
		ResourceSaver.save(make_material(key, Color(PATTERNS[key][0]), PATTERNS[key][1]), path)
		WorldMeshKit.shared_materials[key] = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	return result

func make_material(key: String, color: Color, pattern: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = key; mat.albedo_color = color; mat.roughness = .95
	var image := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var grain := float((x * 73 + y * 151) % 23) / 23.0
			var coarse := float(((x >> 3) * 71 + (y >> 3) * 37) % 17) / 17.0
			var tone := .84 + grain * .1
			match pattern:
				"tile": tone = .5 if (x % 32 == 0 or y % 32 == 0) else .86 + grain * .08 - (.12 if ((x * 7 + y * 3) % 97) < 3 else 0.0)
				"lino": tone = .8 + float((x * 37 + y * 91) % 13) / 13.0 * .14
				"carpet": tone = .7 + float((x * x * 7 + y * 13) % 17) / 17.0 * .24
				"ceiling": tone = .58 if (x % 32 == 0 or y % 32 == 0) else .86 + grain * .06 - (.2 if (x + y * 3) % 61 < 5 else 0.0)
				"panel": tone = .6 if (x == 0 or y % 32 == 0) else .9 + grain * .06
				"stone": tone = .76 + coarse * .14 + grain * .06
				"grass": tone = .55 + float((x * 53 + y * 29) % 19) / 19.0 * .5
				"ivy": tone = .4 + float((x * 31 + y * 57) % 11) / 11.0 * .65
				"paper": tone = .9 + grain * .08
				"corrugated": tone = .66 + .28 * float((x >> 2) % 2) + grain * .04
				"floor": tone = .42 if (x % 32 < 2 or y % 32 < 2) else .8 + grain * .15
				"plaster":
					if (x * 7 + (y / 9) * 13) % 71 < 9: tone *= .66
					if y > 43 and (x * 19 + y / 7) % 31 < 17: tone *= .72
				"concrete": tone = .74 + coarse * .14 + grain * .06 - (.08 if (x * 13 + y * 7) % 53 < 2 else 0.0)
				"dirt": tone = .62 + coarse * .3
				"rust": tone = .7 + coarse * .25
			image.set_pixel(x, y, Color(tone, tone, tone))
	mat.albedo_texture = ImageTexture.create_from_image(image)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.set_meta("wettable", key in ["floor", "concrete", "rust", "tile", "stone", "corrugated"])
	return mat

# ---------------------------------------------------------------- props

static func node_name(title: String) -> String:
	var result := ""
	for word in title.replace("'", "").replace("-", " ").replace("/", " ").replace(",", " ").replace("(", " ").replace(")", " ").split(" ", false):
		result += word.capitalize().replace(" ", "")
	return result

static func sign_id(title: String) -> String:
	var regex := RegEx.create_from_string("[^a-z0-9]+")
	return regex.sub(title.to_lower(), "_", true).strip_edges().trim_prefix("_").trim_suffix("_")

func spec_bounds(spec: String) -> AABB:
	if bounds_cache.has(spec): return bounds_cache[spec]
	var parts := spec.split(":")
	var result := AABB(Vector3(-.5, 0, -.5), Vector3.ONE)
	match parts[0]:
		"e":
			var variant: Dictionary = env[parts[1]].variants[int(parts[2]) if parts.size() > 2 else 0]
			var p: Array = variant.bounds.position; var s: Array = variant.bounds.size
			result = AABB(Vector3(p[0], p[1], p[2]), Vector3(s[0], s[1], s[2]))
		"m", "d":
			var path := ("res://scenes/props/medtac/detail/" if parts[0] == "m" else "res://scenes/props/district/") + parts[1] + ".tscn"
			if not cache.has(path): cache[path] = load(path)
			var probe: Node3D = cache[path].instantiate()
			result = probe.get_meta("bounds"); probe.free()
		"p":
			result = {"office_desk": AABB(Vector3(-.9, 0, -.425), Vector3(1.8, .8, .85)), "office_chair": AABB(Vector3(-.3, 0, -.3), Vector3(.6, 1.2, .6)),
				"campus_rack": AABB(Vector3(-2.1, 0, -.8), Vector3(4.2, 3.2, 1.6)), "water_pump": AABB(Vector3(-.9, 0, -.6), Vector3(1.8, 2.3, 1.2)),
				"fuel_tank": AABB(Vector3(-.95, 0, -.95), Vector3(1.9, 2.2, 1.9))}[parts[1]]
	bounds_cache[spec] = result
	return result

## Environment-catalog props face -Z; MedTac/district/procedural props face +Z.
static func front_yaw(spec: String, facing: Vector3) -> float:
	return atan2(-facing.x, -facing.z) if spec.begins_with("e:") else atan2(facing.x, facing.z)

func place(parent: Node3D, spec: String, at: Vector3, yaw := 0.0, solid := true) -> Node3D:
	var parts := spec.split(":")
	var node: Node3D
	match parts[0]:
		"m": node = asset(parent, parts[1], at, yaw, false, solid)
		"d": node = asset(parent, parts[1], at, yaw, true, solid)
		"p":
			node = equipment(parent, parts[1], at, yaw)
		"e":
			var path := ENV_DIR + parts[1] + "_" + (parts[2] if parts.size() > 2 else "0") + ".tscn"
			if not cache.has(path): cache[path] = load(path)
			node = cache[path].instantiate()
			assert(not node is SearchableFurniture, "decor prop must not be searchable: " + spec)
			add(parent, node); node.position = at; node.rotation.y = yaw
			if not solid:
				for child in node.find_children("*", "CollisionObject3D", true, false): child.collision_layer = 0
	node.set_meta("campus_equipment", spec); node.set_meta("bounds", spec_bounds(spec))
	if not solid: node.set_meta("nonsolid", true)
	if not node.has_meta("supported_by"): node.set_meta("supported_by", "floor")
	var key := spec.get_slice(":", 0) + ":" + spec.get_slice(":", 1)
	usage[key] = int(usage.get(key, 0)) + 1
	return node

# ---------------------------------------------------------------- loot

func profile_for(spec: String) -> String:
	var parts := spec.split(":")
	if parts[0] == "e": return env[parts[1]].storage.profile
	var model := parts[1]
	if model in ["med_cabinet", "medical_bag", "medicine_fridge"]: return "medical"
	if model in ["filing_cabinet", "desk_drawers"]: return "records"
	if model in ["personal_bag", "staff_locker"]: return "personal"
	if model == "security_locker": return "security_gear"
	if model == "weapon_crate" or model == "weapon_box": return "weapons"
	if model == "ammo_box": return "ammo"
	if model == "specimen_cooler": return "specimen"
	return "technical"

## A searchable furnishing whose table follows its container family and floor tier.
func make_source(parent: Node3D, spec: String, at: Vector3, yaw: float, opts := {}) -> SearchableFurniture:
	var parts := spec.split(":")
	var node: SearchableFurniture
	var bounds := spec_bounds(spec)
	if parts[0] == "m":
		node = furnishing(parent, at, parts[1])
		node.rotation.y = yaw
		for child in node.get_children():
			if child.scene_file_path.begins_with("res://scenes/props/medtac/detail/"): child.set_meta("nonsolid", true)
	else:
		var path := ENV_DIR + parts[1] + "_" + (parts[2] if parts.size() > 2 else "0") + ".tscn"
		if not cache.has(path): cache[path] = load(path)
		node = cache[path].instantiate()
		add(parent, node); node.position = at; node.rotation.y = yaw
		node.add_to_group("raid_entities", true)
	node.entity_id = "campus-storage-%03d" % source_serial; source_serial += 1
	node.name = node.entity_id
	var profile: String = opts.get("profile", profile_for(spec))
	if not CampusLoot.config().profiles.has(profile): profile = "technical"
	var source_tier: int = opts.get("tier", tier)
	node.loot_profile = profile
	node.keycard_candidate = opts.get("card", false)
	node.guaranteed_items = opts.get("guarantee", {})
	node.loot_table = CampusLoot.table(profile, source_tier, item_defs, node.container_config)
	node.locked = opts.get("locked", false)
	if node.locked: node.key_item = "medtac_keycard"
	var ransack: bool = opts.get("ransacked", rng.randf() < float(CampusLoot.tier_data(source_tier).ransacked))
	if ransack and not node.locked and node.guaranteed_items.is_empty() and not node.keycard_candidate:
		node.starts_empty = true
		if node.container_config == null: node.loot_table = null
		decayer.ransacked(self, node, parent)
	node.set_meta("campus_equipment", spec); node.set_meta("bounds", bounds)
	node.set_meta("loot_tier", source_tier); node.set_meta("campus_building", building_id); node.set_meta("campus_floor", floor_index)
	node.set_meta("campus_room", parent.get_meta("room_purpose", "")); node.set_meta("supported_by", "floor")
	var key := parts[0] + ":" + parts[1]
	usage[key] = int(usage.get(key, 0)) + 1
	return node

func loose(parent: Node3D, at: Vector3, item := "") -> void:
	var options := CampusLoot.loose_items(tier)
	if item.is_empty(): item = options[rng.randi_range(0, options.size() - 1)]
	pickup(parent, at, item)
	var node: Node3D = parent.get_child(parent.get_child_count() - 1)
	node.entity_id = "campus-loose-%03d" % loose_total; node.name = node.entity_id
	for child in node.get_children():
		if child.scene_file_path != "": child.set_meta("nonsolid", true)
	node.set_meta("loot_tier", tier); node.set_meta("campus_building", building_id); node.set_meta("campus_floor", floor_index)
	loose_total += 1

# ---------------------------------------------------------------- room placement

func room_box(rc: Dictionary) -> AABB:
	return AABB(Vector3(-rc.hw, -1, -rc.hd), Vector3(rc.hw * 2, 12, rc.hd * 2))

func spot_free(rc: Dictionary, box: AABB, ignore_zones := false) -> bool:
	if not room_box(rc).grow(.02).encloses(box): return false
	for other: AABB in rc.occupied:
		var overlap := other.intersection(box)
		if overlap.size.x > .04 and overlap.size.z > .04 and overlap.size.y > .04: return false
	if not ignore_zones:
		for zone: AABB in rc.zones:
			if zone.intersects(box): return false
	return true

func rotated(spec: String, yaw: float) -> AABB:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO) * spec_bounds(spec)

const INWARD := {"n": Vector3.BACK, "s": Vector3.FORWARD, "w": Vector3.RIGHT, "e": Vector3.LEFT}

## Finds a free position with the item's back against `wall`, nearest to fraction t.
func wall_spot(rc: Dictionary, wall: String, t: float, spec: String, gap := .06) -> Dictionary:
	var facing: Vector3 = INWARD[wall]
	var yaw := front_yaw(spec, facing)
	var box := rotated(spec, yaw)
	var along_x: bool = wall in ["n", "s"]
	var half: float = rc.hw if along_x else rc.hd
	var width: float = box.size.x if along_x else box.size.z
	if width > half * 2 - .1: return {}
	var lo := -half + width * .5 + .05
	var hi := half - width * .5 - .05
	var desired := lerpf(lo, hi, clampf(t, 0, 1))
	var steps: Array[float] = [0.0]
	for i in range(1, 40):
		steps.append(i * .25); steps.append(-i * .25)
	for step in steps:
		var a := desired + step
		if a < lo - .001 or a > hi + .001: continue
		var p := Vector3.ZERO
		match wall:
			"n": p = Vector3(a - box.get_center().x, 0, -rc.hd + gap - box.position.z)
			"s": p = Vector3(a - box.get_center().x, 0, rc.hd - gap - box.end.z)
			"w": p = Vector3(-rc.hw + gap - box.position.x, 0, a - box.get_center().z)
			"e": p = Vector3(rc.hw - gap - box.end.x, 0, a - box.get_center().z)
		var placed := AABB(box.position + p, box.size)
		if spot_free(rc, placed): return {"at": p, "yaw": yaw, "box": placed}
	return {}

func wall_item(rc: Dictionary, wall: String, t: float, spec: String, solid := true) -> Node3D:
	var spot := wall_spot(rc, wall, t, spec)
	if spot.is_empty(): return null
	rc.occupied.append(spot.box.grow(.04))
	return place(rc.node, spec, spot.at, spot.yaw, solid)

func free_item(rc: Dictionary, spec: String, at: Vector2, facing := Vector3.BACK, solid := true) -> Node3D:
	var yaw := front_yaw(spec, facing)
	var box := rotated(spec, yaw)
	var p := Vector3(at.x - box.get_center().x, 0, at.y - box.get_center().z)
	var placed := AABB(box.position + p, box.size)
	if not spot_free(rc, placed): return null
	rc.occupied.append(placed.grow(.04))
	return place(rc.node, spec, p, yaw, solid)

func wall_source(rc: Dictionary, wall: String, t: float, spec: String, opts := {}) -> SearchableFurniture:
	var spot := wall_spot(rc, wall, t, spec, .08)
	if spot.is_empty(): return null
	# Searchable fronts need a clear approach for the 3.5 m interaction ray.
	var front := AABB(spot.box.position + INWARD[wall] * .9, spot.box.size)
	if not spot_free(rc, front): return null
	rc.occupied.append(spot.box.grow(.04))
	rc.sources += 1
	return make_source(rc.node, spec, spot.at, spot.yaw, opts)

func free_source(rc: Dictionary, spec: String, at: Vector2, facing := Vector3.BACK, opts := {}) -> SearchableFurniture:
	var yaw := front_yaw(spec, facing)
	var box := rotated(spec, yaw)
	var p := Vector3(at.x - box.get_center().x, 0, at.y - box.get_center().z)
	var placed := AABB(box.position + p, box.size)
	if not spot_free(rc, placed): return null
	rc.occupied.append(placed.grow(.04))
	rc.sources += 1
	return make_source(rc.node, spec, p, yaw, opts)

## Loose sockets sit on furniture tops, never on the floor.
func loose_on(rc: Dictionary, surface: Node3D, count := 1, item := "") -> void:
	if surface == null: return
	var bounds: AABB = surface.get_meta("bounds")
	var top := bounds.end.y + .01
	for i in count:
		var local := Vector3(lerpf(bounds.position.x + .2, bounds.end.x - .2, (i + .5) / count), top, bounds.get_center().z)
		loose(rc.node, surface.transform * local, item)
		rc.loose += 1

func on_top(rc: Dictionary, surface: Node3D, spec: String, offset := Vector3.ZERO, solid := false) -> Node3D:
	if surface == null: return null
	var bounds: AABB = surface.get_meta("bounds")
	var node := place(rc.node, spec, surface.transform * Vector3(bounds.get_center().x + offset.x, bounds.end.y + .005, bounds.get_center().z + offset.z), surface.rotation.y, solid)
	node.set_meta("supported_by", surface.get_meta("campus_equipment"))
	return node

func cover_marker(parent: Node3D, at: Vector3, yaw := 0.0) -> void:
	var marker := Marker3D.new(); add(parent, marker, "Cover%d" % serial)
	marker.position = at; marker.rotation.y = yaw
	marker.add_to_group("district_cover", true)

# ---------------------------------------------------------------- decoration

func flat(parent: Node3D, at: Vector3, size: Vector3, key: String, yaw := 0.0) -> void:
	if is_zero_approx(yaw):
		box(parent, at, size, key, false)
		return
	var holder := section("Debris%d" % serial, at, parent); holder.rotation.y = yaw
	box(holder, Vector3.ZERO, size, key, false)

func papers(parent: Node3D, center: Vector3, spread: Vector2, count: int) -> void:
	for i in count:
		var at := center + Vector3(rng.randf_range(-spread.x, spread.x), .012 + i * .001, rng.randf_range(-spread.y, spread.y))
		flat(parent, at, Vector3(.21, .006, .3), "paper", rng.randf() * TAU)

func body(parent: Node3D, at: Vector3, yaw := 0.0, covered := true) -> void:
	var holder := section("CoveredBody%d" % serial, at, parent); holder.rotation.y = yaw
	box(holder, Vector3(0, .13, 0), Vector3(.55, .26, 1.7), "medical" if covered else "rubber", false)
	box(holder, Vector3(0, .17, -.75), Vector3(.35, .2, .3), "medical" if covered else "rubber", false)
	box(holder, Vector3(.1, .015, .2), Vector3(.9, .01, .7), "red", false)

func stain(parent: Node3D, at: Vector3, radius := .8, key := "red") -> void:
	for i in 3:
		flat(parent, at + Vector3(rng.randf_range(-radius, radius) * .5, .011 + i * .001, rng.randf_range(-radius, radius) * .5), Vector3(radius * rng.randf_range(.5, 1), .004, radius * rng.randf_range(.4, .9)), key, rng.randf() * TAU)

func printed_sign(parent: Node3D, identity: String, at: Vector3, yaw: float, width := 2.6) -> void:
	var path := SIGN_DIR + identity + ".png"
	if not ResourceLoader.exists(path): path = "res://assets/district/signs/" + identity + ".png"
	if not ResourceLoader.exists(path):
		push_error("Missing printed sign: " + identity); return
	var sign := MeshInstance3D.new(); var face := QuadMesh.new(); face.size = Vector2(width, width * .1875); sign.mesh = face
	var material := StandardMaterial3D.new(); material.albedo_texture = load(path)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST; material.roughness = .95
	sign.material_override = material
	sign.position = at; sign.rotation.y = yaw; sign.set_meta("sign_text", identity)
	add(parent, sign, "Sign%d" % serial)
	box(parent, at - Basis(Vector3.UP, yaw) * Vector3(0, 0, .02), Vector3(width + .08, width * .1875 + .08, .03) if is_zero_approx(fmod(absf(yaw), PI)) else Vector3(.03, width * .1875 + .08, width + .08), "steel", false)

func light(parent: Node3D, at: Vector3, emergency := false, reach := 9.0) -> void:
	lamp(parent, at, emergency)
	var fixture: Node = parent.get_child(parent.get_child_count() - 1)
	fixture.entity_id = "campus-fixture-%04d" % light_serial; fixture.name = fixture.entity_id
	light_serial += 1
	for child in fixture.get_children():
		if child is OmniLight3D:
			child.omni_range = reach; child.distance_fade_begin = 32; child.distance_fade_length = 12
			child.light_energy = 1.3 if emergency else .9

# ---------------------------------------------------------------- wall network

func line(h: bool, c: float) -> Dictionary:
	var key := ("h%.2f" if h else "v%.2f") % c
	if not lines.has(key): lines[key] = {"h": h, "c": c, "spans": [], "cuts": [], "glass": []}
	return lines[key]

func add_span(h: bool, c: float, a: float, b: float) -> void:
	line(h, c).spans.append(Vector2(minf(a, b), maxf(a, b)))

func add_rect_lines(r: Rect2) -> void:
	add_span(true, r.position.y, r.position.x, r.end.x); add_span(true, r.end.y, r.position.x, r.end.x)
	add_span(false, r.position.x, r.position.y, r.end.y); add_span(false, r.end.x, r.position.y, r.end.y)

func add_cut(h: bool, c: float, center: float, width: float, kind: String, inward: Vector3, owner_name := "") -> void:
	var record := line(h, c)
	for cut: Dictionary in record.cuts:
		if absf(cut.center - center) < .6: return
	record.cuts.append({"center": center, "width": width, "kind": kind, "inward": inward, "room": owner_name})

func near_opening(h: bool, c: float, pos: float, margin := 1.5) -> bool:
	for id: String in lines:
		var record: Dictionary = lines[id]
		if record.h != h or absf(record.c - c) > .35: continue
		for cut: Dictionary in record.cuts:
			if absf(cut.center - pos) < cut.width * .5 + margin: return true
	return false

## True when a solid wall run (no opening) covers [pos - half, pos + half] on this line.
func wall_covers(h: bool, c: float, pos: float, half: float) -> bool:
	for id: String in lines:
		var record: Dictionary = lines[id]
		if record.h != h or absf(record.c - c) > .3: continue
		for cut: Dictionary in record.cuts:
			if absf(cut.center - pos) < cut.width * .5 + half + 1.0: return false
		for span: Vector2 in merge(record.spans):
			if span.x <= pos - half - .3 and span.y >= pos + half + .3: return true
	return false

func add_glass(h: bool, c: float, a: float, b: float) -> void:
	line(h, c).glass.append(Vector2(minf(a, b), maxf(a, b)))

static func merge(spans: Array) -> Array:
	var sorted := spans.duplicate(); sorted.sort_custom(func(a, b): return a.x < b.x)
	var result: Array = []
	for span: Vector2 in sorted:
		if not result.is_empty() and span.x <= result[-1].y + .01: result[-1] = Vector2(result[-1].x, maxf(result[-1].y, span.y))
		else: result.append(span)
	return result

static func subtract(spans: Array, cuts: Array) -> Array:
	var result := spans.duplicate()
	for cut: Vector2 in cuts:
		var next: Array = []
		for span: Vector2 in result:
			if cut.y <= span.x or cut.x >= span.y: next.append(span); continue
			if cut.x > span.x + .02: next.append(Vector2(span.x, cut.x))
			if cut.y < span.y - .02: next.append(Vector2(cut.y, span.y))
		result = next
	return result

func on_boundary(h: bool, c: float, bounds: Rect2) -> bool:
	if h: return is_equal_approx(c, bounds.position.y) or is_equal_approx(c, bounds.end.y)
	return is_equal_approx(c, bounds.position.x) or is_equal_approx(c, bounds.end.x)

func wall_box(parent: Node3D, h: bool, c: float, a: float, b: float, y0: float, y1: float, key: String, thick := .2, solid := true) -> void:
	if b - a < .04 or y1 - y0 < .02: return
	var mid := (a + b) * .5
	var at := Vector3(mid, (y0 + y1) * .5, c) if h else Vector3(c, (y0 + y1) * .5, mid)
	var size := Vector3(b - a, y1 - y0, thick) if h else Vector3(thick, y1 - y0, b - a)
	if solid and y1 - y0 > 2.5: wall(parent, at, size, key)
	else: box(parent, at, size, key, solid)

func glass_panel(parent: Node3D, h: bool, c: float, a: float, b: float, y0: float, y1: float) -> void:
	var node := MedTacBreakable.new(); node.entity_id = "campus-glass-%04d" % glass_serial; glass_serial += 1
	node.kind = "glass"; node.material = steel
	add(parent, node, node.entity_id)
	var mid := (a + b) * .5
	node.position = Vector3(mid, (y0 + y1) * .5, c) if h else Vector3(c, (y0 + y1) * .5, mid)
	kits[node] = WorldMeshKit.new()
	var size := Vector3(b - a, y1 - y0, .05) if h else Vector3(.05, y1 - y0, b - a)
	box(node, Vector3.ZERO, size, "glass", false)
	var shape := BoxShape3D.new(); shape.size = size
	var collision := CollisionShape3D.new(); collision.shape = shape; add(node, collision, "CollisionShape3D")

func build_walls(parent: Node3D, bounds: Rect2, key := "plaster") -> void:
	for id: String in lines:
		var record: Dictionary = lines[id]
		if on_boundary(record.h, record.c, bounds): continue
		var spans := merge(record.spans)
		var openings: Array = []
		for cut: Dictionary in record.cuts: openings.append(Vector2(cut.center - cut.width * .5, cut.center + cut.width * .5))
		var glazing := merge(record.glass)
		for piece: Vector2 in subtract(spans, openings):
			var solid_parts := subtract([piece], glazing)
			for part: Vector2 in solid_parts:
				wall_box(parent, record.h, record.c, part.x, part.y, 0, WALL_H, key)
				wall_box(parent, record.h, record.c, part.x, part.y, 0, .1, "rubber", .26, false)
			for pane: Vector2 in glazing:
				var a := maxf(pane.x, piece.x); var b := minf(pane.y, piece.y)
				if b - a < .2: continue
				wall_box(parent, record.h, record.c, a, b, 0, 1.0, key)
				wall_box(parent, record.h, record.c, a, b, 2.5, WALL_H, key)
				glass_panel(parent, record.h, record.c, a, b, 1.0, 2.5)
				for edge in [a, b]: wall_box(parent, record.h, record.c, edge - .04, edge + .04, 1.0, 2.5, "steel", .12, false)
		for cut: Dictionary in record.cuts:
			var covered := false
			for span: Vector2 in spans:
				if cut.center > span.x and cut.center < span.y: covered = true
			if not covered: continue
			opening(parent, record.h, record.c, cut)

func opening(parent: Node3D, h: bool, c: float, cut: Dictionary, top := WALL_H, exterior := false) -> void:
	var a: float = cut.center - cut.width * .5
	var b: float = cut.center + cut.width * .5
	var head := DOOR_H if cut.width <= 2.5 else 3.0
	wall_box(parent, h, c, a, b, head, top, "plaster" if not exterior else "concrete", .3 if exterior else .2)
	for edge in [a, b]: wall_box(parent, h, c, edge - .05, edge + .05, 0, head, "steel", .3 if exterior else .26, false)
	var at := Vector3(cut.center, 0, c) if h else Vector3(c, 0, cut.center)
	match cut.kind:
		"door", "glass", "vault", "extdoor": make_door(parent, at, h, cut.width, cut.kind, cut.inward)
		"broken":
			var fallen := section("FallenDoor%d" % serial, at + cut.inward * 1.3, parent)
			fallen.rotation.y = 0.0 if h else PI * .5
			box(fallen, Vector3(0, .05, 0), Vector3(1.9, .06, 1.0), "paint", false)

func make_door(parent: Node3D, at: Vector3, h: bool, width: float, kind: String, inward: Vector3) -> RaidDoor:
	var door := RaidDoor.new(); door.entity_id = "campus-door-%03d" % door_serial; door_serial += 1
	door.material = steel; door.restricted = kind == "vault"
	door.position = at + Vector3.UP * 1.2
	add(parent, door, door.entity_id)
	door.rotation.y = 0.0 if h else PI * .5
	door.inside_direction = (Basis(Vector3.UP, door.rotation.y).inverse() * inward).normalized()
	var visual := MeshInstance3D.new(); var mesh := BoxMesh.new(); mesh.size = Vector3(width - .06, 2.38, .1); visual.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = {"door": Color("8a948a"), "glass": Color("5f7c7a"), "vault": Color("6e5a40"), "extdoor": Color("5d6a66")}[kind]
	mat.roughness = .8; visual.material_override = mat
	add(door, visual, "Panel")
	var collision := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size = mesh.size; collision.shape = shape
	add(door, collision, "CollisionShape3D")
	if kind == "vault":
		var link := NavigationLink3D.new()
		link.start_position = at - inward * 1.6 + Vector3.UP * .1; link.end_position = at + inward * 1.6 + Vector3.UP * .1; link.enabled = false
		add(parent, link, "VaultLink%d" % door_serial); door.traversal_link = door.get_path_to(link)
		printed_sign(parent, "restricted", at - inward * .14 + Vector3.UP * 2.75, atan2(-inward.x, -inward.z), 2.4)
	doors.append(door)
	return door

# ---------------------------------------------------------------- façades

func facade(parent: Node3D, bounds: Rect2, style: String, party: Array, extra_cuts: Array) -> void:
	var node := section("Facade", Vector3.ZERO, parent)
	var bay: float = {"curtain": 1.6, "ribbon": 2.0, "office": 2.0, "industrial": 4.0}[style]
	for side in ["n", "s", "w", "e"]:
		if side in party: continue
		var h: bool = side in ["n", "s"]
		var c: float = {"n": bounds.position.y, "s": bounds.end.y, "w": bounds.position.x, "e": bounds.end.x}[side]
		var a: float = bounds.position.x if h else bounds.position.y
		var b: float = bounds.end.x if h else bounds.end.y
		var outward: Vector3 = -INWARD[side]
		var cuts: Array = []
		var openings: Array = []
		for cut: Dictionary in facade_cuts + extra_cuts:
			if cut.side != side: continue
			cuts.append(cut)
			openings.append(Vector2(cut.pos - cut.width * .5, cut.pos + cut.width * .5))
		for piece: Vector2 in subtract([Vector2(a, b)], openings):
			var count := maxi(1, roundi((piece.y - piece.x) / bay))
			var step := (piece.y - piece.x) / count
			for i in count:
				var x0 := piece.x + i * step; var x1 := x0 + step
				var mid := (x0 + x1) * .5
				var probe := Vector2(mid, c - outward.z * .5) if h else Vector2(c - outward.x * .5, mid)
				facade_bay(node, h, c, x0, x1, style, window_role(probe), outward, i)
		for cut: Dictionary in cuts:
			var record := {"center": cut.pos, "width": cut.width, "kind": cut.kind, "inward": -outward}
			opening(node, h, c, record, WALL_H, true)
			if cut.kind == "ext":
				# A canopy marks each public entrance; posts stay outside the walking line.
				var at := (Vector3(cut.pos, 0, c) if h else Vector3(c, 0, cut.pos)) + outward * 1.6
				var size := Vector3(cut.width + 2, .2, 3.2) if h else Vector3(3.2, .2, cut.width + 2)
				box(node, at + Vector3.UP * 3.3, size, "steel")
				for s in [-1, 1]:
					var post := at + outward * 1.3 + (Vector3(s * (cut.width * .5 + .8), 1.65, 0) if h else Vector3(0, 1.65, s * (cut.width * .5 + .8)))
					box(node, post, Vector3(.18, 3.3, .18), "steel")
	if floor_index > 1:
		for side in ["n", "s", "w", "e"]:
			if side in party: continue
			var h: bool = side in ["n", "s"]
			var c: float = {"n": bounds.position.y, "s": bounds.end.y, "w": bounds.position.x, "e": bounds.end.x}[side]
			var outward: Vector3 = -INWARD[side]
			var length: float = bounds.size.x if h else bounds.size.y
			var center := Vector3(bounds.get_center().x, -.1, c) if h else Vector3(c, -.1, bounds.get_center().y)
			box(node, center + outward * .2, Vector3(length + .5, .36, .14) if h else Vector3(.14, .36, length + .5), "stone" if style == "curtain" else "panel" if style == "ribbon" else "concrete", false)

func room_role_at(probe: Vector2) -> String:
	for spec: Dictionary in floor_rooms:
		if (spec.rect as Rect2).grow(.01).has_point(probe): return spec.role
	return "corridor"

func window_role(probe: Vector2) -> bool:
	for spec: Dictionary in floor_rooms:
		if (spec.rect as Rect2).grow(.01).has_point(probe): return spec.role in WINDOWED
	return true

func facade_bay(node: Node3D, h: bool, c: float, a: float, b: float, style: String, windowed: bool, outward: Vector3, index: int) -> void:
	var skin: String = {"curtain": "stone", "ribbon": "panel", "office": "concrete", "industrial": "corrugated"}[style]
	var top := WALL_H
	if not windowed or style == "industrial":
		wall_box(node, h, c, a, b, 0, top, skin, .3)
	else:
		var sill: float = {"curtain": .55, "ribbon": 1.0, "office": .9}[style]
		var head: float = {"curtain": 3.55, "ribbon": 2.6, "office": 2.5}[style]
		wall_box(node, h, c, a, b, 0, sill, skin, .3)
		wall_box(node, h, c, a, b, head, top, skin, .3)
		var mid := (a + b) * .5
		var role := room_role_at(Vector2(mid, c - outward.z * .5) if h else Vector2(c - outward.x * .5, mid))
		var state: String = decayer.window(self, node, h, c, a, b, sill, head, outward, role)
		var id := "%s/%d" % [building_id, floor_index]
		if not window_states.has(id): window_states[id] = {}
		window_states[id][state] = int(window_states[id].get(state, 0)) + 1
		wall_box(node, h, c, a - .04, a + .04, sill, head, "steel", .34, false)
	decayer.facade_base(self, node, h, c, a, b, outward)
	if style == "curtain" and (int(a / 4.8) + floor_index) % 4 == 0 and windowed:
		# Stepped stone frames break the curtain wall into staggered boxes.
		var mid := (a + b) * .5
		var at := (Vector3(mid, 0, c) if h else Vector3(c, 0, mid)) + outward * .45
		box(node, at + Vector3.UP * (top - .12), Vector3(b - a + .02, .24, .6) if h else Vector3(.6, .24, b - a + .02), "stone", false)
		box(node, at + Vector3.UP * .1, Vector3(b - a + .02, .2, .6) if h else Vector3(.6, .2, b - a + .02), "stone", false)
	if rng.randf() < (.3 if floor_index <= 2 else .14):
		# Ivy climbs from the ground floors and thins out higher up.
		var mid := (a + b) * .5 + rng.randf_range(-.4, .4)
		var at := (Vector3(mid, 0, c) if h else Vector3(c, 0, mid)) + outward * .2
		var height := rng.randf_range(1.6, WALL_H)
		box(node, at + Vector3.UP * height * .5, Vector3(rng.randf_range(.5, 1.3), height, .08) if h else Vector3(.08, height, rng.randf_range(.5, 1.3)), "ivy", false)
	if style == "industrial" and index % 2 == 0:
		box(node, (Vector3((a + b) * .5, 0, c) if h else Vector3(c, 0, (a + b) * .5)) + outward * .2 + Vector3.UP * 3.0, Vector3(b - a - .4, .9, .06) if h else Vector3(.06, .9, b - a - .4), "glass", false)

# ---------------------------------------------------------------- cores

func stair_hole(core: Dictionary) -> Rect2:
	var r: Rect2 = core.rect
	match core.landing:
		"n": return Rect2(r.position.x, r.position.y + 2.0, r.size.x, r.size.y - 2.0)
		"s": return Rect2(r.position.x, r.position.y, r.size.x, r.size.y - 2.0)
		"w": return Rect2(r.position.x + 2.0, r.position.y, r.size.x - 2.0, r.size.y)
	return Rect2(r.position.x, r.position.y, r.size.x - 2.0, r.size.y)

static func core_yaw(core: Dictionary) -> float:
	return {"s": 0.0, "n": PI, "e": PI * .5, "w": -PI * .5}[core.landing]

func core_frame(core: Dictionary) -> Transform3D:
	var r: Rect2 = core.rect
	return Transform3D(Basis(Vector3.UP, core_yaw(core)), Vector3(r.get_center().x, 0, r.get_center().y))

func stair_core(parent: Node3D, core: Dictionary, flights: bool, guard_top: bool) -> void:
	var r: Rect2 = core.rect
	add_rect_lines(r)
	var frame := core_frame(core)
	var door_at := frame * Vector3(0, 0, 4.5)
	var h: bool = core.landing in ["n", "s"]
	add_cut(h, door_at.z if h else door_at.x, door_at.x if h else door_at.z, 2.0, core.get("door", "door"), frame.basis * Vector3.FORWARD, core.id)
	var node := section(core.id, frame.origin, parent)
	node.rotation.y = core_yaw(core)
	node.set_meta("campus_core", core.id)
	if flights:
		# 2 m landings at both ends leave agents a clear turn around the divider.
		for flight in [[-2.05, -.15, 2.5, 0.0, -2.5, 2.1], [.15, 2.05, -2.5, 2.1, 2.5, FH]]:
			var points := PackedVector3Array()
			for x in [flight[0], flight[1]]:
				points.append_array([Vector3(x, flight[3] - .25, flight[2]), Vector3(x, flight[5] - .25, flight[4]), Vector3(x, flight[5], flight[4]), Vector3(x, flight[3], flight[2])])
			var shape := ConvexPolygonShape3D.new(); shape.points = points; collider(node, Vector3.ZERO, shape, "concrete")
			for i in 12:
				var t := (i + .5) / 12.0
				var z := lerpf(flight[2], flight[4], t)
				var y := lerpf(flight[3], flight[5], (i + 1) / 12.0)
				box(node, Vector3((flight[0] + flight[1]) * .5, y - .09, z), Vector3(absf(flight[1] - flight[0]), .18, .42), "concrete", false)
			var lane: float = (flight[0] + flight[1]) * .5
			var rail_x: float = flight[0] if lane < 0 else flight[1]
			for i in 7:
				var t := i / 6.0
				box(node, Vector3(rail_x + (.04 if lane > 0 else -.04), lerpf(flight[3], flight[5], t) + .5, lerpf(flight[2], flight[4], t)), Vector3(.05, 1.0, .05), "rust", false)
		box(node, Vector3(0, 2.1 - .09, -3.5), Vector3(4.3, .18, 2.0), "concrete")
		box(node, Vector3(0, FH * .5, 0), Vector3(.24, FH, 5.0), "concrete")
		var waypoints: Array[Vector3] = []
		for local in [Vector3(0, .05, 3.6), Vector3(-1.1, .05, 2.2), Vector3(-1.1, 2.15, -2.8), Vector3(0, 2.15, -3.6), Vector3(1.1, 2.15, -2.8), Vector3(1.1, FH + .05, 2.2), Vector3(0, FH + .05, 3.6)]:
			waypoints.append(world_transform(node) * local)
		stair_log.append({"building": building_id, "core": core.id, "from": floor_index, "to": floor_index + 1, "points": waypoints})
	if guard_top:
		box(node, Vector3(-1.1, .55, 2.5), Vector3(2.15, 1.1, .08), "rust")
		box(node, Vector3(0, .55, 0), Vector3(.24, 1.1, 5.0), "concrete")
	var label := "level_%d_%s" % [floor_index, building_id]
	printed_sign(node, label, Vector3(0, 2.6, 4.38), PI, 2.2)
	light(node, Vector3(0, CEIL - .1, 3.6), true, 7.0)

func lift(parent: Node3D, core: Dictionary) -> void:
	var r: Rect2 = core.rect
	var cars: int = core.get("cars", 1)
	add_rect_lines(r)
	var along_x: bool = core.side in ["n", "s"]
	var length: float = r.size.x if along_x else r.size.y
	for i in range(1, cars):
		var at: float = (r.position.x if along_x else r.position.y) + length * i / cars
		if along_x: add_span(false, at, r.position.y, r.end.y)
		else: add_span(true, at, r.position.x, r.end.x)
	var outward: Vector3 = -INWARD[core.side]
	var face: float = {"n": r.position.y, "s": r.end.y, "w": r.position.x, "e": r.end.x}[core.side]
	var node := section(core.id, Vector3.ZERO, parent)
	for i in cars:
		var mid: float = (r.position.x if along_x else r.position.y) + length * (i + .5) / cars
		var at := (Vector3(mid, 0, face) if along_x else Vector3(face, 0, mid)) + outward * .13
		var ajar: bool = core.get("stuck", 0) == floor_index and i == 0
		for s in [-1, 1]:
			var shift: float = (.35 if ajar else .0) * s
			var leaf := at + (Vector3(s * .45 + shift, 1.1, 0) if along_x else Vector3(0, 1.1, s * .45 + shift))
			box(node, leaf, Vector3(.88, 2.2, .05) if along_x else Vector3(.05, 2.2, .88), "steel", false)
		box(node, at + Vector3.UP * 2.35 + (Vector3.ZERO), Vector3(2.0, .2, .08) if along_x else Vector3(.08, .2, 2.0), "steel", false)
		box(node, at + (Vector3(1.25, 1.2, 0) if along_x else Vector3(0, 1.2, 1.25)), Vector3(.12, .3, .04) if along_x else Vector3(.04, .3, .12), "warning", false)
		if ajar: box(node, at - outward * .3 + Vector3.UP * 1.1, Vector3(.6, 2.2, .05) if along_x else Vector3(.05, 2.2, .6), "rubber", false)

# ---------------------------------------------------------------- rooms

static func parse_door(token: String) -> Dictionary:
	var p := token.split(":")
	var kind := p[2] if p.size() > 2 else "door"
	var width := float(p[3]) if p.size() > 3 else (3.6 if kind == "ext" else 3.0 if kind == "extopen" else 2.0)
	return {"side": p[0], "pos": float(p[1]), "kind": kind, "width": width}

func plan_room(parent: Node3D, spec: Dictionary) -> Node3D:
	var r: Rect2 = spec.rect
	var title: String = spec.name
	var role: String = spec.role
	var node := section(node_name(title), Vector3(r.get_center().x, 0, r.get_center().y), parent)
	var hw := r.size.x * .5 - .25
	var hd := r.size.y * .5 - .25
	node.set_meta("room_purpose", title); node.set_meta("room_role", role)
	node.set_meta("room_bounds", AABB(Vector3(-hw, 0, -hd), Vector3(hw * 2, 3.2, hd * 2)))
	node.set_meta("campus_building", building_id); node.set_meta("campus_floor", floor_index); node.set_meta("loot_tier", spec.get("tier", tier))
	add_rect_lines(r)
	floor_rooms.append(spec)
	var rc := {"node": node, "spec": spec, "role": role, "hw": hw, "hd": hd, "occupied": [], "zones": [], "rect": r, "title": title, "tier": spec.get("tier", tier), "sources": 0, "loose": 0, "kit": self}
	var entrances: Array[Vector3] = []
	var entry := Vector3.ZERO
	var signed := false
	for token: String in spec.get("doors", []):
		var d := parse_door(token)
		var h: bool = d.side in ["n", "s"]
		var c: float = {"n": r.position.y, "s": r.end.y, "w": r.position.x, "e": r.end.x}[d.side]
		var inward: Vector3 = INWARD[d.side]
		var local := Vector3(d.pos - r.get_center().x, 0, c - r.get_center().y) if h else Vector3(c - r.get_center().x, 0, d.pos - r.get_center().y)
		var exterior := on_boundary(h, c, plan.bounds)
		if exterior and d.side in plan.get("party", []):
			var wp := world_transform(parent) * (Vector3(d.pos, 0, c) if h else Vector3(c, 0, d.pos))
			party_cuts.append({"building": building_id, "floor": floor_index, "world": wp.x if h else wp.z, "width": d.width, "kind": d.kind})
		elif exterior: facade_cuts.append({"side": d.side, "pos": d.pos, "kind": d.kind, "width": d.width})
		else: add_cut(h, c, d.pos, d.width, d.kind, inward, title)
		entrances.append(local)
		if entry == Vector3.ZERO: entry = local - inward * .9 + Vector3.UP * .1
		var along := Vector3(d.width + .7, 4, 1.9) if h else Vector3(1.9, 4, d.width + .7)
		rc.zones.append(AABB(local + inward * .95 - along * .5 + Vector3.UP * 2, along))
		if not signed and not exterior and not d.kind.begins_with("ext"):
			signed = true
			var outward := -inward
			printed_sign(node, sign_id(title), local + outward * .14 + Vector3.UP * 2.78, atan2(outward.x, outward.z), 2.4)
	# Keep approaches clear for every opening on this room's walls, including
	# doors that neighbouring rooms, cores and partitions declared.
	for id: String in lines:
		var record: Dictionary = lines[id]
		var on_edge: bool = (record.h and (is_equal_approx(record.c, r.position.y) or is_equal_approx(record.c, r.end.y))) or (not record.h and (is_equal_approx(record.c, r.position.x) or is_equal_approx(record.c, r.end.x)))
		if not on_edge: continue
		for cut: Dictionary in record.cuts:
			var lo: float = r.position.x if record.h else r.position.y
			var hi: float = r.end.x if record.h else r.end.y
			if cut.center <= lo or cut.center >= hi: continue
			var inward: Vector3
			if record.h: inward = Vector3.BACK if is_equal_approx(record.c, r.position.y) else Vector3.FORWARD
			else: inward = Vector3.RIGHT if is_equal_approx(record.c, r.position.x) else Vector3.LEFT
			var local := Vector3(cut.center - r.get_center().x, 0, record.c - r.get_center().y) if record.h else Vector3(record.c - r.get_center().x, 0, cut.center - r.get_center().y)
			var along := Vector3(cut.width + .7, 4, 1.9) if record.h else Vector3(1.9, 4, cut.width + .7)
			rc.zones.append(AABB(local + inward * .95 - along * .5 + Vector3.UP * 2, along))
	node.set_meta("entrance_points", entrances)
	node.set_meta("entry_local", entry)
	for pane: Array in spec.get("glass", []):
		var side: String = pane[0]
		var h: bool = side in ["n", "s"]
		add_glass(h, {"n": r.position.y, "s": r.end.y, "w": r.position.x, "e": r.end.x}[side], pane[1], pane[2])
	var area := r.size.x * r.size.y
	if area >= 14 and role not in ["riser", "restroom"]:
		if area > 150:
			var along_x := r.size.x > r.size.y
			for s in [-1, 1]: light(node, Vector3(s * r.size.x * .25, CEIL - .12, 0) if along_x else Vector3(0, CEIL - .12, s * r.size.y * .25), false, 10.0)
		else: light(node, Vector3(0, CEIL - .12, 0), false, 8.0)
	var t0 := Time.get_ticks_usec()
	dresser.dress(self, rc)
	t0 = lap("dress:" + role, t0)
	weather_room(rc)
	t0 = lap("weather", t0)
	var placed_equipment: Array[String] = []
	for child in node.get_children():
		if child.has_meta("campus_equipment"): placed_equipment.append(child.get_meta("campus_equipment"))
	room_log.append({"name": title, "building": building_id, "floor": floor_index, "tier": rc.tier, "role": role, "rect": [r.position.x, r.position.y, r.size.x, r.size.y], "area_m2": snappedf(area, .1), "doors": spec.get("doors", []), "sources": rc.sources, "loose": rc.loose, "equipment": placed_equipment, "node": node})
	return node

func weather_room(rc: Dictionary) -> void:
	decayer.room(self, rc)
	for i in 2:
		var marker := Vector3((-1 if i == 0 else 1) * (rc.hw - .9), .1, rng.randf_range(-rc.hd * .4, rc.hd * .4))
		cover_marker(rc.node, marker, 0.0 if i == 0 else PI)

# ---------------------------------------------------------------- floors

func ceiling(parent: Node3D, bounds: Rect2, holes: Array[Rect2]) -> void:
	var node := section("Ceiling", Vector3.ZERO, parent)
	var cut: Array[Rect2] = []
	cut.append_array(holes)
	var decay_profile: Dictionary = decayer.profile(building_id, floor_index)
	for i in int(bounds.get_area() / 160.0 * (.5 + decay_profile.wet + decay_profile.scav * .4)):
		var at := Vector2(rng.randf_range(bounds.position.x + 2, bounds.end.x - 3), rng.randf_range(bounds.position.y + 2, bounds.end.y - 3))
		var tile := Rect2(snappedf(at.x, .5), snappedf(at.y, .5), 1.0 if rng.randf() < .6 else 1.5, .5 if rng.randf() < .5 else 1.0)
		var clear := true
		for hole in holes:
			if hole.grow(.5).intersects(tile): clear = false
		if not clear: continue
		cut.append(tile)
		# Fallen tiles lie below the missing panels; exposed services hang through.
		flat(node, Vector3(tile.get_center().x + rng.randf_range(-.4, .4), .02, tile.get_center().y + rng.randf_range(-.4, .4)), Vector3(.5, .02, .5), "ceiling", rng.randf() * TAU)
		box(node, Vector3(tile.get_center().x, CEIL + .25, tile.get_center().y), Vector3(.05, .5, .05), "rubber", false)
		if rng.randf() < .4:
			# A duct or cable loom sags through the gap, kept above head height.
			var sag := section("SaggingService%d" % serial, Vector3(tile.get_center().x, CEIL - .15, tile.get_center().y), node)
			sag.rotation = Vector3(rng.randf_range(-.35, .35), rng.randf() * TAU, rng.randf_range(-.2, .2))
			box(sag, Vector3.ZERO, Vector3(.45, .3, 1.6) if rng.randf() < .5 else Vector3(.08, .08, 2.2), "steel" if rng.randf() < .5 else "rubber", false)
		if rng.randf() < .2: flat(node, Vector3(tile.get_center().x + .3, .03, tile.get_center().y - .2), Vector3(1.0, .06, .3), "steel", rng.randf() * TAU)
	var pieces: Array[PackedVector2Array] = [polygon(bounds)]
	for hole in cut:
		var next: Array[PackedVector2Array] = []
		for piece in pieces: next.append_array(DistrictSurfaceGeometry.subtract(piece, polygon(hole)))
		pieces = next
	var kit: WorldMeshKit = kits[node]
	for piece in pieces:
		var indices := Geometry2D.triangulate_polygon(piece)
		for i in range(0, indices.size(), 3):
			var a := piece[indices[i]]; var b := piece[indices[i + 1]]; var c := piece[indices[i + 2]]
			kit.tri(Vector3(a.x, CEIL, a.y), Vector3(b.x, CEIL, b.y), Vector3(c.x, CEIL, c.y), Vector3.DOWN, "ceiling")

func floor_holes(levels_below: bool) -> Array[Rect2]:
	var holes: Array[Rect2] = []
	if not levels_below: return holes
	for core: Dictionary in plan.cores:
		if core.kind == "stair" and floor_index - 1 < int(core.top): holes.append(stair_hole(core))
	if plan.has("atrium"): holes.append(plan.atrium)
	return holes

func build_building(data: Dictionary) -> Node3D:
	plan = data
	building_id = data.id
	var bounds: Rect2 = data.bounds
	building_node = section("Building_" + data.id, data.origin)
	building_node.set_meta("building_id", data.id); building_node.set_meta("enterable", true)
	building_node.set_meta("building_bounds", AABB(Vector3(bounds.position.x, 0, bounds.position.y), Vector3(bounds.size.x, data.levels.size() * FH + 1.2, bounds.size.y)))
	building_node.set_meta("building_title", data.title)
	building_nodes.append(building_node)
	var footprint := PackedVector2Array()
	for p in polygon(bounds): footprint.append(p + Vector2(data.origin.x, data.origin.z))
	building_footprints.append(footprint)
	for level: Dictionary in data.levels: build_floor(level)
	build_roof()
	return building_node

func build_floor(level: Dictionary) -> Node3D:
	floor_index = level.floor; tier = level.tier
	lines.clear(); facade_cuts.clear(); floor_rooms.clear()
	floor_node = section("Floor%d" % floor_index, Vector3(0, (floor_index - 1) * FH, 0), building_node)
	floor_node.set_meta("campus_floor", floor_index); floor_node.set_meta("loot_tier", tier)
	floor_node.set_meta("floor_title", level.title); floor_node.set_meta("campus_building", building_id)
	split_scenes.append({"node": floor_node, "path": "res://scenes/raid/campus/%s/floor_%d.tscn" % [building_id, floor_index]})
	var bounds: Rect2 = plan.bounds
	var holes := floor_holes(floor_index > 1)
	foundation(floor_node, bounds, 0, holes, level.get("floor_key", "lino"))
	for core: Dictionary in plan.cores:
		match core.kind:
			"stair": stair_core(floor_node, core, floor_index < int(core.top), floor_index == int(core.top))
			"lift": lift(floor_node, core)
	# Register every interior opening first so each room is dressed knowing
	# all the doors on its walls.
	for spec: Dictionary in level.rooms:
		var r: Rect2 = spec.rect
		for token: String in spec.get("doors", []):
			var d := parse_door(token)
			var h: bool = d.side in ["n", "s"]
			var c: float = {"n": r.position.y, "s": r.end.y, "w": r.position.x, "e": r.end.x}[d.side]
			if not on_boundary(h, c, bounds): add_cut(h, c, d.pos, d.width, d.kind, INWARD[d.side], spec.name)
	for part: Dictionary in level.get("partitions", []):
		var a: Vector2 = part.a; var b: Vector2 = part.b
		var h := is_equal_approx(a.y, b.y)
		var c := a.y if h else a.x
		add_span(h, c, a.x if h else a.y, b.x if h else b.y)
		for token: String in part.get("doors", []):
			var bits := token.split(":")
			add_cut(h, c, float(bits[0]), 2.0, bits[1] if bits.size() > 1 else "door", Vector3.BACK if h else Vector3.RIGHT, "partition")
	for spec: Dictionary in level.rooms: plan_room(floor_node, spec)
	if plan.has("atrium"): atrium(floor_node, plan.atrium)
	var t0 := Time.get_ticks_usec()
	var walls := section("Walls", Vector3.ZERO, floor_node)
	build_walls(walls, bounds, level.get("wall_key", "plaster"))
	t0 = lap("walls", t0)
	facade(floor_node, bounds, plan.style, plan.get("party", []), level.get("facade_doors", []))
	t0 = lap("facade", t0)
	var ceiling_holes: Array[Rect2] = []
	for core: Dictionary in plan.cores:
		if core.kind == "stair": ceiling_holes.append((core.rect as Rect2).grow(.1))
	if plan.has("atrium"): ceiling_holes.append(plan.atrium)
	if plan.has("roof_failure") and floor_index == plan.levels.size():
		ceiling_holes.append(plan.roof_failure)
		roof_failure_below(floor_node, plan.roof_failure)
	ceiling(floor_node, bounds, ceiling_holes)
	t0 = lap("ceiling", t0)
	corridors(floor_node, level)
	t0 = lap("corridors", t0)
	for item: Array in level.get("story", []): dresser.story(self, floor_node, item)
	for spec: Array in level.get("encounters", []):
		var patrol: Array[Vector3] = []
		for p: Vector2 in spec[2]: patrol.append(world_transform(floor_node) * Vector3(p.x, .1, p.y))
		encounter_specs.append({"kind": spec[0], "building": building_id, "floor": floor_index, "at": world_transform(floor_node) * Vector3(spec[1].x, .1, spec[1].y), "patrol": patrol})
	decayer.flush_litter(self, floor_node)
	return floor_node

## Rain through the failed roof: puddles, fallen tiles, rubble and water marks.
func roof_failure_below(parent: Node3D, r: Rect2) -> void:
	var node := section("RoofFailureDamage", Vector3(r.get_center().x, 0, r.get_center().y), parent)
	for i in 3: place(node, "e:152:%d" % (i % 4), Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)), rng.randf() * TAU, false)
	for i in 8: flat(node, Vector3(rng.randf_range(-r.size.x * .5, r.size.x * .5), .03, rng.randf_range(-r.size.y * .5, r.size.y * .5)), Vector3(rng.randf_range(.3, .9), rng.randf_range(.04, .16), rng.randf_range(.3, .8)), "concrete" if i % 2 else "ceiling", rng.randf() * TAU)
	decayer.grime(self, node, Vector3(0, .15, 0), Vector3.UP, "water_stain", r.size * 1.6)
	decayer.grime(self, node, Vector3(0, CEIL - .05, 0), Vector3.DOWN, "mould", r.size * 2.0, 0.0, .3)
	place(node, "e:153:1", Vector3(r.size.x * .3, 0, -r.size.y * .3), 0.0, false)
	var rain := DistrictAtmosphere.emitter("rain", 30); rain.position = Vector3(0, 3.6, 0); add(node, rain)
	area_log.append({"name": plan.title + " roof failure", "building": building_id, "floor": floor_index})

func corridors(parent: Node3D, level: Dictionary) -> void:
	var node := section("Circulation", Vector3.ZERO, parent)
	var index := 0
	for route: Dictionary in plan.corridors:
		var points: PackedVector2Array = route.points
		var marker := Marker3D.new(); add(node, marker, "Route%d" % index); index += 1
		var local := PackedVector3Array()
		for p in points: local.append(Vector3(p.x, .1, p.y))
		marker.set_meta("route_points", local); marker.set_meta("route_width", route.get("check", 1.4))
		for i in range(1, points.size()):
			var a := points[i - 1]; var b := points[i]
			var length := a.distance_to(b)
			var count := maxi(1, int(length / 11.0))
			for n in count:
				var t := (n + .5) / count
				var at := a.lerp(b, t)
				light(node, Vector3(at.x, CEIL - .12, at.y), (n + i) % 3 == 0, 9.0)
			cover_marker(node, Vector3(a.x, .1, a.y))
			dresser.corridor_clutter(self, node, a, b, route.get("width", 3.0))
			decayer.corridor(self, node, a, b, route.get("width", 3.0))
	area_log.append({"name": "%s level %d circulation" % [plan.title, floor_index], "building": building_id, "floor": floor_index})

func atrium(parent: Node3D, r: Rect2) -> void:
	var node := section("Atrium", Vector3(r.get_center().x, 0, r.get_center().y), parent)
	var hw := r.size.x * .5; var hd := r.size.y * .5
	if floor_index == 1:
		dresser.garden(self, node, hw, hd)
		return
	for side in [[Vector3(0, .55, -hd), Vector3(r.size.x, 1.1, .08)], [Vector3(0, .55, hd), Vector3(r.size.x, 1.1, .08)], [Vector3(-hw, .55, 0), Vector3(.08, 1.1, r.size.y)], [Vector3(hw, .55, 0), Vector3(.08, 1.1, r.size.y)]]:
		box(node, side[0], side[1], "glass")
		box(node, side[0] + Vector3.UP * .58, Vector3(maxf(side[1].x, .12), .06, maxf(side[1].z, .12)), "steel", false)
	cover_marker(node, Vector3(-hw - 1, .1, 0), 0)
	cover_marker(node, Vector3(hw + 1, .1, 0), PI)

func build_roof() -> void:
	floor_index = plan.levels.size() + 1
	var node := section("Roof", Vector3(0, plan.levels.size() * FH, 0), building_node)
	node.set_meta("campus_roof", true)
	split_scenes.append({"node": node, "path": "res://scenes/raid/campus/%s/roof.tscn" % building_id})
	var bounds: Rect2 = plan.bounds
	var holes: Array[Rect2] = []
	for core: Dictionary in plan.cores:
		if core.kind == "stair" and int(core.top) > plan.levels.size(): holes.append(stair_hole(core))
	if plan.has("atrium"): holes.append(plan.atrium)
	if plan.has("roof_failure"): holes.append(plan.roof_failure)
	foundation(node, bounds, 0, holes, "concrete")
	if plan.has("roof_failure"):
		# Collapsed roof deck: bent sheets at the edge, guarded so nobody falls through.
		var r: Rect2 = plan.roof_failure
		decayer.guard(self, node, Vector3(r.get_center().x, .05, r.get_center().y), Vector3(r.size.x, .1, r.size.y))
		for i in 4: flat(node, Vector3(r.get_center().x + rng.randf_range(-r.size.x * .5, r.size.x * .5), .1, r.position.y - .4 if i % 2 else r.end.y + .4), Vector3(1.4, .06, .8), "rust", rng.randf_range(-.4, .4))
		var drip := DistrictAtmosphere.emitter("rain", 24); drip.position = Vector3(r.get_center().x, 4, r.get_center().y); add(node, drip)
	for side in [[Vector3(bounds.get_center().x, .55, bounds.position.y), Vector3(bounds.size.x, 1.1, .3)], [Vector3(bounds.get_center().x, .55, bounds.end.y), Vector3(bounds.size.x, 1.1, .3)], [Vector3(bounds.position.x, .55, bounds.get_center().y), Vector3(.3, 1.1, bounds.size.y)], [Vector3(bounds.end.x, .55, bounds.get_center().y), Vector3(.3, 1.1, bounds.size.y)]]:
		box(node, side[0], side[1], "stone" if plan.style == "curtain" else "panel")
	for core: Dictionary in plan.cores:
		if core.kind == "stair" and int(core.top) > plan.levels.size():
			# Penthouse over the roof stair; the landing door opens onto the roof.
			var r: Rect2 = core.rect
			lines.clear()
			add_rect_lines(r)
			var frame := core_frame(core)
			var door_at := frame * Vector3(0, 0, 4.5)
			var h: bool = core.landing in ["n", "s"]
			add_cut(h, door_at.z if h else door_at.x, door_at.x if h else door_at.z, 2.0, "door", frame.basis * Vector3.FORWARD, "roof")
			var penthouse := section("Penthouse", Vector3.ZERO, node)
			build_walls(penthouse, Rect2(-9999, -9999, 1, 1), "concrete")
			box(penthouse, Vector3(r.get_center().x, WALL_H + .1, r.get_center().y), Vector3(r.size.x + .4, .2, r.size.y + .4), "concrete")
			var guard := section(core.id + "Top", frame.origin, node); guard.rotation.y = core_yaw(core)
			box(guard, Vector3(-1.1, .55, 2.5), Vector3(2.15, 1.1, .08), "rust")
			box(guard, Vector3(0, .55, 0), Vector3(.24, 1.1, 5.0), "concrete")
			light(guard, Vector3(0, CEIL - .2, 3.6), true, 6.0)
			area_log.append({"name": plan.title + " roof access", "building": building_id, "floor": floor_index})
	if plan.has("atrium"):
		var r: Rect2 = plan.atrium
		var sky := section("Skylight", Vector3(r.get_center().x, 0, r.get_center().y), node)
		for i in range(0, int(r.size.x) + 1, 2):
			box(sky, Vector3(-r.size.x * .5 + i, .5, 0), Vector3(.12, .12, r.size.y), "steel", false)
		for i in range(0, int(r.size.y) + 1, 4):
			box(sky, Vector3(0, .5, -r.size.y * .5 + i), Vector3(r.size.x, .12, .12), "steel", false)
		var shape := BoxShape3D.new(); shape.size = Vector3(r.size.x, .1, r.size.y)
		collider(sky, Vector3(0, .5, 0), shape, "glass")
		for i in 6:
			if i % 3 == 0: continue
			box(sky, Vector3(-r.size.x * .5 + 1 + i * 2.6, .52, -r.size.y * .25 + (i % 2) * 3), Vector3(2.2, .04, 3.8), "glass", false)
		var rain := DistrictAtmosphere.emitter("rain", 40); rain.position = Vector3(0, 4, 0); add(sky, rain)
	dresser.roof(self, node, bounds, plan)
