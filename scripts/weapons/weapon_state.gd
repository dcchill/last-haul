class_name WeaponState
extends RefCounted

const LOADOUTS := {"standard": [], "control": ["vertical_grip", "suppressor"], "mobile": ["reflex_sight"]}
var definition: WeaponDef
var inventory: RaidInventory
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
		return int(data.magazine.state.rounds) if not data.get("magazine", {}).is_empty() else int(data.get("rounds", 0)) if definition.magazine_id.is_empty() else 0
	set(value):
		if not data.get("magazine", {}).is_empty():
			data.magazine.state.rounds = clampi(value, 0, definition.magazine_size)
		else:
			data.rounds = clampi(value, 0, definition.magazine_size) if definition.magazine_id.is_empty() else 0
var reserve: int:
	get:
		return inventory.count(definition.ammo.id) if inventory != null else 0

func _init(gun: WeaponDef, _loadout: String = "standard", _definitions: Dictionary = {}) -> void:
	definition = gun
	fallback = {"instance_id": ProfileStore._new_id(), "rounds": 0, "magazine": {}, "attachments": {}}
	muzzle_velocity = gun.muzzle_velocity
	vertical_recoil = deg_to_rad(gun.recoil_degrees)
	hipfire_spread = gun.spread

func bind(pack: RaidInventory, entry: Dictionary) -> void:
	inventory = pack
	instance_id = entry.state.instance_id

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
		var donor := inventory.find_instance(reload_magazine) if inventory != null else -1
		if not reload_magazine.is_empty() and (donor < 0 or Vector2i(int(inventory.slots[donor].x), int(inventory.slots[donor].y)) != reload_magazine_cell):
			cancel_reload()
		elif clock >= reload_end:
			_complete_reload()
		else:
			reload_left = (reload_end - clock) / 20.0

func fire() -> bool:
	if clock < next_shot or reload_end > 0 or customizing or magazine <= 0:
		return false
	magazine -= 1
	next_shot = clock + definition.interval_ticks
	cooldown = definition.fire_interval
	event("fire")
	return true

func cycling_bolt() -> bool:
	return definition.id == "bolt_action_sniper" and clock < next_shot

func reload(chosen_instance: String = "auto") -> bool:
	if inventory == null or reload_end > 0 or cycling_bolt():
		return false
	reload_magazine = ""
	reload_action = "reload"
	if not definition.magazine_id.is_empty():
		var best := -1
		var rounds := 0
		for index in range(inventory.slots.size()):
			var entry: Dictionary = inventory.slots[index]
			if entry.id != definition.magazine_id:
				continue
			if chosen_instance != "auto" and entry.state.instance_id != chosen_instance:
				continue
			if int(entry.state.rounds) > rounds:
				best = index
				rounds = int(entry.state.rounds)
		if best < 0 and chosen_instance not in ["auto", "eject"]:
			return false
		if best < 0 or chosen_instance == "eject":
			if data.magazine.is_empty():
				return false
			var trial := RaidInventory.new(inventory.items, inventory.width, inventory.height)
			trial.slots = inventory.snapshot()
			if not trial.add_entry(data.magazine):
				return false
			reload_action = "unload"
		else:
			reload_magazine = inventory.slots[best].state.instance_id
			reload_magazine_cell = Vector2i(int(inventory.slots[best].x), int(inventory.slots[best].y))
			reload_action = "reload_insert" if data.magazine.is_empty() else "reload_empty" if magazine == 0 else "reload"
	else:
		if magazine >= definition.magazine_size or inventory.count(definition.ammo.id) == 0:
			return false
	trigger = false
	aiming = false
	reload_end = clock + definition.reload_ticks
	reload_left = definition.reload_seconds
	event(reload_action)
	return true

func _complete_reload() -> void:
	if definition.magazine_id.is_empty():
		var amount := mini(definition.magazine_size - magazine, inventory.count(definition.ammo.id))
		if amount > 0 and inventory.remove(definition.ammo.id, amount):
			magazine += amount
	elif reload_action == "unload":
		if inventory.add_entry(data.magazine):
			data.magazine = {}
	else:
		var index := inventory.find_instance(reload_magazine)
		if index >= 0:
			var incoming: Dictionary = inventory.slots[index].duplicate(true)
			var outgoing: Dictionary = data.magazine.duplicate(true)
			data.magazine = {"id": incoming.id, "quantity": 1, "state": incoming.state.duplicate(true)}
			if outgoing.is_empty():
				inventory.slots.remove_at(index)
			else:
				incoming.id = outgoing.id
				incoming.state = outgoing.state
				inventory.slots[index] = incoming
	cancel_reload()
	inventory.changed.emit()

func cancel_reload() -> void:
	reload_end = 0
	reload_left = 0.0
	reload_magazine = ""
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
