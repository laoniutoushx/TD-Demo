# BloodDecal.gd
extends Decal
class_name BloodDecal

## 生命期与氧化动画参数
@export var fade_in_duration: float = 0.15   # 飞溅初期的淡入/展开时间
@export var stay_duration: float = 3.5       # 停留与氧化干燥时间
@export var fade_out_duration: float = 2.0   # 最终渗入地面淡出时间

# 血液氧化颜色过渡：从刚喷射的新鲜暗红，氧化为干燥凝固的深黑褐色
@export var fresh_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var dried_color: Color = Color(0.42, 0.28, 0.28, 1.0)

enum FadePhase {
	FADE_IN,
	STAYING,
	FADE_OUT,
	FINISHED
}

var _fade_tween: Tween
var _current_phase: FadePhase = FadePhase.FADE_IN
var _is_managed: bool = false

# 全局 Decal 管理池（FIFO 控制最大活跃贴花数量，防止超负荷和 GC 抖动）
static var _active_decals: Array[BloodDecal] = []
const MAX_ACTIVE_DECALS: int = 48

func _ready() -> void:
	_register_to_pool()
	start_lifecycle()

func _exit_tree() -> void:
	_unregister_from_pool()

func _register_to_pool() -> void:
	if not _is_managed:
		_active_decals.append(self)
		_is_managed = true
		# 若超出上限，让最老的一个迅速淡出
		while _active_decals.size() > MAX_ACTIVE_DECALS:
			var oldest = _active_decals.pop_front()
			if is_instance_valid(oldest) and oldest != self:
				oldest._is_managed = false
				oldest.force_fade_out(0.4)

func _unregister_from_pool() -> void:
	if _is_managed:
		_active_decals.erase(self)
		_is_managed = false

## 外部初始化尺寸与位置的规范入口
func setup_blood(target_size: Vector3, world_pos: Vector3, random_yaw: bool = true) -> void:
	# 严禁用 scale 缩放 Decal，使用 size
	# 限制 Y 轴投影深度为 0.3~0.6m，避免穿透跨多层楼板
	var clamped_depth: float = clampf(target_size.y, 0.3, 0.6)
	var extent_x: float = maxf(target_size.x, 0.5)
	var extent_z: float = maxf(target_size.z, 0.5)
	size = Vector3(extent_x, clamped_depth, extent_z)
	# 中心置于接触面稍上方，向下充分投射在石板与地面
	var target_pos: Vector3 = world_pos + Vector3(0, 0.08, 0)
	if is_inside_tree():
		global_position = target_pos
	else:
		position = target_pos
	if random_yaw:
		rotation.y = randf_range(0.0, TAU)

func start_lifecycle() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()

	_current_phase = FadePhase.FADE_IN
	modulate = Color(fresh_color.r, fresh_color.g, fresh_color.b, 0.0)

	_fade_tween = create_tween()
	# 1. 溅射出现：Alpha 0 -> 1.0
	_fade_tween.tween_property(self, "modulate:a", 1.0, fade_in_duration)
	
	# 2. 停留与氧化变深：从鲜红氧化为深黑干涸色
	_fade_tween.tween_callback(func(): _current_phase = FadePhase.STAYING)
	_fade_tween.tween_property(self, "modulate:r", dried_color.r, stay_duration)
	_fade_tween.parallel().tween_property(self, "modulate:g", dried_color.g, stay_duration)
	_fade_tween.parallel().tween_property(self, "modulate:b", dried_color.b, stay_duration)
	
	# 3. 渐隐渗入地面：Alpha 1.0 -> 0.0
	_fade_tween.tween_callback(func(): _current_phase = FadePhase.FADE_OUT)
	_fade_tween.tween_property(self, "modulate:a", 0.0, fade_out_duration)
	
	# 4. 完成销毁
	_fade_tween.tween_callback(_on_fade_complete)

func force_fade_out(fast_duration: float = 0.5) -> void:
	"""超额淘汰或外部要求强制快速淡出"""
	if _current_phase == FadePhase.FINISHED:
		return
	_current_phase = FadePhase.FADE_OUT
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0, fast_duration)
	_fade_tween.tween_callback(_on_fade_complete)

func _on_fade_complete() -> void:
	_current_phase = FadePhase.FINISHED
	_unregister_from_pool()
	queue_free()

func set_fade_parameters(fade_in: float, stay: float, fade_out: float) -> void:
	fade_in_duration = fade_in
	stay_duration = stay
	fade_out_duration = fade_out

func get_current_phase() -> FadePhase:
	return _current_phase
