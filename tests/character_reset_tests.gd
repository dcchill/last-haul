extends SceneTree

var checks := 0
var failures := 0
var app: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func settle() -> void:
	for frame in range(3): await physics_frame

func reset_button() -> Button:
	for node in app.ui.panel.get_children():
		if node is Button and node.text == "Reset character": return node
	return null

func possessions() -> Dictionary:
	var quantities := {}
	for root_inventory in app.inventory_service().roots:
		for grid in root_inventory.all_grids():
			for entry in grid.slots:
				quantities[entry.id] = quantities.get(entry.id, 0) + entry.quantity
	return quantities

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	app.test_profile_path = "res://.godot/character-reset-" + ProfileStore._new_id() + ".json"
	app.settings = SettingsStore.new(app.test_profile_path + ".cfg")
	root.add_child(app)
	await settle()
	app.settings.sensitivity = 0.006
	app.settings.sensor_enabled = false
	app.settings.save_settings()
	var preferences := FileAccess.get_file_as_string(app.settings.path)
	var old_player: String = app.profile.profile.player_id
	app.stash_view.add("small_pack", 1)
	app.stash_view.slots.back().storage.add("battery_cell", 1)
	app.stash_view.add("tool", 2)
	app._save_stash_layout()
	var no_loot: Array[Dictionary] = []
	app.profile.commit_result({"raid_id": "previous", "success": false, "reason": "defeat"}, no_loot)
	app.profile.profile.pending_result = {"result": {"raid_id": "pending", "success": true, "reason": "pending loot"}, "items": []}
	app.profile.save_profile()
	app.pending_save = true
	var before: Dictionary = app.profile.profile.duplicate(true)
	app.ui.show_settings(false)
	check(reset_button() != null, "main menu settings expose reset")
	reset_button().pressed.emit()
	await settle()
	var dialog: ConfirmationDialog
	for node in app.ui.screen.get_children():
		if node is ConfirmationDialog: dialog = node
	check(dialog != null and dialog.visible and app.profile.profile == before, "opening reset asks for confirmation without changing profile")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/reset-confirmation.png")
	dialog.canceled.emit()
	await settle()
	check(app.profile.profile == before and app.pending_save, "cancel keeps possessions and pending rewards")
	var original_path: String = app.profile.path
	app.profile.path = original_path + "/missing/profile.json"
	check(not app.reset_character() and app.profile.profile == before and app.pending_save, "failed reset write leaves character and pending state intact")
	app.profile.path = original_path
	check(possessions().has("battery_cell") and possessions().get("tool") == 2, "failed reset keeps nested and staged inventories")
	reset_button().pressed.emit()
	await settle()
	for node in app.ui.screen.get_children():
		if node is ConfirmationDialog: dialog = node
	dialog.confirmed.emit()
	await settle()
	check(app.ui.mode == "home" and not app.pending_save, "confirmed reset returns home and clears pending save")
	check(app.profile.profile.player_id != old_player, "reset creates a fresh character identity")
	check(app.profile.profile.last_result.is_empty() and app.profile.profile.committed_raids.is_empty() and app.profile.profile.pending_result.is_empty(), "raid history and pending rewards cleared")
	check(possessions() == {"m_four": 1, "patrol": 1, "five_five_six": 60, "stanag_magazine": 2}, "only the original starter kit remains across stash and staged gear")
	check(not app.loadout.gear.slots.primary.slots.is_empty() and not app.loadout.gear.slots.body_armor.slots.is_empty(), "starter equipment is staged normally")
	for entry in app.loadout.pockets.slots:
		if entry.id == "stanag_magazine": check(entry.state.rounds == 30, "starter magazine has thirty rounds")
	check(FileAccess.get_file_as_string(app.settings.path) == preferences and app.settings.sensitivity == 0.006 and not app.settings.sensor_enabled, "reset preserves game settings")
	var disk := ProfileStore.new(app.catalog, original_path)
	check(disk.load_profile() and disk.profile == JSON.parse_string(JSON.stringify(app.profile.profile)), "reset persists across profile reload")
	check(app.profile.valid(app.profile._read(original_path + ".bak")) and app.profile._read(original_path + ".bak").player_id == app.profile.profile.player_id, "backup also belongs to fresh character")
	app.deploy(false)
	await settle()
	app.ui.show_pause()
	app.ui.show_settings(true)
	check(reset_button() == null, "raid pause settings do not expose reset")
	before = app.profile.profile.duplicate(true)
	check(not app.reset_character() and app.profile.profile == before, "controller blocks reset during raid")
	app.ui._confirm_reset_character()
	check(not app.ui.screen.get_children().any(func(node): return node is ConfirmationDialog), "raid settings cannot open reset confirmation")
	var participant: RaidParticipant = app.raid.participants[app.profile.profile.player_id]
	check(participant.health == 20 and participant.battery > 479, "reset character starts raid at full health and power")
	app.ui._resume()
	app.raid.request_abandon(app.profile.profile.player_id)
	app.home()
	await settle()
	app.deploy(true)
	await settle()
	app.ui.show_pause()
	app.ui.show_settings(true)
	check(reset_button() == null and not app.reset_character(), "practice pause settings also exclude reset")
	paused = false
	app.free()
	await settle()
	print("CHARACTER RESET: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
