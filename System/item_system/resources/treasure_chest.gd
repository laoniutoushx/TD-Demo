class_name TreasureChest extends Node3D


@export var drop_item: DropItem


# hud 显示高度（固定值）
var _height: float = 2.5
var _selection_local_aabb: AABB = AABB()


func _ready() -> void:
    add_to_group("selectable_units")
    $AnimationPlayer.play("burning")
    refresh_selection_bounds()


func refresh_selection_bounds() -> void:
    _selection_local_aabb = CommonUtil.get_node_hierarchy_local_aabb(self)


func get_selection_aabb() -> AABB:
    if _selection_local_aabb.size.length_squared() < 0.001:
        refresh_selection_bounds()
    return CommonUtil.transform_aabb(global_transform, _selection_local_aabb)


func steup(_drop_item: DropItem) -> void:
    drop_item = _drop_item


func show_selected_circle() -> void:
    var select_circle = CommonUtil.get_first_node_by_node_name(self, "FadedCircle3D")	
    if select_circle:
        select_circle.visible = true

        # 添加动效
        var tween = create_tween()
        tween.tween_property(select_circle, "radius", select_circle.radius * 1.25, 0.0)
        tween.tween_property(select_circle, "radius", select_circle.radius, 0.1)
