class_name BuildingBaseTurret extends Node3D

const CONSTRUCTION_CIRCLE_SCENE = preload("res://VFX/building/vfx_construction_circle.tscn")
const CONSTRUCTION_DUST_SCENE = preload("res://VFX/building/vfx_construction_dust.tscn")
const BUILDING_IMPACT_SCENE = preload("res://VFX/building/vfx_building_impact.tscn")

func action(skill_context: SkillContext) -> void:
    # 播放施法动画 & 声音
    var skill: Skill = skill_context.skill
    var source_unit: BaseUnit = skill_context.source
    var target_unit: BaseUnit = skill_context.target

    # 技能释放
    var building: BaseUnit = skill_context.building
    if not is_instance_valid(building): return
    var generation = SOS.main.level_controller.session_id
    var gp = skill_context.building.global_position

    # 1. 地基旋转魔力法阵 (Decal 贴合地形)
    var circle: Node3D = CONSTRUCTION_CIRCLE_SCENE.instantiate()
    building.get_parent().add_child(circle)
    circle.global_position = gp

    # 2. 地表施工尘土与魔力升腾粒子
    var dust: Node3D = CONSTRUCTION_DUST_SCENE.instantiate()
    building.get_parent().add_child(dust)
    dust.global_position = gp

    # 3. 播放施工阶段音效
    CommonUtil.play_audio(source_unit, "271137__strange_dragoon__building-constructing", 0.5)

    # 4. 建筑拔地升起（平滑缓动向上构建生长）
    building.global_position = gp
    building.scale = Vector3(0.2, 0.05, 0.2)
    var tween: Tween = create_tween()
    tween.set_ease(Tween.EASE_OUT)
    tween.set_trans(Tween.TRANS_BACK)
    tween.tween_property(building, "scale", Vector3.ONE, 1.2)

    await tween.finished
    if not SystemUtil.skill_system._session_valid(generation, source_unit) or not is_instance_valid(building):
        if is_instance_valid(circle): circle.queue_free()
        if is_instance_valid(dust): dust.queue_free()
        return

    # 5. 落成震撼反馈（播放落成音效 + 释放地面冲击波）
    CommonUtil.play_audio(source_unit, "271134__strange_dragoon__building-placement", 1.0)
    var impact: Node3D = BUILDING_IMPACT_SCENE.instantiate()
    building.get_parent().add_child(impact)
    impact.global_position = gp

    if is_instance_valid(dust) and dust.has_method("stop_emitting"):
        dust.stop_emitting()
    elif is_instance_valid(dust):
        dust.queue_free()

    if is_instance_valid(circle) and circle.has_method("fade_out"):
        circle.fade_out(0.4)
    elif is_instance_valid(circle):
        circle.queue_free()

    skill_context.callback.call()
    # fixed bug when player building another turret（status changed to building）
    if building.has_method("change_state"):
        building.change_state(building.TurretState.IDLE)

