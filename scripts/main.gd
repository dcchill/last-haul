extends Node

var catalog := Catalog.new()
var profile: ProfileStore
var settings := SettingsStore.new()
var raid: RaidAuthority
var pending_save: bool = false
var ui: PrototypeUI

func _ready() -> void:
	_install_input()
	var error := catalog.load_all()
	profile = ProfileStore.new(catalog)
	settings.load_settings()
	settings.apply()
	ui = PrototypeUI.new()
	add_child(ui)
	ui.app = self
	profile.problem.connect(ui.show_notice)
	profile.load_profile()
	if not error.is_empty():
		profile.writable = false
		profile.load_error = error
	ui.show_home()

func deploy() -> void:
	if pending_save or not profile.writable:
		return
	if raid != null:
		raid.queue_free()
		raid = null
	raid = preload("res://scenes/raid/test_yard.tscn").instantiate()
	add_child(raid)
	var error := raid.deploy(profile.profile.player_id, catalog, settings)
	if not error.is_empty():
		ui.show_notice(error)
		raid.queue_free()
		raid = null
		return
	raid.notice.connect(ui.show_notice)
	raid.container_opened.connect(ui.open_container)
	raid.finished.connect(_raid_finished)
	ui.show_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _raid_finished(_result: Dictionary) -> void:
	pending_save = true
	retry_save()
	ui.show_result()

func retry_save() -> void:
	if pending_save and profile.commit_result(raid.result, raid.participants[profile.profile.player_id].inventory.snapshot()):
		pending_save = false

func home() -> void:
	if pending_save:
		return
	get_tree().paused = false
	if raid != null:
		raid.queue_free()
		raid = null
	ui.show_home()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if pending_save:
			ui.show_notice("Result is not saved. Retry saving before quitting, or use Quit without saving.")
			ui.show_result()
		else:
			get_tree().quit()

func _install_input() -> void:
	get_tree().auto_accept_quit = false
	var keys := {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"reload": KEY_R, "interact": KEY_E, "jump": KEY_SPACE, "sprint": KEY_SHIFT}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = keys[action]
			InputMap.action_add_event(action, event)
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", mouse)
