class_name RaidParticipant
extends RefCounted

# Raid-only state, indexed by stable player ID; never aliases the persistent stash.
var actor: RaidPlayer
var inventory: RaidInventory
var weapon: WeaponState
var armor: ArmorPlates
var equipment: Array[Dictionary] = []
var ammo_id: String = ""
var ammo_position: Vector2i = Vector2i.ZERO
var found_salvage: int = 0
var health: float = 100.0
var extraction_left: float = 3.0
var extracting: bool = false
var opened_container: String = ""

func _init(player: RaidPlayer, catalog: Catalog, pack: RaidInventory, weapon_id: String, armor_id: String, attachment_ids: Array) -> void:
	actor = player
	inventory = pack
	var weapon_def: WeaponDef = catalog.definitions[weapon_id]
	weapon = WeaponState.new(weapon_def)
	weapon.set_attachments(attachment_ids, catalog.definitions)
	var armor_def: ArmorDef = catalog.definitions[armor_id]
	armor = ArmorPlates.new(armor_def)
	ammo_id = weapon_def.ammo.id
	var rounds := inventory.count(ammo_id)
	for slot in inventory.slots:
		if slot.id == ammo_id:
			ammo_position = Vector2i(int(slot.x), int(slot.y))
			break
	inventory.remove(ammo_id, rounds)
	weapon.magazine = mini(rounds, weapon_def.magazine_size)
	weapon.reserve = maxi(0, rounds - weapon.magazine)
	equipment = [{"id": weapon_id, "quantity": 1}, {"id": armor_id, "quantity": 1}]
	for id in attachment_ids:
		equipment.append({"id": id, "quantity": 1})
	actor.armor_plates = armor

func recovered_items() -> Array[Dictionary]:
	var recovered := inventory.snapshot()
	var rounds := weapon.magazine + weapon.reserve
	if rounds > 0:
		recovered.append({"id": ammo_id, "quantity": rounds, "x": ammo_position.x, "y": ammo_position.y, "rotated": false})
	return recovered
