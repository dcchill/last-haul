class_name WeaponState
extends RefCounted

const LOADOUTS := {"standard": [], "control": ["vertical_grip", "suppressor"], "mobile": ["reflex_sight"]}
var definition: WeaponDef
var inventory: RaidInventory
var supplies: Array[RaidInventory] = []
var donor_grid: RaidInventory
var donor_revision := 0
var fired_ammo := ""
var weapon_cell := Vector2i(-1, -1)
var instance_id := ""
var fallback: Dictionary = {}
var cooldown := 0.0
var reload_left := 0.0
var clock := 0
var next_shot := 0
var reload_end := 0
var reload_magazine := ""
var reload_magazine_cell := Vector2i(-1, -1)
var reload_action := "reload"
var trigger := false
var aiming := false
var customizing := false
var action_serial := 0
var last_action := "equip"
var tick_remainder := 0.0
var muzzle_velocity: float
var vertical_recoil: float
var horizontal_recoil := 0.0
var ads_time := 0.2
var sway := 0.0
var hipfire_spread: float
var damage_multiplier := 1.0
var attachments: Array[AttachmentDef] = []
var data: Dictionary:
	get:
		if inventory != null:
			var index := inventory.find_instance(instance_id)
			if index >= 0:
				return inventory.slots[index].state
		return fallback
var magazine: int:
	get:
		var state: Dictionary = data.get("magazine", {}).get("state", data if definition.magazine_id.is_empty() else {})
		return int(state.get("rounds", 0)) + (0 if data.get("chamber", "").is_empty() else 1)
	set(value):
		var state: Dictionary = data.get("magazine", {}).get("state", data if definition.magazine_id.is_empty() else {})
		var count := maxi(0, value - (0 if data.get("chamber", "").is_empty() else 1))
		state.rounds = count
		state.ammo = []
		for i in range(count): state.ammo.append(definition.ammo.id)
var reserve: int:
	get:
		var total := 0
		for grid in supply_grids():
			for entry in grid.slots:
				if Ammunition.caliber(entry.id, grid.items) == definition.ammo.caliber: total += int(entry.quantity)
		return total

func _init(gun: WeaponDef, _loadout: String = "standard", _definitions: Dictionary = {}) -> void:
	definition = gun
	fallback = {"instance_id": ProfileStore._new_id(), "rounds": 0, "magazine": {}, "attachments": {}, "chamber": ""}
	muzzle_velocity = gun.muzzle_velocity
	vertical_recoil = deg_to_rad(gun.recoil_degrees)
	hipfire_spread = gun.spread

func bind(pack: RaidInventory, entry: Dictionary) -> void:
	inventory = pack
	instance_id = entry.state.instance_id
	weapon_cell = Vector2i(int(entry.x), int(entry.y))

func supply_grids() -> Array[RaidInventory]:
	if not supplies.is_empty(): return supplies
	var result: Array[RaidInventory] = []
	if inventory != null: result.append(inventory)
	return result

func event(action: String) -> void:
	last_action = action
	action_serial += 1

func tick(delta: float) -> void:
	tick_remainder += delta
	while tick_remainder + 0.0000001 >= 0.05:
		tick_remainder -= 0.05
		advance_tick()

func advance_tick() -> void:
	clock += 1
	cooldown = maxf(0.0, (next_shot - clock) / 20.0)
	if reload_end > 0:
		var donor := donor_grid.find_instance(reload_magazine) if donor_grid != null else -1
		var gun := inventory.find_instance(instance_id) if inventory != null else -1
		if gun < 0 or Vector2i(int(inventory.slots[gun].x), int(inventory.slots[gun].y)) != weapon_cell:
			cancel_reload()
		elif not reload_magazine.is_empty() and (donor < 0 or donor_grid not in supply_grids() or not donor_grid.is_accessible() or donor_grid.revision != donor_revision):
			cancel_reload()
		elif clock >= reload_end:
			_complete_reload()
		else:
			reload_left = (reload_end - clock) / 20.0

func feed_state() -> Dictionary:
	return data.magazine.state if not data.get("magazine", {}).is_empty() else data if definition.magazine_id.is_empty() else {}

func fire() -> bool:
	if clock < next_shot or reload_end > 0 or customizing or magazine <= 0:
		return false
	if inventory != null and inventory.find_instance(instance_id) < 0:
		return false
	var state := feed_state()
	var rounds := Ammunition.sequence(state, definition.ammo.id)
	if data.get("chamber", "").is_empty() and not rounds.is_empty():
		data.chamber = rounds.pop_front()
	fired_ammo = data.get("chamber", "")
	if fired_ammo.is_empty(): return false
	data.chamber = "" if rounds.is_empty() else rounds.pop_front()
	state.rounds = rounds.size()
	next_shot = clock + definition.interval_ticks
	cooldown = definition.fire_interval
	event("fire")
	if inventory != null: inventory._notify()
	return true

func cycling_bolt() -> bool:
	return definition.id == "bolt_action_sniper" and clock < next_shot

func reload(chosen_instance: String = "auto") -> bool:
	if inventory == null or reload_end > 0 or cycling_bolt(): return false
	reload_magazine = ""
	donor_grid = null
	reload_action = "reload"
	if not definition.magazine_id.is_empty():
		var best_rounds := 0
		for grid in supply_grids():
			if not grid.is_accessible(): continue
			for entry in grid.slots:
				if entry.id != definition.magazine_id or (chosen_instance != "auto" and entry.state.instance_id != chosen_instance): continue
				if int(entry.state.rounds) > best_rounds:
					best_rounds = int(entry.state.rounds)
					reload_magazine = entry.state.instance_id
					donor_grid = grid
					donor_revision = grid.revision
					reload_magazine_cell = Vector2i(int(entry.x), int(entry.y))
		if donor_grid == null:
			if chosen_instance != "eject" or data.magazine.is_empty(): return false
			reload_action = "unload"
			if not exchange(true): return false
		else:
			reload_action = "reload_insert" if data.magazine.is_empty() else "reload_empty" if magazine == 0 else "reload"
	else:
		if magazine >= definition.magazine_size or reserve == 0: return false
	trigger = false
	aiming = false
	reload_end = clock + definition.reload_ticks
	reload_left = definition.reload_seconds
	event(reload_action)
	return true

func exchange(preview := false) -> bool:
	var gun_index := inventory.find_instance(instance_id)
	if gun_index < 0: return false
	for grid in ([donor_grid] if donor_grid != null else supply_grids()):
		var plans := {inventory: inventory.slots.duplicate(true)}
		if grid != inventory: plans[grid] = grid.slots.duplicate(true)
		var gun: Dictionary = plans[inventory][gun_index]
		var outgoing: Dictionary = gun.state.magazine
		var entries: Array[Dictionary] = plans[grid]
		if reload_action == "unload":
			var position := InventoryManager._space(grid, entries, outgoing.id, false)
			var rotation := false
			if position.x < 0:
				rotation = true
				position = InventoryManager._space(grid, entries, outgoing.id, true)
			if position.x < 0: continue
			outgoing.x = position.x
			outgoing.y = position.y
			outgoing.rotated = rotation
			entries.append(outgoing)
			gun.state.magazine = {}
		else:
			var index: int = grid.find_instance(reload_magazine)
			if index < 0: return false
			var incoming: Dictionary = entries[index]
			entries.remove_at(index)
			if not outgoing.is_empty():
				outgoing.x = incoming.x
				outgoing.y = incoming.y
				outgoing.rotated = incoming.rotated
				entries.append(outgoing)
			gun.state.magazine = incoming
		if InventoryManager._commit(plans, preview): return true
	return false

func _complete_reload() -> void:
	if definition.magazine_id.is_empty():
		var plans := {inventory: inventory.slots.duplicate(true)}
		var gun_index := inventory.find_instance(instance_id)
		if gun_index >= 0:
			var state: Dictionary = plans[inventory][gun_index].state
			var rounds := Ammunition.sequence(state, definition.ammo.id)
			var remaining := definition.magazine_size - magazine
			for grid in supply_grids():
				if not plans.has(grid): plans[grid] = grid.slots.duplicate(true)
				var entries: Array[Dictionary] = plans[grid]
				for i in range(entries.size() - 1, -1, -1):
					if Ammunition.caliber(entries[i].id, grid.items) != definition.ammo.caliber: continue
					var amount := mini(remaining, int(entries[i].quantity))
					for n in range(amount): rounds.append(entries[i].id)
					entries[i].quantity -= amount
					remaining -= amount
					if entries[i].quantity == 0: entries.remove_at(i)
				state.rounds = rounds.size()
			InventoryManager._commit(plans)
	else:
		exchange()
	cancel_reload()

func cancel_reload() -> void:
	reload_end = 0
	reload_left = 0.0
	reload_magazine = ""
	donor_grid = null
	aiming = false
	trigger = false
	event("reset")

func magnification(definitions: Dictionary) -> int:
	var optic: Dictionary = data.get("attachments", {}).get("optic", {})
	return definitions[optic.id].magnification if not optic.is_empty() else 1

func suppressed() -> bool:
	return data.get("attachments", {}).has("muzzle")

func recoil_strength() -> float:
	return definition.recoil_degrees * (0.7 if data.get("attachments", {}).has("grip") else 1.0)

func set_loadout(_name: String, _definitions: Dictionary) -> bool:
	return false

func set_attachments(_ids: Array, _definitions: Dictionary) -> bool:
	return false
