extends SceneTree

func _initialize() -> void:
 call_deferred("run")

func run() -> void:
 var paths = ["res://VFX/projectiles/asif20_kunai_knife/vfx_asif20_kunai_knife_running.tscn", "res://VFX/projectiles/black_bird/vfx_black_bird_running.tscn", "res://VFX/projectiles/electric/vfx_Electric_strike_running.tscn", "res://VFX/projectiles/fireball/vfx_fireball_running.tscn", "res://VFX/projectiles/fireball/vfx_Fire_ball_standar_running.tscn", "res://VFX/projectiles/fireball/vfx_Fire_strike_running.tscn", "res://VFX/projectiles/fireball_another/vfx_fireball_another_running.tscn", "res://VFX/projectiles/hammer/vfx_hammer_running.tscn", "res://VFX/projectiles/ice_prise/vfx_ice_prise_running.tscn", "res://VFX/projectiles/missile/vfx_missile_01_running.tscn", "res://VFX/projectiles/missile/vfx_missile_02_running.tscn", "res://VFX/projectiles/missile/vfx_missile_03_running.tscn", "res://VFX/projectiles/missile/vfx_missile_07_running.tscn", "res://VFX/projectiles/missile/vfx_missile_7_running.tscn", "res://VFX/projectiles/scream_ball/vfx_scream_ball_running.tscn", "res://VFX/projectiles/water/vfx_water_another_running.tscn", "res://VFX/projectiles/water/vfx_water_running.tscn"]
 var failures := 0
 for path in paths:
  var scene = load(path).instantiate()
  root.add_child(scene)
  var trail = scene.find_child("RibbonTrail", true, false)
  if not trail is GPUParticles3D or trail.amount != 1 or not trail.trail_enabled or not trail.process_material is ShaderMaterial:
   failures += 1
   push_error("Invalid ribbon: " + path)
  for i in range(20):
   scene.position += Vector3(0.1, 0.02, 0.03)
   await process_frame
  scene.queue_free()
  await process_frame
 await create_timer(0.3).timeout
 if failures == 0:
  print("PROJECTILE_TRAILS_OK")
 quit(failures)
