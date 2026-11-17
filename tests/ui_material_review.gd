extends SceneTree
var main_scene
var output_dir := "res://.godot/ui_material_review"
func rect_values(control: Control) -> Array:
 var r = control.get_global_rect()
 return [r.position.x,r.position.y,r.size.x,r.size.y]
func assert_slot_edges(frame: Image, slot_control: Control) -> void:
 var r = slot_control.get_global_rect()
 var p = Vector2i(r.position.round())
 var sz = Vector2i(r.size.round())
 var edges = [[Vector2i(p.x,p.y+sz.y/2),Vector2i.RIGHT],[Vector2i(p.x+sz.x-1,p.y+sz.y/2),Vector2i.LEFT],[Vector2i(p.x+sz.x/2,p.y),Vector2i.DOWN],[Vector2i(p.x+sz.x/2,p.y+sz.y-1),Vector2i.UP]]
 for edge in edges:
  var strongest := 0.0
  for offset in range(2):
   var point: Vector2i = edge[0] + edge[1]*offset
   var color = frame.get_pixelv(point)
   strongest = maxf(strongest,(color.r+color.g+color.b)/3.0)
  assert(strongest > 0.20,"Slot straight edge hidden behind icon or transparent texture padding")

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
 root.gui_embed_subwindows = true
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
  var start_button = controller._cur_scene.index_ui.get_node("%Start")
  start_button.grab_focus()
  await shot(tag+"_menu_focus")
  start_button.release_focus()
  var settings = controller.open_settings()
  await shot(tag+"_settings")
  root.grab_focus()
  await process_frame
  await process_frame
  settings.gra_opt.grab_focus()
  await process_frame
  assert(settings.gra_opt.has_focus(), "Quality dropdown must receive keyboard focus")
  var key = InputEventKey.new()
  key.keycode = KEY_SPACE
  key.pressed = true
  root.push_input(key)
  await process_frame
  key = InputEventKey.new()
  key.keycode = KEY_SPACE
  key.pressed = false
  root.push_input(key)
  await process_frame
  assert(settings.gra_opt.get_popup().visible, "Quality dropdown must open from keyboard")
  await shot(tag+"_settings_dropdown")
  settings.gra_opt.get_popup().hide()
  settings._on_return_pressed()
  await process_frame
 var choose_screen = load("res://Levels/choose_player/ChoosePlayer.tscn").instantiate()
 root.add_child(choose_screen)
 for dims in [Vector2i(1080,768), Vector2i(1920,1080), Vector2i(2560,1080)]:
  await resize_to(dims)
  await shot("%dx%d_choose_player" % [dims.x,dims.y])
 choose_screen.queue_free()
 await process_frame
 controller._cur_scene.index_ui._on_start_pressed()
 await create_timer(2.0).timeout
 var level = controller._cur_scene
 level.get_node("RTSController").edge_scroll_enabled = false
 var unit = level.gdbot
 root.get_node("SignalBus").player_selected_units.emit({unit.get_instance_id():unit}, Vector3.ZERO, 0)
 main_scene.player_controller.add_talent("greedy_talent")
 level.action_bar.player_bar_comp.reset_slot_for_player()
 await create_timer(1.2).timeout
 var card = level.action_bar.player_bar.get_child(0)
 assert(card.icon_texture.texture.resource_path.ends_with("talent_greedy_cutout.png"), "Greedy card must use cutout")
 assert(card.talent_title_label.text == "GREEDY", "Greedy card must have a single native title")
 assert(card.tooltip_text.contains("贪婪"), "Localized talent tooltip must remain intact")
 await resize_to(Vector2i(1080,768))
 var card_rect: Rect2 = card.get_global_rect()
 assert(card_rect.grow(-12.0).encloses(card.talent_title_label.get_global_rect()), "Talent title must clear copper border")
 var copper_frame = card.get_node("CopperCorners/Frame")
 assert(copper_frame.get_global_rect().is_equal_approx(card_rect), "Copper frame must cover card, not inset content")
 card._on_mouse_entered()
 await process_frame
 assert(card.get_global_rect() == card_rect, "Talent hover must not change layout")
 await shot("1080x768_talent_hover")
 card._on_mouse_exited()
 var talent_ref = card.reference
 talent_ref.change_state(talent_ref.TALENT_STATE.Cool_Down)
 await create_timer(0.15).timeout
 assert(card.progress_bar.visible and card.progress_bar.value > 0.0,"Cutout talent must show real cooldown")
 assert(card.progress_bar.texture_progress == card.icon_texture.texture, "Cutout cooldown must preserve the icon silhouette")
 await shot("1080x768_talent_cooldown")
 await create_timer(1.0).timeout
 assert(not card.progress_bar.visible,"Talent cooldown must recover normally")
 print("TALENT_PRESENTATION_STATES_OK")
 await process_frame
 for dims in [Vector2i(1080,768), Vector2i(1920,1080), Vector2i(2560,1080)]:
  await resize_to(dims)
  var tag := "%dx%d" % [dims.x,dims.y]
  await shot(tag+"_battle")
  var bar: Control = level.action_bar.get_node("CanvasLayer/Container")
  assert(bar.get_global_rect().end.x <= root.size.x + 1, "Bottom bar exceeds viewport")
  var visible_bar: Control = bar.get_node("MarginContainer/PanelContainer")
  assert(absf(visible_bar.size.y - 236.0 * 0.874) <= 8.0, "Visible bottom frame height must match uniformly scaled reference within eight pixels")
  var garnish = bar.find_child("MossFrameAccents",true,false)
  for leaf in garnish.get_children():
   assert(leaf.mouse_filter == Control.MOUSE_FILTER_IGNORE,"Foliage must pass mouse input")
   var leaf_rect: Rect2 = leaf.get_global_rect()
   assert(leaf_rect.position.x >= 0 and leaf_rect.position.y >= 0 and leaf_rect.end.x <= root.size.x and leaf_rect.end.y <= root.size.y,"Foliage must fit viewport")
  var metrics = {"bar":str(bar.get_global_rect()),"icon_ratio":0.0}
  var skill_slot = level.action_bar.skill_bar.get_child(0)
  var icon_rect: Rect2 = skill_slot.icon_texture.get_global_rect()
  var slot_rect: Rect2 = skill_slot.get_global_rect()
  metrics.bar_rect = rect_values(bar)
  metrics.bar_panel_rect = rect_values(bar.get_node("MarginContainer/PanelContainer"))
  metrics.layout = {}
  for n in ["TopC","BottomC","BottomContainer","SkillPanel","ItemABuff","PlayerPanel","PlayerBar"]:
   var ctl = bar.find_child(n,true,false)
   if ctl != null:
    metrics.layout[n] = {"size":str(ctl.size),"min":str(ctl.get_combined_minimum_size())}
  metrics.container_frames = {}
  for panel_name in ["SkillPanel","ItemABuff","PlayerPanel"]:
   var panel_control = bar.find_child(panel_name,true,false)
   var panel_style = panel_control.get_theme_stylebox("panel")
   var panel_rect: Rect2 = panel_control.get_global_rect()
   var frame_rect = panel_rect
   if panel_style is StyleBoxTexture:
    frame_rect = panel_rect.grow_individual(float(panel_style.get("expand_margin_left")),float(panel_style.get("expand_margin_top")),float(panel_style.get("expand_margin_right")),float(panel_style.get("expand_margin_bottom")))
   assert(bar.get_global_rect().encloses(frame_rect),"Secondary frame must fit action bar")
   metrics.container_frames[panel_name] = {"control":rect_values(panel_control),"drawn_frame":[frame_rect.position.x,frame_rect.position.y,frame_rect.size.x,frame_rect.size.y],"style":panel_style.resource_path}
  var wave_plaque = level.ui.find_child("WavePill",true,false)
  metrics.wave_rect = rect_values(wave_plaque)
  metrics.header_rects = {"avatar":rect_values(level.ui.get_node("CanvasLayer/PanelContainer")),"resources":rect_values(level.ui.get_node("CanvasLayer/HeaderContainer/LayoutCtl/Panel")),"ledge":rect_values(level.ui.get_node("CanvasLayer/TopVineLedge"))}
  var resource_panel = level.ui.get_node("CanvasLayer/HeaderContainer/LayoutCtl/Panel")
  var header_ledge = level.ui.get_node("CanvasLayer/TopVineLedge")
  assert(is_equal_approx(wave_plaque.size.y,resource_panel.size.y) and is_equal_approx(wave_plaque.size.y,header_ledge.size.y),"Header plaque and resource rails must align vertically")
  for header_control in [wave_plaque,resource_panel,header_ledge,level.ui.get_node("CanvasLayer/PanelContainer")]:
   assert(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(header_control.get_global_rect()),"Header outside viewport")
  var wave_label = wave_plaque.get_node("WaveLabel")
  assert(wave_plaque.get_global_rect().encloses(wave_label.get_global_rect()),"Wave text must fit plaque")
  var wave_garnish = wave_plaque.get_node("WaveGarnish")
  for leaf in wave_garnish.get_children():
   assert(leaf.mouse_filter == Control.MOUSE_FILTER_IGNORE,"Wave leaves must pass input")
   assert(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(leaf.get_global_rect()),"Wave leaf outside viewport")
  metrics.skill_rect = rect_values(skill_slot)
  metrics.item_rect = rect_values(level.action_bar.item_bar.get_child(0))
  var rendered_frame = root.get_texture().get_image()
  assert_slot_edges(rendered_frame,skill_slot)
  assert_slot_edges(rendered_frame,level.action_bar.item_bar.get_child(0))
  metrics.units_rect = rect_values(level.action_bar.selection_bar)
  metrics.slot_rects = {}
  metrics.icon_rects = {}
  for slot_pair in [["skill",skill_slot],["unit",level.action_bar.selection_bar.get_child(0)],["item",level.action_bar.item_bar.get_child(0)],["empty_item",level.action_bar.item_bar.get_child(1)],["buff",level.action_bar.buff_bar.get_child(0)],["talent",card]]:
   metrics.slot_rects[slot_pair[0]] = rect_values(slot_pair[1])
   metrics.icon_rects[slot_pair[0]] = rect_values(slot_pair[1].icon_texture)
  var skill_next: Rect2 = level.action_bar.skill_bar.get_child(1).get_global_rect()
  var skill_lower: Rect2 = level.action_bar.skill_bar.get_child(4).get_global_rect()
  var item_first: Rect2 = level.action_bar.item_bar.get_child(0).get_global_rect()
  var item_next: Rect2 = level.action_bar.item_bar.get_child(1).get_global_rect()
  var buff_first: Rect2 = level.action_bar.buff_bar.get_child(0).get_global_rect()
  var buff_next: Rect2 = level.action_bar.buff_bar.get_child(1).get_global_rect()
  metrics.slot_gaps = {"skill_horizontal":skill_next.position.x-slot_rect.end.x,"skill_vertical":skill_lower.position.y-slot_rect.end.y,"item_horizontal":item_next.position.x-item_first.end.x,"buff_horizontal":buff_next.position.x-buff_first.end.x}
  metrics.icon_ratio = icon_rect.size.x / slot_rect.size.x
  assert(metrics.icon_ratio >= 0.9, "Skill icon loses more than 10 percent width")
  var fp = FileAccess.open(output_dir+"/"+tag+"_metrics.json", FileAccess.WRITE)
  fp.store_string(JSON.stringify(metrics))
  fp.close()
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
 await resize_to(Vector2i(1080,768))
 var second_unit = main_scene.unit_system.create_unit(load("res://Unit/player/resources/gdbot_skin.tres"),0)
 level.turret_manager.add_child(second_unit)
 var bus = root.get_node("SignalBus")
 bus.player_selected_units.emit({unit.get_instance_id():unit,second_unit.get_instance_id():second_unit},Vector3.ZERO,0)
 await process_frame
 await process_frame
 assert(level.action_bar.selection_bar.get_child_count() == 2, "Both selected units must retain portraits")
 await shot("1080x768_multiselect")
 bus.player_selected_units.emit({},Vector3.ZERO,0)
 await process_frame
 assert(not level.action_bar.layer.visible, "No selection must hide bottom bar")
 await shot("1080x768_unselected")
 bus.player_selected_units.emit({unit.get_instance_id():unit},Vector3.ZERO,0)
 await process_frame
 await process_frame
 print("SELECTION_STATES_OK")
 var details = main_scene.unit_slot_indicator
 var selected_slot = level.action_bar.selection_bar.get_child(0)
 details.show_for_slot(selected_slot)
 await create_timer(0.25).timeout
 unit.health = maxf(1.0, unit.health - 2.0)
 await create_timer(0.2).timeout
 assert(details.health.text == "生命值： %.0f / %.0f" % [unit.health,unit.max_health], "Unit tooltip must follow HP")
 assert(details.damage.text.contains("移速"), "Unit tooltip must contain movement speed")
 await shot("unit_details")
 details.hide_for_slot(selected_slot)
 assert(details._detail_timer.is_stopped(), "Hidden details must stop refreshing")
 print("UNIT_DETAILS_REACTIVE_OK")
 for pair in [["skill",level.action_bar.skill_bar.get_child(0)], ["unit",level.action_bar.selection_bar.get_child(0)], ["item",level.action_bar.item_bar.get_child(0)], ["empty_item",level.action_bar.item_bar.get_child(1)], ["buff",level.action_bar.buff_bar.get_child(0)]]:
  var slot_control = pair[1]
  var before_rect: Rect2 = slot_control.get_global_rect()
  slot_control._on_mouse_entered()
  await shot("1080x768_slot_"+pair[0]+"_hover")
  assert(slot_control.get_global_rect() == before_rect,"Slot hover must retain geometry")
  slot_control._on_mouse_exited()
  var enabled_before = slot_control.is_active
  slot_control.do(false)
  await shot("1080x768_slot_"+pair[0]+"_disabled")
  slot_control.do(enabled_before)
  if pair[0] in ["skill","item"]:
   var mask = slot_control.progress_bar
   var old_mask = [mask.visible,mask.max_value,mask.value]
   var old_processing = slot_control.is_processing()
   slot_control.set_process(false)
   mask.max_value = 1.0
   mask.value = 0.5
   mask.visible = true
   await shot("1080x768_slot_"+pair[0]+"_cooldown_preview")
   assert(is_equal_approx(mask.value,0.5), "Cooldown mask preview must retain the chosen value")
   mask.max_value = old_mask[1]
   mask.value = old_mask[2]
   mask.visible = old_mask[0]
   slot_control.set_process(old_processing)
 print("SLOT_STATES_OK")
 var talent_choice = level.ui.talent_choose
 talent_choice.show()
 for dims in [Vector2i(1080,768), Vector2i(1920,1080), Vector2i(2560,1080)]:
  await resize_to(dims)
  for bar_name in ["ChooseTalentBar","ChooseTalentBar2","ChooseTalentBar3"]:
   var choice_bar = talent_choice.find_child(bar_name,true,false)
   var choice_icon = choice_bar.get_node("ChooseTalentBarContainer/HBoxContainer/PanelContainer/CenterContainer/TextureRect")
   assert(choice_icon.texture == choice_bar.talent_icon and choice_icon.size.x >= 64.0 and choice_icon.size.y >= 64.0, "Talent choices must show real, nonzero-size icons")
   assert(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(choice_icon.get_global_rect()), "Talent icon outside viewport")
  await shot("%dx%d_talent_choice" % [dims.x,dims.y])
 talent_choice.hide()
 controller.finish_battle(true)
 await process_frame
 var result_screen = controller._cur_scene
 for dims in [Vector2i(1080,768), Vector2i(1920,1080), Vector2i(2560,1080)]:
  await resize_to(dims)
  result_screen.setup(true)
  await shot("%dx%d_victory" % [dims.x,dims.y])
  result_screen.setup(false)
  await shot("%dx%d_defeat" % [dims.x,dims.y])
 print("ALL_UI_PAGES_OK")
 await controller.return_to_menu("")
 main_scene.queue_free()
 await process_frame
 print("UI_MATERIAL_REVIEW_OK")
 quit(0)
