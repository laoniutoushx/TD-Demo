class_name TreasureChest extends Node3D


@export var drop_item: DropItem


# hud 显示高度（固定值）
var _height: float = 2.5
var _selection_local_aabb: AABB = AABB()


var _eject_tween: Tween = null

func _ready() -> void:
    add_to_group("selectable_units")
    add_to_group("treasure_chests")
    $AnimationPlayer.play("burning")
    refresh_selection_bounds()
    if not $AnimationPlayer.animation_finished.is_connected(_on_spawn_anim_finished):
        $AnimationPlayer.animation_finished.connect(_on_spawn_anim_finished, CONNECT_ONE_SHOT)

func _on_spawn_anim_finished(_anim_name: StringName) -> void:
    refresh_selection_bounds()

## 当建筑建造在宝箱上或掉落位置被建筑占满时，平滑滑移到建筑外缘
func eject_to(target_pos: Vector3, duration: float = 0.24) -> void:
    if not is_inside_tree():
        global_position = target_pos
        return
    if _eject_tween != null and _eject_tween.is_valid():
        _eject_tween.kill()
    _eject_tween = create_tween()
    _eject_tween.set_trans(Tween.TRANS_QUAD)
    _eject_tween.set_ease(Tween.EASE_OUT)
    _eject_tween.tween_property(self, "global_position", target_pos, duration)
    _eject_tween.finished.connect(refresh_selection_bounds, CONNECT_ONE_SHOT)


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


var _cached_outline_meshes: Array[MeshInstance3D] = []

## 规范接口：精准返回 Chest 实体模型网格，杜绝任何外部特效或光柱被误描边
func get_outline_meshes() -> Array[MeshInstance3D]:
    if _cached_outline_meshes.is_empty():
        var chest_model = get_node_or_null("Chest")
        _cached_outline_meshes = CommonUtil.collect_solid_meshes(chest_model if chest_model != null else self)
    return _cached_outline_meshes
