extends Node
class_name EnemySpawner

const BakedPathDataScript = preload("res://System/movement/baked_path_data.gd")
const DEFAULT_LANE_HALF_WIDTH := 0.8

signal enemy_spawn_finished


var _enemy_spawner_res: EnemySpawnerResource
var _path: Node
var _start_node: Marker3D

var is_game_over = false
var wave_index := -1



func _init(enemy_spawner_res: EnemySpawnerResource, path: Node, start_node: Node, wave_spawner: WaveManager.WaveSpawner) -> void:
	_enemy_spawner_res = enemy_spawner_res
	wave_index = wave_spawner.wave_index
	_path = path
	_start_node = start_node
	
	# bind spawning end event
	enemy_spawn_finished.connect(wave_spawner.finish_listener, CONNECT_ONE_SHOT)

	# game over listener
	SignalBus.game_over.connect(self._on_game_over)

func start():
	# spawning

	await CommonUtil.await_timer(_enemy_spawner_res.spawn_start_delay)
	if not is_inside_tree() or is_game_over:
		return	

	var baked_path: BakedPathDataScript = null
	var container: Node = _path
	if _path is Path3D:
		baked_path = BakedPathDataScript.for_path3d(_path as Path3D)
		container = _resolve_enemies_container(_path)

	for i in _enemy_spawner_res.enemy_amount:
		if is_game_over:
			return 
			
		# enemy res name
		var enemy_res_name = _enemy_spawner_res.enemy_res_name
		# load enemy resource file
		var enemy_resource:EnemyResource = load("res://Unit/enemy/resources/%s.tres" % enemy_res_name)
		
		# generate enemy instance
		var enemy_instance: Enemy = SystemUtil.unit_system.create_unit(enemy_resource, 1)
		enemy_instance.wave_index = wave_index
		get_parent().register_enemy(enemy_instance, wave_index)
		
		# y offset
		if is_instance_valid(_start_node):
			var base_y := baked_path.start_y if baked_path != null and baked_path.is_valid_path() else 0.0
			enemy_instance.v_offset = _start_node.global_position.y - base_y
		else:
			return

		if baked_path != null and is_instance_valid(container):
			var lane_offset := _compute_lane_offset(i, _enemy_spawner_res.enemy_amount)
			enemy_instance.set_baked_path(baked_path, lane_offset)
			container.add_child(enemy_instance)

			await CommonUtil.await_timer(_enemy_spawner_res.spawn_interval)
			if not is_inside_tree() or is_game_over:
				return
		elif _path != null:
			_path.add_child(enemy_instance)
			await CommonUtil.await_timer(_enemy_spawner_res.spawn_interval)
			if not is_inside_tree() or is_game_over:
				return

	
	# emit spawning end signal
	enemy_spawn_finished.emit()
	queue_free()


func _resolve_enemies_container(path_node: Node) -> Node:
	var host := path_node.get_parent()
	if not is_instance_valid(host):
		return path_node
	var existing := host.get_node_or_null(^"Enemies")
	if is_instance_valid(existing):
		return existing
	var container := Node3D.new()
	container.name = "Enemies"
	host.add_child(container)
	return container


func _compute_lane_offset(spawn_idx: int, total_count: int) -> float:
	if total_count <= 1:
		return 0.0
	# Low-discrepancy golden-ratio sequence spreads consecutive enemies evenly across lanes.
	var frac := fmod(float(spawn_idx) * 0.61803398875, 1.0)
	var jitter := randf_range(-0.12, 0.12)
	return clampf((frac * 2.0 - 1.0) * DEFAULT_LANE_HALF_WIDTH + jitter, -DEFAULT_LANE_HALF_WIDTH, DEFAULT_LANE_HALF_WIDTH)


func _on_game_over():
	is_game_over = true
