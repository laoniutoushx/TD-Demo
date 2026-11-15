class_name BaseSlotIndicator extends Control


@onready var panel: PanelContainer = %PanelContainer


# slot_indicator 下边界 与 slot 中心点的距离
@export var keep_bottom_margin: float = 8.0
var cur_slot: BaseSlot
var _show_token: int = 0
var _is_scrollable: bool = false
var _waiting_pointer_exit: bool = false
@onready var _scroll: ScrollContainer = get_node_or_null("%TooltipScroll")
@onready var _content_vbox: VBoxContainer = get_node_or_null("%VBoxContainer")


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	_apply_mouse_filters(false)
	hide()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		_is_scrollable = false
		_waiting_pointer_exit = false
		set_process(false)
		_apply_mouse_filters(false)


func _apply_mouse_filters(scrollable: bool) -> void:
	var vbar: VScrollBar = _scroll.get_v_scroll_bar() if _scroll else null
	var hbar: HScrollBar = _scroll.get_h_scroll_bar() if _scroll else null
	for control in find_children("*", "Control", true, false):
		if control == _scroll or control == vbar:
			continue
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if hbar:
		hbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _scroll:
		_scroll.mouse_filter = Control.MOUSE_FILTER_STOP if scrollable else Control.MOUSE_FILTER_IGNORE
		if scrollable and visible:
			if not _scroll.is_in_group("blocks_world_input"):
				_scroll.add_to_group("blocks_world_input")
		elif _scroll.is_in_group("blocks_world_input"):
			_scroll.remove_from_group("blocks_world_input")
	if vbar:
		vbar.mouse_filter = Control.MOUSE_FILTER_STOP if scrollable else Control.MOUSE_FILTER_IGNORE


func is_pointer_over_scrollable() -> bool:
	if not visible or not _is_scrollable or not is_instance_valid(panel):
		return false
	var mouse_pos := get_viewport().get_mouse_position()
	var bridge_rect := panel.get_global_rect().grow(12.0)
	return bridge_rect.has_point(mouse_pos)


func begin_hover_watch() -> void:
	if visible and _is_scrollable:
		_waiting_pointer_exit = true
		set_process(true)


func _process(_delta: float) -> void:
	if not _waiting_pointer_exit or not visible or not _is_scrollable:
		_waiting_pointer_exit = false
		set_process(false)
		return
	var mouse_pos := get_viewport().get_mouse_position()
	var in_panel := is_instance_valid(panel) and panel.get_global_rect().grow(12.0).has_point(mouse_pos)
	var in_slot := is_instance_valid(cur_slot) and cur_slot.get_global_rect().has_point(mouse_pos)
	if not in_panel and not in_slot:
		_show_token += 1
		hide()

# 依据 base_slot 显示对应提示信息（数据驱动）
func show_toggle(_slot: BaseSlot) -> void:
	if visible and cur_slot == _slot and not _waiting_pointer_exit:
		_show_token += 1
		hide()
		return
	cur_slot = _slot
	defer_show(true)


func show_for_slot(_slot: BaseSlot) -> void:
	if visible and cur_slot == _slot and modulate.a > 0.0:
		_waiting_pointer_exit = false
		set_process(false)
		return
	cur_slot = _slot
	defer_show(true)


func hide_for_slot(_slot: BaseSlot) -> void:
	if not visible or cur_slot != _slot:
		return
	if is_pointer_over_scrollable():
		begin_hover_watch()
	else:
		_show_token += 1
		hide()


func defer_show(force_open: bool = false) -> void:
	if visible and not force_open:
		_show_token += 1
		hide()
		return
	_show_token += 1
	var token := _show_token
	_is_scrollable = false
	_waiting_pointer_exit = false
	set_process(false)
	_apply_mouse_filters(false)
	modulate.a = 0.0
	refresh_slot_indicator_info(cur_slot)
	if _scroll:
		_scroll.scroll_vertical = 0
		_scroll.custom_minimum_size.y = 0.0
	show()
	await get_tree().process_frame
	if token != _show_token or not visible or not is_instance_valid(cur_slot):
		return
	_fit_scroll_height()
	await get_tree().process_frame
	if token != _show_token or not visible or not is_instance_valid(cur_slot):
		return
	_position_indicator()
	_apply_mouse_filters(_is_scrollable)
	modulate.a = 1.0


func _fit_scroll_height() -> void:
	if not _scroll or not _content_vbox or not is_instance_valid(cur_slot):
		_is_scrollable = false
		panel.reset_size()
		return
	var vp_size := get_viewport_rect().size
	var gap := maxf(8.0, keep_bottom_margin)
	var avail_above := cur_slot.global_position.y - gap - 8.0
	var avail_below := vp_size.y - (cur_slot.global_position.y + cur_slot.size.y + gap) - 8.0
	var cap_h := minf(vp_size.y - 16.0, maxf(360.0, vp_size.y * 0.56))
	var max_panel_h := clampf(maxf(avail_above, avail_below), 140.0, cap_h)
	var content_h := _content_vbox.get_combined_minimum_size().y
	# Account for PanelContainer + MarginContainer padding (~36px)
	var max_scroll_h := maxf(96.0, max_panel_h - 36.0)
	_is_scrollable = content_h > max_scroll_h + 1.0
	_scroll.custom_minimum_size.y = minf(content_h, max_scroll_h)
	panel.reset_size()


func _position_indicator() -> void:
	if not is_instance_valid(cur_slot):
		return
	var vp_size := get_viewport_rect().size
	var slot_rect := Rect2(cur_slot.global_position, cur_slot.size)
	var panel_rect := panel.get_global_rect()
	var rect_size := panel_rect.size
	if rect_size.x <= 1.0 or rect_size.y <= 1.0:
		rect_size = panel.get_combined_minimum_size()
	var gap := maxf(8.0, keep_bottom_margin)

	var slot_center_x := slot_rect.position.x + slot_rect.size.x * 0.5
	var target_x := clampf(slot_center_x - rect_size.x * 0.5, 8.0, maxf(8.0, vp_size.x - rect_size.x - 8.0))

	var above_top := slot_rect.position.y - gap - rect_size.y
	var target_y: float
	if above_top >= 8.0:
		target_y = above_top
	else:
		var below_top := slot_rect.end.y + gap
		if below_top + rect_size.y <= vp_size.y - 8.0:
			target_y = below_top
		else:
			target_y = clampf(above_top, 8.0, maxf(8.0, vp_size.y - rect_size.y - 8.0))

	self.global_position += Vector2(target_x, target_y) - panel_rect.position


# 刷新位置
func _on_panel_container_resized() -> void:
	if visible and modulate.a > 0.0 and is_instance_valid(cur_slot):
		_position_indicator()


func refresh_slot_indicator_info(_slot: BaseSlot) -> void:
	pass
	
