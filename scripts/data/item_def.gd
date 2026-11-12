class_name ItemDef
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export_range(1, 999) var stack_limit: int = 20
@export_range(1, 10) var width: int = 1
@export_range(1, 18) var height: int = 1
@export_enum("item", "ammo", "weapon", "armor", "attachment") var kind: String = "item"
var definition: Resource
