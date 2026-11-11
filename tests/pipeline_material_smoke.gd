extends SceneTree
## Mechanical identity binding test, not gameplay or rendered-style acceptance.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var script = load("res://tests/pipeline_mage_adapter.gd")
	if script == null or not script.can_instantiate():
		push_error("ADAPTER_PARSE_FAILED")
		quit(1)
		return
	var unit = script.new()
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	unit.add_child(pivot)
	var visual = load("res://tests/pipeline_identity_fixture.glb").instantiate()
	pivot.add_child(visual)
	unit.material_plan_path = "res://tests/pipeline_material_fixture.json"
	var passed: bool = unit.bind_materials() and unit.bind_materials()
	var count := 0
	for mesh in pivot.find_children("*", "MeshInstance3D", true, false):
		for index in mesh.mesh.get_surface_count():
			count += 1
			var source: Material = mesh.mesh.surface_get_material(index)
			var target: Material = mesh.get_surface_override_material(index)
			var expected := "res://tests/pipeline_body.tres" if source.resource_name == "BodyMat" else "res://tests/pipeline_staff.tres"
			passed = passed and target != null and target.resource_path == expected
	unit.free()
	if passed and count == 2:
		print("MATERIAL_BINDING_SMOKE_OK")
		quit(0)
	else:
		push_error("MATERIAL_BINDING_SMOKE_FAILED")
		quit(1)
