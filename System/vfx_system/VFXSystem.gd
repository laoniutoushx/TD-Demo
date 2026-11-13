extends Node3D
class_name VFXSystem

const m_hit_flash: Material = preload("res://Asserts/materials/hit_flash.tres")
const MAX_POOL_CAPACITY: int = 32

enum VFX_TYPE {
	BURNING,
	RUNNING,
	DESTORY
}

var vfx_res_map: Dictionary = {}
var _pool: Dictionary = {}
var session_active: bool = true

func _ready() -> void:
	SystemUtil.vfx_system = self
	CommonUtil.load_resources_to_container_from_directory("res://VFX", vfx_res_map)

func create_vfx(vfx_name: String, vfx_type: Variant) -> Node3D:
	session_active = true
	var path := ""
	if vfx_type == null or (vfx_type is String and vfx_type.is_empty()):
		path = "vfx_%s" % vfx_name
	else:
		var type_str := ""
		if vfx_type is int and vfx_type in VFX_TYPE.values():
			type_str = str(VFX_TYPE.keys()[vfx_type]).to_lower()
		else:
			type_str = str(vfx_type).to_lower()
		path = "vfx_%s_%s" % [vfx_name, type_str]

	# 1. Check object pool
	var pool_list: Array = _pool.get(path, [])
	while not pool_list.is_empty():
		var recycled: Node3D = pool_list.pop_back()
		if is_instance_valid(recycled):
			if recycled.get_parent():
				recycled.get_parent().remove_child(recycled)
			_prepare_vfx_for_reuse(recycled)
			return recycled

	# 2. Instantiate from cached resources
	var vfx_scene: PackedScene = vfx_res_map.get(path)
	if vfx_scene == null:
		vfx_scene = vfx_res_map.get(path.to_lower())
	if vfx_scene == null and vfx_type != null:
		vfx_scene = vfx_res_map.get("vfx_%s" % vfx_name)
	if vfx_scene == null:
		return null

	var inst: Node3D = vfx_scene.instantiate()
	if inst:
		inst.set_meta(&"vfx_key", path)
	return inst

func recycle_vfx(vfx_node: Node3D) -> void:
	if not is_instance_valid(vfx_node) or vfx_node.is_queued_for_deletion():
		return
	if not session_active:
		vfx_node.queue_free()
		return
	if vfx_node.has_meta(&"vfx_key"):
		var key: String = vfx_node.get_meta(&"vfx_key")
		var pool_list: Array = _pool.get_or_add(key, [])
		if pool_list.size() < MAX_POOL_CAPACITY:
			vfx_node.set_process(false)
			vfx_node.set_physics_process(false)
			vfx_node.visible = false
			for p in vfx_node.find_children("*", "GPUParticles3D", true, false):
				if p is GPUParticles3D: p.emitting = false
			for p in vfx_node.find_children("*", "CPUParticles3D", true, false):
				if p is CPUParticles3D: p.emitting = false
			if vfx_node.get_parent() != self:
				if vfx_node.get_parent():
					vfx_node.get_parent().remove_child(vfx_node)
				add_child(vfx_node)
			pool_list.push_back(vfx_node)
			return

	vfx_node.queue_free()

func _prepare_vfx_for_reuse(inst: Node3D) -> void:
	inst.visible = true
	inst.transform = Transform3D.IDENTITY
	inst.set_process(true)
	inst.set_physics_process(true)
	if "transparency" in inst:
		inst.transparency = 0.0
	for p in inst.find_children("*", "GPUParticles3D", true, false):
		if p is GPUParticles3D:
			p.restart()
			p.emitting = true
	for p in inst.find_children("*", "CPUParticles3D", true, false):
		if p is CPUParticles3D:
			p.restart()
			p.emitting = true
	var ap = CommonUtil.get_first_node_by_node_type(inst, "AnimationPlayer")
	if ap:
		if ap.has_animation(Constants.ANIM_RUN):
			ap.play(Constants.ANIM_RUN)
		elif ap.has_animation("burning"):
			ap.play("burning")

func reset_session() -> void:
	session_active = false
	for key in _pool:
		var list: Array = _pool[key]
		for node in list:
			if is_instance_valid(node):
				node.queue_free()
	_pool.clear()
	for effect in get_children():
		effect.queue_free()

func _exit_tree() -> void:
	reset_session()
