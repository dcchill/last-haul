extends RefCounted

## Lab 2 — Clinical. 89 x 31 m racetrack plan, building-local metres (north = -Z).
## North rooms 7 m, north corridor 2.8 m, central support band 11.4 m, south
## corridor 2.8 m, south rooms 7 m. Stairs at the west and east ends of the
## central band (east stair continues to the roof); a three-car lift bank faces
## the north corridor opposite the floor-three skybridge landing at x -2.5.

static func R(title: String, x0: float, z0: float, x1: float, z1: float, role: String, doors: Array, extra := {}) -> Dictionary:
	var result := {"name": title, "rect": Rect2(x0, z0, x1 - x0, z1 - z0), "role": role, "doors": doors}
	result.merge(extra)
	return result

static func patient_rooms(first: int, x0: float, z0: float, z1: float, count: int, door_side: String) -> Array:
	var rooms: Array = []
	for i in count:
		var a := x0 + i * 6.0
		rooms.append(R("Patient room %d" % (first + i), a, z0, a + 6, z1, "patient", ["%s:%s:door" % [door_side, str(a + 3)]]))
	return rooms

static func plan() -> Dictionary:
	return {
		"id": "lab2", "title": "Lab 2 Clinical", "origin": Vector3(50, 0, 45.6), "bounds": Rect2(-44.5, -15.5, 89, 31), "style": "ribbon",
		"cores": [
			{"kind": "stair", "id": "StairWest", "rect": Rect2(-44.5, -5.7, 9, 4.4), "landing": "e", "top": 4},
			{"kind": "stair", "id": "StairEast", "rect": Rect2(35.5, 1.3, 9, 4.4), "landing": "w", "top": 5},
			{"kind": "lift", "id": "BedLifts", "rect": Rect2(-6.4, -5.7, 7.8, 2.6), "side": "n", "cars": 3, "stuck": 3},
		],
		"corridors": [
			{"points": PackedVector2Array([Vector2(-43.6, -7.1), Vector2(43.6, -7.1)]), "width": 2.8, "check": 1.0},
			{"points": PackedVector2Array([Vector2(-43.6, 7.1), Vector2(43.6, 7.1)]), "width": 2.8, "check": 1.0},
			{"points": PackedVector2Array([Vector2(-34.1, -7.1), Vector2(-34.1, 7.1)]), "width": 2.8, "check": 1.0},
			{"points": PackedVector2Array([Vector2(2.8, -7.1), Vector2(2.8, 7.1)]), "width": 2.8, "check": 1.0},
			{"points": PackedVector2Array([Vector2(34.1, -7.1), Vector2(34.1, 7.1)]), "width": 2.8, "check": 1.0},
		],
		"levels": [floor_1(), floor_2(), floor_3(), floor_4()],
	}

static func floor_1() -> Dictionary:
	var rooms := [
		R("Emergency treatment bays", -44.5, -15.5, -30, -8.5, "er", ["s:-40:open:3", "s:-33:door"]),
		R("Triage", -30, -15.5, -24, -8.5, "triage", ["s:-27:door"]),
		R("Patient reception", -24, -15.5, -12, -8.5, "reception", ["n:-18:ext", "s:-18:open:4"]),
		R("Waiting area", -12, -15.5, 2, -8.5, "waiting", ["w:-12:open:4", "s:-5:open:4"]),
	]
	for i in 5: rooms.append(R("Examination room %d" % (i + 1), 2 + i * 5.5, -15.5, 7.5 + i * 5.5, -8.5, "exam", ["s:%s:door" % str(4.75 + i * 5.5)]))
	rooms.append_array([
		R("Supply storage", 29.5, -15.5, 36, -8.5, "medstore", ["s:32.75:door"]),
		R("Staff lounge", 36, -15.5, 44.5, -8.5, "breakroom", ["s:40:door"]),
		R("Resuscitation room", -44.5, 8.5, -34, 15.5, "resus", ["n:-39:door"]),
		R("Minor procedures", -34, 8.5, -26, 15.5, "procedure", ["n:-30:door"]),
		R("Wound care", -26, 8.5, -18, 15.5, "treatment", ["n:-22:door"]),
		R("X-ray room", -18, 8.5, -6, 15.5, "xray", ["n:-12:door"]),
		R("Patient restrooms", -6, 8.5, 0, 15.5, "restroom", ["n:-3:door"]),
		R("Decontamination intake", 0, 8.5, 8, 15.5, "decon", ["n:4:door", "s:4:extdoor"]),
		R("Admissions office", 8, 8.5, 16, 15.5, "office", ["n:12:door"]),
		R("Medical records", 16, 8.5, 24, 15.5, "records", ["n:20:door"]),
		R("Security post", 24, 8.5, 32, 15.5, "security", ["n:28:door"]),
		R("Linen and laundry", 32, 8.5, 38, 15.5, "laundry", ["n:35:door"]),
		R("Deliveries", 38, 8.5, 44.5, 15.5, "loading", ["n:41:door", "s:41:extdoor"]),
		R("Ambulance dispatch", -44.5, -1.3, -35.5, 5.7, "dispatch", ["s:-40:door"]),
		R("Emergency staff station", -32.7, -5.7, -22, 5.7, "nurse_station", ["n:-27:open:3", "s:-27:open:3"]),
		R("Medication room", -22, -5.7, -14, 5.7, "medprep", ["n:-18:door"]),
		R("Clean supply room", -14, -5.7, -6.4, 5.7, "clean_utility", ["s:-10:door"]),
		R("Staff restrooms", -6.4, -3.1, 1.4, 5.7, "restroom", ["s:-2.5:door"]),
		R("Outpatient pharmacy", 4.2, -5.7, 14, 5.7, "dispensary", ["n:9:door"]),
		R("Soiled utility", 14, -5.7, 20, 5.7, "soiled_utility", ["s:17:door"]),
		R("Equipment store", 20, -5.7, 32.7, 5.7, "equipment", ["s:26:door", "n:26:door"]),
		R("Electrical room", 35.5, -5.7, 44.5, 1.3, "electrical", ["n:40:door"]),
	])
	return {"floor": 1, "tier": 1, "title": "Intake and Emergency Treatment", "floor_key": "tile", "rooms": rooms,
		"facade_doors": [{"side": "w", "pos": -7.1, "kind": "ext", "width": 2.6}, {"side": "e", "pos": 7.1, "kind": "extdoor", "width": 2.0}],
		"story": [
			["sign", Vector2(-18, -8.4), PI, "triage_full", 2.2, 2.4], ["barricade", Vector2(-20, -8.1), 0.0], ["body", Vector2(-38, -6.4), 1.5],
			["body", Vector2(10, 6.6), -1.5], ["stain", Vector2(-40, -7.1), 1.4], ["papers", Vector2(-27, 0), 12],
			["sign", Vector2(15, -5.8), PI, "medtac_poster_care", 2.0, 3.0], ["camp", Vector2(28, 1.5), 0.0],
		], "encounters": [
			["infected", Vector2(-37, -12), [Vector2(-37, -12), Vector2(-40, -7.1), Vector2(-31, -12)]],
			["infected", Vector2(-12, 12), [Vector2(-12, 12), Vector2(-12, 7.1), Vector2(-20, 7.1)]],
		]}

static func floor_2() -> Dictionary:
	var rooms := [R("Observation room A", -44.5, -15.5, -36, -8.5, "observation_clinical", ["s:-40:door"], {"glass": [["s", -43.5, -42]]})]
	rooms.append_array(patient_rooms(201, -36, -15.5, -8.5, 10, "s"))
	rooms.append_array([
		R("Treatment room A", 24, -15.5, 32, -8.5, "treatment", ["s:28:door"]),
		R("Treatment room B", 32, -15.5, 38, -8.5, "treatment", ["s:35:door"]),
		R("Observation room B", 38, -15.5, 44.5, -8.5, "observation_clinical", ["s:41:door"], {"glass": [["s", 42.5, 44]]}),
	])
	rooms.append_array(patient_rooms(211, -44.5, 8.5, 15.5, 6, "n"))
	rooms.append_array([
		R("Staff changing", -8.5, 8.5, 0, 15.5, "changing", ["n:-4:door"]),
		R("Clean utility", 0, 8.5, 6, 15.5, "clean_utility", ["n:3:door"]),
		R("Ward soiled utility", 6, 8.5, 12, 15.5, "soiled_utility", ["n:9:door"]),
		R("Medical storage", 12, 8.5, 22, 15.5, "medstore", ["n:17:door"]),
		R("Patient day room", 22, 8.5, 32.7, 15.5, "dayroom", ["n:27:open:3"]),
		R("Service store", 32.7, 8.5, 44.5, 15.5, "service", ["n:36:door", "n:42:door"]),
		R("Ward linen store", -44.5, -1.3, -35.5, 5.7, "laundry", ["s:-40:door"]),
		R("Doctors' office", -32.7, -5.7, -22, 5.7, "office", ["n:-27:door"]),
		R("Medication preparation", -22, -5.7, -14, 5.7, "medprep", ["n:-18:door", "s:-18:door"]),
		R("Nurses' station", -14, -5.7, -6.4, 5.7, "nurse_station", ["n:-10:open:3", "s:-10:open:3"]),
		R("Ward staff restrooms", -6.4, -3.1, 1.4, 5.7, "restroom", ["s:-2.5:door"]),
		R("Equipment bay", 4.2, -5.7, 12, 5.7, "equipment", ["n:8:open:3"]),
		R("Ward staff room", 12, -5.7, 22, 5.7, "breakroom", ["s:17:door"]),
		R("Ward records", 22, -5.7, 32.7, 5.7, "records", ["n:27:door"]),
		R("Ward plant room", 35.5, -5.7, 44.5, 1.3, "plant", ["n:40:door"]),
	])
	return {"floor": 2, "tier": 2, "title": "Patient Care and Observation", "floor_key": "lino", "rooms": rooms,
		"partitions": [{"a": Vector2(32.7, 5.7), "b": Vector2(32.7, 8.5), "doors": ["7.1:door"]}],
		"story": [
			["body", Vector2(-20, -7.0), 1.6], ["stain", Vector2(-9, -7.1), 1.2], ["papers", Vector2(-10, 0), 10],
			["barricade", Vector2(-38.5, 8.1), 0.0], ["sign", Vector2(-25, 5.8), 0.0, "quarantine_ward", 2.0, 2.4],
		], "encounters": [
			["infected", Vector2(-9, -12), [Vector2(-9, -12), Vector2(-9, -7.1), Vector2(0, -7.1)]],
			["infected", Vector2(-29.5, 12), [Vector2(-29.5, 12), Vector2(-29.5, 7.1), Vector2(-20, 7.1)]],
			["infected", Vector2(27, 12), [Vector2(27, 12), Vector2(25, 9.8), Vector2(30, 13)]],
		]}

static func floor_3() -> Dictionary:
	var rooms := [
		R("Clinical trial lab A", -44.5, -15.5, -30, -8.5, "trial_lab", ["s:-37:door"]),
		R("Clinical trial lab B", -30, -15.5, -16, -8.5, "trial_lab", ["s:-23:door"]),
		R("Diagnostic laboratory", -16, -15.5, -6, -8.5, "diagnostic", ["s:-11:door"]),
		R("Skybridge security post", -6, -15.5, 1, -8.5, "bridge_security", ["s:-2.5:open:3", "n:-2.5:extopen"]),
		R("Research administration", 1, -15.5, 14, -8.5, "openoffice", ["s:5:door", "s:11:door"]),
		R("Trial coordinator office", 14, -15.5, 22, -8.5, "office", ["s:18:door"]),
		R("Consent and screening", 22, -15.5, 30, -8.5, "consent", ["s:26:door"]),
		R("Restricted medication storage", 30, -15.5, 38, -8.5, "medvault", ["s:34:door"]),
		R("Trial pharmacy", 38, -15.5, 44.5, -8.5, "dispensary", ["s:41:door"]),
	]
	for i in 3: rooms.append(R("Trial treatment room %d" % (i + 1), -44.5 + i * 8, 8.5, -36.5 + i * 8, 15.5, "trial_treatment", ["n:%s:door" % str(-40.5 + i * 8)]))
	rooms.append_array([
		R("Controlled patient observation", -20.5, 8.5, -6, 15.5, "controlled_obs", ["n:-17:door"]),
		R("Observation control", -6, 8.5, 2, 15.5, "obs_control", ["n:-2:door"], {"glass": [["w", 9.5, 14.5]]}),
		R("Patient holding", 2, 8.5, 14, 15.5, "holding", ["n:8:door"]),
		R("Sample processing", 14, 8.5, 24, 15.5, "diagnostic", ["n:19:door"]),
		R("Trial records", 24, 8.5, 32.7, 15.5, "records", ["n:28:door"]),
		R("Secure patient transfer", 32.7, 8.5, 44.5, 15.5, "transfer", ["n:38:door"]),
		R("Trial monitoring", -44.5, -1.3, -35.5, 5.7, "monitoring", ["s:-40:door"]),
		R("Specimen cold room", -32.7, -5.7, -22, 5.7, "cold", ["n:-27:door"]),
		R("Trial data room", -22, -5.7, -14, 5.7, "server", ["s:-18:door"]),
		R("Clinical staff base", -14, -5.7, -6.4, 5.7, "nurse_station", ["n:-10:open:3", "s:-10:open:3"]),
		R("Level three staff restrooms", -6.4, -3.1, 1.4, 5.7, "restroom", ["s:-2.5:door"]),
		R("Level three equipment storage", 4.2, -5.7, 14, 5.7, "equipment", ["n:9:door"]),
		R("Level three clean utility", 14, -5.7, 22, 5.7, "clean_utility", ["s:18:door"]),
		R("Trial investigator office", 22, -5.7, 32.7, 5.7, "office", ["n:27:door"]),
		R("Level three plant room", 35.5, -5.7, 44.5, 1.3, "plant", ["n:40:door"]),
	])
	return {"floor": 3, "tier": 3, "title": "Clinical Trials and Skybridge", "floor_key": "lino", "rooms": rooms,
		"partitions": [
			{"a": Vector2(4.2, 5.7), "b": Vector2(4.2, 8.5), "doors": ["7.1:glass"]},
			{"a": Vector2(32.7, 5.7), "b": Vector2(32.7, 8.5), "doors": ["7.1:glass"]},
		], "story": [
			["barricade", Vector2(-8.4, -8.1), 0.0], ["body", Vector2(-1, -6.4), 1.6], ["stain", Vector2(-12, 7.1), 1.4],
			["sign", Vector2(-24, -8.4), PI, "mt_rg_01", 2.2, 2.6], ["papers", Vector2(26, -7.1), 12], ["body", Vector2(18, 7.0), -1.6],
		], "encounters": [
			["infected", Vector2(-13, 12), [Vector2(-13, 12), Vector2(-17, 7.1), Vector2(-8, 11)]],
			["infected", Vector2(-23, -12), [Vector2(-23, -12), Vector2(-23, -7.1), Vector2(-30, -7.1)]],
			["infected", Vector2(8, 12), [Vector2(8, 12), Vector2(8, 7.1), Vector2(14, 7.1)]],
			["scav", Vector2(-2.5, -12), [Vector2(-2.5, -12), Vector2(-2.5, -7.1), Vector2(10, -7.1)]],
		]}

static func floor_4() -> Dictionary:
	var rooms := [
		R("Isolation room one", -44.5, -15.5, -38.5, -8.5, "isolation", ["s:-41.5:door"], {"glass": [["s", -40.2, -39]]}),
		R("Isolation room two", -38.5, -15.5, -32.5, -8.5, "isolation", ["s:-35.5:door"], {"glass": [["s", -34.2, -33]]}),
		R("Intensive care unit", -32.5, -15.5, -6, -8.5, "icu", ["s:-27:open:3", "s:-12:open:3"]),
		R("Patient monitoring station", -6, -15.5, 2, -8.5, "monitoring", ["s:-2:door"], {"glass": [["w", -14.5, -9.5]]}),
		R("Experimental treatment suite A", 2, -15.5, 14, -8.5, "experimental", ["s:8:door"]),
		R("Experimental treatment suite B", 14, -15.5, 26, -8.5, "experimental", ["s:20:door"]),
		R("Isolation room three", 26, -15.5, 32, -8.5, "isolation", ["s:29:door"], {"glass": [["s", 30.2, 31.4]]}),
		R("Isolation room four", 32, -15.5, 38, -8.5, "isolation", ["s:35:door"], {"glass": [["s", 36.2, 37.4]]}),
		R("Staff gowning", 38, -15.5, 44.5, -8.5, "gowning", ["s:41:door"]),
		R("Secure pharmaceutical storage", -44.5, 8.5, -36, 15.5, "vault_pharma", ["n:-40:vault"]),
		R("Clinical research records", -36, 8.5, -24, 15.5, "records_secure", ["n:-30:door"]),
		R("Medical equipment storage", -24, 8.5, -12, 15.5, "equipment", ["n:-18:door"]),
		R("Staff preparation", -12, 8.5, -4, 15.5, "changing", ["n:-8:door"]),
		R("Improvised quarantine ward", -4, 8.5, 14, 15.5, "makeshift", ["n:0:open:3", "n:10:door"]),
		R("On-call room", 14, 8.5, 22, 15.5, "oncall", ["n:18:door"]),
		R("Maintenance store", 22, 8.5, 32.7, 15.5, "maintenance", ["n:27:door"]),
		R("Decontamination showers", 32.7, 8.5, 44.5, 15.5, "decon", ["n:36:door"]),
		R("Isolation anteroom", -44.5, -1.3, -35.5, 5.7, "gowning", ["s:-40:door"]),
		R("ICU central monitoring", -32.7, -5.7, -22, 5.7, "monitoring", ["n:-27:open:3"]),
		R("Experimental drug preparation", -22, -5.7, -14, 5.7, "drugprep", ["n:-18:door"]),
		R("Blood and sample bank", -14, -5.7, -6.4, 5.7, "cold", ["s:-10:door"]),
		R("Level four staff restrooms", -6.4, -3.1, 1.4, 5.7, "restroom", ["s:-2.5:door"]),
		R("Ventilator store", 4.2, -5.7, 14, 5.7, "equipment", ["n:9:door"]),
		R("Clinical lead office", 14, -5.7, 22, 5.7, "exec", ["s:18:door"]),
		R("Trial outcome archive", 22, -5.7, 32.7, 5.7, "records_secure", ["n:27:door"]),
		R("Maintenance and roof access", 35.5, -5.7, 44.5, 1.3, "maintenance", ["n:40:door"]),
	]
	return {"floor": 4, "tier": 4, "title": "Intensive Care and Experimental Treatments", "floor_key": "tile", "rooms": rooms,
		"partitions": [{"a": Vector2(-32.5, -8.5), "b": Vector2(-32.5, -5.7), "doors": ["-7.1:broken"]}],
		"story": [
			["sign", Vector2(-32.3, -7.1), PI * .5, "do_not_open", 1.6, 2.0], ["decay", Vector2(-38, -7.1)], ["body", Vector2(-20, -7.0), 1.6, false],
			["body", Vector2(5, 7.0), 1.5], ["stain", Vector2(20, -7.1), 1.6], ["sign", Vector2(8, -8.4), PI, "exposure_trial", 2.2, 2.6],
			["barricade", Vector2(-14, 8.1), 0.0], ["decay", Vector2(16, 7.1)],
		], "encounters": [
			["infected", Vector2(-25, -12), [Vector2(-25, -12), Vector2(-20, -12), Vector2(-27, -7.1)]],
			["infected", Vector2(-14, -12), [Vector2(-14, -12), Vector2(-10, -11), Vector2(-12, -7.1)]],
			["infected", Vector2(5, 12), [Vector2(5, 12), Vector2(0, 11), Vector2(10, 12)]],
			["infected", Vector2(-40, 2), [Vector2(-40, 2), Vector2(-40, 5), Vector2(-38, 0)]],
			["infected", Vector2(20, -12), [Vector2(20, -12), Vector2(20, -7.1), Vector2(26, -7.1)]],
		]}
