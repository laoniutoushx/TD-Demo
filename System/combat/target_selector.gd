class_name TargetSelector
extends Resource

@export var team: CombatTypes.TeamFilter = CombatTypes.TeamFilter.ENEMY
@export var exclude_source: bool = true
@export var require_alive: bool = true
@export var required_tags: Array[StringName] = []
@export var max_targets: int = 0


func matches(source_team: int, source_id: int, candidate: Object) -> bool:
	if not is_instance_valid(candidate):
		return false
	if exclude_source and candidate.get_instance_id() == source_id:
		return false
	if require_alive and candidate.has_method(&"is_alive") and not candidate.call(&"is_alive"):
		return false

	var cand_team_val: Variant = candidate.get(&"player_owner_idx")
	if cand_team_val != null and team != CombatTypes.TeamFilter.ANY:
		var cand_team: int = int(cand_team_val)
		if team == CombatTypes.TeamFilter.ENEMY and cand_team == source_team:
			return false
		if team == CombatTypes.TeamFilter.ALLY and cand_team != source_team:
			return false

	if not required_tags.is_empty():
		var cand_tags: Variant = candidate.get(&"tags")
		if cand_tags == null or not (cand_tags is Array):
			return false
		for tag in required_tags:
			if not (tag in cand_tags):
				return false

	return true
