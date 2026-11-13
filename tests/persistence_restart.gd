extends SceneTree

const PATH := "res://.godot/restart_probe_armory.json"
func _initialize() -> void:
	var catalog := Catalog.new()
	if not catalog.load_all().is_empty():
		quit(1)
		return
	var store := ProfileStore.new(catalog, PATH)
	var passed := false
	if "--write" in OS.get_cmdline_user_args():
		# Only this fixed, test-owned path is reset; real profiles are never opened.
		for suffix in ["", ".bak"]:
			if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)
		passed = store.load_profile()
		var state := ArmoryInstance.fresh("bolt_action_sniper", catalog.items)
		var mag := ArmoryInstance.fresh("barret_magazine", catalog.items)
		mag.rounds = 4
		state.magazine = {"id": "barret_magazine", "quantity": 1, "state": mag}
		state.attachments.optic = {"id": "sniper_scope", "quantity": 1, "state": ArmoryInstance.fresh("sniper_scope", catalog.items)}
		var loot: Array[Dictionary] = [{"id": "bolt_action_sniper", "quantity": 1, "state": state}]
		passed = passed and store.commit_result({"raid_id": "restart-probe", "success": true, "reason": "restart test"}, loot)
		print("RESTART WRITE: ", passed)
	else:
		passed = store.load_profile() and store.profile.committed_raids.has("restart-probe")
		var found := false
		for entry in store.profile.stash:
			if entry.id == "bolt_action_sniper":
				found = entry.state.magazine.state.rounds == 4 and entry.state.attachments.optic.id == "sniper_scope"
		passed = passed and found
		print("RESTART READ: ", passed)
	quit(0 if passed else 1)
