class_name RaidParticipant
extends RefCounted

var actor: RaidPlayer
var inventory: RaidInventory
var weapon: WeaponState
var armor := ArmorPlates.new()
var equipment: EquipmentComponent
var pockets: RaidInventory
var transactions: InventoryTransactions
var stamina := 100.0
var health := 20.0
const EXTRACTION_SECONDS := 15.0
const BATTERY_CAPACITY := 480.0
var battery := BATTERY_CAPACITY
var battery_warning := 0
var extraction_left := EXTRACTION_SECONDS
var extracting := false
var opened_container := ""
var found_salvage := 0
var quickbar: Array[String] = []
var selected := 0
var armor_slots: Dictionary = {}
var weapons: Dictionary = {}
var clock := 0
var next_shot := 0
var grenade_cooldown := 0
var pending_throw: Dictionary = {}
var last_input := 0

func _init(player: RaidPlayer, catalog: Catalog, pack: RaidInventory, weapon_id: String = "m_four", armor_id: String = "", _attachments: Array = [], loadout: Dictionary = {}) -> void:
	actor = player
	inventory = pack
	equipment = loadout.get("gear", EquipmentComponent.new(catalog.items))
	pockets = loadout.get("pockets", RaidInventory.new(catalog.items, 4, 1))
	transactions = InventoryTransactions.new()
	transactions.actor_id = player.entity_id
	transactions.roots = [inventory, pockets]
	transactions.roots.append_array(equipment.roots())
	quickbar.resize(9)
	quickbar.fill("")
	# Legacy/practice callers supply a pack; move their equipment into real slots once.
	if not loadout.has("gear"):
		for index in range(inventory.slots.size() - 1, -1, -1):
			var entry := inventory.slots[index]
			var definition: ItemDef = catalog.items[entry.id]
			for slot in definition.equipment_slots:
				if equipment.slots.has(slot) and equipment.slots[slot].slots.is_empty():
					InventoryManager.move(inventory, index, equipment.slots[slot])
					break
	if loadout.get("practice", false):
		for index in range(inventory.slots.size() - 1, -1, -1):
			if catalog.items[inventory.slots[index].id].kind not in ["ammo", "magazine"]: continue
			for destination in reload_grids():
				if InventoryManager.move(inventory, index, destination): break
	var next := 0
	for root in equipment.roots():
		for entry in root.slots:
			if catalog.definitions.get(entry.id) is WeaponDef and next < 9:
				quickbar[next] = entry.uid
				if entry.id == weapon_id: selected = next
				next += 1
	select(selected, catalog)
	refresh_armor(catalog)

func owner_of(identity: String) -> RaidInventory:
	for root in transactions.roots:
		var owner := root.owner_of(identity)
		if owner != null:
			return owner
	return null

func entry_for(identity: String) -> Dictionary:
	var owner := owner_of(identity)
	if owner == null:
		return {}
	var index := owner.find_uid(identity)
	if index < 0: index = owner.find_instance(identity)
	return owner.slots[index] if index >= 0 else {}

func held_entry() -> Dictionary:
	var entry := entry_for(quickbar[selected])
	if not entry.is_empty() and inventory.items[entry.id].kind == "weapon":
		var owner := equipment.owner_of(quickbar[selected])
		if owner == null or owner.equipment_slot not in ["primary", "secondary", "holster", "melee"]:
			return {}
	return entry

func reload_grids() -> Array[RaidInventory]:
	var result: Array[RaidInventory] = [pockets]
	var rig: RaidInventory = equipment.slots.rig
	for entry in rig.slots:
		if entry.has("storage"): result.append(entry.storage)
	return result

func total_weight() -> float:
	return inventory.total_weight() + pockets.total_weight() + equipment.total_weight()

func select(index: int, catalog: Catalog) -> bool:
	if index < 0 or index >= 9:
		return false
	if weapon != null:
		next_shot = weapon.next_shot
		weapon.cancel_reload()
	selected = index
	var entry := held_entry()
	weapon = null
	if not entry.is_empty() and catalog.definitions.get(entry.id) is WeaponDef:
		if not weapons.has(entry.state.instance_id):
			weapons[entry.state.instance_id] = WeaponState.new(catalog.definitions[entry.id])
		weapon = weapons[entry.state.instance_id]
		weapon.bind(owner_of(entry.uid), entry)
		weapon.supplies = reload_grids()
		weapon.clock = clock
		weapon.next_shot = next_shot
		weapon.event("equip")
	return true

func refresh_armor(catalog: Catalog) -> void:
	armor.entries.clear()
	armor_slots.clear()
	armor.definitions = catalog.definitions
	for grid in equipment.roots():
		for entry in grid.slots:
			var definition: Resource = catalog.definitions.get(entry.id)
			if definition is ArmorDef:
				armor.entries[definition.slot] = entry
				armor_slots[definition.slot] = entry.uid
				armor.definition = definition
	actor.armor_plates = armor

func recovered_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for root in equipment.roots():
		result.append_array(root.snapshot())
	result.append_array(inventory.snapshot())
	result.append_array(pockets.snapshot())
	return result
