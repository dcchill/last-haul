extends SceneTree

var catalog := Catalog.new()
var stage: Node3D
var view: Node3D
var rig: WeaponHands
var failures := 0
var checks := 0
var samples := 0
var adaptive_samples := 0
var combinations := 0
var quick := false
var only_weapon := ""
var report: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures <= 20: push_error("HAND FAIL: " + label)

func run() -> void:
	quick = "--quick" in OS.get_cmdline_user_args()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--weapon="): only_weapon = argument.trim_prefix("--weapon=")
	check(catalog.load_all().is_empty(), "catalog and profile completeness")
	_geometry_tests()
	stage = Node3D.new()
	root.add_child(stage)
	view = load("res://scripts/weapons/bedrock_weapon.gd").new()
	stage.add_child(view)
	rig = WeaponHands.new()
	stage.add_child(rig)
	var glove_instance: int = rig.hands.right.glove.get_instance_id()
	var sleeve_instance: int = rig.hands.left.sleeve.get_instance_id()
	for source in ArmoryContent.DATA.data.guns:
		if "--switches-only" in OS.get_cmdline_user_args(): continue
		if not only_weapon.is_empty() and source.id != only_weapon: continue
		var definition: WeaponDef = catalog.definitions[source.id]
		check(definition.hand_profile != null and definition.hand_profile.weapon_id == source.id, source.id + " explicit profile")
		var weapon := _weapon(definition)
		view.configure(definition.model_path, definition.texture_path, definition.animation_path)
		rig.bind(definition.hand_profile)
		check(not view.has_method("_create_hands") and rig.get_child_count() == 4, "exactly two persistent glove/sleeve pairs")
		for bone in [rig.profile.right_bone, rig.profile.left_bone, rig.profile.loading_bone]:
			check(view.bones.has(bone), source.id + " anchor " + bone)
		rig.worst_correction = 0
		var starting_samples := samples
		for config in _configurations(definition):
			combinations += 1
			view.configure(definition.model_path, definition.texture_path, definition.animation_path)
			weapon.data.attachments = config
			view.show_attachments(weapon)
			var zoom := weapon.magnification(catalog.definitions)
			for action in ["idle", "fire", "reload", "reload_empty", "reload_insert", "unload", "equip", "reset"]:
				if not view.clips.has(action): continue
				var loaded: Dictionary = weapon.data.magazine.duplicate(true)
				if action == "reload_insert": weapon.data.magazine = {}
				if action == "reload_empty" and not weapon.data.magazine.is_empty(): weapon.data.magazine.state.rounds = 0
				weapon.reload_action = action
				var duration: float = maxf(0.05, view.clips[action].length)
				var times := _sample_times(action, duration)
				var previous: Dictionary = {}
				var previous_time := 0.0
				for seconds: float in times:
					var pose := _sample(weapon, action, seconds, 0, zoom)
					if not quick and not previous.is_empty():
						_refine(weapon, action, previous_time, previous, seconds, pose, 0, zoom, 0)
					previous = pose
					previous_time = seconds
				weapon.data.magazine = loaded
			# Every attachment combination crosses the whole aim-in/aim-out range.
			if definition.can_aim:
				for index in range(25 if quick else 121):
					_sample(weapon, "idle", 0, float(index) / (24 if quick else 120), zoom)
				for index in range(8 if quick else 61):
					var seconds: float = view.clips.fire.length * index / (7.0 if quick else 60.0)
					_sample(weapon, "fire", seconds, 1, zoom)
				for index in range(8 if quick else 31):
					var seconds: float = 0.2 * index / (7.0 if quick else 30.0)
					_sample(weapon, "reload", seconds, 1 - seconds / 0.2, zoom)
			_transitions(weapon, zoom)
			_motion_trace(weapon, zoom)
			_cancel_paths(weapon, zoom)
		check(rig.hands.right.glove.get_instance_id() == glove_instance and rig.hands.left.sleeve.get_instance_id() == sleeve_instance, source.id + " rebuilds preserve hands")
		report[source.id] = {"samples": samples - starting_samples, "maximum_correction_m": rig.worst_correction}
		print("HAND CHECK ", source.id, ": ", samples - starting_samples, " poses")
		await process_frame
	if only_weapon.is_empty(): _switches()
	stage.free()
	await process_frame
	var file := FileAccess.open("res://.godot/hand_pose_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"weapons": report, "checks": checks, "poses": samples, "adaptive": adaptive_samples, "combinations": combinations, "failures": failures}, "  "))
	file.close()
	print("HAND POSES: %d checks, %d poses (%d adaptive), %d attachment combinations, %d failures" % [checks, samples, adaptive_samples, combinations, failures])
	quit(1 if failures > 0 else 0)

func _weapon(definition: WeaponDef) -> WeaponState:
	var weapon := WeaponState.new(definition)
	if definition.magazine_id.is_empty():
		weapon.data.rounds = definition.magazine_size
	else:
		var mag := ArmoryInstance.fresh(definition.magazine_id, catalog.items)
		mag.rounds = definition.magazine_size
		weapon.data.magazine = {"id": definition.magazine_id, "quantity": 1, "state": mag}
	return weapon

func _configurations(definition: WeaponDef) -> Array[Dictionary]:
	var options: Dictionary = {"optic": [""], "muzzle": [""], "grip": [""]}
	for source in ArmoryContent.DATA.data.attachments:
		if catalog.definitions[source.id].supports(definition): options[source.slot].append(source.id)
	var result: Array[Dictionary] = []
	for optic: String in options.optic:
		for muzzle: String in options.muzzle:
			for grip: String in options.grip:
				var config: Dictionary = {}
				for pair in [["optic", optic], ["muzzle", muzzle], ["grip", grip]]:
					if not pair[1].is_empty(): config[pair[0]] = {"id": pair[1], "quantity": 1, "state": ArmoryInstance.fresh(pair[1], catalog.items)}
				result.append(config)
	return result

func _sample_times(action: String, duration: float) -> Array[float]:
	var times: Dictionary = {}
	var count := 10 if quick else ceili(duration * 120)
	for index in range(count + 1): times[duration * index / count] = true
	for tracks in view.clips[action].bones.values():
		for frames in tracks.values():
			for frame in frames: times[float(frame.time)] = true
	var result: Array[float] = []
	for time in times: result.append(time)
	result.sort()
	return result

func _sample(weapon: WeaponState, action: String, seconds: float, aim: float, zoom: int) -> Dictionary:
	var pose := WeaponPoseEvaluator.seek(view, rig, weapon, action, seconds, aim, zoom, seconds * 1440)
	samples += 1
	var intersections := rig.intersections()
	check(intersections.is_empty(), "%s %s %.5fs aim %.2f: %s" % [weapon.definition.id, action, seconds, aim, str(intersections)])
	for side in ["right", "left"]:
		check(absf(pose[side].glove.basis.determinant() - 1) < 0.0001, "glove size independent of ADS/weapon scale")
		check(absf(pose[side].sleeve.basis.determinant() - 1) < 0.0001, "sleeve size independent of ADS/weapon scale")
		if action == "idle":
			check(_touching(pose[side].glove), "%s %s holds exposed surface at %.5fs aim %.2f correction %.4fm" % [weapon.definition.id, side, seconds, aim, pose[side].glove.origin.distance_to(rig.targets_debug[side].origin)])
	return pose

func _touching(glove: Transform3D) -> bool:
	var shape := HandClearance.box(glove, WeaponHands.GLOVE_HALF)
	for solid in rig.solids:
		if not HandClearance.penetration(shape, solid, 0.025).is_zero_approx(): return true
	return false

func _near_plane_clear() -> bool:
	# Visible rectangle at the actual 70-degree, 16:9 camera's 5cm near plane.
	var near_plane := HandClearance.box(Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.05)), Vector3(0.06224, 0.03501, 0.00005))
	for side in rig.poses:
		for part in ["glove", "sleeve"]:
			var shape := HandClearance.box(rig.poses[side][part], WeaponHands.GLOVE_HALF if part == "glove" else WeaponHands.SLEEVE_HALF)
			if not HandClearance.penetration(shape, near_plane).is_zero_approx(): return false
	return true

func _motion_trace(weapon: WeaponState, zoom: int) -> void:
	var motion := WeaponMotion.new()
	for index in range(240):
		var seconds := index / 120.0
		var reloading := index >= 150
		var action := "reload" if reloading else "fire"
		var time := (index - 150) / 120.0 if reloading else fmod(seconds, float(view.clips.fire.length))
		if index % (weapon.definition.interval_ticks * 6) == 0: motion.fire(1.6)
		if index == 30: motion.land(1)
		motion.update(1.0 / 120, index >= 70 and index < 130 and weapon.definition.can_aim, 0.2, Vector2(sin(seconds * 4), cos(seconds * 4)), 1, index < 70, not weapon.definition.can_aim, time / weapon.definition.reload_seconds if reloading else -1)
		view.spin_angle = motion.barrel_angle
		view.seek_visual(weapon, action, time)
		WeaponPoseEvaluator.place(view, weapon, motion.aim, zoom, motion.position, motion.angles)
		rig.evaluate(view, weapon, action, time, 1.0 / 120, false)
		samples += 1
		check(rig.intersections().is_empty(), weapon.definition.id + " recoil/walk/sprint/landing/sway")
		check(_near_plane_clear(), weapon.definition.id + " visible hand near-plane clearance")

func _cancel_paths(weapon: WeaponState, zoom: int) -> void:
	if weapon.definition.magazine_id.is_empty(): return
	var state: Dictionary = weapon.data.duplicate(true)
	for progress in [0.15, 0.30, 0.42, 0.60, 0.80]:
		var seconds: float = weapon.definition.reload_seconds * progress
		_sample(weapon, "reload", seconds, 0, zoom)
		rig.evaluate(view, weapon, "reload", seconds, 0, false)
		var bone: Node3D = view.bones[rig.profile.magazine_bone]
		var previous := bone.global_transform
		for index in range(37):
			view.seek_visual(weapon, "reset", index / 120.0)
			WeaponPoseEvaluator.place(view, weapon, 0, zoom)
			rig.evaluate(view, weapon, "reset", index / 120.0, 0 if index == 0 else 1.0 / 120, false)
			samples += 1
			check(rig.intersections().is_empty(), weapon.definition.id + " cancellation phase " + str(progress) + " frame " + str(index) + ": " + str(rig.intersections()))
			if index == 0:
				check(previous.origin.distance_to(bone.global_position) < 0.0001, weapon.definition.id + " cancelled prop does not teleport")
		check(rig.prop_return.is_empty(), "cancelled magazine return finishes")
	check(weapon.data == state, "pose evaluation preserves authoritative item instance")

func _refine(weapon: WeaponState, action: String, start: float, a: Dictionary, end: float, b: Dictionary, aim: float, zoom: int, depth: int) -> void:
	if depth >= 4 or end - start < 0.0005: return
	var distance := 0.0
	for side in ["right", "left"]:
		for part in ["glove", "sleeve"]:
			distance = maxf(distance, a[side][part].origin.distance_to(b[side][part].origin))
	if distance < 0.008: return
	var middle := (start + end) * 0.5
	var pose := _sample(weapon, action, middle, aim, zoom)
	adaptive_samples += 1
	_refine(weapon, action, start, a, middle, pose, aim, zoom, depth + 1)
	_refine(weapon, action, middle, pose, end, b, aim, zoom, depth + 1)

func _transitions(weapon: WeaponState, zoom: int) -> void:
	# Continuous live evaluation, including interruptions and automatic fire restarts.
	var sequence := [["reload", 0.65], ["reset", 0.0], ["idle", 0.0], ["equip", 0.0], ["fire", 0.0], ["fire", 0.0]]
	for entry in sequence:
		for index in range(12):
			var seconds: float = float(entry[1]) + index / 120.0
			view.seek_visual(weapon, entry[0], seconds)
			WeaponPoseEvaluator.place(view, weapon, 0, zoom)
			rig.evaluate(view, weapon, entry[0], seconds, 1.0 / 120, false)
			samples += 1
			check(rig.intersections().is_empty(), weapon.definition.id + " interrupted transition")
	# Rebuilding compatible attachments preserves the two hands and blends into
	# the new contact target, including a newly installed vertical grip.
	var installed: Dictionary = weapon.data.attachments.duplicate(true)
	for config in [{}, installed]:
		weapon.data.attachments = config
		view.configure(weapon.definition.model_path, weapon.definition.texture_path, weapon.definition.animation_path)
		view.show_attachments(weapon)
		rig.bind(weapon.definition.hand_profile)
		for index in range(25):
			view.seek_visual(weapon, "equip", index / 120.0)
			WeaponPoseEvaluator.place(view, weapon, 0, zoom)
			rig.evaluate(view, weapon, "equip", index / 120.0, 1.0 / 120, false)
			samples += 1
			check(rig.intersections().is_empty(), weapon.definition.id + " attachment rebuild")
	weapon.data.attachments = installed

func _switches() -> void:
	# Every ordered pair, including leaving an interrupted reload or ADS pose.
	for from_source in ArmoryContent.DATA.data.guns:
		for to_source in ArmoryContent.DATA.data.guns:
			var from := _weapon(catalog.definitions[from_source.id])
			var into := _weapon(catalog.definitions[to_source.id])
			view.configure(from.definition.model_path, from.definition.texture_path, from.definition.animation_path)
			_sample(from, "reload", from.definition.reload_seconds * 0.3, 0, 1)
			view.configure(into.definition.model_path, into.definition.texture_path, into.definition.animation_path)
			rig.bind(into.definition.hand_profile)
			for index in range(43):
				var seconds := index / 120.0
				view.seek_visual(into, "equip", seconds)
				WeaponPoseEvaluator.place(view, into, 0)
				rig.evaluate(view, into, "equip", seconds, 1.0 / 120, false)
				samples += 1
				check(rig.intersections().is_empty(), from_source.id + " -> " + to_source.id + " switch " + str(index) + ": " + str(rig.intersections()))
	print("HAND SWITCHES: 144 ordered weapon pairs")

func _geometry_tests() -> void:
	var a := HandClearance.box(Transform3D.IDENTITY, Vector3.ONE * 0.5)
	var b := HandClearance.box(Transform3D(Basis.IDENTITY, Vector3(0.75, 0, 0)), Vector3.ONE * 0.5)
	check(is_equal_approx(HandClearance.penetration(a, b).length(), 0.25), "SAT detects known penetration depth")
	b = HandClearance.box(Transform3D(Basis.IDENTITY, Vector3(1, 0, 0)), Vector3.ONE * 0.5)
	check(HandClearance.penetration(a, b).is_zero_approx(), "surface contact is allowed")
	var rotation := Basis(Vector3.BACK, PI / 4)
	a = HandClearance.box(Transform3D(rotation, Vector3.ZERO), Vector3(1, 0.03, 0.03))
	b = HandClearance.box(Transform3D(rotation, Vector3(-0.1, 0.1, 0)), Vector3(1, 0.03, 0.03))
	check(a.bounds.intersects(b.bounds) and HandClearance.penetration(a, b).is_zero_approx(), "SAT rejects rotated AABB false positives")
