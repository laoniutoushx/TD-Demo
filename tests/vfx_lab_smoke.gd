extends SceneTree
var failures := 0
func _initialize() -> void:
 call_deferred("run")
func check(ok: bool,label: String) -> void:
 if not ok:
  failures += 1
  push_error("VFX_LAB_FAILED: "+label)
func frames(count: int = 4) -> void:
 for i in count: await process_frame
func run() -> void:
 root.size = Vector2i(1080,768)
 var lab = load("res://VFX/lab/VFXLab.tscn").instantiate()
 root.add_child(lab)
 await frames(8)
 check(lab._view.size.x > 150 and lab._view.size.y > 200,"Dedicated stage has usable area")
 check(lab.EFFECTS.size() >= 61,"All VFX scenes including variants are cataloged")
 check(lab._path_index("res://VFX/lab/VFXLab.tscn") < 0,"Workbench never recursively catalogs itself")
 var unique_paths := {}
 for entry in lab.EFFECTS: unique_paths[entry[1]] = true
 check(unique_paths.size() == lab.EFFECTS.size(),"Distinct scene paths never collapse by basename")
 check(lab.ground.material_override != null,"Explicit default floor material")
 lab._search.text = "脉冲"
 lab._search.text_changed.emit("脉冲")
 check(lab._visible_indices.size() == 2,"Search filters flight and impact")
 lab._category.select(1)
 lab._category.item_selected.emit(1)
 check(lab._visible_indices == [8],"Category and search combine")
 lab._effect_list.select(0)
 lab._effect_list.item_selected.emit(0)
 check(lab.preset.effect_index == 8 and lab.effect.style == 1,"Library selection drives live preview")
 lab._fields.scale[1].value = 1.75
 check(is_equal_approx(lab.preset.effect_scale,1.75),"Spin box updates actual scale")
 lab.record_a()
 lab._fields.scale[1].value = 2.25
 lab.baseline.effect_index = 0 # Simulate an old position after catalog insertion.
 lab.swap_ab()
 check(is_equal_approx(lab.preset.effect_scale,1.75) and is_equal_approx(lab._fields.scale[1].value,1.75),"A/B recalls preset and visible controls")
 var old_distance: float = lab.distance
 var wheel := InputEventMouseButton.new()
 wheel.button_index = MOUSE_BUTTON_WHEEL_UP
 wheel.pressed = true
 lab._stage_container.gui_input.emit(wheel)
 check(lab.distance < old_distance,"Stage wheel signal zooms camera")
 lab.frame_effect()
 var previous_background: Color = lab.preset.background_color
 lab._floor_picker.color_changed.emit(Color(0.21,0.13,0.08))
 check(lab.preset.background_color == previous_background,"Floor color independent of backdrop")
 check(lab._floor_mat.get_shader_parameter("floor_color") == lab.preset.ground_color,"Floor shader follows picker")
 lab._layer_checks.meshes.button_pressed = false
 await frames()
 check(not lab.effect.get_node("VisualLayers/MoltenCrown").visible,"Layer override survives effect animation")
 lab.replay()
 await frames()
 check(not lab.effect.get_node("VisualLayers/MoltenCrown").visible,"Layer override survives replay")
 lab._layer_checks.meshes.button_pressed = true
 lab.set_paused(true)
 await frames()
 var frozen_time: float = lab.effect.age
 await frames()
 check(is_equal_approx(lab.effect.age,frozen_time),"Pause freezes script-based effect time")
 lab.set_paused(false)
 DirAccess.make_dir_recursive_absolute("res://.godot/vfx_lab")
 lab.save_preset("res://.godot/vfx_lab/roundtrip.tres")
 lab.preset.effect_scale = 0.5
 check(lab.load_preset("res://.godot/vfx_lab/roundtrip.tres"),"Saved preset loads")
 check(is_equal_approx(lab._fields.scale[1].value,1.75),"Loaded controls match saved preset")
 var focus_owner := root.gui_get_focus_owner()
 if focus_owner: focus_owner.release_focus()
 var tab := InputEventKey.new()
 tab.keycode = KEY_TAB
 tab.pressed = true
 root.push_input(tab)
 check(not lab.get_node("Interface/Root/Margin/Layout/Body/LibraryPanel").visible,"Tab shortcut hides panels")
 root.push_input(tab.duplicate())
 check(lab.get_node("Interface/Root/Margin/Layout/Body/LibraryPanel").visible,"Tab shortcut restores panels")
 # Persisted resource paths override unstable numeric positions in expanded catalogs.
 var stable = lab.preset.duplicate(true)
 stable.effect_index = 0
 ResourceSaver.save(stable,"res://.godot/vfx_lab/path_identity.tres")
 check(lab.load_preset("res://.godot/vfx_lab/path_identity.tres") and lab.preset.effect_index == 8,"Saved path resolves even if numeric index changes")
 var count_before: int = lab.EFFECTS.size()
 lab._fields.scale[1].value = 1.6
 lab.refresh_catalog()
 check(lab.EFFECTS.size() == count_before and is_equal_approx(lab.preset.effect_scale,1.6),"Catalog refresh preserves current settings")
 # Short-lived scripted effects must not permanently stall the repeat clock.
 var transient_index: int = lab._path_index("res://VFX/building/vfx_building_impact.tscn")
 check(transient_index >= 0,"Building impact discovered")
 lab.select_effect(transient_index)
 lab.preset.duration = 0.9
 await create_timer(0.7).timeout
 check(not is_instance_valid(lab.effect) and lab.elapsed > 0.6,"Self-deletion does not stop preview clock")
 await create_timer(0.35).timeout
 check(is_instance_valid(lab.effect) and lab.elapsed < 0.5,"Self-deleting effect replays automatically")
 # Every registered asset still previews after the viewport/material refactor.
 for index in range(lab.EFFECTS.size()):
  lab.select_effect(index)
  await frames(3)
  check(is_instance_valid(lab.effect),"Asset previews: %d" % index)
 # Volumetric tornado parameters remain editable and survive A/B and replay.
 lab.select_effect(lab._path_index("res://VFX/tornado/vfx_tornado_running.tscn"))
 lab._fields.optical_density[1].value = 4.3
 lab._fields.volume_steps[1].value = 40
 check(is_equal_approx(lab.effect.optical_density,4.3) and lab.effect.volume_steps == 40,"Tornado controls drive live shader settings")
 lab.record_a()
 lab._fields.optical_density[1].value = 1.2
 lab.swap_ab()
 check(is_equal_approx(lab.effect.optical_density,4.3) and lab.effect.volume_steps == 40,"Tornado quality survives A/B")
 lab.frame_effect()
 check(lab.focus.y > 3.0,"Tornado framing includes its baked proxy height")
 lab.set_paused(true)
 await frames(2)
 var tornado_time: float = lab.effect._age
 await frames(5)
 check(is_equal_approx(lab.effect._age,tornado_time),"Tornado pause freezes procedural motion")
 lab.set_paused(false)
 lab.replay()
 check(lab.effect._age < 0.1 and lab.effect._dust.emitting,"Tornado replay restarts formation and dust")
 if DisplayServer.get_name() != "headless":
  root.size = Vector2i(1600,900)
  lab._search.text = "龙卷风"
  lab._search.text_changed.emit("龙卷风")
  lab._category.select(0)
  lab._category.item_selected.emit(0)
  lab.set_background(0)
  lab._floor_picker.color_changed.emit(Color(0.12,0.14,0.16))
  await frames(8)
  lab.frame_effect()
  await create_timer(1.0).timeout
  await RenderingServer.frame_post_draw
  DirAccess.make_dir_recursive_absolute("res://.godot/tornado_review")
  root.get_texture().get_image().save_png("res://.godot/tornado_review/lab.png")
  root.size = Vector2i(1080,768)
 # Legacy presets whose original effect_index=0 was omitted keep their meaning.
 var legacy := FileAccess.open("res://.godot/vfx_lab/legacy.tres",FileAccess.WRITE)
 legacy.store_string('[gd_resource type="Resource" load_steps=2 format=3]\n[ext_resource type="Script" path="res://VFX/lab/vfx_lab_preset.gd" id="1"]\n[resource]\nscript = ExtResource("1")\neffect_scale = 1.2\n')
 legacy.close()
 check(lab.load_preset("res://.godot/vfx_lab/legacy.tres") and lab.preset.effect_index == 0,"Legacy default-index compatibility")
 # Return to a clean, readable default for visual review.
 lab._search.text = ""
 lab._search.text_changed.emit("")
 lab._category.select(0)
 lab.select_effect(8)
 lab.set_background(0)
 lab.camera_preset(0)
 if DisplayServer.get_name() != "headless":
  await create_timer(1.0).timeout
  for size in [Vector2i(1080,768),Vector2i(1600,900),Vector2i(900,600)]:
   root.size = size
   await frames(8)
   check(lab._root.size.x <= size.x+1,"UI fits window width %s" % size)
   check(lab._view.size.x > 150,"Stage remains usable %s" % size)
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("res://.godot/vfx_lab/ui_%d_%d.png" % [size.x,size.y])
  root.size = Vector2i(1600,900)
  await frames(8)
  var shot: String = await lab.capture()
  check(not shot.is_empty(),"Clean stage screenshot saved")
  if not shot.is_empty():
   var image := Image.load_from_file(shot)
   check(image.get_size() == lab._view.size,"Clean screenshot excludes UI panels")
  (lab.get_node("Interface/Root/Margin/Layout/Body/InspectorPanel/Tabs") as TabContainer).current_tab = 1
  await frames(4)
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://.godot/vfx_lab/ui_stage_settings.png")
  lab.toggle_panels()
  await frames(8)
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://.godot/vfx_lab/ui_focus.png")
 lab.stop()
 lab.queue_free()
 await frames(4)
 await create_timer(0.3).timeout
 check(is_equal_approx(Engine.time_scale,1.0),"Global time restored on exit")
 if failures == 0: print("VFX_LAB_OK")
 quit(1 if failures else 0)
