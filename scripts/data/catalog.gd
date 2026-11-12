class_name Catalog
extends RefCounted

const PATHS: Array[String] = [
	"res://resources/items/salvage.tres", "res://resources/ammo/rifle_round.tres",
	"res://resources/weapons/rifle.tres", "res://resources/materials/steel.tres",
	"res://resources/materials/concrete.tres", "res://resources/armor/vest.tres",
	"res://resources/loot/crate.tres", "res://resources/npcs/guard.tres"]
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
	for definition in definitions.values():
		if definition is ItemDef and definition.stack_limit < 1:
			return "Item stack limit must be positive"
		if definition is AmmoDef and (not is_finite(definition.damage) or definition.damage < 0):
			return "Ammunition damage must be finite and nonnegative"
		if definition is WeaponDef and (definition.ammo == null or not definitions.has(definition.ammo.id)):
			return "Weapon has missing ammunition"
		if definition is WeaponDef:
			if definition.magazine_size < 1 or definition.starter_reserve < 0:
				return "Invalid weapon ammunition capacity"
			for value in [definition.fire_interval, definition.reload_seconds, definition.range_meters]:
				if not is_finite(value) or value <= 0:
					return "Weapon timing and range must be positive and finite"
		if definition is MaterialDef and (not is_finite(definition.damage_multiplier) or definition.damage_multiplier < 0):
			return "Invalid material damage multiplier"
		if definition is ArmorDef and (not is_finite(definition.damage_reduction) or definition.damage_reduction < 0 or definition.damage_reduction > 1):
			return "Armor reduction must be between zero and one"
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
	return ""
