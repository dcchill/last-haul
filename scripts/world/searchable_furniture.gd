class_name SearchableFurniture
extends RaidEntity

@export var display_name := "Storage"
@export var opening := "hinge"
@export var loot_profile := "technical"
@export var container_config: ContainerDef
@export var locked := false
@export var key_item := ""
@export var starts_empty := false
@export var opened := false
@export var opening_direction := 1.0
@export var panel_rest := Transform3D.IDENTITY
signal audio_requested(cue: String)
var contents: RaidInventory
var panel_tween: Tween

func _ready() -> void:
	super._ready()
	var panel := get_node_or_null("MovingPanel") as Node3D
	if container_config == null and panel != null: panel_rest = panel.transform

func create_inventory(definitions: Dictionary, rng: RandomNumberGenerator) -> RaidInventory:
	var grid := RaidInventory.new(definitions, 10, 6)
	if container_config != null: grid.configure(container_config)
	grid.display_name = display_name
	if not starts_empty:
		for id: String in guaranteed_items:
			if not grid.add(id, int(guaranteed_items[id])): push_error("Guaranteed item does not fit: " + entity_id + " / " + id)
		if loot_table != null and not loot_table.generate(grid, rng): push_error("Invalid loot table: " + entity_id)
	else: grid.loot_generated = true
	bind_inventory(grid)
	return grid

func bind_inventory(grid: RaidInventory) -> void:
	if contents != null and contents.changed.is_connected(_inventory_changed): contents.changed.disconnect(_inventory_changed)
	contents = grid
	contents.changed.connect(_inventory_changed)
	_inventory_changed()

func _inventory_changed() -> void:
	var visual := get_node_or_null("LootContents") as Node3D
	if visual != null: visual.visible = contents != null and not contents.slots.is_empty()

func set_open(value: bool, animated := true) -> void:
	if locked and value: return
	if opened == value: return
	opened = value
	audio_requested.emit("open" if value else "close")
	var panel := get_node_or_null("MovingPanel") as Node3D
	if panel == null: return
	var target := panel_rest
	if value:
		if opening == "drawer": target.origin.z += .4 * opening_direction
		elif opening == "lid": target.basis = Basis(Vector3.RIGHT, -1.35 * opening_direction) * target.basis
		else: target.basis = Basis(Vector3.UP, -1.4 * opening_direction) * target.basis
	if panel_tween != null: panel_tween.kill()
	if animated and is_inside_tree():
		panel_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		panel_tween.tween_property(panel, "transform", target, .3)
	else: panel.transform = target

func storage_snapshot() -> Dictionary:
	return {"entity_id": entity_id, "locked": locked, "opened": opened, "inventory": contents.serialize() if contents != null else {}}

func restore_storage(data: Dictionary, definitions: Dictionary) -> bool:
	if data.get("entity_id") != entity_id or not data.get("locked") is bool or not data.get("opened") is bool: return false
	var restored := InventoryPersistence.decode(data.get("inventory"), definitions)
	if restored == null or (container_config != null and restored.config != container_config): return false
	if container_config != null and Vector2i(restored.width, restored.height) != container_config.dimensions: return false
	# Validate everything before replacing live contents; failed restores lose nothing.
	locked = false
	opened = not data.opened
	set_open(data.opened, false)
	locked = data.locked
	bind_inventory(restored)
	return true

func open_furniture() -> void:
	set_open(true)

