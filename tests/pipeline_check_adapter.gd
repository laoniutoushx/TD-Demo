extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var adapter = load("res://tests/pipeline_mage_adapter.gd")
	if adapter == null or not adapter.can_instantiate():
		push_error("INTEGRATION_PARSE_FAILED")
		quit(1)
		return
	print("INTEGRATION_PARSE_OK")
	quit()
