extends SceneTree
var failures := 0
func _initialize() -> void:
 call_deferred("run")
func check(ok: bool, label: String) -> void:
 if not ok:
  failures += 1
  push_error(label)
func run() -> void:
 var pool = load("res://System/vfx_system/VFXSystem.gd").new()
 root.add_child(pool)
 for code in ["lattice_orb", "helix_orb", "frost_orb"]:
  for kind in ["running", "destory"]:
   var scene = pool.create_vfx(code,kind)
   check(scene != null,"Resource discovery: " + code + kind)
   if scene == null: continue
   root.add_child(scene)
   var identity = scene.get_instance_id()
   scene.seek_preview(0.45)
   check(scene._surfaces.size() >= 2,"Layered materials")
   if code == "helix_orb":
    check(scene._pulse_rings.size() == 3,"Three independent pulse rings")
    check(scene._pulse_rings[0].position.z != scene._pulse_rings[1].position.z,"Pulse rings have staggered birth phases")
    scene.seek_preview(0.02)
    var first_z: float = scene._pulse_rings[0].position.z
    var first_scale: float = scene._pulse_rings[0].scale.x
    scene.seek_preview(0.04)
    check(scene._pulse_rings[0].position.z > first_z and scene._pulse_rings[0].scale.x > first_scale,"Pulse propagates rearward and expands")
   if code == "frost_orb":
    check(scene.get_node_or_null("VisualLayers/CrownShell0") != null,"Open crown shell replaces orbital sphere")
   check(scene._shards.multimesh.instance_count == scene.density,"Instanced fragments")
   var child_count: int = scene.find_children("*","MeshInstance3D",true,false).size()
   check(child_count <= 12,"Geometry should be batched, not per-segment nodes")
   scene.reset_effect()
   scene.position = Vector3(5,2,0)
   scene._process(0.1)
   scene.position = Vector3(6,2,0)
   scene._process(0.1)
   check(scene._samples.size() == 2,"World history samples")
   pool.recycle_vfx(scene)
   var reused = pool.create_vfx(code,kind)
   check(reused.get_instance_id() == identity,"Identical object reused")
   check(reused.visible and is_zero_approx(reused.age) and reused._samples.is_empty(),"Reuse resets time, visibility and world history")
   root.add_child(reused)
   reused.position = Vector3(-15,3,10)
   reused._process(0.016)
   check(reused._samples.size() == 1,"No previous-location trail after reuse")
   var other = load("res://VFX/projectiles/reference_set/vfx_%s_%s.tscn" % [code,kind]).instantiate()
   root.add_child(other)
   check(other._surfaces[0] != reused._surfaces[0],"Independent instance materials")
   reused.seek_preview(0.3)
   check(is_zero_approx(other.age),"Preview time isolation")
   other.queue_free()
   pool.recycle_vfx(reused)
   await process_frame
 pool.reset_session()
 pool.queue_free()
 await process_frame
 await create_timer(0.3).timeout
 if failures == 0: print("REFERENCE_PROJECTILES_OK")
 quit(1 if failures else 0)
