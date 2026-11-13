extends Button

var accepts_drop: Callable
var drop_item: Callable

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return accepts_drop.is_valid() and accepts_drop.call(data)

func _drop_data(_position: Vector2, data: Variant) -> void:
	if drop_item.is_valid():
		drop_item.call(data)
