extends Camera3D

@export var preview_title := "LAST HAUL / 64 WORLD PROPS"
var home_transform: Transform3D

func _ready() -> void:
	home_transform = transform
	var hud := CanvasLayer.new()
	var label := Label.new()
	label.position = Vector2(24, 20)
	label.text = preview_title + "\nHold RMB + WASD to fly · Q/E down/up · Shift faster · Home overview · Esc release"
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	hud.add_child(label)
	add_child(hud)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if event.keycode == KEY_HOME: transform = home_transform
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * 0.003
		rotation.x = clampf(rotation.x - event.relative.y * 0.003, -1.5, 1.5)

func _process(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return
	var direction := Vector3(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	position += basis * direction.limit_length() * delta * (35.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 10.0)
