class_name TornadoFox
extends Node3D
## Legacy thin shim: Fox Tornado now runs declaratively via tornado_fox_ability.tres on SkillMetaResource.ability_definition.

func action(context: SkillContext) -> void:
	if context == null or not is_instance_valid(context.skill) or not is_instance_valid(context.source):
		return
	if SystemUtil.skill_system != null and context.skill.skill_meta_res != null and context.skill.skill_meta_res.ability_definition != null:
		SystemUtil.skill_system.release(context)
