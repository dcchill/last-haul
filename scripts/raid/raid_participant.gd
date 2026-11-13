class_name RaidParticipant
extends RefCounted

var actor: RaidPlayer
var inventory: RaidInventory
var weapon: WeaponState
var armor := ArmorPlates.new()
var equipment: Array[Dictionary] = []
var health := 20.0
var extraction_left := 3.0
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

func _init(player: RaidPlayer, catalog: Catalog, pack: RaidInventory, weapon_id: String = "m_four", armor_id: String = "", _attachments: Array = []) -> void:
	actor = player
	inventory = pack
	quickbar.resize(9)
	quickbar.fill("")
	var next := 0
	for entry in inventory.slots:
		var definition: Resource = catalog.definitions.get(entry.id)
		if definition is WeaponDef and definition.armory and next < 9:
			quickbar[next] = entry.state.instance_id
			if entry.id == weapon_id:
				selected = next
			next += 1
		elif definition is ArmorDef and definition.id not in ArmoryContent.MIGRATIONS:
			if not armor_slots.has(definition.slot) or definition.id == armor_id:
				armor_slots[definition.slot] = entry.state.instance_id
	if next == 0:
		inventory.add(weapon_id, 1)
		quickbar[0] = inventory.slots.back().state.instance_id
	select(selected, catalog)
	refresh_armor(catalog)

func held_entry() -> Dictionary:
	var index := inventory.find_instance(quickbar[selected])
	return inventory.slots[index] if index >= 0 else {}

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
		weapon.bind(inventory, entry)
		weapon.clock = clock
		weapon.next_shot = next_shot
		weapon.event("equip")
	return true

func refresh_armor(catalog: Catalog) -> void:
	armor.entries.clear()
	armor.definitions = catalog.definitions
	for slot in armor_slots.keys():
		var index := inventory.find_instance(armor_slots[slot])
		if index < 0:
			armor_slots.erase(slot)
			continue
		var entry: Dictionary = inventory.slots[index]
		var definition: ArmorDef = catalog.definitions[entry.id]
		if definition.max_durability > 0 and int(entry.state.wear) >= definition.max_durability:
			inventory.slots.remove_at(index)
			armor_slots.erase(slot)
			continue
		armor.entries[slot] = entry
		armor.definition = definition
	actor.armor_plates = armor

func recovered_items() -> Array[Dictionary]:
	return inventory.snapshot()
