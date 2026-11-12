extends SceneTree

# Run twice in separate processes: -- --write, followed by -- --read.
func _initialize() -> void:
	var catalog := Catalog.new()
	if not catalog.load_all().is_empty():
		quit(1)
		return
	var store := ProfileStore.new(catalog, "res://.godot/restart_probe.json")
	if "--write" in OS.get_cmdline_user_args():
		var loot: Array[Dictionary] = [{"id": "salvage", "quantity": 2}]
		var saved := store.commit_result({"raid_id": "restart-probe", "success": true, "reason": "restart test"}, loot)
		print("RESTART WRITE: ", saved)
		quit(0 if saved else 1)
	else:
		var passed := store.load_profile() and store.profile.stash.size() == 1 and store.profile.stash[0].quantity == 2 and store.profile.committed_raids.has("restart-probe")
		print("RESTART READ: ", passed)
		quit(0 if passed else 1)
