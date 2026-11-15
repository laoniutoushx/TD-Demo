extends SceneTree
var main_scene
var output_dir := "res://.godot/ui_material_review"
func _initialize() -> void:
 call_deferred("run")
func shot(name: String) -> void:
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(output_dir + "/" + name + ".png")
func resize_to(dims: Vector2i) -> void:
 root.size = dims
 await process_frame
 await process_frame
func run() -> void:
 DirAccess.make_dir_recursive_absolute(output_dir)
 main_scene = load("res://Main.tscn").instantiate()
 main_scene.settings_path = "user://ui_material_review_settings.cfg"
 root.add_child(main_scene)
 await create_timer(1.0).timeout
 var controller = main_scene.level_controller
 for dims in [Vector2i(1080,768), Vector2i(1920,1080), Vector2i(2560,1080)]:
  await resize_to(dims)
  var tag := "%dx%d" % [dims.x,dims.y]
  await shot(tag+"_menu")
  var settings = controller.open_settings()
  await shot(tag+"_settings")
  settings._on_return_pressed()
  await process_frame
 controller._cur_scene.index_ui._on_start_pressed()
 await create_timer(2.0).timeout
 var level = controller._cur_scene
 level.get_node("RTSController").edge_scroll_enabled = false
 var unit = level.gdbot
 root.get_node("SignalBus").player_selected_units.emit({unit.get_instance_id():unit}, Vector3.ZERO, 0)
 main_scene.player_controller.add_talent("greedy_talent")
 level.action_bar.player_bar_comp.reset_slot_for_player()
 await process_frame
 for dims in [Vector2i(1080,768), Vector2i(1920,1080), Vector2i(2560,1080)]:
  await resize_to(dims)
  var tag := "%dx%d" % [dims.x,dims.y]
  await shot(tag+"_battle")
  var bar: Control = level.action_bar.get_node("CanvasLayer/Container")
  assert(bar.get_global_rect().end.x <= root.size.x + 1, "Bottom bar exceeds viewport")
  var indicator = main_scene.skill_slot_indicator
  var slot = level.action_bar.skill_bar.get_child(0)
  indicator.show_toggle(slot)
  await process_frame
  await process_frame
  await process_frame
  await shot(tag+"_tooltip")
  var rect: Rect2 = indicator.panel.get_global_rect()
  assert(rect.position.x >= 0 and rect.position.y >= 0, "Tooltip outside viewport")
  assert(rect.end.x <= root.size.x + 1 and rect.end.y <= root.size.y + 1, "Tooltip outside viewport")
  indicator.show_toggle(slot)
  print("UI_MATERIAL_VIEW_OK:",tag)
 await controller.return_to_menu("")
 main_scene.queue_free()
 await process_frame
 print("UI_MATERIAL_REVIEW_OK")
 quit(0)
