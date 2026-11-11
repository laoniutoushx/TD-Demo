"""Read back native geometry and packaged textures; do not rebuild the asset."""
import bpy,bmesh,json
from pathlib import Path
OUT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(OUT/'source/broadleaf_editable.blend'))
scene=next(s for s in bpy.data.scenes if any(o.get('role')=='benchmark_asset' for o in s.objects))
objects=[o for o in scene.objects if o.get('role')=='benchmark_asset']
leaves=[o for o in objects if o.name.startswith('LeafClump')]
root=next(o for o in objects if o.name=='Trunk_Branches_LOD0')
bm=bmesh.new();bm.from_mesh(root.data)
closed=all(e.is_manifold for e in bm.edges);bm.free()
assert closed,'Open root geometry'
report=json.loads((OUT/'reports/geometry.json').read_text())
report.update(root_closed=closed,leaves=sum(o['leaf_count'] for o in leaves),clumps=len(leaves),triangles=sum(sum(len(f.vertices)-2 for f in o.data.polygons) for o in objects),height=max((o.matrix_world@v.co).z for o in objects for v in o.data.vertices))
assert report['triangles']<=8000
assert report['leaves']==660
assert len(bpy.data.scenes)==2,'Keep one asset scene and one editable bake scene'
texture_keys=['bark_base','bark_normal','bark_orm','leaf_natural_base','leaf_painted_base','leaf_normal_gl']
for key in texture_keys:
    assert any(im.name.startswith(key) and im.packed_file for im in bpy.data.images),'Missing packed texture: '+key
report.update(source_scenes=len(bpy.data.scenes),packed_textures=len(texture_keys))
(OUT/'reports/geometry.json').write_text(json.dumps(report,indent=2))
print('NATIVE_PASS',report)
