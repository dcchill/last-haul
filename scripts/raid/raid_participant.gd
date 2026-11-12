class_name RaidParticipant
extends RefCounted

# Raid-only state, indexed by stable player ID; never aliases the persistent stash.
var actor: RaidPlayer
var inventory: RaidInventory
var weapon: WeaponState
var health: float = 100.0
var extraction_left: float = 3.0
var extracting: bool = false
var opened_container: String = ""

func _init(player: RaidPlayer, catalog: Catalog) -> void:
	actor = player
	inventory = RaidInventory.new(catalog.items, 8)
	weapon = WeaponState.new(catalog.definitions["rifle"])
