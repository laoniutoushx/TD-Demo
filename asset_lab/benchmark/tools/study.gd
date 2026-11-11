extends Node3D
var style=1
func _ready():
 get_viewport().msaa_3d=Viewport.MSAA_4X
 pose(0)
 $Camera3D.set_reset_pose()
 if "--study-audit" in OS.get_cmdline_user_args():
  for s in 3:
   select_style(s)
   for view in 3:
    pose(view)
    for i in 20:await get_tree().process_frame
    await RenderingServer.frame_post_draw
    get_viewport().get_texture().get_image().save_png("res://asset_lab/benchmark/reports/spray_study_style%d_view%d.png"%[s,view])
  get_tree().quit()
func select_style(index):
 style=index
 $Tree.free()
 var tree=load("res://asset_lab/benchmark/study_style_%d.tscn"%index).instantiate()
 tree.name="Tree";add_child(tree)
func pose(index):
 $Camera3D.position=[Vector3(2,1.8,2.4),Vector3(0,2.5,-.3),Vector3(-2,1.4,1.7)][index]
 $Camera3D.look_at(Vector3(0,.35,-.30),Vector3.FORWARD if index==1 else Vector3.UP)
func _unhandled_input(event):
 if event is InputEventKey and event.pressed and not event.echo:
  if event.physical_keycode>=KEY_F1 and event.physical_keycode<=KEY_F3:select_style(event.physical_keycode-KEY_F1)
