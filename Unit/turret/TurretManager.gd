class_name TurretManager extends Node3D

const BattleInput = preload("res://Scripts/utils/BattleInput.gd")
const HOLOGRAM_VALID_MAT: Material = preload("res://Asserts/shared/shader/3d/building/hologram_valid_mat.tres")
const HOLOGRAM_INVALID_MAT: Material = preload("res://Asserts/shared/shader/3d/building/hologram_invalid_mat.tres")
const TACTICAL_GRID_SCENE: PackedScene = preload("res://Components/tactical_grid/tactical_grid_controller.tscn")

## 2m 细分网格与标准 4m x 4m 防御塔体系
const SUBCELL_SIZE: float = 2.0
const DEFAULT_TOWER_FOOTPRINT: Vector2i = Vector2i(2, 2) # 2x2 子格 = 4m x 4m 物理塔

@export var cell_mesh_indicator_scene: PackedScene
var turret: BaseUnit
var cell_mesh_indicator: MeshInstance3D
var tactical_grid: Node3D
var skill_context: SkillContext
var cell_mesh_container: Dictionary = {}
## 记录被占用的 2m 细分子格字典: occupied[subcell_vector3i] = building_instance_id
var occupied: Dictionary = {}
var grid: GridMap
var preview_cell := Vector3i.ZERO # 当前鼠标锁定的基准 2m 子格坐标
var preview_valid := false
var last_reason := ""
var _turret_original_materials: Dictionary = {}
var _active_range_indicator: Node = null

func _ready() -> void:
	grid = get_parent().get_node("GridMap")
	SignalBus.building_floor_indicator_show.connect(_on_building_floor_indicator_show)
	SignalBus.building_floor_indicator_hide.connect(_on_building_floor_indicator_hide)
	SOS.main.turret_manager = self
	_ensure_tactical_grid()

func _ensure_tactical_grid() -> void:
	if not is_instance_valid(tactical_grid):
		var existing = get_node_or_null("TacticalGridController")
		if is_instance_valid(existing):
			tactical_grid = existing
		else:
			tactical_grid = TACTICAL_GRID_SCENE.instantiate()
			tactical_grid.name = "TacticalGridController"
			add_child(tactical_grid)
			tactical_grid.owner = self
		if "cell_size" in tactical_grid:
			tactical_grid.cell_size = SUBCELL_SIZE

## 世界坐标转 2m 细分子格坐标
func world_to_subcell(point: Vector3) -> Vector3i:
	var local = grid.to_local(point) if is_instance_valid(grid) else point
	return Vector3i(int(floor(local.x / SUBCELL_SIZE)), 0, int(floor(local.z / SUBCELL_SIZE)))

## 2m 细分子格坐标转世界中心坐标
func subcell_to_world(subcell: Vector3i) -> Vector3:
	var local = Vector3((float(subcell.x) + 0.5) * SUBCELL_SIZE, 0.0, (float(subcell.z) + 0.5) * SUBCELL_SIZE)
	return grid.to_global(local) if is_instance_valid(grid) else local

func world_to_cell(point: Vector3) -> Vector3i:
	return world_to_subcell(point)

func cell_to_world(cell: Vector3i) -> Vector3:
	return subcell_to_world(cell)

## 获取塔在 2m 系统下的实际子格占地（例如 4m 塔映射为 2x2 子格）
func get_effective_footprint(definition: BaseUnitResource = null) -> Vector2i:
	if definition == null and skill_context != null and is_instance_valid(skill_context.skill):
		definition = skill_context.skill.skill_meta_res.building_res
	if definition and definition.building_footprint != Vector2i.ZERO:
		var fp = definition.building_footprint
		# 若原配置为 1x1（代表原 4m 单格塔），在 2m 系统下自动升维为 2x2 子格（4m x 4m）
		if fp == Vector2i(1, 1):
			return DEFAULT_TOWER_FOOTPRINT
		return Vector2i(max(1, fp.x * 2), max(1, fp.y * 2))
	return DEFAULT_TOWER_FOOTPRINT

## 获取防御塔所占用的所有 2m 细分子格列表
func footprint_cells(base_subcell: Vector3i, definition: BaseUnitResource = null) -> Array[Vector3i]:
	var fp: Vector2i = get_effective_footprint(definition)
	var cells: Array[Vector3i] = []
	for x in range(fp.x):
		for z in range(fp.y):
			cells.append(base_subcell + Vector3i(x, 0, z))
	return cells

## 查询单格 2m 子格状态：0=不可建/道路, 1=可建, 2=占用
func get_subcell_state(subcell: Vector3i) -> int:
	if occupied.has(subcell):
		return 2 # 已被建筑占用
	var pt = subcell_to_world(subcell)
	if is_instance_valid(grid):
		var macro_cell = grid.local_to_map(grid.to_local(pt))
		if grid.get_cell_item(macro_cell) == 0:
			return 1 # 可建造
	return 0 # 不可建 / 道路

func placement_reason(base_subcell: Vector3i, definition: BaseUnitResource = null) -> String:
	for sub in footprint_cells(base_subcell, definition):
		var st = get_subcell_state(sub)
		if st == 2:
			return "地块已被建筑占用"
		if st == 0:
			return "占地范围包含不可建造地块"
	return ""

## 计算防御塔落位的物理世界中心坐标（4 个子格几何中心）
func placement_position(base_subcell: Vector3i, definition: BaseUnitResource = null) -> Vector3:
	var fp: Vector2i = get_effective_footprint(definition)
	var local = Vector3((float(base_subcell.x) + float(fp.x) * 0.5) * SUBCELL_SIZE, 0.0, (float(base_subcell.z) + float(fp.y) * 0.5) * SUBCELL_SIZE)
	return grid.to_global(local) if is_instance_valid(grid) else local

func _apply_hologram(is_valid: bool) -> void:
	if not is_instance_valid(turret): return
	var target_mat = HOLOGRAM_VALID_MAT if is_valid else HOLOGRAM_INVALID_MAT
	for node in turret.find_children("*", "MeshInstance3D"):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh == null: continue
		if mesh.name == "mesh_standing": continue
		if not _turret_original_materials.has(mesh):
			_turret_original_materials[mesh] = mesh.material_override
		mesh.material_override = target_mat

func _restore_turret_materials() -> void:
	for mesh in _turret_original_materials:
		if is_instance_valid(mesh):
			mesh.material_override = _turret_original_materials[mesh]
	_turret_original_materials.clear()

func _update_range_indicator(show: bool) -> void:
	if not is_instance_valid(turret):
		_active_range_indicator = null
		return
	if show:
		var indicator = turret.get_node_or_null("RangeIndicator")
		if is_instance_valid(indicator):
			_active_range_indicator = indicator
			if indicator.has_method("show"):
				indicator.show()
			elif "visible" in indicator:
				indicator.visible = true
	elif is_instance_valid(_active_range_indicator):
		if _active_range_indicator.has_method("hide"):
			_active_range_indicator.hide()
		elif "visible" in _active_range_indicator:
			_active_range_indicator.visible = false
		_active_range_indicator = null

func callable_build_turret(ray: RayCast3D, _grid: GridMap) -> void:
	preview_valid = false
	if not is_instance_valid(turret) or not ray.is_colliding() or ray.get_collider() != grid: return
	
	# 以碰撞点计算 2m 细分子格基准
	preview_cell = world_to_subcell(ray.get_collision_point())
	last_reason = placement_reason(preview_cell)
	var cost_reason := ""
	if skill_context and is_instance_valid(SOS.main) and is_instance_valid(SOS.main.player_controller):
		cost_reason = SOS.main.player_controller.validate_skill_cost(skill_context)
	if cost_reason != "":
		last_reason = cost_reason
	preview_valid = (last_reason == "")
	
	var point := placement_position(preview_cell)
	turret.global_position = point + Vector3.UP * 0.001
	_apply_hologram(preview_valid)

	# 联动战术网格、焦点吸附框与周围可建地块全息热力图
	if is_instance_valid(tactical_grid):
		var fp = get_effective_footprint()
		tactical_grid.update_cursor(point, preview_valid, fp)
		if tactical_grid.has_method("update_stencil_matrix"):
			tactical_grid.update_stencil_matrix(point, get_subcell_state)

	# 兼容旧指示器
	if is_instance_valid(cell_mesh_indicator):
		cell_mesh_indicator.global_position = point + Vector3.UP * 0.02
		if cell_mesh_indicator.material_override:
			var col = Color(0.2, 2.5, 0.5, 1.0) if preview_valid else Color(2.5, 0.2, 0.2, 1.0)
			cell_mesh_indicator.material_override.set_shader_parameter("ColorParameter", col)

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(turret): return

	# 1. 鼠标右键或 ESC 键一键安全取消建造
	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed) or \
	   (event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed):
		cancel_preview()
		if skill_context and is_instance_valid(skill_context.skill):
			skill_context.skill.change_state(Skill.SKILL_STATE.Idle)
		if is_instance_valid(SOS.main) and is_instance_valid(SOS.main.player_controller):
			SOS.main.player_controller.switch_cursor(Constants.CURSOR_STATUS.DEFAULT)
		get_viewport().set_input_as_handled()
		return

	# 2. 鼠标左键点击确认建造
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not BattleInput.pointer_available(get_viewport(), event.position): return
		var camera = get_viewport().get_camera_3d()
		if camera is RayPicker:
			camera.ray_cast_3d.force_raycast_update()
			callable_build_turret(camera.ray_cast_3d, grid)
		if not preview_valid:
			SOS.main.message_bar.set_message(last_reason if last_reason != "" else "请选择可建造地块")
			return

		var is_shift = event.shift_pressed
		var confirmed_cell = preview_cell
		var ok = confirm_build(confirmed_cell)
		if ok:
			get_viewport().set_input_as_handled()
			# 3. Shift 连续建造队列支持
			if is_shift and skill_context and is_instance_valid(skill_context.skill):
				_continue_shift_build()

func _continue_shift_build() -> void:
	var cost_reason = ""
	if is_instance_valid(SOS.main) and is_instance_valid(SOS.main.player_controller):
		cost_reason = SOS.main.player_controller.validate_skill_cost(skill_context)
	if cost_reason != "":
		SOS.main.message_bar.set_message(cost_reason)
		return

	var definition: BaseUnitResource = skill_context.skill.skill_meta_res.building_res
	if definition != null:
		turret = SystemUtil.unit_system.create_unit(definition, SOS.main.player_controller.player_group_idx)
		add_child(turret)
		turret.global_position = placement_position(preview_cell) + Vector3.UP * 0.001
		_apply_hologram(preview_valid)
		_update_range_indicator(true)

func confirm_build(cell: Vector3i) -> bool:
	if not is_instance_valid(turret) or skill_context == null or placement_reason(cell) != "": return false
	var reason := SOS.main.player_controller.validate_skill_cost(skill_context)
	if reason != "":
		SOS.main.message_bar.set_message(reason)
		return false
	var building: BaseUnit = turret
	var point := placement_position(cell) + Vector3.UP * 0.001
	var cells := footprint_cells(cell)
	for reserved_cell in cells: occupied[reserved_cell] = building.get_instance_id()
	building.set_meta("build_cell", cell)
	building.set_meta("build_cells", cells)
	building.tree_exiting.connect(_release_cells.bind(cells, building.get_instance_id()), CONNECT_ONE_SHOT)
	building.logical_death.connect(_on_building_left.bind(cells, building.get_instance_id()), CONNECT_ONE_SHOT)
	_restore_turret_materials()
	_update_range_indicator(false)
	skill_context.building = building
	skill_context.callback = _finish_building.bind(building, point)
	building.global_position = point
	skill_context.skill.change_state(Skill.SKILL_STATE.Release)
	return true

func _finish_building(building: BaseUnit, point: Vector3) -> void:
	if not is_instance_valid(building): return
	building.global_position = point
	building.player_group = SOS.main.player_controller.get_player_group_idx()
	building.player_owner_idx = SOS.main.player_controller.get_player_idx()
	building.change_state(Turret.TurretState.IDLE)

func _release_cell(cell: Vector3i, id: int) -> void:
	if occupied.get(cell, -1) == id: occupied.erase(cell)

func _release_cells(cells: Array, id: int) -> void:
	for cell in cells: _release_cell(cell, id)

func _on_building_left(_unit: BaseUnit, cells: Array, id: int) -> void:
	_release_cells(cells, id)

func replace_building(old: BaseUnit, replacement: BaseUnit) -> void:
	if not old.has_meta("build_cell"): return
	var cell: Vector3i = old.get_meta("build_cell")
	var cells: Array = old.get_meta("build_cells", [cell])
	for reserved_cell in cells: occupied[reserved_cell] = replacement.get_instance_id()
	replacement.set_meta("build_cell", cell)
	replacement.set_meta("build_cells", cells)
	replacement.tree_exiting.connect(_release_cells.bind(cells, replacement.get_instance_id()), CONNECT_ONE_SHOT)
	replacement.logical_death.connect(_on_building_left.bind(cells, replacement.get_instance_id()), CONNECT_ONE_SHOT)

func _on_building_floor_indicator_show(context: SkillContext) -> void:
	cancel_preview()
	skill_context = context
	skill_context.cost_paid = false
	_clear_cell_mesh_indicator_in_position()
	_ensure_tactical_grid()

	var definition: BaseUnitResource = context.skill.skill_meta_res.building_res
	if definition != null:
		turret = SystemUtil.unit_system.create_unit(definition, SOS.main.player_controller.player_group_idx)
		add_child(turret)
		_apply_hologram(false)
		_update_range_indicator(true)

	# 开启战术全息网格
	if is_instance_valid(tactical_grid):
		var init_pos = global_position
		if is_instance_valid(grid):
			init_pos = grid.global_position
		if is_instance_valid(context.source):
			init_pos = context.source.global_position
		tactical_grid.show_grid(init_pos, Vector2(140.0, 140.0))
		if tactical_grid.has_method("update_stencil_matrix"):
			tactical_grid.update_stencil_matrix(init_pos, get_subcell_state)
		# 若相机射线已有碰撞点，立即预吸附焦点框与态势热力图
		var cam = get_viewport().get_camera_3d() if is_inside_tree() else null
		if cam is RayPicker and is_instance_valid(cam.ray_cast_3d) and cam.ray_cast_3d.is_colliding():
			var hit_pt = cam.ray_cast_3d.get_collision_point()
			var hit_cell = world_to_subcell(hit_pt)
			var snap_pt = placement_position(hit_cell)
			var valid = (placement_reason(hit_cell) == "")
			var fp = get_effective_footprint()
			tactical_grid.update_cursor(snap_pt, valid, fp)
			if tactical_grid.has_method("update_stencil_matrix"):
				tactical_grid.update_stencil_matrix(snap_pt, get_subcell_state)

	if cell_mesh_indicator_scene:
		cell_mesh_indicator = cell_mesh_indicator_scene.instantiate()
		add_child(cell_mesh_indicator)
	SignalBus.ray_picker_regist.emit(callable_build_turret)

func _on_building_floor_indicator_hide(context: SkillContext) -> void:
	if context != skill_context: return
	SignalBus.ray_picker_unregist.emit(callable_build_turret)
	_clear_cell_mesh_indicator_in_position()
	_restore_turret_materials()
	_update_range_indicator(false)
	if is_instance_valid(tactical_grid):
		tactical_grid.hide_grid()
	if is_instance_valid(cell_mesh_indicator): cell_mesh_indicator.queue_free()
	cell_mesh_indicator = null
	if context.cost_paid:
		turret = null
		preview_valid = false

func cancel_preview() -> void:
	SignalBus.ray_picker_unregist.emit(callable_build_turret)
	_clear_cell_mesh_indicator_in_position()
	_restore_turret_materials()
	_update_range_indicator(false)
	if is_instance_valid(tactical_grid):
		tactical_grid.hide_grid()
	if is_instance_valid(turret): turret.queue_free()
	if is_instance_valid(cell_mesh_indicator): cell_mesh_indicator.queue_free()
	turret = null
	cell_mesh_indicator = null
	preview_valid = false

func _clear_cell_mesh_indicator_in_position() -> void:
	for indicator in cell_mesh_container.values():
		if is_instance_valid(indicator): indicator.queue_free()
	cell_mesh_container.clear()
