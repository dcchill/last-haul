extends RefCounted

## Role recipes for the MedTac Research Campus. Every recipe uses existing
## project props: m: MedTac detail, e: environment catalog id:variant,
## d: district props, p: procedural campus furniture. Placement is checked
## against room bounds, door approaches and previously placed equipment.
var k

const OPPOSITE := {"n": "s", "s": "n", "e": "w", "w": "e"}
const INWARD := {"n": Vector3.BACK, "s": Vector3.FORWARD, "w": Vector3.RIGHT, "e": Vector3.LEFT}

func walls(rc: Dictionary) -> Array[String]:
	## [back wall, preferred side, other side, door wall]; sides without doors first.
	var doors: Array[String] = []
	for token: String in rc.spec.get("doors", []): doors.append(token.get_slice(":", 0))
	var first: String = doors[0] if not doors.is_empty() else "s"
	var sides: Array[String] = []
	if first in ["n", "s"]: sides.append_array(["e", "w"])
	else: sides.append_array(["n", "s"])
	sides.sort_custom(func(a, b): return int(a in doors) < int(b in doors))
	var result: Array[String] = [OPPOSITE[first]]
	result.append_array(sides)
	result.append(first)
	return result

func long_axis(rc: Dictionary) -> bool: return rc.hw >= rc.hd

func fill_wall(rc: Dictionary, wall: String, spec: String, count: int, solid := true) -> Array[Node3D]:
	var placed: Array[Node3D] = []
	for i in count:
		var node: Node3D = k.wall_item(rc, wall, (i + .5) / count, spec, solid)
		if node != null: placed.append(node)
	return placed

func src(rc: Dictionary, wall: String, t: float, spec: String, opts := {}) -> SearchableFurniture:
	return k.wall_source(rc, wall, t, spec, opts)

func card_ok(rc: Dictionary) -> bool:
	return rc.tier in [2, 3]

func bench(rc: Dictionary, at: Vector2, facing: Vector3, instrument := "") -> Node3D:
	var table: Node3D = k.free_item(rc, "m:clean_workbench", at, facing)
	if table != null and not instrument.is_empty(): k.on_top(rc, table, "m:" + instrument)
	return table

func wall_bench(rc: Dictionary, wall: String, t: float, instrument := "") -> Node3D:
	var table: Node3D = k.wall_item(rc, wall, t, "m:clean_workbench")
	if table != null and not instrument.is_empty(): k.on_top(rc, table, "m:" + instrument)
	return table

func desk(rc: Dictionary, at: Vector2, facing: Vector3, computer := true) -> Node3D:
	var table: Node3D = k.free_item(rc, "p:office_desk", at, facing)
	if table == null: return null
	if computer: k.on_top(rc, table, "m:terminal", Vector3(-.3, 0, 0))
	k.free_item(rc, "p:office_chair", at + Vector2(facing.x, facing.z) * -.95, facing)
	return table

func islands(rc: Dictionary, instruments: Array, rows := 1) -> Array[Node3D]:
	## Back-to-back bench islands with >= 1.4 m aisles and 2.4 m kept clear of
	## the short walls for wall equipment and circulation.
	var tables: Array[Node3D] = []
	var along_x := long_axis(rc)
	var span: float = rc.hw if along_x else rc.hd
	var depth: float = rc.hd if along_x else rc.hw
	if depth < 3.6: return tables
	var usable := span * 2 - 4.8
	if usable < 2.5: return tables
	var count := maxi(1, int((usable + 1.4) / 3.9))
	for i in count:
		var a := 0.0 if count == 1 else lerpf(-span + 2.4 + 1.25, span - 2.4 - 1.25, float(i) / (count - 1))
		for r in rows:
			var offset := 0.0 if rows == 1 else (r - (rows - 1) * .5) * 3.0
			for s in [-1, 1]:
				var at := Vector2(a, offset + s * .58) if along_x else Vector2(offset + s * .58, a)
				var facing := Vector3(0, 0, s) if along_x else Vector3(s, 0, 0)
				var table := bench(rc, at, facing, instruments[(i + r + (0 if s < 0 else 1)) % instruments.size()])
				if table != null: tables.append(table)
	return tables

func scatter_chairs(rc: Dictionary, count: int) -> void:
	for i in count:
		var at := Vector2(k.rng.randf_range(-rc.hw + .8, rc.hw - .8), k.rng.randf_range(-rc.hd + .8, rc.hd - .8))
		k.free_item(rc, "e:042:%d" % (2 if k.rng.randf() < .4 else 1), at, Vector3(k.rng.randf_range(-1, 1), 0, k.rng.randf_range(-1, 1)).normalized() + Vector3(0, 0, .01))

func dress(kit, rc: Dictionary) -> void:
	k = kit
	var w := walls(rc)
	var t: int = rc.tier
	var room_node: Node3D = rc.node
	match rc.role:
		"lobby", "reception":
			var counter: Node3D = k.wall_item(rc, w[0], .5, "m:nurse_desk")
			k.wall_item(rc, w[0], .2, "m:nurse_desk")
			if counter != null: k.loose_on(rc, counter, 1)
			fill_wall(rc, w[1], "e:048:%d" % (1 if t == 1 else 2), 2)
			k.wall_item(rc, w[2], .7, "e:048:3")
			k.wall_item(rc, w[2], .3, "e:034:2")
			src(rc, w[1], .9, "m:personal_bag")
			src(rc, w[0], .85, "m:filing_cabinet")
			scatter_chairs(rc, 2)
		"waiting", "dayroom":
			for wall in [w[0], w[1]]: fill_wall(rc, wall, "e:047:%d" % (k.rng.randi() % 2), maxi(2, int((rc.hw if wall in ["n", "s"] else rc.hd) * 2 / 1.1) - 2))
			var table: Node3D = k.free_item(rc, "e:046:0", Vector2.ZERO)
			if table != null: k.loose_on(rc, table, 1)
			k.wall_item(rc, w[2], .5, "e:048:%d" % (2 if rc.role == "dayroom" else 1))
			if rc.role == "dayroom": k.wall_item(rc, w[2], .15, "e:057:0")
			src(rc, w[2], .9, "m:personal_bag")
			k.wall_item(rc, w[0], .95, "m:trash_bin")
		"checkpoint":
			for i in 3:
				var along := long_axis(rc)
				k.free_item(rc, "e:115:%d" % (1 if i != 1 else 2), Vector2((i - 1) * 2.0, 0) if along else Vector2(0, (i - 1) * 2.0), Vector3.BACK if along else Vector3.RIGHT)
			var guard_desk: SearchableFurniture = src(rc, w[1], .5, "e:114:2", {"profile": "records", "card": card_ok(rc)})
			src(rc, w[2], .5, "m:security_locker", {"profile": "security_gear"})
			if t >= 3:
				k.wall_item(rc, w[1], .1, "e:111:1")
				k.wall_item(rc, w[2], .9, "e:122:1")
				k.body(room_node, Vector3(k.rng.randf_range(-.5, .5), 0, k.rng.randf_range(-.5, .5)), k.rng.randf() * TAU)
		"security", "security_ops", "security_monitor", "security_desk", "bridge_security":
			k.wall_item(rc, w[0], .4, "e:124:%d" % (1 if t < 4 else 2))
			if rc.role == "bridge_security":
				# The post sits beside the through-route between corridor and bridge.
				var post: Node3D = k.wall_item(rc, w[1], .3, "p:office_desk")
				if post != null: k.on_top(rc, post, "m:terminal")
			else: desk(rc, Vector2(0, 0), Vector3.BACK)
			src(rc, w[1], .3, "m:security_locker", {"profile": "security_gear", "card": card_ok(rc)})
			src(rc, w[1], .7, "e:095:1")
			if t >= 2 and rc.role != "security_desk": src(rc, w[2], .4, "m:weapon_crate" if t >= 3 else "m:ammo_box")
			if rc.role == "bridge_security":
				k.wall_item(rc, w[2], .8, "e:111:2")
				k.body(room_node, Vector3(1, 0, 0), .8)
			k.wall_item(rc, w[0], .9, "e:116:0")
		"mail", "loading", "service", "service_entry", "receipt":
			var table: Node3D = k.wall_item(rc, w[0], .3, "m:packing_table")
			k.loose_on(rc, table, 1)
			fill_wall(rc, w[1], "m:roll_cage", 2)
			k.wall_item(rc, w[0], .8, "m:pallet_jack")
			src(rc, w[2], .5, "m:shipping_crate")
			k.free_item(rc, "m:cardboard_box", Vector2(.5, .4))
			k.free_item(rc, "m:wrapped_pallet", Vector2(-1.5, -.4))
		"openoffice", "workstations":
			var along := long_axis(rc)
			var span: float = rc.hw if along else rc.hd
			var count := maxi(1, int((span * 2 - 2) / 3.6))
			for i in count:
				var a := -span + 1.6 + (span * 2 - 3.2) * (i + .5) / count
				for s in [-1, 1]:
					var at := Vector2(a, s * 1.15) if along else Vector2(s * 1.15, a)
					var facing := Vector3(0, 0, -s) if along else Vector3(-s, 0, 0)
					var work: Node3D = k.free_item(rc, "e:058:%d" % (2 if k.rng.randf() < .3 else 0), at, facing)
					if work != null and k.rng.randf() < .3: k.loose_on(rc, work, 1)
					k.free_item(rc, "e:042:%d" % (2 if k.rng.randf() < .35 else 1), at + Vector2(facing.x, facing.z) * -1.0, facing)
			src(rc, w[0], .2, "m:filing_cabinet")
			src(rc, w[0], .8, "e:043:0")
			k.wall_item(rc, w[1], .5, "e:044:1")
			k.wall_item(rc, w[2], .5, "e:060:0")
		"office", "consent", "interview", "dispatch", "oncall":
			var main_desk := desk(rc, Vector2(0, 0), Vector3.BACK if w[0] == "n" else Vector3.FORWARD if w[0] == "s" else Vector3.RIGHT if w[0] == "w" else Vector3.LEFT)
			if main_desk != null and k.rng.randf() < .5: k.loose_on(rc, main_desk, 1)
			src(rc, w[1], .5, "m:filing_cabinet" if rc.role != "oncall" else "e:051:0")
			k.wall_item(rc, w[0], .2, "e:044:%d" % (1 if t < 3 else 2))
			k.wall_item(rc, w[2], .8, "m:trash_bin")
			if rc.role == "interview": k.free_item(rc, "m:break_table", Vector2(0, 0))
			if rc.role == "oncall":
				k.wall_item(rc, w[0], .8, "e:049:0")
				k.wall_item(rc, w[2], .3, "e:050:1")
			if rc.role == "dispatch":
				k.wall_item(rc, w[1], .1, "e:118:1")
				src(rc, w[2], .3, "e:095:1")
		"exec", "exec_reception":
			var facing := Vector3.BACK if w[0] == "n" else Vector3.FORWARD if w[0] == "s" else Vector3.RIGHT if w[0] == "w" else Vector3.LEFT
			var main_desk := desk(rc, Vector2(facing.x, facing.z) * -.8, facing)
			if main_desk != null: k.loose_on(rc, main_desk, 1)
			k.wall_item(rc, w[0], .15, "e:044:1")
			k.wall_item(rc, w[1], .4, "e:048:0")
			k.wall_item(rc, w[2], .5, "e:057:1")
			src(rc, w[1], .85, "m:filing_cabinet")
			if t >= 3: src(rc, w[0], .85, "e:184:1", {"locked": true, "profile": "records"})
			if t >= 4: k.papers(room_node, Vector3.ZERO, Vector2(rc.hw * .6, rc.hd * .6), 8)
		"exec_lounge":
			fill_wall(rc, w[0], "e:048:0", 2)
			k.free_item(rc, "e:046:1", Vector2.ZERO)
			k.wall_item(rc, w[1], .5, "e:057:1")
			src(rc, w[2], .3, "e:052:2")
			src(rc, w[2], .7, "e:053:0", {"profile": "food"})
		"conference", "meeting", "secure_conference":
			var along := long_axis(rc)
			var span: float = rc.hw if along else rc.hd
			var count := maxi(1, int((span * 2 - 3) / 2.1))
			for i in count:
				var a := -span + 1.5 + (span * 2 - 3) * (i + .5) / count
				var table: Node3D = k.free_item(rc, "m:break_table", Vector2(a, 0) if along else Vector2(0, a), Vector3.BACK if along else Vector3.RIGHT)
				for s in [-1, 1]:
					k.free_item(rc, "e:042:%d" % (2 if k.rng.randf() < .3 else 1), Vector2(a, s * 1.35) if along else Vector2(s * 1.35, a), Vector3(0, 0, -s) if along else Vector3(-s, 0, 0))
				if i == 0 and table != null: k.loose_on(rc, table, 1)
			k.wall_item(rc, w[0], .5, "e:057:1")
			src(rc, w[1], .5, "m:filing_cabinet")
			if rc.role == "secure_conference":
				src(rc, w[2], .5, "e:184:1", {"locked": true, "profile": "records"})
				k.papers(room_node, Vector3.ZERO, Vector2(rc.hw * .7, rc.hd * .6), 10)
		"records", "records_secure", "archive":
			var count := maxi(2, int(((rc.hw if w[0] in ["n", "s"] else rc.hd) * 2) / 1.6))
			for i in count:
				if i % 2 == 0: src(rc, w[0], (i + .5) / count, "m:filing_cabinet")
				else: k.wall_item(rc, w[0], (i + .5) / count, "m:filing_cabinet")
			fill_wall(rc, w[1], "e:045:1", 2)
			var table: Node3D = k.free_item(rc, "m:storage_table", Vector2.ZERO)
			k.loose_on(rc, table, 2 if t >= 3 else 1)
			if rc.role == "records_secure" or rc.role == "archive": src(rc, w[2], .5, "e:185:0" if t >= 4 else "e:199:0", {"locked": true, "profile": "records" if t >= 4 else "specimen"})
			if rc.role == "archive":
				fill_wall(rc, w[1], "m:ultra_freezer", 2)
				src(rc, w[2], .15, "m:specimen_cooler")
		"breakroom", "kitchen", "cafeteria":
			fill_wall(rc, w[0], "m:wall_cabinet", 3)
			src(rc, w[0], .9, "e:053:0" if rc.role != "cafeteria" else "e:193:0")
			k.wall_item(rc, w[0], .05, "e:054:1")
			var along := long_axis(rc)
			var tables := 1 if rc.role != "cafeteria" else 4
			for i in tables:
				var a := (i - (tables - 1) * .5) * 3.2
				var table: Node3D = k.free_item(rc, "m:break_table", Vector2(a, .6) if along else Vector2(.6, a), Vector3.BACK)
				if table != null and i == 0: k.loose_on(rc, table, 1)
				for s in [-1, 1]: k.free_item(rc, "e:047:%d" % (k.rng.randi() % 3), (Vector2(a, .6 + s * 1.2) if along else Vector2(.6 + s * 1.3, a)), Vector3(0, 0, -s) if along else Vector3(-s, 0, 0))
			k.wall_item(rc, w[1], .5, "e:057:0")
			k.wall_item(rc, w[2], .2, "m:trash_bin")
			if rc.role == "cafeteria":
				src(rc, w[1], .15, "e:191:2")
				k.wall_item(rc, w[2], .7, "e:048:3")
		"storage", "supplies", "equipment", "gasstore", "linen", "laundry":
			fill_wall(rc, w[0], "e:045:1" if rc.role != "equipment" else "e:079:1", 2)
			src(rc, w[1], .3, "m:shipping_crate" if rc.role != "laundry" else "m:staff_locker")
			src(rc, w[1], .75, "e:172:0" if rc.role != "linen" else "m:tool_drawers")
			k.free_item(rc, "m:cardboard_box", Vector2(0, .5))
			if rc.role == "gasstore":
				for i in 4: k.free_item(rc, "e:092:%d" % (i % 2), Vector2(-.8 + i * .5, -.3))
			if rc.role == "laundry": fill_wall(rc, w[2], "m:roll_cage", 2)
			if rc.role == "equipment": k.wall_item(rc, w[2], .5, "m:work_cart")
			var table: Node3D = k.wall_item(rc, w[2], .2, "m:storage_table")
			k.loose_on(rc, table, 1)
		"janitor", "waste":
			k.wall_item(rc, w[0], .2, "m:mop_bucket")
			k.wall_item(rc, w[0], .6, "e:045:1")
			src(rc, w[1], .5, "m:tool_drawers")
			for i in 2: k.wall_item(rc, w[2 if w.size() > 2 else 0], .3 + i * .3, "e:091:%d" % (i % 2) if rc.role == "janitor" else "e:108:%d" % (i % 3))
			if rc.role == "waste": k.wall_item(rc, w[0], .9, "m:sharps_bin")
		"restroom":
			var wall: String = w[0]
			var count := clampi(int(((rc.hw if wall in ["n", "s"] else rc.hd) * 2) / 1.6), 1, 4)
			for i in count:
				var stall: Node3D = k.wall_item(rc, wall, (i + .5) / count, "m:toilet")
				if stall != null:
					var depth := stall.transform * Vector3(0, 0, .9)
					k.box(room_node, Vector3(stall.position.x, 1.0, stall.position.z).lerp(depth, .5) + (Vector3(.8, 0, 0) if wall in ["n", "s"] else Vector3(0, 0, .8)), Vector3(.05, 2.0, 1.4) if wall in ["n", "s"] else Vector3(1.4, 2.0, .05), "paint", false)
			fill_wall(rc, w[1], "m:wash_station", 1)
			k.wall_item(rc, w[1], .9, "m:trash_bin")
		"exit_hall":
			k.wall_item(rc, w[1], .5, "e:048:3")
			k.wall_item(rc, w[2], .4, "e:129:1")
			k.wall_item(rc, w[1], .1, "e:125:2")
			k.body(room_node, Vector3(-.8, 0, .5), 1.2)
			src(rc, w[2], .9, "e:180:2")
		"firstaid", "triage", "exam":
			k.wall_item(rc, w[0], .5, "m:exam_bed" if rc.role != "triage" else "m:exam_chair")
			if rc.role == "triage": k.wall_item(rc, w[0], .15, "m:exam_chair")
			k.wall_item(rc, w[1], .3, "m:wash_station")
			k.wall_item(rc, w[1], .8, "m:iv_stand")
			src(rc, w[2], .4, "m:med_cabinet")
			if t >= 2 or rc.role == "firstaid": src(rc, w[0], .95, "e:176:%d" % (0 if t > 1 else 1))
			k.wall_item(rc, w[2], .9, "m:sharps_bin")
			var cart: Node3D = k.free_item(rc, "m:supply_cart", Vector2(.6, .6))
			k.loose_on(rc, cart, 1)
		"dispensary", "medstore", "clean_utility", "medvault", "medprep", "drugprep", "vault_pharma":
			fill_wall(rc, w[0], "e:045:1", 2)
			src(rc, w[1], .25, "m:med_cabinet")
			src(rc, w[1], .75, "m:medicine_fridge" if rc.role != "clean_utility" else "e:175:0")
			if rc.role in ["dispensary", "medprep", "drugprep"]:
				var counter: Node3D = k.wall_item(rc, w[2], .5, "m:clean_workbench" if rc.role != "dispensary" else "m:nurse_desk")
				k.loose_on(rc, counter, 1)
			if rc.role in ["medvault", "vault_pharma"] or (t >= 3 and rc.role == "drugprep"):
				src(rc, w[2], .3, "e:177:2", {"locked": rc.role != "vault_pharma", "guarantee": {"infection_suppressant": 2} if rc.role == "vault_pharma" else {}})
				src(rc, w[2], .75, "e:104:0")
			if t >= 2 and rc.role != "clean_utility": src(rc, w[0], .95, "e:175:2")
			k.wall_item(rc, w[2], .95, "m:supply_cart")
		"soiled_utility":
			k.wall_item(rc, w[0], .3, "m:wash_station")
			for i in 3: k.wall_item(rc, w[1], .2 + i * .3, "e:108:%d" % (i % 3))
			k.wall_item(rc, w[0], .85, "m:mop_bucket")
			k.wall_item(rc, w[2], .5, "m:trash_bin")
		"it", "server", "datacentre":
			var count := 2 if rc.role == "it" else 4
			fill_wall(rc, w[0], "m:server_rack", count)
			src(rc, w[1], .3, "e:190:%d" % (1 if t >= 4 else 0), {"locked": t >= 4})
			src(rc, w[1], .75, "e:189:0")
			var table: Node3D = k.wall_item(rc, w[2], .5, "m:storage_table")
			if table != null:
				k.on_top(rc, table, "m:terminal")
				k.loose_on(rc, table, 1)
			k.wall_item(rc, w[2], .9, "e:094:1")
			if rc.role == "datacentre":
				for i in 2: desk(rc, Vector2(-2 + i * 4, 0), Vector3.BACK)
				k.papers(room_node, Vector3.ZERO, Vector2(rc.hw * .7, rc.hd * .7), 10)
		"riser", "electrical", "plant", "maintenance":
			k.wall_item(rc, w[0], .5, "m:electrical_panel" if rc.role != "plant" else "m:air_handler")
			src(rc, w[1], .5, "e:082:%d" % (1 if t > 1 else 0) if rc.role != "maintenance" else "e:179:1")
			k.wall_item(rc, w[0], .9, "e:085:1")
			if rc.role == "maintenance":
				k.wall_item(rc, w[2], .3, "m:instrument_bench")
				k.wall_item(rc, w[2], .8, "m:work_cart")
			if rc.role == "plant": k.wall_item(rc, w[1], .1, "e:073:1")
		"exhibit":
			k.wall_item(rc, w[0], .3, "d:medical_station")
			k.wall_item(rc, w[0], .7, "d:medical_station")
			k.free_item(rc, "m:recovery_bed", Vector2(-2, 0))
			k.free_item(rc, "m:monitor_cart", Vector2(-.6, -1.2))
			k.free_item(rc, "e:110:0", Vector2(2.2, -.5))
			var plinth: Node3D = k.free_item(rc, "m:storage_table", Vector2(2.2, 2.2))
			k.loose_on(rc, plinth, 1)
			k.wall_item(rc, w[1], .5, "m:exam_chair")
			src(rc, w[2], .3, "e:175:1")
			k.wall_item(rc, w[2], .7, "e:048:1")
		"coatroom", "changing", "gowning":
			for i in 3:
				if i != 1: src(rc, w[0], (i + .5) / 3.0, "m:staff_locker")
				else: k.wall_item(rc, w[0], .5, "m:staff_locker")
			k.free_item(rc, "e:047:1", Vector2(0, 0))
			if rc.role != "coatroom": k.wall_item(rc, w[1], .5, "e:109:0" if rc.role == "gowning" else "m:shower")
			if rc.role == "coatroom": src(rc, w[1], .5, "e:051:0")
		"pharmalab", "chemlab", "prep", "trial_lab", "diagnostic":
			var instruments: Array = ["microscope", "centrifuge", "analyzer", "sample_rack"] if rc.role != "chemlab" else ["analyzer", "sample_rack", "centrifuge"]
			var tables := islands(rc, instruments)
			if not tables.is_empty(): k.loose_on(rc, tables[0], 1)
			wall_bench(rc, w[0], .25, "microscope")
			k.wall_item(rc, w[0], .7, "m:biosafety_cabinet" if rc.role in ["prep", "trial_lab"] else "e:105:1")
			k.wall_item(rc, w[1], .2, "m:eyewash")
			k.wall_item(rc, w[1], .5, "m:wash_station")
			src(rc, w[1], .85, "m:specimen_cooler")
			src(rc, w[2], .3, "m:tool_drawers")
			k.wall_item(rc, w[2], .7, "m:lab_fridge")
			if t >= 3: src(rc, w[0], .95, "m:specimen_cooler")
		"biolab", "regenesis", "experimental", "dissection", "containment":
			if rc.role in ["biolab", "regenesis"]:
				var tables := islands(rc, ["microscope", "sample_rack", "centrifuge"])
				if not tables.is_empty(): k.loose_on(rc, tables[-1], 1)
			fill_wall(rc, w[0], "m:biosafety_cabinet", 2 if rc.role != "dissection" else 1)
			k.wall_item(rc, w[1], .2, "m:ultra_freezer")
			src(rc, w[1], .55, "m:specimen_cooler")
			if rc.role in ["experimental", "containment", "regenesis", "dissection"]:
				k.free_item(rc, "e:102:%d" % (1 if t < 4 else 2) if rc.role != "containment" else "m:recovery_bed", Vector2(0, .4))
				k.free_item(rc, "m:monitor_cart", Vector2(1.6, -.6))
				k.free_item(rc, "m:iv_stand", Vector2(-1.2, -.8))
				k.free_item(rc, "e:110:%d" % (2 if t >= 4 else 1), Vector2(-2.2, 1.2))
				k.stain(room_node, Vector3(.3, 0, .5), 1.0)
			if t >= 3: src(rc, w[2], .3, "e:199:0", {"locked": true})
			if rc.role == "regenesis":
				src(rc, w[2], .7, "e:199:2", {"profile": "specimen"})
				k.printed_sign(room_node, "regenesis_board", Vector3(0, 2.0, 0) - INWARD[w[0]] * ((rc.hd if w[0] in ["n", "s"] else rc.hw) + .12), k.front_yaw("m:x", INWARD[w[0]]), 3.0)
			if rc.role == "containment":
				k.decay(room_node, Vector3(0, 0, 0))
				k.body(room_node, Vector3(-1.5, 0, 1.0), .4, false)
				k.printed_sign(room_node, "containment_failed", Vector3(0, 2.0, 0) - INWARD[w[0]] * ((rc.hd if w[0] in ["n", "s"] else rc.hw) + .12), k.front_yaw("m:x", INWARD[w[0]]), 2.6)
		"cold", "vault_samples", "vault_data":
			var count := maxi(2, int(((rc.hw if w[0] in ["n", "s"] else rc.hd) * 2) / 1.5))
			for i in count:
				if rc.role == "vault_data": k.wall_item(rc, w[0], (i + .5) / count, "m:server_rack")
				else: k.wall_item(rc, w[0], (i + .5) / count, "m:ultra_freezer" if i % 2 == 0 else "m:lab_fridge")
			src(rc, w[1], .3, "m:specimen_cooler" if rc.role != "vault_data" else "m:filing_cabinet", {"guarantee": {"research_drive": 1} if rc.role == "vault_data" else {"sealed_specimen": 1} if rc.role == "vault_samples" else {}})
			src(rc, w[1], .75, "e:104:1" if rc.role == "cold" else "e:199:2", {"profile": "specimen"} if rc.role != "cold" else {})
			if rc.role == "vault_data": src(rc, w[2], .5, "e:185:0", {"guarantee": {"research_drive": 1}})
			var table: Node3D = k.wall_item(rc, w[2], .2, "m:storage_table")
			k.loose_on(rc, table, 1)
		"glasswash", "calibration", "balance", "imaging", "labsupport":
			k.wall_item(rc, w[0], .3, "m:autoclave" if rc.role == "glasswash" else "m:instrument_bench")
			k.wall_item(rc, w[0], .75, "m:wash_station" if rc.role == "glasswash" else "e:105:1")
			var table: Node3D = wall_bench(rc, w[1], .5, "analyzer" if rc.role != "balance" else "sample_rack")
			k.loose_on(rc, table, 1)
			src(rc, w[2 if w.size() > 2 else 1], .4, "m:tool_drawers")
			k.free_item(rc, "m:supply_cart", Vector2(0, 0))
		"chemstore":
			for i in 3: k.wall_item(rc, w[0], (i + .5) / 3.0, "e:091:%d" % (i % 3))
			fill_wall(rc, w[1], "e:045:1", 2)
			src(rc, w[2], .3, "m:tool_drawers")
			src(rc, w[2], .7, "e:177:0")
			k.wall_item(rc, w[0], .95, "e:071:0")
		"pressroom", "mixing":
			var along := long_axis(rc)
			for i in 3:
				var a := (i - 1) * 4.2
				k.free_item(rc, "e:071:%d" % (0 if i != 2 else 1) if rc.role == "mixing" else "e:066:0", Vector2(a, -1.2) if along else Vector2(-1.2, a))
				k.free_item(rc, "e:080:0" if rc.role == "mixing" else "m:conveyor", Vector2(a, 2.2) if along else Vector2(2.2, a))
			k.wall_item(rc, w[0], .5, "e:074:1")
			k.wall_item(rc, w[1], .4, "e:073:2")
			src(rc, w[1], .8, "m:tool_drawers")
			var table: Node3D = k.wall_item(rc, w[2], .5, "m:packing_table")
			k.loose_on(rc, table, 1)
		"animal":
			for wall in [w[0], w[1]]: fill_wall(rc, wall, "m:roll_cage", 3)
			var table: Node3D = k.free_item(rc, "m:storage_table", Vector2.ZERO)
			k.loose_on(rc, table, 1)
			src(rc, w[2], .5, "m:specimen_cooler")
			k.stain(room_node, Vector3(1, 0, -1), 1.2, "contamination")
		"observation", "obs_control", "control", "monitoring":
			var facing := Vector3.BACK if w[0] == "n" else Vector3.FORWARD if w[0] == "s" else Vector3.RIGHT if w[0] == "w" else Vector3.LEFT
			desk(rc, Vector2(facing.x, facing.z) * -(minf(rc.hw, rc.hd) - 1.1), facing)
			k.wall_item(rc, w[1], .3, "m:monitor_cart")
			k.wall_item(rc, w[1], .7, "e:124:1")
			src(rc, w[2], .5, "m:filing_cabinet")
			if rc.role == "control": src(rc, w[2], .15, "e:188:2")
		"cafeteria_small":
			pass
		"er", "icu", "ward", "patient", "transfer", "observation_clinical", "controlled_obs", "holding", "trial_treatment", "resus", "procedure", "treatment", "isolation", "xray", "makeshift":
			var bed := "e:096:%d" % (1 if t < 3 else 2) if rc.role not in ["holding", "controlled_obs", "ward", "trial_treatment"] else "m:recovery_bed"
			if rc.role in ["resus", "procedure", "treatment"]: bed = "e:102:%d" % (1 if t < 3 else 0)
			if rc.role == "transfer":
				k.wall_item(rc, w[1], .2, "e:097:0")
				k.wall_item(rc, w[2], .5, "m:wheel_chair")
			if rc.role == "xray": bed = "m:exam_bed"
			if rc.role == "makeshift": bed = "e:050:2"
			var span: float = (rc.hw if w[0] in ["n", "s"] else rc.hd) * 2
			var count := clampi(int(span / 3.2), 1, 8) if rc.role in ["er", "icu", "ward", "holding", "makeshift", "controlled_obs"] else 1
			for i in count:
				var placed: Node3D = k.wall_item(rc, w[0], (i + .5) / count, bed)
				if placed == null: continue
				if rc.role in ["er", "icu"] and i < count - 1:
					var divider := placed.transform * Vector3(1.55, 0, 0)
					k.free_item(rc, "e:107:%d" % (1 if t < 4 else 2), Vector2(divider.x, divider.z), INWARD[w[0]].rotated(Vector3.UP, PI * .5), false)
				if k.rng.randf() < (.15 + t * .08): k.body(room_node, placed.position + Vector3(0, .62, 0), placed.rotation.y)
			k.wall_item(rc, w[1], .3, "m:monitor_cart" if rc.role != "makeshift" else "e:126:1")
			k.wall_item(rc, w[1], .6, "m:iv_stand")
			if rc.role in ["icu", "resus", "isolation", "er"]: k.wall_item(rc, w[1], .9, "e:101:%d" % (1 if t < 4 else 2))
			src(rc, w[2], .35, "m:med_cabinet" if rc.role != "patient" else "m:personal_bag")
			if rc.role in ["icu", "er", "ward", "makeshift"] or t >= 3: src(rc, w[2], .8, "m:medical_bag" if rc.role == "makeshift" else "e:175:%d" % (2 if t >= 3 else 0))
			if rc.role == "patient": k.wall_item(rc, w[2], .8, "e:047:0")
			if rc.role == "transfer":
				k.wall_item(rc, w[1], .2, "e:097:0")
				k.wall_item(rc, w[2], .5, "m:wheel_chair")
			if rc.role == "xray":
				k.wall_item(rc, w[1], .1, "m:instrument_bench")
				k.wall_item(rc, w[2], .1, "m:privacy_screen")
			if rc.role in ["isolation", "makeshift", "controlled_obs"] or (t >= 4 and rc.role == "icu"):
				k.decay(room_node, Vector3(k.rng.randf_range(-.5, .5), 0, k.rng.randf_range(-.5, .5)))
			if rc.role == "makeshift":
				k.wall_item(rc, w[2], .1, "e:048:3")
				k.wall_item(rc, w[1], .95, "e:107:2")
				k.printed_sign(room_node, "do_not_open", -INWARD[w[-1]] * ((rc.hd if w[-1] in ["n", "s"] else rc.hw) + .12) + Vector3.UP * 1.5, k.front_yaw("m:x", INWARD[w[-1]]), 2.0)
			var cart: Node3D = k.free_item(rc, "e:099:%d" % (0 if t < 3 else 2), Vector2(0, 0))
			if cart != null: k.loose_on(rc, cart, 1)
		"nurse_station":
			var counter: Node3D = k.free_item(rc, "m:nurse_desk", Vector2(-1.2, 0), Vector3.BACK)
			k.free_item(rc, "m:nurse_desk", Vector2(1.2, 0), Vector3.BACK)
			k.loose_on(rc, counter, 1)
			k.free_item(rc, "p:office_chair", Vector2(-1.2, 1.1), Vector3.FORWARD)
			src(rc, w[0], .3, "m:med_cabinet")
			src(rc, w[0], .7, "m:filing_cabinet")
			k.wall_item(rc, w[1], .5, "m:supply_cart")
		"decon":
			k.wall_item(rc, w[0], .3, "e:109:%d" % (1 if t < 3 else 2))
			k.wall_item(rc, w[0], .75, "m:wash_station")
			k.wall_item(rc, w[1], .5, "m:eyewash")
			src(rc, w[1], .1, "m:staff_locker")
			for i in 2: k.wall_item(rc, w[2 if w.size() > 2 else 1], .3 + i * .4, "e:108:%d" % i)
		"prototype", "workshop", "charging":
			k.wall_item(rc, w[0], .3, "m:instrument_bench")
			if rc.role == "charging": k.wall_item(rc, w[0], .75, "e:094:1")
			else: src(rc, w[0], .75, "e:061:1")
			src(rc, w[1], .3, "m:tool_drawers")
			src(rc, w[1], .75, "e:188:0" if rc.role == "prototype" else "e:179:0")
			k.free_item(rc, "m:work_cart", Vector2.ZERO)
			if rc.role == "charging": k.free_item(rc, "m:forklift", Vector2(1.6, 0))
			if rc.role == "workshop": k.wall_item(rc, w[2], .5, "e:063:1")
		"destruction":
			for i in 2: k.free_item(rc, "e:090:%d" % (1 if i == 0 else 3), Vector2(-1 + i * 2, 0))
			src(rc, w[0], .3, "m:filing_cabinet", {"ransacked": true})
			src(rc, w[0], .7, "m:filing_cabinet")
			k.papers(room_node, Vector3.ZERO, Vector2(rc.hw * .8, rc.hd * .8), 24)
			k.stain(room_node, Vector3(-1, 0, 0), 1.0, "rubber")
			k.printed_sign(room_node, "destroy_records", -INWARD[w[1]] * ((rc.hd if w[1] in ["n", "s"] else rc.hw) + .12) + Vector3.UP * 1.8, k.front_yaw("m:x", INWARD[w[1]]), 2.2)
		"bridge_access":
			k.wall_item(rc, w[1], .5, "e:111:0")
			k.wall_item(rc, w[2], .4, "e:122:0")
			src(rc, w[1], .1, "e:180:1")
		"dispatch_reception":
			var counter: Node3D = k.wall_item(rc, w[0], .5, "m:nurse_desk")
			k.loose_on(rc, counter, 1)
			fill_wall(rc, w[1], "e:047:0", 3)
			src(rc, w[2], .4, "m:filing_cabinet")
			k.wall_item(rc, w[2], .8, "m:trash_bin")
		"dist_cold":
			fill_wall(rc, w[0], "m:cold_chain_crate", 4)
			src(rc, w[1], .3, "m:medicine_fridge")
			src(rc, w[1], .7, "e:192:1")
			k.free_item(rc, "m:pallet_jack", Vector2(0, .5))
		_:
			push_error("No campus dressing recipe for role: " + rc.role)

# ---------------------------------------------------------------- circulation and stories

func corridor_clutter(kit, node: Node3D, a: Vector2, b: Vector2, width: float) -> void:
	k = kit
	var length := a.distance_to(b)
	if length < 8: return
	var along := (b - a).normalized()
	var across := Vector2(-along.y, along.x)
	var h := absf(along.x) > absf(along.y)
	var pieces := int(length / 9.0)
	for i in pieces:
		var t: float = (i + k.rng.randf_range(.25, .75)) / pieces
		var at := a.lerp(b, t)
		if at.distance_to(a) < 3.5 or at.distance_to(b) < 3.5: continue
		var side: float = -1.0 if k.rng.randf() < .5 else 1.0
		var wall_c: float = (at.y if h else at.x) + side * width * .5
		var roll: float = k.rng.randf()
		var spec: String = "m:trash_bin" if roll < .2 else "e:099:2" if roll < .35 else "e:042:2" if roll < .55 else "e:108:2" if roll < .65 else "e:014:1" if roll < .8 else "e:097:2"
		var facing := Vector3(-across.x * side, 0, -across.y * side)
		var yaw: float = k.front_yaw(spec, facing)
		var box: AABB = k.rotated(spec, yaw)
		var across_extent: float = box.size.z if h else box.size.x
		var along_extent: float = box.size.x if h else box.size.z
		if not k.wall_covers(h, wall_c, at.x if h else at.y, along_extent * .5): continue
		# Corridor clutter is dressing only; authored barricades provide corridor cover.
		var solid := false
		var p := at + across * side * (width * .5 - .14 - across_extent * .5)
		var placed: Node3D = k.place(node, spec, Vector3(p.x, 0, p.y) - box.get_center() * Vector3(1, 0, 1), yaw, solid)
		if not solid: placed.set_meta("bounds", AABB())
		if k.rng.randf() < .25: k.papers(node, Vector3(at.x, 0, at.y), Vector2(.6, .6), 5)
		if k.rng.randf() < .12 + k.floor_index * .04: k.stain(node, Vector3(at.x, 0, at.y), .7)

func story(kit, node: Node3D, item: Array) -> void:
	k = kit
	var at := Vector3(item[1].x, 0, item[1].y)
	match item[0]:
		"body": k.body(node, at, item[2] if item.size() > 2 else 0.0, item[3] if item.size() > 3 else true)
		"decay": k.decay(node, at)
		"stain": k.stain(node, at, item[2] if item.size() > 2 else 1.0)
		"papers": k.papers(node, at, Vector2(1.5, 1.5), item[2] if item.size() > 2 else 12)
		"sign": k.printed_sign(node, item[3], at + Vector3.UP * (item[4] if item.size() > 4 else 2.2), item[2], item[5] if item.size() > 5 else 2.6)
		"barricade":
			var holder: Node3D = k.section("Barricade%d" % k.serial, at, node)
			holder.rotation.y = item[2] if item.size() > 2 else 0.0
			# Slim barricades hug one side so the route stays open; furniture adds cover.
			k.place(holder, "e:129:1", Vector3(0, 0, 0), 0.0)
			k.place(holder, "e:042:2", Vector3(-1.4, 0, .1), 1.4, false)
			k.cover_marker(node, at + Basis(Vector3.UP, holder.rotation.y) * Vector3(0, .1, .9))
		"camp":
			var holder: Node3D = k.section("SurvivorCamp%d" % k.serial, at, node)
			holder.rotation.y = item[2] if item.size() > 2 else 0.0
			k.place(holder, "e:126:1", Vector3(-1.2, 0, 0), 0.0)
			k.place(holder, "e:135:1", Vector3(1.0, 0, .6), 0.0, false)
			k.place(holder, "e:139:0", Vector3(0, 0, -1.4), 0.0)
			k.place(holder, "e:138:1", Vector3(2.2, 0, -1.2), PI)
		_: push_error("Unknown story beat " + str(item[0]))

func garden(kit, node: Node3D, hw: float, hd: float) -> void:
	k = kit
	# Raised beds around a cross path; the collapsed skylight lets rain and roots in.
	for qx in [-1, 1]:
		for qz in [-1, 1]:
			var center := Vector3(qx * (hw * .5 + .6), 0, qz * (hd * .5 + .6))
			var size := Vector2(hw - 1.8, hd - 1.8)
			k.box(node, center + Vector3(0, .02, 0), Vector3(size.x, .04, size.y), "grass", false)
			for edge in [[Vector3(0, .22, -size.y * .5), Vector3(size.x, .45, .3)], [Vector3(0, .22, size.y * .5), Vector3(size.x, .45, .3)], [Vector3(-size.x * .5, .22, 0), Vector3(.3, .45, size.y)], [Vector3(size.x * .5, .22, 0), Vector3(.3, .45, size.y)]]:
				k.box(node, center + edge[0], edge[1], "stone")
			k.place(node, "e:142:%d" % (1 if qx == qz else 2), center + Vector3(k.rng.randf_range(-1, 1), .04, k.rng.randf_range(-1, 1)), k.rng.randf() * TAU)
			for i in 3: k.place(node, "e:144:%d" % (i % 2), center + Vector3(k.rng.randf_range(-size.x * .35, size.x * .35), .04, k.rng.randf_range(-size.y * .35, size.y * .35)), k.rng.randf() * TAU, false)
			k.place(node, "e:143:%d" % (1 if qx > 0 else 3), center + Vector3(size.x * .3 * -qx, .04, size.y * .3 * -qz), k.rng.randf() * TAU, false)
	k.place(node, "e:146:1", Vector3(1.0, 0, 1.1), .5, false)
	k.place(node, "e:152:3", Vector3(-.4, 0, .2), 0.0, false)
	k.place(node, "e:154:1", Vector3(.6, 0, -1.4), 1.0, false)
	k.place(node, "e:147:2", Vector3(-hw + 1.2, .45, -hd + 1.2), 0.0, false)
	for i in 8: k.flat(node, Vector3(k.rng.randf_range(-1.2, 1.2), .02, k.rng.randf_range(-hd + 1, hd - 1)), Vector3(.5, .02, .4), "glass", k.rng.randf() * TAU)
	k.cover_marker(node, Vector3(-hw * .5, .1, 0)); k.cover_marker(node, Vector3(hw * .5, .1, 0), PI)
	k.area_log.append({"name": "Atrium garden", "building": k.building_id, "floor": 1})

func roof(kit, node: Node3D, bounds: Rect2, data: Dictionary) -> void:
	k = kit
	var blocked: Array[Rect2] = []
	for core: Dictionary in data.cores: blocked.append((core.rect as Rect2).grow(2.5))
	if data.has("atrium"): blocked.append((data.atrium as Rect2).grow(1.5))
	var specs := ["m:air_handler", "e:027:1", "e:027:0", "e:038:1", "e:026:1", "e:093:0", "m:air_handler", "e:027:2", "e:085:1"]
	for i in specs.size() * 2:
		var at := Vector2(k.rng.randf_range(bounds.position.x + 3, bounds.end.x - 3), k.rng.randf_range(bounds.position.y + 3, bounds.end.y - 3))
		var clear := true
		for r in blocked:
			if r.has_point(at): clear = false
		if not clear: continue
		k.place(node, specs[i % specs.size()], Vector3(at.x, 0, at.y), (k.rng.randi() % 4) * PI * .5)
		blocked.append(Rect2(at - Vector2(2.5, 2.5), Vector2(5, 5)))
		k.cover_marker(node, Vector3(at.x + 1.8, .1, at.y))
	for i in 6:
		k.place(node, "e:152:%d" % (i % 4), Vector3(k.rng.randf_range(bounds.position.x + 2, bounds.end.x - 2), 0, k.rng.randf_range(bounds.position.y + 2, bounds.end.y - 2)), k.rng.randf() * TAU, false)
		k.flat(node, Vector3(k.rng.randf_range(bounds.position.x + 2, bounds.end.x - 2), .02, k.rng.randf_range(bounds.position.y + 2, bounds.end.y - 2)), Vector3(k.rng.randf_range(2, 5), .03, k.rng.randf_range(1, 3)), "ivy", k.rng.randf() * TAU)
