extends Node

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var scene: PackedScene = load("res://Unit/turret/scenes/tower_fox_battle_mage_base_v001.tscn")
	var skill: SkillMetaResource = load("res://System/skill_system/resources/building/build_tower_fox_battle_mage_base_v001.tres")
	var material: ORMMaterial3D = load("res://Asserts/Pipeline/tower_fox_battle_mage_base_v001/fox_2k.tres")
	if scene == null or skill == null or material == null:
		push_error("FOX_CANDIDATE_RESOURCE_MISSING")
		get_tree().quit(1)
		return
	var unit = scene.instantiate()
	var ok: bool = unit.bind_materials() and unit.bind_materials()
	var meshes: Array[Node] = unit.get_node("Pivot").find_children("*", "MeshInstance3D", true, false)
	var skeletons: Array[Node] = unit.get_node("Pivot").find_children("*", "Skeleton3D", true, false)
	var players: Array[Node] = unit.get_node("Pivot").find_children("*", "AnimationPlayer", true, false)
	ok = ok and meshes.size() == 1 and skeletons.size() == 1 and players.size() == 1
	if ok:
		var skel: Skeleton3D = skeletons[0]
		ok = skel.get_bone_count() == 27 and skel.find_bone("LeftHand") >= 0 and skel.find_bone("TailBase") >= 0
		var player: AnimationPlayer = players[0]
		for clip in ["idle", "walk", "attack_normal", "attack_special", "death", "spell"]:
			ok = ok and player.has_animation(clip)
		var mesh: MeshInstance3D = meshes[0]
		var instance_material: Material = mesh.get_surface_override_material(0)
		ok = ok and instance_material != null and instance_material != material and instance_material.resource_name == material.resource_name
		var other = scene.instantiate()
		ok = ok and other.bind_materials()
		var other_mesh: MeshInstance3D = other.get_node("Pivot").find_children("*", "MeshInstance3D", true, false)[0]
		var other_material: Material = other_mesh.get_surface_override_material(0)
		ok = ok and other_material != instance_material and other_material != material
		if instance_material is BaseMaterial3D and other_material is BaseMaterial3D:
			instance_material.albedo_color = Color.RED
			ok = ok and other_material.albedo_color == Color.WHITE and material.albedo_color == Color.WHITE
		other.free()
	ok = ok and material.get_meta("pipeline_material_id", "") == "mat_75d2d72ebfd45d3bb80b671c7acd0a7a"
	ok = ok and material.normal_enabled and is_equal_approx(material.normal_scale, 0.35) and is_equal_approx(material.roughness, 1.0) and is_equal_approx(material.metallic, 1.0)
	ok = ok and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and material.cull_mode == BaseMaterial3D.CULL_BACK and not material.emission_enabled
	var texture_results := []
	for tex in [material.albedo_texture, material.normal_texture, material.orm_texture]:
		var image: Image = tex.get_image() if tex != null else null
		var mips := image != null and image.has_mipmaps()
		texture_results.append(mips)
		ok = ok and mips
	ok = ok and skill.code == "build_tower_fox_battle_mage_base_v001" and skill.building_scene != null and skill.building_res != null
	print("FOX_MATERIAL_DIAGNOSTIC ", JSON.stringify({"mesh_count":meshes.size(),"skeleton_count":skeletons.size(),"players":players.size(),"mipmaps":texture_results,"skill":skill.code,"pass":ok}))
	unit.free()
	get_tree().quit(0 if ok else 1)
