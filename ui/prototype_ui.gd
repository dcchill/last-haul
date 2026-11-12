class_name PrototypeUI
extends CanvasLayer

var app: Node
var root: Control
var panel: VBoxContainer
var hud: Label
var notice_label: Label
var crosshair: Label
var message: String = ""
var notice_until: int = 0
var mode: String = "home"
var container_id: String = ""
var focus_scheduled: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	theme.default_font_size = 20
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0.12, 0.25, 0.31)
	focus.border_color = Color(0.4, 1, 0.8)
	focus.set_border_width_all(3)
	theme.set_stylebox("focus", "Button", focus)
	root.theme = theme
	hud = Label.new()
	hud.position = Vector2(24, 20)
	hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	hud.add_theme_constant_override("shadow_outline_size", 5)
	root.add_child(hud)
	notice_label = Label.new()
	notice_label.position = Vector2(24, 635)
	notice_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	notice_label.add_theme_constant_override("shadow_outline_size", 5)
	root.add_child(notice_label)
	crosshair = Label.new()
	crosshair.text = "+"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.position -= Vector2(7, 14)
	root.add_child(crosshair)

func _clear(new_mode: String) -> void:
	mode = new_mode
	focus_scheduled = false
	if panel != null:
		panel.get_parent().hide()
		panel.get_parent().queue_free()
		panel = null
	var is_hud := new_mode == "hud"
	hud.visible = is_hud
	crosshair.visible = is_hud
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if is_hud else Input.MOUSE_MODE_VISIBLE
	if is_hud:
		return
	var background := PanelContainer.new()
	background.position = Vector2(250, 55)
	background.custom_minimum_size = Vector2(780, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.075, 0.98)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	background.add_theme_stylebox_override("panel", style)
	root.add_child(background)
	panel = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 12)
	background.add_child(panel)

func _text(value: String, size: int = 20) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	panel.add_child(label)
	return label

func _button(value: String, callback: Callable, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = value
	button.disabled = disabled
	button.pressed.connect(callback)
	panel.add_child(button)
	if not disabled and not focus_scheduled:
		focus_scheduled = true
		button.grab_focus.call_deferred()
	return button

func show_home() -> void:
	_clear("home")
	_text("LAST HAUL", 42)
	_text("FIELD TEST  /  SALVAGE YARD", 22)
	_text("Deploy. Secure salvage from the orange crate. Extract at green.")
	_text("Free rifle + ammo each raid. Death loses raid loot.")
	var amount := 0
	for slot in app.profile.profile.stash:
		amount += int(slot.quantity)
	_text("PERSISTENT STASH   ·   Salvage × %d" % amount, 26)
	if not app.profile.load_error.is_empty():
		_text(app.profile.load_error).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button("Deploy to yard", app.deploy, not app.profile.writable)
	_button("Save stash now", _save_stash, not app.profile.writable)
	_button("Settings", func(): show_settings(false))
	_button("Quit", func(): get_tree().quit())

func _save_stash() -> void:
	if app.profile.save_profile():
		show_notice("Stash saved")

func show_hud() -> void:
	_clear("hud")

func show_notice(value: String) -> void:
	message = value
	notice_until = Time.get_ticks_msec() + 5000

func open_container(_player_id: String, id: String) -> void:
	container_id = id
	_clear("container")
	var container: RaidEntity = app.raid.entities[id]
	_text("SALVAGE CRATE", 32)
	_text("%s × %d" % [container.loot.item.display_name, container.remaining])
	_button("Take one", _take, container.remaining == 0)
	_button("Close [Esc]", _close_container)

func _take() -> void:
	if app.raid.request_claim(app.raid.player.entity_id, container_id, 1):
		open_container(app.raid.player.entity_id, container_id)
	else:
		show_notice("Loot claim rejected. Move closer or check pack capacity.")

func _close_container() -> void:
	app.raid.participants[app.profile.profile.player_id].opened_container = ""
	show_hud()

func show_result() -> void:
	get_tree().paused = false
	_clear("result")
	_text("EXTRACTED" if app.raid.result.success else "RAID FAILED", 40)
	_text(app.raid.result.reason)
	_text("Salvage credited to stash." if app.raid.result.success and not app.pending_save else "")
	if app.pending_save:
		_text("Result not saved. Retry before leaving this screen.")
		_button("Retry save", func(): app.retry_save(); show_result())
		_button("Quit without saving", func(): get_tree().quit())
	else:
		_button("Return to stash", app.home)

func show_pause() -> void:
	get_tree().paused = true
	_clear("pause")
	_text("PAUSED", 36)
	_button("Resume [Esc]", _resume)
	_button("Settings", func(): show_settings(true))
	_button("Abandon raid · lose salvage", _abandon)

func _resume() -> void:
	get_tree().paused = false
	show_hud()

func _abandon() -> void:
	get_tree().paused = false
	app.raid.request_abandon(app.profile.profile.player_id)

func show_settings(from_raid: bool) -> void:
	_clear("settings")
	_text("SETTINGS", 36)
	_text("Mouse sensitivity")
	var sensitivity := HSlider.new()
	sensitivity.min_value = 0.0005
	sensitivity.max_value = 0.01
	sensitivity.step = 0.0001
	sensitivity.value = app.settings.sensitivity
	panel.add_child(sensitivity)
	_text("Master volume")
	var volume := HSlider.new()
	volume.min_value = 0
	volume.max_value = 1
	volume.step = 0.05
	volume.value = app.settings.volume
	panel.add_child(volume)
	var fullscreen := CheckButton.new()
	fullscreen.text = "Fullscreen"
	fullscreen.button_pressed = app.settings.fullscreen
	panel.add_child(fullscreen)
	_button("Apply and save", func():
		app.settings.sensitivity = sensitivity.value
		app.settings.volume = volume.value
		app.settings.fullscreen = fullscreen.button_pressed
		app.settings.apply()
		show_notice("Settings saved" if app.settings.save_settings() == OK else "Could not save settings")
	)
	_button("Back", show_pause if from_raid else show_home)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and app.raid != null and app.raid.is_active():
		if mode == "hud":
			show_pause()
		elif mode == "pause":
			_resume()
		elif mode == "container":
			_close_container()
		elif mode == "settings":
			show_pause()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	notice_label.text = message if Time.get_ticks_msec() < notice_until else ""
	if mode != "hud" or app.raid == null or not app.raid.is_active():
		return
	var raid: RaidAuthority = app.raid
	var state: RaidParticipant = raid.participants[app.profile.profile.player_id]
	var weapon: WeaponState = state.weapon
	var objective := "Collect salvage · orange crate" if not raid.objective_complete(app.profile.profile.player_id) else "Reach green extraction zone"
	var prompt := "[E] Open salvage crate" if not raid.player.interaction_id().is_empty() else ""
	if state.extracting:
		prompt = "EXTRACTING · %.1f s · stay in zone" % state.extraction_left
	hud.text = "LAST HAUL  /  FIELD TEST\nHP %d   |   RIFLE %d / %d%s\n%s\n%s\nWASD move · Shift sprint · Space jump · LMB fire · R reload · Esc pause" % [ceili(state.health), weapon.magazine, weapon.reserve, "  RELOADING" if weapon.reload_left > 0 else "", objective, prompt]
