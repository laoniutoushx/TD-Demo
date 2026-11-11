extends SceneTree
func _initialize():
 var n = load("res://asset_lab/benchmark/models/broadleaf_lod0.glb").instantiate()
 var m = StandardMaterial3D.new()
 m.albedo_color = Color(0.42,0.48,0.35)
 m.roughness = 0.9
 m.cull_mode = BaseMaterial3D.CULL_DISABLED
 ResourceSaver.save(m,"res://asset_lab/benchmark/gray.tres")
 var text='[gd_scene load_steps=3 format=3]\n[ext_resource type="PackedScene" path="res://asset_lab/benchmark/models/broadleaf_lod0.glb" id="1"]\n[ext_resource type="Material" path="res://asset_lab/benchmark/gray.tres" id="gray"]\n[node name="GrayTree" type="Node3D"]\n[node name="Model" parent="." instance=ExtResource("1")]\n'
 text+=overrides(n,n)
 text+='[editable path="Model"]\n'
 var file=FileAccess.open("res://asset_lab/benchmark/gray_tree.tscn",FileAccess.WRITE)
 file.store_string(text);file.close();n.free()
 quit()
func overrides(n,root):
 var text=""
 if n is MeshInstance3D:
  var rel=str(root.get_path_to(n))
  var parent="Model" if rel.get_base_dir()=="" else "Model/"+rel.get_base_dir()
  text+='[node name="%s" parent="%s" index="%d"]\nmaterial_override = ExtResource("gray")\nlod_bias = 100.0\n'%[n.name,parent,n.get_index()]
 for c in n.get_children():text+=overrides(c,root)
 return text
