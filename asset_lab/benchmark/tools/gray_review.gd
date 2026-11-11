extends Node3D
func _ready():
 $Camera3D.look_at(Vector3(0,2.05,0))
 $Camera3D.set_reset_pose()
 get_viewport().msaa_3d = Viewport.MSAA_4X
 if "--audit" in OS.get_cmdline_user_args():
  await get_tree().process_frame
  await get_tree().process_frame
  for i in 3:
   $Camera3D.position=[Vector3(6,4.4,8),Vector3(0,8,7),Vector3(-7,3,6)][i]
   $Camera3D.look_at(Vector3(0,2.05,0))
   for frame in 20:await get_tree().process_frame
   await RenderingServer.frame_post_draw
   get_viewport().get_texture().get_image().save_png("res://asset_lab/benchmark/reports/gray_%d.png"%i)
  get_tree().quit()
