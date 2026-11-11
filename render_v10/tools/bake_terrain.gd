extends SceneTree

func _initialize() -> void:
	var heightfield := Image.load_from_file("res://render_v10/textures/road_distance_level1.png")
	ResourceSaver.save(heightfield, "res://render_v10/assets/heightfield.res")
	var terrain = load("res://render_v10/terrain.gd")
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(-88,88):
		for x in range(-136,136):
			for offset in [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,0), Vector2(1,1), Vector2(0,1)]:
				var px: float = x + offset.x
				var pz: float = z + offset.y
				surface.set_uv(Vector2(px,pz))
				surface.add_vertex(Vector3(px, terrain.sample_ground_height(px,pz), pz))
	surface.generate_normals()
	surface.generate_tangents()
	surface.index()
	var mesh := surface.commit()
	assert(ResourceSaver.save(mesh, "res://render_v10/assets/terrain.res") == OK)
	print("TERRAIN_BAKED normal=", mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL][0])
	quit()
