extends Node

var catalog := Catalog.new()
var profile: ProfileStore
var settings := SettingsStore.new()
var raid: RaidAuthority
var pending_save := false
var ui: PrototypeUI
var loadout: Dictionary = {}
var stash_view: RaidInventory
var test_profile_path := ""

func _ready() -> void:
	_install_input()
	var args := OS.get_cmdline_user_args()
	var test_path_index := args.find("--test-profile")
	if test_path_index >= 0 and test_path_index + 1 < args.size():
		test_profile_path = args[test_path_index + 1]
	var error := catalog.load_all()
	if profile == null:
		profile = ProfileStore.new(catalog, test_profile_path if not test_profile_path.is_empty() else "user://profile.json")
	settings.load_settings()
	settings.apply()
	ui = PrototypeUI.new()
	add_child(ui)
	ui.app = self
	profile.problem.connect(ui.show_notice)
	if error.is_empty():
		profile.load_profile()
	else:
		profile.writable = false
		profile.load_error = error
		push_error(error)
	prepare_loadout()
	ui.show_home()
	if "--practice" in args and error.is_empty():
		deploy.call_deferred(true)

func prepare_loadout() -> void:
	stash_view = RaidInventory.new(catalog.items, 10, 18)
	for entry in profile.profile.stash:
		var decoded := InventoryPersistence.decode_item(entry, catalog.items, {})
		if not decoded.is_empty():
			stash_view.slots.append(decoded)
	var pack := RaidInventory.new(catalog.items, 10, 6)
	loadout = {"pack": pack, "weapon": "m_four", "armor": ""}
	for id in ["m_four", "patrol", "stanag_magazine", "stanag_magazine", "five_five_six"]:
		for index in range(stash_view.slots.size()):
			if stash_view.slots[index].id == id:
				InventoryManager.move(stash_view, index, pack)
				break

func _loadout_entries() -> Array[Dictionary]:
	return loadout.pack.snapshot()

func _save_stash_layout() -> void:
	var combined := RaidInventory.new(catalog.items, 10, 18)
	for entry in stash_view.snapshot() + loadout.pack.snapshot():
		if not combined.add_entry(entry):
			ui.show_notice("Stash cannot fit staged items")
			return
	if not profile.save_stash_layout(combined.snapshot()):
		ui.show_notice("Could not save stash")

func loadout_ready() -> bool:
	for entry in loadout.pack.slots:
		if catalog.definitions.get(entry.id) is WeaponDef and catalog.definitions[entry.id].armory:
			return true
	return false

func deploy(practice_mode: bool = false) -> void:
	if pending_save or (not practice_mode and (not profile.writable or not loadout_ready())):
		ui.show_notice("Stage a firearm in the raid pack before deploying")
		return
	if raid != null:
		raid.queue_free()
		raid = null
	var pack := RaidInventory.new(catalog.items, 10, 18 if practice_mode else 6)
	if practice_mode:
		pack.add("m_four", 1)
		pack.add("patrol", 1)
		pack.add("five_five_six", 64)
		for rounds in [30, 30]:
			var mag := ArmoryInstance.fresh("stanag_magazine", catalog.items)
			mag.rounds = rounds
			pack.add("stanag_magazine", 1, mag)
		pack.add("impact_nade", 8)
		pack.add("smoke_nade", 8)
	else:
		for entry in loadout.pack.slots:
			pack.slots.append(entry.duplicate(true))
	var weapon := "m_four"
	for entry in pack.slots:
		if catalog.definitions.get(entry.id) is WeaponDef and catalog.definitions[entry.id].armory:
			weapon = entry.id
			break
	raid = preload("res://scenes/raid/test_yard.tscn").instantiate()
	add_child(raid)
	var error := raid.deploy(profile.profile.player_id, catalog, settings, {"pack": pack, "weapon": weapon, "practice": practice_mode})
	if not error.is_empty():
		ui.show_notice(error)
		raid.queue_free()
		raid = null
		return
	if not practice_mode and not profile.debit_loadout(_loadout_entries()):
		ui.show_notice("Could not save loadout debit; deployment cancelled")
		raid.queue_free()
		raid = null
		return
	raid.notice.connect(ui.show_notice)
	raid.container_opened.connect(ui.open_container)
	raid.finished.connect(_raid_finished)
	raid.player.refresh_view()
	raid.player.refresh_armor_visuals()
	ui.show_hud()

func _raid_finished(_result: Dictionary) -> void:
	pending_save = not raid.practice
	if pending_save:
		retry_save()
	ui.show_result()

func retry_save() -> void:
	if pending_save and raid != null and not raid.practice:
		var participant: RaidParticipant = raid.participants[profile.profile.player_id]
		if profile.commit_result(raid.result, participant.recovered_items()):
			pending_save = false

func home() -> void:
	if pending_save:
		return
	get_tree().paused = false
	var was_practice := raid != null and raid.practice
	if raid != null:
		raid.queue_free()
		raid = null
	if not was_practice:
		prepare_loadout()
	ui.show_home()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if pending_save:
			ui.show_notice("Result not saved. Retry or use Quit without saving.")
			ui.show_result()
		else:
			get_tree().quit()

func _install_input() -> void:
	get_tree().auto_accept_quit = false
	var keys := {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"reload": KEY_R, "interact": KEY_E, "jump": KEY_SPACE, "sprint": KEY_SHIFT, "crouch": KEY_CTRL}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = keys[action]
			InputMap.action_add_event(action, event)
	for action in {"fire": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT}:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT if action == "fire" else MOUSE_BUTTON_RIGHT
			InputMap.action_add_event(action, event)
