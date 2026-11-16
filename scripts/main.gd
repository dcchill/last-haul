extends Node

var catalog := Catalog.new()
var profile: ProfileStore
var settings := SettingsStore.new()
var selected_map: RaidMapDefinition = load("res://resources/maps/medtac_campus.tres")
# Explicit override for compact regression scenes; normal play follows map data.
var normal_raid_scene: PackedScene
var raid: RaidAuthority
var pending_save := false
var ui: PrototypeUI
var loadout: Dictionary = {}
var stash_view: RaidInventory
var staging_transactions: InventoryTransactions
var test_profile_path := ""
var requested_layout_seed := -1
var requested_raid_seed := -1

func _ready() -> void:
	_install_input()
	var args := OS.get_cmdline_user_args()
	for flag in ["--layout-seed","--raid-seed"]:
		var index:=args.find(flag)
		if index>=0 and index+1<args.size() and args[index+1].is_valid_int():
			if flag=="--layout-seed": requested_layout_seed=int(args[index+1])
			else: requested_raid_seed=int(args[index+1])
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
	pending_save = not profile.profile.pending_result.is_empty()
	if pending_save:
		retry_save()
	ui.show_home()
	if "--practice" in args and error.is_empty():
		deploy.call_deferred(true)

func prepare_loadout() -> void:
	stash_view = profile.stash_grid()
	if stash_view == null:
		stash_view = RaidInventory.new(catalog.items, 10, 18)
	var pack := RaidInventory.new(catalog.items)
	pack.configure(preload("res://resources/containers/base_pack.tres"))
	var pockets := RaidInventory.new(catalog.items, 4, 1)
	pockets.configure(preload("res://resources/containers/pockets.tres"))
	var gear := EquipmentComponent.new(catalog.items)
	var saved: Dictionary = profile.profile.get("staged", {})
	for name in saved:
		var grid := InventoryPersistence.decode(saved[name], catalog.items, {})
		if grid == null:
			continue
		if name == "pack": pack = grid
		elif name == "pockets": pockets = grid
		elif gear.slots.has(name):
			gear.slots[name] = grid
			grid.changed.connect(gear._changed)
	loadout = {"pack": pack, "pockets": pockets, "gear": gear, "weapon": "", "armor": ""}
	if saved.is_empty() and profile.profile.pending_result.is_empty():
		for id in ["m_four", "patrol", "stanag_magazine", "stanag_magazine", "five_five_six"]:
			for index in range(stash_view.slots.size()):
				if stash_view.slots[index].id != id:
					continue
				var destination := pack
				if id == "m_four": destination = gear.slots.primary
				elif id == "patrol": destination = gear.slots.body_armor
				elif id == "five_five_six" or id == "stanag_magazine": destination = pockets
				if not InventoryManager.move(stash_view, index, destination):
					InventoryManager.move(stash_view, index, pack)
				break
	staging_transactions = InventoryTransactions.new()
	staging_transactions.actor_id = profile.profile.player_id
	staging_transactions.roots = [stash_view, pack, pockets]
	staging_transactions.roots.append_array(gear.roots())
	if saved.is_empty() and profile.writable:
		profile.save_layout(stash_view, staged_roots())

func staged_roots() -> Dictionary:
	var roots := {"pack": loadout.pack, "pockets": loadout.pockets}
	roots.merge(loadout.gear.slots)
	return roots

func _save_stash_layout() -> void:
	if not profile.save_layout(stash_view, staged_roots()):
		ui.show_notice("Could not save stash")

func loadout_ready() -> bool:
	return profile.writable

func inventory_service() -> InventoryTransactions:
	if raid != null and raid.is_active():
		var service := raid.inventory_service(profile.profile.player_id)
		service.handle_operation = handle_inventory_operation
		return service
	staging_transactions.handle_operation = handle_inventory_operation
	return staging_transactions

func submit_inventory(request: Dictionary, preview := false) -> Dictionary:
	var service := inventory_service()
	var before: Dictionary = {}
	if raid == null and not preview:
		for grid: RaidInventory in service.grids().values():
			before[grid] = {"slots": grid.slots.duplicate(true), "revision": grid.revision}
	var result := service.submit(request, preview)
	if result.ok and not preview:
		if raid == null and not profile.save_layout(stash_view, staged_roots()):
			for grid: RaidInventory in before:
				grid.slots = before[grid].slots
				grid.revision = before[grid].revision
				for entry in grid.slots: grid._adopt(entry)
				grid.changed.emit()
			service.results.erase(request.request_id)
			return {"ok": false, "reason": "Save failed; action rolled back"}
		if raid != null:
			raid.refresh_inventory(profile.profile.player_id)
	return result

func deploy(practice_mode: bool = false) -> void:
	if raid != null:
		ui.show_notice("Finish the current raid before deploying")
		return
	if pending_save or (not practice_mode and (not profile.writable or not loadout_ready())):
		ui.show_notice("Resolve the pending save before deploying")
		return
	if raid != null:
		raid.queue_free()
		raid = null
	var pack := RaidInventory.new(catalog.items, 10, 18 if practice_mode else 6)
	if practice_mode:
		pack.add("m_four", 1)
		pack.add("patrol", 1)
		pack.add("field_rig", 1)
		pack.add("five_five_six", 64)
		for rounds in [30, 30]:
			var mag := ArmoryInstance.fresh("stanag_magazine", catalog.items)
			mag.rounds = rounds
			pack.add("stanag_magazine", 1, mag)
		pack.add("impact_nade", 8)
		pack.add("smoke_nade", 8)
	else:
		if not profile.save_layout(stash_view, staged_roots()):
			ui.show_notice("Could not save staged loadout")
			return
		pack = InventoryPersistence.decode(loadout.pack.serialize(), catalog.items, {})
	var weapon := "m_four"
	for entry in pack.slots:
		if catalog.definitions.get(entry.id) is WeaponDef and catalog.definitions[entry.id].armory:
			weapon = entry.id
			break
	var layout_path := selected_map.scene_path
	if not practice_mode and normal_raid_scene==null and not selected_map.approved_layouts.is_empty():
		if requested_layout_seed>=0:
			var matches:=selected_map.approved_layouts.filter(func(path): return path.get_file().get_basename().ends_with("_"+str(requested_layout_seed)))
			if matches.is_empty(): ui.show_notice("That layout seed is not an approved map"); return
			layout_path=matches[0]
		else: layout_path=selected_map.approved_layouts.pick_random()
	var destination: PackedScene = preload("res://scenes/raid/test_yard.tscn") if practice_mode else normal_raid_scene if normal_raid_scene != null else load(layout_path)
	raid = destination.instantiate()
	if not practice_mode and normal_raid_scene==null: raid.map_definition=selected_map
	if requested_raid_seed>=0: raid.raid_seed=requested_raid_seed
	get_viewport().use_occlusion_culling=not practice_mode and raid.map_definition!=null
	# Complete the static/variant navigation assembly before actors start moving.
	var navigation_map:=get_viewport().find_world_3d().navigation_map
	NavigationServer3D.map_set_use_async_iterations(navigation_map,false)
	NavigationServer3D.map_force_update(navigation_map)
	add_child(raid)
	var atmosphere:=raid.get_node_or_null("Atmosphere") as DistrictAtmosphere
	if atmosphere!=null:
		atmosphere.quality=WorldQualitySettings.make(settings.world_quality)
		atmosphere.apply()
	var raid_loadout := {"pack": pack, "weapon": weapon, "practice": practice_mode}
	if not practice_mode:
		raid_loadout.pockets = InventoryPersistence.decode(loadout.pockets.serialize(), catalog.items, {})
		raid_loadout.gear = EquipmentComponent.new(catalog.items)
		raid_loadout.gear.restore(loadout.gear.serialize(), catalog.items)
	var error := raid.deploy(profile.profile.player_id, catalog, settings, raid_loadout)
	if not error.is_empty():
		ui.show_notice(error)
		raid.queue_free()
		raid = null
		return
	if not practice_mode and not profile.debit_loadout():
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
	if pending_save and raid == null and not profile.profile.pending_result.is_empty():
		var pending: Dictionary = profile.profile.pending_result
		if profile.commit_result(pending.result, pending.items):
			pending_save = false
			prepare_loadout()
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

func reset_character() -> bool:
	if raid != null:
		ui.show_notice("Reset character is only available from main menu settings")
		return false
	if not profile.reset_character():
		ui.show_notice("Could not save character reset; character unchanged")
		return false
	pending_save = false
	prepare_loadout()
	ui.show_home()
	ui.show_notice("Character reset to the starter kit")
	return true

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
		"inventory_rotate": KEY_R, "inventory_quick_transfer": KEY_CTRL, "inventory_quick_equip": KEY_ALT, "inventory_split": KEY_SHIFT, "inventory_toggle": KEY_I, "reload": KEY_R, "interact": KEY_E, "jump": KEY_SPACE, "sprint": KEY_SHIFT, "crouch": KEY_CTRL}
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

func handle_inventory_operation(request: Dictionary, source: RaidInventory, index: int, preview: bool) -> bool:
	var identity: String = source.slots[index].uid
	match request.operation:
		"load", "unload":
			if raid != null and raid.participants[profile.profile.player_id].weapon != null and raid.participants[profile.profile.player_id].weapon.reload_magazine == identity: return false
			return Ammunition.load(source, index, str(request.get("ammo_id", "")), request.operation == "unload", preview)
		"use":
			return raid != null and (preview or raid.request_use(profile.profile.player_id, identity))
		"drop":
			return raid != null and (preview or raid.request_drop(profile.profile.player_id, identity))
		"discard":
			if raid != null: return false
			var candidate := source.slots.duplicate(true)
			candidate.remove_at(index)
			return InventoryManager._commit({source: candidate}, preview)
	return false

func open_recovery() -> void:
	if not pending_save or profile.profile.pending_result.is_empty(): return
	if raid != null:
		raid.queue_free()
		raid = null
	prepare_loadout()
	ui.show_inventory(false)
