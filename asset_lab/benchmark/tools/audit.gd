extends SceneTree
var triangles=0
var surfaces=0
var vertices_with_color=0
func _initialize():
 for style in 3:
  for lod in 3:
   triangles=0;surfaces=0;vertices_with_color=0
   var model=load("res://asset_lab/benchmark/tree_style_%d_lod_%d.tscn"%[style,lod]).instantiate()
   inspect(model)
   assert(triangles>0 and triangles<=[8000,4000,1500][lod])
   assert(vertices_with_color>0,"Lost vertex data")
   assert(model.scale==Vector3.ONE)
   print("PASS style=",style," lod=",lod," triangles=",triangles," surfaces=",surfaces," foliage_vertices=",vertices_with_color)
   model.free()
 print("TECHNICAL CHECKS PASS; visual approval remains a separate art review.")
 quit()
func inspect(n):
 if n is MeshInstance3D:
  assert(n.lod_bias==100.0)
  for i in n.mesh.get_surface_count():
   triangles+=n.mesh.surface_get_array_index_len(i)/3;surfaces+=1
   var mat=n.get_active_material(i)
   assert(mat.resource_path.begins_with("res://asset_lab/benchmark/materials/"),"Material not external")
   if "LeafClump" in n.name:
    assert(mat is ShaderMaterial)
    assert(mat.get_shader_parameter("base_map")!=null)
    assert(mat.get_shader_parameter("normal_map")!=null)
    var arrays=n.mesh.surface_get_arrays(i)
    assert(arrays[Mesh.ARRAY_COLOR]!=null)
    vertices_with_color+=arrays[Mesh.ARRAY_COLOR].size()
   else:
    assert(mat is ORMMaterial3D)
    assert(mat.albedo_texture!=null and mat.normal_texture!=null and mat.orm_texture!=null)
 for c in n.get_children():inspect(c)
