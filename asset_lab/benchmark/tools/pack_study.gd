extends SceneTree
func _initialize():
 var source=load("res://asset_lab/benchmark/models/leaf_spray_study.glb").instantiate()
 for style in 3:
  var text='[gd_scene load_steps=4 format=3]\n[ext_resource type="PackedScene" path="res://asset_lab/benchmark/models/leaf_spray_study.glb" id="1"]\n'
  text+='[ext_resource type="Material" path="res://asset_lab/benchmark/materials/leaves_%d.tres" id="leaf"]\n'%style
  text+='[ext_resource type="Material" path="res://asset_lab/benchmark/materials/bark_%d.tres" id="bark"]\n'%style
  text+='[node name="LeafStudy" type="Node3D"]\n[node name="Model" parent="." instance=ExtResource("1")]\n'
  text+=overrides(source,source)
  text+='[editable path="Model"]\n'
  var file=FileAccess.open("res://asset_lab/benchmark/study_style_%d.tscn"%style,FileAccess.WRITE)
  file.store_string(text);file.close()
 source.free();quit()
func overrides(n,root):
 var text=""
 if n is MeshInstance3D:
  var rel=str(root.get_path_to(n))
  var parent="Model" if rel.get_base_dir()=="" else "Model/"+rel.get_base_dir()
  text+='[node name="%s" parent="%s" index="%d"]\nlod_bias = 100.0\n'%[n.name,parent,n.get_index()]
  for i in n.mesh.get_surface_count():text+='surface_material_override/%d = ExtResource("%s")\n'%[i,"leaf" if "LeafClump" in n.name else "bark"]
 for c in n.get_children():text+=overrides(c,root)
 return text
