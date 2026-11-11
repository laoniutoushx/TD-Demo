extends SceneTree
var bounds: AABB
var first := true
var material_count := 0
var texture_count := 0
func _initialize():
 var choices = {"02_meshy_broadleaf":"res://meshy_assets/broadleaf_tree.glb", "03_meshy_evergreen":"res://meshy_assets/pilot_tree.glb", "04_fab_tree_1":"res://fab_candidates/08/tree_1.gltf", "05_fab_tree_2":"res://fab_candidates/08/tree_2.gltf"}
 for key in choices:
  var source = load(choices[key]) as PackedScene
  if source == null:
   push_error("Cannot load " + choices[key])
   quit(1)
   return
  var model = source.instantiate()
  first = true
  material_count = 0
  texture_count = 0
  inspect(model, Transform3D.IDENTITY)
  if first or bounds.size.y < 0.001:
   push_error("Invalid geometry")
   quit(1)
   return
  var holder = Node3D.new()
  holder.name = "TreeCandidate"
  holder.add_child(model)
  model.owner = holder
  var factor = 4.5 / bounds.size.y
  model.scale *= factor
  model.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * factor
  var packed = PackedScene.new()
  packed.pack(holder)
  ResourceSaver.save(packed, "res://asset_lab/comparison/" + key + ".tscn")
  print("PASS ", key, " source_height=",bounds.size.y," surfaces=",material_count," textured=",texture_count)
  if texture_count == 0: push_error("No albedo textures: " + key)
  holder.free()
 quit()
func inspect(n: Node, parent_transform: Transform3D):
 var current = parent_transform
 if n is Node3D: current = parent_transform * n.transform
 if n is MeshInstance3D and n.mesh:
  var box = current * n.mesh.get_aabb()
  bounds = box if first else bounds.merge(box)
  first = false
  for i in n.mesh.get_surface_count():
   material_count += 1
   var m = n.get_active_material(i)
   if m is BaseMaterial3D and m.albedo_texture != null: texture_count += 1
 for c in n.get_children(): inspect(c,current)
