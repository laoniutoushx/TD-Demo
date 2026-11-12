extends "res://Unit/turret/scenes/turret.gd"
## Installed only for a final audited candidate in the isolated Demo.
@export var hand_bone: StringName
@export var socket_offset := Vector3.ZERO
@export_file("*.json") var material_plan_path: String
var _material_instances: Dictionary = {}

func bind_materials() -> bool:
	var plan = JSON.parse_string(FileAccess.get_file_as_string(material_plan_path))
	if not plan is Dictionary or not plan.get("bindings") is Array:
		push_error("Candidate material plan missing or invalid")
		return false
	var by_id := {}
	var names := {}
	for binding in plan.bindings:
		if by_id.has(binding.id) or names.has(binding.source_name):
			push_error("Candidate material identity duplicated")
			return false
		by_id[binding.id] = binding
		names[binding.source_name] = binding.id
	var seen := {}
	for mesh in $Pivot.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		for index in mesh.mesh.get_surface_count():
			var source: Material = mesh.mesh.surface_get_material(index)
			if source == null:
				push_error("Candidate surface has no material")
				return false
			var extras = source.get_meta("extras", {})
			var id = extras.get("pipeline_material_id", "") if extras is Dictionary else ""
			# Identity must survive GLB import. Names are only an additional consistency check.
			if not by_id.has(id) or source.resource_name != by_id[id].source_name:
				push_error("Candidate surface identity/name not mapped: " + source.resource_name)
				return false
			var external = load(by_id[id].resource)
			if not external is Material:
				push_error("Candidate external material missing")
				return false
			# Share textures and parameters, but isolate per-unit material changes.
			if not _material_instances.has(id):
				_material_instances[id] = external.duplicate()
			mesh.set_surface_override_material(index, _material_instances[id])
			seen[id] = true
	if seen.size() != by_id.size():
		push_error("Candidate contains unused/missing material bindings")
		return false
	return true

func _ready() -> void:
	if not bind_materials(): return
	turret_top = $Pivot
	hud = $Hud
	var skeleton: Skeleton3D
	var skeletons := $Pivot.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() != 1:
		push_error("Candidate must have exactly one reviewed Skeleton3D")
		return
	skeleton = skeletons[0]
	if hand_bone == &"" or skeleton.find_bone(hand_bone) < 0:
		push_error("Candidate hand bone must be explicitly reviewed")
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = "StaffSocket"
	skeleton.add_child(attachment)
	attachment.bone_name = hand_bone
	var marker = $FirePosCmp
	marker.reparent(attachment, false)
	marker.position = socket_offset
	fire_poses = [marker]
	var players := $Pivot.find_children("*", "AnimationPlayer", true, false)
	if players.size() != 1:
		push_error("Candidate must have exactly one AnimationPlayer")
		return
	animation_player_path = get_path_to(players[0])
	health_anchor_path = NodePath("HealthAnchor")
	for clip in ["idle", "walk", "attack_normal", "attack_special", "death", "spell"]:
		if not players[0].has_animation(clip):
			push_error("Candidate missing canonical animation: " + clip)
			return
		players[0].get_animation(clip).loop_mode = Animation.LOOP_LINEAR if clip in ["idle", "walk"] else Animation.LOOP_NONE
	super._ready()
	# BaseUnitResource copying can reset explicit paths; restore validated bindings.
	_ap = players[0]
	ap = _ap
	animation_player_path = get_path_to(_ap)
	health_anchor_path = NodePath("HealthAnchor")
	refresh_selection_bounds()
