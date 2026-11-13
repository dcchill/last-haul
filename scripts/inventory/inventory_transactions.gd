class_name InventoryTransactions
extends RefCounted

var roots: Array[RaidInventory] = []
var actor_id := ""
var authorize: Callable
var handle_operation: Callable
var results: Dictionary = {}

func grids() -> Dictionary:
	var result: Dictionary = {}
	for root in roots:
		for grid in root.all_grids():
			result[grid.uid] = grid
	return result

func submit(request: Dictionary, preview := false) -> Dictionary:
	if not request.get("request_id") is String or not request.get("actor_id") is String or not request.get("operation") is String or not request.get("source") is String or not request.get("target", "") is String or not request.get("item", "") is String or not request.get("revisions") is Dictionary:
		return {"ok": false, "reason": "Malformed inventory request"}
	for field in ["x", "y", "quantity"]:
		if not InventoryPersistence.whole(request.get(field, -1), -1):
			return {"ok": false, "reason": "Malformed inventory quantity or position"}
	if not request.get("rotated", false) is bool:
		return {"ok": false, "reason": "Malformed rotation"}
	var request_id: String = request.get("request_id", "")
	if request_id.is_empty() or request.get("actor_id") != actor_id:
		return {"ok": false, "reason": "Invalid actor or request ID"}
	if results.has(request_id) and not preview:
		return results[request_id].duplicate(true)
	var available := grids()
	var source: RaidInventory = available.get(request.get("source", ""))
	var target: RaidInventory = available.get(request.get("target", ""))
	var response := {"ok": false, "reason": "Inventory unavailable", "revisions": {}}
	if source == null or not source.is_accessible() or (authorize.is_valid() and not authorize.call(source)):
		return finish(request_id, response, preview)
	for grid: RaidInventory in [source, target]:
		if grid == null:
			continue
		if authorize.is_valid() and not authorize.call(grid):
			return finish(request_id, response, preview)
		if not request.get("revisions", {}).has(grid.uid) or request.revisions[grid.uid] != grid.revision:
			response.reason = "Inventory changed; try again"
			return finish(request_id, response, preview)
	var index := source.find_uid(str(request.get("item", "")))
	var operation: String = request.get("operation", "move")
	var ok := false
	if operation == "sort":
		ok = InventoryManager.sort_grid(source, preview)
	elif index >= 0 and source.visible_item(index):
		if operation in ["move", "rotate", "split", "merge", "equip", "transfer", "loot"] and target != null:
			ok = InventoryManager.move(source, index, target,
				Vector2i(int(request.get("x", -1)), int(request.get("y", -1))),
				bool(request.get("rotated", source.slots[index].rotated)), int(request.get("quantity", -1)), preview)
		elif operation == "consume":
			var amount := int(request.get("quantity", 1))
			if amount > 0 and amount <= int(source.slots[index].quantity) and not source.slots[index].has("storage"):
				var candidate := source.slots.duplicate(true)
				candidate[index].quantity -= amount
				if candidate[index].quantity == 0:
					candidate.remove_at(index)
				ok = InventoryManager._commit({source: candidate}, preview)
		elif handle_operation.is_valid():
			ok = handle_operation.call(request, source, index, preview)
	response.ok = ok
	response.reason = "" if ok else "Action rejected: incompatible item, restricted storage, or no space"
	for grid: RaidInventory in [source, target]:
		if grid != null:
			response.revisions[grid.uid] = grid.revision
	return finish(request_id, response, preview)

func finish(request_id: String, response: Dictionary, preview: bool) -> Dictionary:
	if not preview: results[request_id] = response.duplicate(true)
	return response

func request(operation: String, source: RaidInventory, target: RaidInventory = null, identity := "", at := Vector2i(-1, -1), rotated := false, quantity := -1) -> Dictionary:
	var revisions := {source.uid: source.revision}
	if target != null:
		revisions[target.uid] = target.revision
	return {"request_id": ProfileStore._new_id(), "actor_id": actor_id, "operation": operation,
		"source": source.uid, "target": target.uid if target != null else "", "item": identity,
		"x": at.x, "y": at.y, "rotated": rotated, "quantity": quantity, "revisions": revisions}
