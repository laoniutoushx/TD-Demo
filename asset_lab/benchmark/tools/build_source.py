"""One-time offline Blender assembly. Runtime scenes never execute this file.

Desktop automation was unavailable during construction. All generated geometry,
individual clumps, UVs, normals and source materials remain editable in the blend.
"""
import bpy, bmesh, math, random, json
from pathlib import Path
from mathutils import Vector, Euler

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'asset_lab/benchmark'
OUT.mkdir(parents=True, exist_ok=True)
for folder in ('source', 'models', 'textures', 'reports'):
    (OUT / folder).mkdir(exist_ok=True)
rng = random.Random(117)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1
collection = bpy.data.collections.new('01_Trunk_and_Primary_Branches')
scene.collection.children.link(collection)

# Reuse the source's separated material regions, not the old scattered crown.
bpy.ops.import_scene.gltf(filepath=str(ROOT/'atmosphere/assets/tree_mid_geometry.glb'))
trunk = next(o for o in scene.objects if o.type == 'MESH')
trunk.name = 'Trunk_Branches_LOD0'
bm = bmesh.new(); bm.from_mesh(trunk.data)
remove = [f for f in bm.faces if any(k in trunk.data.materials[f.material_index].name for k in ('leaves','branches'))]
bmesh.ops.delete(bm, geom=remove, context='FACES')
bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
bm.to_mesh(trunk.data); bm.free()
lowest = min(v.co.z for v in trunk.data.vertices)
root_verts = [v.co for v in trunk.data.vertices if v.co.z < lowest + .06]
origin = sum(root_verts, Vector())/len(root_verts)
for v in trunk.data.vertices:
    v.co -= origin
    flare=1.0+0.8*max(0,1-v.co.z/1.7)+0.4*max(0,1-v.co.z/.3)
    v.co.x*=flare;v.co.y*=flare
for face in trunk.data.polygons:face.use_smooth=True
for c in list(trunk.users_collection): c.objects.unlink(trunk)
collection.objects.link(trunk)
trunk['source'] = 'Poly Haven tree_small_02 mid: trunk 984 tris reused; old branch cards removed'

def plain(name, color):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1)
    m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value=(*color,1)
    bs.inputs['Roughness'].default_value=.8
    return m

gray=plain('Gray_Structure_Check',(.32,.36,.31))
leaf_mat=plain('Leaves_Editable_PBR_Source',(.24,.43,.075))
helpers=bpy.data.collections.new('90_Editable_Form_Guides_NO_EXPORT')
scene.collection.children.link(helpers)
canopy=bpy.data.collections.new('02_Canopy_30_Editable_Clumps')
scene.collection.children.link(canopy)
modules=bpy.data.collections.new('91_Leaf_Modules_NO_EXPORT')
scene.collection.children.link(modules)

outline=[(0,-.25)]
for j in range(1,8):
    t=j/8;outline.append((.125*math.sin(math.pi*t)**.8,-.25+.53*t))
outline.append((0,.28))
for j in range(7,0,-1):
    t=j/8;outline.append((-.125*math.sin(math.pi*t)**.8,-.25+.53*t))
prototype=[Vector((0,0,.055))]+[Vector((x,y,.018*math.cos(y*9))) for x,y in outline]
faces=[(0,1+i,1+(i+1)%16) for i in range(16)]
uvs=[(.5,.48)]+[(x/.26+.5,(y+.26)/.55) for x,y in outline]
for variant in range(4):
    me=bpy.data.meshes.new('Leaf_Module_%02d'%variant)
    verts=[(v.x*(.85+variant*.1),v.y,v.z*(.7+variant*.25)) for v in prototype]
    me.from_pydata(verts,[],faces); me.update()
    ob=bpy.data.objects.new(me.name,me); modules.objects.link(ob)
    uv=me.uv_layers.new(name='UVMap')
    for poly in me.polygons:
        for li in poly.loop_indices: uv.data[li].uv=uvs[me.loops[li].vertex_index]
    ob.data.materials.append(leaf_mat)
    ob.hide_render=True; ob.hide_viewport=True

# Guide positions are authored in meters in Blender Z-up.
forms=[(-1.05,.10,2.8),(1.0,.20,2.95),(-.18,.25,3.7),(.00,-.95,3.12),(.22,1.15,2.78)]
all_clumps=[]
for main, p in enumerate(forms):
    guide_center=Vector(p)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, location=p)
    guide=bpy.context.object;guide.name='FormGuide_%d'%main
    guide.scale=(1,.95,.75)
    for c in list(guide.users_collection):c.objects.unlink(guide)
    helpers.objects.link(guide);guide.hide_render=True;guide.hide_viewport=True
    for sub in range(6):
        a=sub*math.tau/6+main*.37
        center=guide_center+Vector((math.cos(a)*.48,math.sin(a)*.46, [.05,.27,-.16,.18,-.05,.3][sub]))
        vs=[]; fs=[]; loop_uvs=[]; colors=[]; ns=[]
        group_tint=rng.uniform(.22,.78)
        # Rounded leaf edges need sixteen triangles; twelve leaves per clump
        # preserve the same crown budget as the earlier 24 x 8-triangle draft.
        for leaf in range(12):
            theta=leaf*2.399963+main*.3
            radius=.07+.37*math.sqrt((leaf+.5)/12)
            off=Vector((math.cos(theta)*radius,math.sin(theta)*radius,rng.uniform(-.20,.22)))
            rot=Euler((rng.uniform(-.65,.65),rng.uniform(-.65,.65),theta-math.pi/2),'XYZ').to_matrix()
            scale=rng.uniform(.85,1.20)
            start=len(vs)
            for vi,v in enumerate(prototype):
                local=rot @ Vector((v.x*(.85+(leaf%4)*.1)*scale,v.y*scale,v.z*scale))
                point=center+off+local
                vs.append(tuple(point))
                original=rot @ Vector((0,0,1))
                radial=(off+local+Vector((0,0,.40))).normalized()
                normal=(original*.30+radial*.70).normalized()
                ns.append(tuple(normal))
                colors.append((rng.uniform(.78,1.0),group_tint,max(0,min(1,(point.z-.7)/4))*uvs[vi][1],1))
            for f in faces:
                fs.append(tuple(start+i for i in f));loop_uvs.extend(uvs[i] for i in f)
        me=bpy.data.meshes.new('LeafClump_%02d'%(main*6+sub))
        me.from_pydata(vs,[],fs);me.update()
        for poly in me.polygons:poly.use_smooth=True
        me.normals_split_custom_set_from_vertices(ns)
        uv=me.uv_layers.new(name='UVMap')
        for i,val in enumerate(loop_uvs):uv.data[i].uv=val
        attr=me.color_attributes.new(name='AssetData',type='FLOAT_COLOR',domain='POINT')
        for i,val in enumerate(colors):attr.data[i].color=val
        ob=bpy.data.objects.new(me.name,me);canopy.objects.link(ob)
        ob.data.materials.append(leaf_mat)
        ob['cluster_id']=main*6+sub;ob['leaf_count']=12;ob['normal_blend']=.70
        all_clumps.append(ob)

branches=[]
def branch(name,points,radius):
    curve=bpy.data.curves.new(name,'CURVE');curve.dimensions='3D'
    curve.resolution_u=3;curve.bevel_depth=radius;curve.bevel_resolution=1
    curve.use_fill_caps=True
    spline=curve.splines.new('BEZIER');spline.bezier_points.add(len(points)-1)
    for i,(p,co) in enumerate(zip(spline.bezier_points,points)):
        p.co=co;p.handle_left_type='AUTO';p.handle_right_type='AUTO';p.radius=1-i/(len(points)-1)*.9
    ob=bpy.data.objects.new(name,curve);collection.objects.link(ob)
    bpy.context.view_layer.objects.active=ob;ob.select_set(True)
    bpy.ops.object.convert(target='MESH');ob=bpy.context.object
    for poly in ob.data.polygons:poly.use_smooth=True
    branches.append(ob)
for i,p in enumerate(forms):
    end=Vector(p)
    level=1.05+i*.045
    cross=[]
    for edge in trunk.data.edges:
        a,b=[trunk.data.vertices[j].co for j in edge.vertices]
        if (a.z-level)*(b.z-level)<0:
            cross.append(a.lerp(b,(level-a.z)/(b.z-a.z)))
    start=sum(cross,Vector())/len(cross) if cross else Vector((0,0,level))
    branch('Primary_Branch_%02d'%i,[start,start.lerp(end,.42)+Vector((0,0,.1)),end],.075 if i<2 else .055)

# Source bark maps remain explicit in Blender and are packed into the source file.
for mat in trunk.data.materials:
    part='branch' if 'branch' in mat.name else 'trunk'
    if 'leaves' in mat.name:continue
    mat.use_nodes=True; nt=mat.node_tree;nt.nodes.clear()
    out=nt.nodes.new('ShaderNodeOutputMaterial');bs=nt.nodes.new('ShaderNodeBsdfPrincipled')
    nt.links.new(bs.outputs['BSDF'],out.inputs['Surface'])
    for kind in ('base','normal','orm'):
        image=bpy.data.images.load(str(ROOT/f'atmosphere/textures/tree_{part}_{kind}.jpg'),check_existing=True)
        tex=nt.nodes.new('ShaderNodeTexImage');tex.image=image;tex.label=kind
        if kind=='base':nt.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
        else:
            image.colorspace_settings.name='Non-Color'
            if kind=='normal':
                normal=nt.nodes.new('ShaderNodeNormalMap');nt.links.new(tex.outputs['Color'],normal.inputs['Color']);nt.links.new(normal.outputs['Normal'],bs.inputs['Normal'])
            else:
                sep=nt.nodes.new('ShaderNodeSeparateColor');nt.links.new(tex.outputs['Color'],sep.inputs['Color']);nt.links.new(sep.outputs['Green'],bs.inputs['Roughness'])
for ob in branches:
    ob.data.materials.append(next(m for m in trunk.data.materials if 'trunk' in m.name))
    bpy.context.view_layer.objects.active=ob
    bpy.ops.object.select_all(action='DESELECT');ob.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(island_margin=.025);bpy.ops.object.mode_set(mode='OBJECT')

bpy.ops.object.select_all(action='DESELECT')
visible=[trunk]+branches+all_clumps
for o in visible:o.select_set(True)
bpy.context.view_layer.objects.active=trunk
for obj in visible:obj['role']='benchmark_asset'
scene['construction']='Offline initial assembly; all meshes editable. Not represented as manual UI work.'
scene['vertex_contract']='R local AO (1 unoccluded), G variation (.5 neutral), B wind weight'
scene['lod0_triangles']=sum(len(o.data.polygons)*0+sum(len(f.vertices)-2 for f in o.data.polygons) for o in visible)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'source/broadleaf_editable.blend'))
bark_export=plain('Bark',(.24,.16,.095))
for obj in [trunk]+branches:
    obj.data.materials.clear();obj.data.materials.append(bark_export)
    for poly in obj.data.polygons:poly.material_index=0
bpy.ops.export_scene.gltf(filepath=str(OUT/'models/broadleaf_lod0.glb'),use_selection=True,export_format='GLB',export_normals=True,export_tangents=True,export_all_vertex_colors=True)
report={'triangles':scene['lod0_triangles'],'leaves':360,'clumps':30,'leaf_triangles':16,'source':'Poly Haven tree_small_02','process':'offline assembly, editable Blender meshes','height':max(v.co.z for o in all_clumps for v in o.data.vertices)}
(OUT/'reports/geometry.json').write_text(json.dumps(report,indent=2))
print('BENCHMARK_GEOMETRY',report)

