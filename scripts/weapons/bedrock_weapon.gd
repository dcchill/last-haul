extends Node3D

# shortcut: supports the cube and per-face UV format in this model, extend for other Bedrock assets.
@export var model: JSON = preload("res://resources/weapons/kalashnikov.json")
@export var texture: Texture2D = preload("res://resources/weapons/kalashnikov_texture.png")
@export var animations: JSON = preload("res://resources/weapons/kalashnikov.animation.json")
const UNIT := 1.0 / 16.0

var bones: Dictionary = {}
var clips: Dictionary = {}
var action := "equip"
var action_time := 0.0
var reloading := false
var hands: Dictionary = {}

func _ready() -> void:
	var geometry: Dictionary = model.data["minecraft:geometry"][0]
	var texture_size := Vector2(geometry.description.texture_width, geometry.description.texture_height)
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for bone in geometry.bones:
		var node := Node3D.new()
		node.name = bone.name
		var parent: Node3D = bones.get(bone.get("parent", ""), self)
		parent.add_child(node)
		var pivot := _vector(bone.get("pivot", [0, 0, 0]))
		var parent_pivot := Vector3.ZERO
		if bone.has("parent"):
			parent_pivot = parent.get_meta("pivot")
		node.position = (pivot - parent_pivot) * UNIT
		node.rotation_degrees = _vector(bone.get("rotation", [0, 0, 0]))
		node.set_meta("pivot", pivot)
		node.set_meta("rest_position", node.position)
		node.set_meta("rest_rotation", node.rotation_degrees)
		bones[bone.name] = node
		for cube in bone.get("cubes", []):
			var part := MeshInstance3D.new()
			part.mesh = _cube_mesh(cube, pivot, texture_size)
			part.material_override = material
			node.add_child(part)

	_create_hands()
	_compile_animations()

func _create_hands() -> void:
	var glove := StandardMaterial3D.new()
	glove.albedo_color = Color(0.25, 0.22, 0.16)
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_color = Color(0.19, 0.24, 0.17)
	for socket_name in ["right_hand_socket", "left_hand_socket", "reload_hand_socket"]:
		if not bones.has(socket_name):
			continue
		var hand := Node3D.new()
		hand.name = "Hand"
		bones[socket_name].add_child(hand)
		var side := 1.0 if socket_name == "right_hand_socket" else -1.0
		hand.rotation_degrees = Vector3(30, 0, side * 15)
		for part in [[Vector3(0.1, 0.09, 0.12), Vector3.ZERO, glove], [Vector3(0.11, 0.11, 0.27), Vector3(0, -0.025, 0.18), sleeve]]:
			var mesh := BoxMesh.new()
			mesh.size = part[0]
			var visual := MeshInstance3D.new()
			visual.mesh = mesh
			visual.material_override = part[2]
			visual.position = part[1]
			hand.add_child(visual)
		hands[socket_name] = hand
	if hands.has("reload_hand_socket"):
		hands["reload_hand_socket"].visible = false

func _compile_animations() -> void:
	clips.clear()
	for clip_name in animations.data.animations:
		var source: Dictionary = animations.data.animations[clip_name]
		var loop_mode: Variant = source.get("loop", false)
		var clip := {"length": float(source.get("animation_length", 0.0)), "loop": loop_mode is bool and loop_mode, "hold": loop_mode is String and loop_mode == "hold_on_last_frame", "bones": {}}
		for bone_name in source.get("bones", {}):
			if not bones.has(bone_name):
				continue
			var tracks := {}
			for property in source.bones[bone_name]:
				if property not in ["position", "rotation", "scale"]:
					continue
				var keys: Dictionary = source.bones[bone_name][property]
				if keys.has("vector"):
					tracks[property] = [{"time": 0.0, "value": _vector(keys.vector), "easing": "linear", "steps": 1.0}]
					continue
				var times := keys.keys()
				times.sort_custom(func(a, b): return float(a) < float(b))
				var frames := []
				for time in times:
					var key: Variant = keys[time]
					var values: Array = key.get("vector", []) if key is Dictionary else key
					if values.size() == 3:
						frames.append({"time": float(time), "value": _vector(values), "easing": key.get("easing", "linear") if key is Dictionary else "linear", "steps": float(key.get("easingArgs", [1])[0]) if key is Dictionary and not key.get("easingArgs", []).is_empty() else 1.0})
				tracks[property] = frames
			clip.bones[bone_name] = tracks
		clips[clip_name] = clip

func play_clip(clip_name: String) -> bool:
	if not clips.has(clip_name):
		return false
	action = clip_name
	action_time = 0.0
	return true

func fire() -> void:
	play_clip("fire")

func animate(delta: float, weapon: WeaponState) -> void:
	var is_reloading := weapon.reload_left > 0.0
	if is_reloading:
		if not reloading:
			action = "reload_empty" if weapon.magazine == 0 and clips.has("reload_empty") else "reload"
		var length: float = clips.get(action, {}).get("length", 0.0)
		action_time = length * (1.0 - weapon.reload_left / weapon.definition.reload_seconds)
	elif reloading:
		action = "idle"
		action_time = 0.0
	else:
		action_time += delta
		if not clips.has(action):
			action = "idle"
			action_time = 0.0
		elif clips[action].length > 0.0 and action_time >= clips[action].length:
			if clips[action].loop:
				action_time = fmod(action_time, clips[action].length)
			elif clips[action].hold:
				action_time = clips[action].length
			else:
				action = "idle"
				action_time = 0.0
	reloading = is_reloading
	apply_clip(action, action_time)
	_update_hands(weapon)

func _update_hands(weapon: WeaponState) -> void:
	var progress := 1.0 - weapon.reload_left / weapon.definition.reload_seconds if reloading else -1.0
	var carrying := reloading and (progress >= 0.14 and progress < 0.36 or progress >= 0.46 and progress <= 0.79)
	if hands.has("left_hand_socket"):
		hands["left_hand_socket"].visible = not carrying
	if hands.has("reload_hand_socket"):
		hands["reload_hand_socket"].visible = carrying
	if bones.has("standard_mag"):
		bones["standard_mag"].visible = not reloading or progress < 0.36 or progress >= 0.46

func apply_clip(clip_name: String, time: float) -> void:
	for node in bones.values():
		node.position = node.get_meta("rest_position")
		node.rotation_degrees = node.get_meta("rest_rotation")
		node.scale = Vector3.ONE
	if not clips.has(clip_name):
		return
	for bone_name in clips[clip_name].bones:
		var node: Node3D = bones[bone_name]
		var tracks: Dictionary = clips[clip_name].bones[bone_name]
		if tracks.has("position"):
			node.position += _sample(tracks.position, time) * UNIT
		if tracks.has("rotation"):
			var angles := _sample(tracks.rotation, time)
			angles.x = -angles.x
			node.rotation_degrees += angles
		if tracks.has("scale"):
			node.scale = _sample(tracks.scale, time)

func _sample(frames: Array, time: float) -> Vector3:
	if frames.is_empty():
		return Vector3.ZERO
	var previous: Dictionary = frames[0]
	for frame in frames:
		if time < frame.time:
			var weight := clampf((time - previous.time) / (frame.time - previous.time), 0.0, 1.0)
			return previous.value.lerp(frame.value, _ease(weight, frame.easing, frame.steps))
		previous = frame
	return previous.value

func _ease(weight: float, easing: String, steps: float) -> float:
	if easing == "step":
		return floor(weight * maxf(steps, 1.0)) / maxf(steps, 1.0)
	if easing == "linear":
		return weight
	var transition := Tween.TRANS_LINEAR
	if easing.ends_with("Sine"):
		transition = Tween.TRANS_SINE
	elif easing.ends_with("Quad"):
		transition = Tween.TRANS_QUAD
	elif easing.ends_with("Cubic"):
		transition = Tween.TRANS_CUBIC
	elif easing.ends_with("Quart"):
		transition = Tween.TRANS_QUART
	elif easing.ends_with("Quint"):
		transition = Tween.TRANS_QUINT
	elif easing.ends_with("Expo"):
		transition = Tween.TRANS_EXPO
	elif easing.ends_with("Back"):
		transition = Tween.TRANS_BACK
	var direction := Tween.EASE_IN_OUT if easing.begins_with("easeInOut") else (Tween.EASE_OUT if easing.begins_with("easeOut") else Tween.EASE_IN)
	return Tween.interpolate_value(0.0, 1.0, weight, 1.0, transition, direction)

func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

func _cube_mesh(cube: Dictionary, bone_pivot: Vector3, texture_size: Vector2) -> ArrayMesh:
	var origin := _vector(cube.origin)
	var size := _vector(cube.size)
	var inflate: float = cube.get("inflate", 0.0)
	var low := origin - Vector3.ONE * inflate
	var high := origin + size + Vector3.ONE * inflate
	var pivot := _vector(cube.get("pivot", cube.origin))
	var angles := _vector(cube.get("rotation", [0, 0, 0]))
	angles.x = -angles.x
	var rotation := Basis.from_euler(angles * PI / 180.0)
	var vertices := [
		Vector3(low.x, low.y, low.z), Vector3(high.x, low.y, low.z),
		Vector3(high.x, high.y, low.z), Vector3(low.x, high.y, low.z),
		Vector3(low.x, low.y, high.z), Vector3(high.x, low.y, high.z),
		Vector3(high.x, high.y, high.z), Vector3(low.x, high.y, high.z)]
	var faces := {"north": [2, 3, 0, 1], "south": [7, 6, 5, 4],
		"east": [6, 2, 1, 5], "west": [3, 7, 4, 0],
		"up": [6, 7, 3, 2], "down": [1, 0, 4, 5]}
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in faces:
		if not cube.uv.has(face):
			continue
		var uv_data: Dictionary = cube.uv[face]
		var uv := Vector2(uv_data.uv[0], uv_data.uv[1])
		var span := Vector2(uv_data.uv_size[0], uv_data.uv_size[1])
		var uvs := [uv, uv + Vector2(span.x, 0), uv + span, uv + Vector2(0, span.y)]
		for index in [0, 1, 2, 0, 2, 3]:
			surface.set_uv(uvs[index] / texture_size)
			surface.add_vertex((pivot + rotation * (vertices[faces[face][index]] - pivot) - bone_pivot) * UNIT)
	surface.generate_normals()
	return surface.commit()
