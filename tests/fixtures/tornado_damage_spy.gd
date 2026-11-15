extends "res://System/damage_system/DamageSystem.gd"
var received: Dictionary={}
func _ready() -> void: SystemUtil.damage_system=self
func _process(_delta: float) -> void: pass
func skill_damage(skill: Variant,source: BaseUnit,target: BaseUnit) -> bool:
 if not is_instance_valid(source) or not target.is_alive(): return false
 var key: int=target.get_instance_id()
 received[key]=int(received.get(key,0))+1
 target.health-=skill.value
 return true
