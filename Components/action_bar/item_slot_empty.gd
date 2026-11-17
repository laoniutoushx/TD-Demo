extends BaseSlot


func _get_normal_panel_style() -> StyleBox:
	return _slot_empty_item_style


func _on_mouse_exited() -> void:
	super._on_mouse_exited()


func _on_mouse_entered() -> void:
	super._on_mouse_entered()
