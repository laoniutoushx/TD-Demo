extends SceneTree
func _initialize():
 var n = load("res://asset_lab/tree_01.tscn").instantiate()
 var mesh = n.get_node("Tree_mid_tree_small_02_LOD0") as MeshInstance3D
 var expected = ["branch", "leaves", "trunk"]
 for i in 3:
  var m = mesh.get_surface_override_material(i) as ORMMaterial3D
  assert(m != null, "Missing surface material")
  assert(m.resource_path == "res://asset_lab/materials/%s.tres" % expected[i])
  assert(m.albedo_texture != null and m.normal_texture != null and m.orm_texture != null)
  print("PASS surface ",i," ",m.resource_path," albedo=",m.albedo_texture.resource_path," normal=",m.normal_texture.resource_path," ORM=",m.orm_texture.resource_path)
 n.free()
 quit()
