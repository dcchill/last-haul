extends Node

var catalog := Catalog.new()
var profile: ProfileStore
var settings := SettingsStore.new()
var raid: RaidAuthority
var pending_save: bool = false
var ui: PrototypeUI
var loadout: Dictionary = {}
var stash_view: RaidInventory

func _ready() -> void:
	_install_input()
	var error := catalog.load_all()
	if profile == null:
		profile = ProfileStore.new(catalog)
	settings.load_settings()
	settings.apply()
	ui = PrototypeUI.new()
	add_child(ui)
	ui.app = self
	profile.problem.connect(ui.show_notice)
	profile.load_profile(settings.starter_loadout)
	if not error.is_empty():
		profile.writable = false
		profile.load_error = error
	prepare_loadout()
	ui.show_home()

func prepare_loadout() -> void:
	var pack := RaidInventory.new(catalog.items, 10, 6)
	var ammo := mini(60, _stash_count("rifle_round"))
	if ammo > 0:
		pack.add("rifle_round", ammo)
	var attachments: Array[String] = []
	for id in WeaponState.LOADOUTS.get(settings.starter_loadout, []):
		if _stash_count(id) > 0:
			attachments.append(id)
	loadout = {"pack": pack, "weapon": "rifle" if _stash_count("rifle") > 0 else "", "armor": "patrol" if _stash_count("patrol") > 0 else "", "attachments": attachments}
	_refresh_stash_view()

func _stash_count(id: String) -> int:
	var total := 0
	for slot in profile.profile.stash:
		if slot.id == id:
			total += int(slot.quantity)
	return total

func _loadout_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = loadout.pack.snapshot()
	for id in [loadout.weapon, loadout.armor]:
		if not id.is_empty():
			entries.append({"id": id, "quantity": 1})
	for id in loadout.attachments:
		entries.append({"id": id, "quantity": 1})
	return entries

func _refresh_stash_view() -> void:
	stash_view = RaidInventory.new(catalog.items, 10, 18)
	for slot in profile.profile.stash:
		stash_view.slots.append(slot.duplicate(true))
	for entry in _loadout_entries():
		stash_view.remove(entry.id, int(entry.quantity))
	stash_view.changed.connect(_save_stash_layout)

func _save_stash_layout() -> void:
	var combined := RaidInventory.new(catalog.items, 10, 18)
	for slot in stash_view.snapshot():
		if not combined.add_at(slot.id, int(slot.quantity), int(slot.x), int(slot.y), bool(slot.get("rotated", false))):
			ui.show_notice("Stash layout cannot fit the current items")
			return
	for entry in _loadout_entries():
		if not combined.add(entry.id, int(entry.quantity)):
			ui.show_notice("Stash layout cannot fit the staged items")
			return
	if not profile.save_stash_layout(combined.snapshot()):
		ui.show_notice("Could not save stash layout")

func set_starter_loadout(name: String) -> void:
	if not WeaponState.LOADOUTS.has(name):
		return
	settings.starter_loadout = name
	settings.save_settings()
	loadout.attachments.clear()
	for id in WeaponState.LOADOUTS[name]:
		if _stash_count(id) > 0:
			loadout.attachments.append(id)
	_refresh_stash_view()

func available_for_loadout(id: String, omit_slot: String = "") -> int:
	var available: int = _stash_count(id) - loadout.pack.count(id)
	if omit_slot != "weapon" and loadout.weapon == id:
		available -= 1
	if omit_slot != "armor" and loadout.armor == id:
		available -= 1
	if omit_slot != "attachments":
		available -= loadout.attachments.count(id)
	return available

func equip(slot: String, id: String) -> bool:
	if slot not in ["weapon", "armor"] or not catalog.items.has(id):
		return false
	var kind: String = catalog.items[id].kind
	if kind != slot or available_for_loadout(id, slot) <= 0:
		return false
	loadout[slot] = id
	_refresh_stash_view()
	return true

func toggle_attachment(id: String, enabled: bool) -> bool:
	var definition = catalog.definitions.get(id)
	if not definition is AttachmentDef:
		return false
	if enabled:
		if loadout.attachments.has(id) or available_for_loadout(id, "attachments") <= 0 or loadout.weapon.is_empty():
			return false
		if not definition.supports(catalog.definitions[loadout.weapon]):
			return false
		for selected in loadout.attachments:
			if catalog.definitions[selected].slot == definition.slot:
				return false
		loadout.attachments.append(id)
	else:
		loadout.attachments.erase(id)
	_refresh_stash_view()
	return true

func loadout_ready() -> bool:
	return not loadout.weapon.is_empty() and not loadout.armor.is_empty() and loadout.pack.count("rifle_round") > 0

func deploy() -> void:
	if pending_save or not profile.writable or not loadout_ready():
		if not loadout_ready():
			ui.show_notice("Loadout needs a rifle, armor, and ammunition")
		return
	if raid != null:
		raid.queue_free()
		raid = null
	raid = preload("res://scenes/raid/test_yard.tscn").instantiate()
	add_child(raid)
	var raid_pack := RaidInventory.new(catalog.items, 10, 6)
	for slot in loadout.pack.snapshot():
		raid_pack.slots.append(slot.duplicate(true))
	var raid_loadout := loadout.duplicate()
	raid_loadout.pack = raid_pack
	var error := raid.deploy(profile.profile.player_id, catalog, settings, raid_loadout)
	if not error.is_empty():
		ui.show_notice(error)
		raid.queue_free()
		raid = null
		return
	if not profile.debit_loadout(_loadout_entries()):
		ui.show_notice("Could not save loadout debit; deployment cancelled")
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
	if pending_save:
		var participant: RaidParticipant = raid.participants[profile.profile.player_id]
		if profile.commit_result(raid.result, participant.recovered_items(), participant.equipment):
			pending_save = false

func home() -> void:
	if pending_save:
		return
	get_tree().paused = false
	if raid != null:
		raid.queue_free()
		raid = null
	prepare_loadout()
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
	var mouse_actions := {"fire": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT}
	for action in mouse_actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var mouse := InputEventMouseButton.new()
			mouse.button_index = mouse_actions[action]
			InputMap.action_add_event(action, mouse)
