class_name Catalog
extends RefCounted

const PATHS: Array[String] = [
	"res://resources/items/battery_cell.tres", "res://resources/materials/medical_partition.tres",
	"res://resources/items/field_knife.tres", "res://resources/items/face_cover.tres", "res://resources/items/field_glasses.tres",
	"res://resources/items/small_pack.tres",
"res://resources/items/large_pack.tres",
"res://resources/items/field_rig.tres",
"res://resources/items/pockets.tres",
"res://resources/items/tool_case.tres",
"res://resources/items/medkit.tres",
"res://resources/items/food.tres",
"res://resources/items/tool.tres",
"res://resources/items/pistol.tres",
"res://resources/items/magazine.tres",
	"res://resources/items/salvage.tres", "res://resources/ammo/rifle_round.tres",
	"res://resources/weapons/rifle.tres", "res://resources/materials/steel.tres",
	"res://resources/weapons/attachments/reflex_sight.tres",
	"res://resources/weapons/attachments/balanced_compensator.tres",
	"res://resources/weapons/attachments/precision_stock.tres",
	"res://resources/weapons/attachments/heavy_barrel.tres",
	"res://resources/materials/concrete.tres", "res://resources/armor/patrol.tres", "res://resources/armor/vest.tres",
	"res://resources/armor/sentinel.tres", "res://resources/armor/bastion.tres", "res://resources/armor/juggernaut.tres",
	"res://resources/loot/crate.tres", "res://resources/npcs/guard.tres", "res://resources/npcs/zombie.tres"]
var definitions: Dictionary = {}
var items: Dictionary = {}

func load_all() -> String:
	definitions.clear()
	items.clear()
	for path in PATHS:
		var definition = load(path)
		if definition == null or definition.id.is_empty() or definitions.has(definition.id):
			return "Missing or duplicate definition: " + path
		definitions[definition.id] = definition
		if definition is ItemDef:
			items[definition.id] = definition
		elif definition is AmmoDef:
			items[definition.id] = _inventory_item(definition, 60, 1, 1, "ammo")
		elif definition is WeaponDef:
			items[definition.id] = _inventory_item(definition, 1, 2, 5, "weapon")
		elif definition is ArmorDef:
			items[definition.id] = _inventory_item(definition, 1, 2, 3, "armor")
		elif definition is AttachmentDef:
			items[definition.id] = _inventory_item(definition, 1, 1, 1, "attachment")
	for item: ItemDef in items.values():
		if item.kind == "weapon" and item.equipment_slots.is_empty():
			item.equipment_slots = PackedStringArray(["primary", "secondary"])
		if item.kind == "armor":
			item.equipment_slots = PackedStringArray(["body_armor"])
		if item.weight == 0:
			item.weight = 3.0 if item.kind == "weapon" else 2.0 if item.kind == "armor" else 0.01 if item.kind == "ammo" else 0.25
	for definition in definitions.values():
		if definition is ItemDef and (not is_finite(definition.battery_amount) or definition.battery_amount < 0):
			return "Invalid battery restoration amount"
		if definition is ItemDef and definition.stack_limit < 1:
			return "Item stack limit must be positive"
		if definition is AmmoDef and (not is_finite(definition.damage) or definition.damage < 0):
			return "Ammunition damage must be finite and nonnegative"
		if definition is AmmoDef:
			for value in [definition.mass_kg, definition.penetration]:
				if not is_finite(value) or value <= 0:
					return "Ammunition mass and penetration must be positive and finite"
			for value in [definition.drag, definition.gravity, definition.armor_damage, definition.bypass, definition.stopped_damage]:
				if not is_finite(value) or value < 0:
					return "Invalid ammunition ballistic property"
			if definition.bypass > 1.0 or definition.stopped_damage > 1.0:
				return "Ammunition transfer fractions cannot exceed one"
		if definition is WeaponDef and (definition.ammo == null or not definitions.has(definition.ammo.id)):
			return "Weapon has missing ammunition"
		if definition is WeaponDef:
			if definition.magazine_size < 1 or definition.starter_reserve < 0:
				return "Invalid weapon ammunition capacity"
			for value in [definition.fire_interval, definition.reload_seconds, definition.range_meters, definition.muzzle_velocity, definition.ads_time]:
				if not is_finite(value) or value <= 0:
					return "Weapon timing and range must be positive and finite"
			for value in [definition.vertical_recoil, definition.horizontal_recoil, definition.sway, definition.hipfire_spread]:
				if not is_finite(value) or value < 0:
					return "Invalid weapon handling property"
		if definition is MaterialDef and (not is_finite(definition.damage_multiplier) or definition.damage_multiplier < 0):
			return "Invalid material damage multiplier"
		if definition is ArmorDef:
			for value in [definition.resistance, definition.ricochet, definition.plate_durability, definition.plate_weight, definition.carrier_weight, definition.durability_loss]:
				if not is_finite(value) or value < 0:
					return "Invalid armor plate property"
			if definition.resistance <= 0.0 or definition.plate_durability <= 0.0 or definition.durability_loss <= 0.0 or definition.ricochet > 1.0:
				return "Armor resistance, durability, wear, and ricochet must be valid"
		if definition is MaterialDef:
			if not is_finite(definition.footstep_pitch) or definition.footstep_pitch <= 0:
				return "Invalid footstep pitch"
			for value in [definition.resistance, definition.thickness_meters, definition.ricochet]:
				if not is_finite(value) or value < 0:
					return "Invalid material ballistic property"
			if definition.ricochet > 1.0:
				return "Material ricochet chance cannot exceed one"
		if definition is AttachmentDef:
			if definition.slot.is_empty() or definition.compatible_weapons.is_empty():
				return "Attachment requires a slot and compatible weapon: %s (%s, %s)" % [definition.id, definition.slot, str(definition.compatible_weapons)]
			for weapon_id in definition.compatible_weapons:
				if not definitions.has(weapon_id) or not definitions[weapon_id] is WeaponDef:
					return "Attachment references a missing weapon"
			for value in [definition.vertical_recoil, definition.horizontal_recoil, definition.ads_time, definition.sway, definition.hipfire, definition.muzzle_velocity, definition.damage]:
				if not is_finite(value) or value <= 0.0:
					return "Attachment modifiers must be positive and finite"
		if definition is LootDef and (definition.item == null or not items.has(definition.item.id)):
			return "Loot has missing item"
		if definition is LootDef and definition.quantity < 1:
			return "Loot quantity must be positive"
		if definition is NPCDef and definition.armor != null and not definitions.has(definition.armor.id):
			return "NPC has missing armor"
		if definition is NPCDef:
			for value in [definition.health, definition.speed, definition.sight_range, definition.hearing_range, definition.attack_range, definition.attack_interval]:
				if not is_finite(value) or value <= 0:
					return "NPC health, movement, perception and timing must be positive and finite"
			if not is_finite(definition.field_of_view) or definition.field_of_view <= 0 or definition.field_of_view > 360 or not is_finite(definition.damage) or definition.damage < 0:
				return "Invalid NPC FOV or damage"
	ArmoryContent.install(self)
	for definition in definitions.values():
		if definition is WeaponDef and definition.armory:
			if definition.hand_profile == null or not definition.hand_profile.valid() or definition.hand_profile.weapon_id != definition.id:
				return "Missing or invalid weapon hand profile: " + definition.id
	for item: ItemDef in items.values():
		if item.kind == "weapon":
			if item.definition is WeaponDef:
				item.equipment_slots = item.definition.equipment_slots.duplicate()
				item.width = item.definition.inventory_dimensions.x
				item.height = item.definition.inventory_dimensions.y
				item.weight = item.definition.inventory_weight
		elif item.kind == "armor" and definitions[item.id] is ArmorDef:
			item.equipment_slots = PackedStringArray([{ "helmet": "headgear", "chestplate": "body_armor" }.get(definitions[item.id].slot, definitions[item.id].slot)])
		if item.kind == "ammo" and item.definition is AmmoDef: item.weight = item.definition.mass_kg
		if item.weight <= 0:
			item.weight = 0.012 if item.kind == "ammo" else 3.0 if item.kind == "weapon" else 0.3
		if item.width < 1 or item.height < 1 or item.stack_limit < 1 or not is_finite(item.weight) or item.weight < 0:
			return "Invalid inventory definition: " + item.id
		if item.container != null and (item.stack_limit != 1 or item.container.dimensions.x < 1 or item.container.dimensions.y < 1):
			return "Invalid container: " + item.id
		if item.icon == null:
			var icon_kind := item.kind if item.kind in ["weapon", "ammo", "magazine", "armor", "backpack", "rig", "medical", "food", "melee", "attachment", "grenade"] else "item"
			item.icon = load("res://assets/inventory/" + icon_kind + ".svg")
	return ""

func _inventory_item(definition: Resource, stack_limit: int, width: int, height: int, kind: String) -> ItemDef:
	var item := ItemDef.new()
	item.id = definition.id
	item.display_name = definition.id.replace("_", " ").capitalize()
	if definition is AmmoDef or definition is WeaponDef or definition is AttachmentDef or definition is ArmorDef:
		item.display_name = definition.display_name
	item.stack_limit = stack_limit
	item.width = width
	item.height = height
	item.kind = kind
	item.definition = definition
	return item
