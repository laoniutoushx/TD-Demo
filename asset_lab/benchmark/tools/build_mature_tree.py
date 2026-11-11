"""Rebuild the editable broadleaf as a mature tree; export shared, explicit LODs.

Run in Blender background mode. Reuses the packed bark/leaf source materials,
keeps real leaf geometry and light-independent textures; no runtime assembly.
"""
import bpy
import math
import random
import json
from pathlib import Path
from mathutils import Vector, Euler
from mathutils.bvhtree import BVHTree

OUT = Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(OUT / 'source/broadleaf_editable.blend'))
bpy.context.preferences.filepaths.save_version = 0
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1
leaf_material = bpy.data.materials.get('Leaf_PBR_Natural') or bpy.data.materials['Leaf_PBR_Painted']
bark_material = next(m for m in bpy.data.materials if 'trunk' in m.name and m.use_nodes)
for ob in list(scene.objects):
    if ob.get('role') == 'benchmark_asset':
        bpy.data.objects.remove(ob, do_unlink=True)

rng = random.Random(263)
wood_v, wood_f, wood_uv = [], [], []
leaf_v, leaf_f, leaf_uv, leaf_normals, leaf_colors = [], [], [], [], []
leaf_centers = []


def tube(points, radii, sides=6):
    start = len(wood_v)
    distance = 0.0
    for i, (p, radius) in enumerate(zip(points, radii)):
        if i:
            distance += (p - points[i-1]).length
        tangent = (points[min(i+1, len(points)-1)] - points[max(0, i-1)]).normalized()
        side = tangent.cross(Vector((0, 1, 0)) if abs(tangent.z) > .9 else Vector((0, 0, 1))).normalized()
        up = tangent.cross(side).normalized()
        for j in range(sides):
            angle = j * math.tau / sides
            flare = 1 + .16 * math.cos(angle * 5) * max(0, 1-p.z/.8)
            wood_v.append(tuple(p + radius * flare * (side*math.cos(angle) + up*math.sin(angle))))
        if i:
            for j in range(sides):
                a = start + (i-1)*sides+j
                b = start + (i-1)*sides+(j+1)%sides
                wood_f.append((a, b, b+sides, a+sides))
                wood_uv.append(((j/sides, (distance-(p-points[i-1]).length)/1.8), ((j+1)/sides, (distance-(p-points[i-1]).length)/1.8), ((j+1)/sides, distance/1.8), (j/sides, distance/1.8)))
    for ring, reverse in [(0, True), (len(points)-1, False)]:
        for j in range(1, sides-1):
            face = (start+ring*sides, start+ring*sides+j, start+ring*sides+j+1)
            wood_f.append(tuple(reversed(face)) if reverse else face)
            wood_uv.append(((0, 0), (.5, 1), (1, 0)))


trunk_points = [Vector((.10*math.sin(z*.7), .07*math.sin(z), z)) for z in [0, .18, .55, 1.2, 2.3, 3.5, 4.6, 5.8, 7.0, 8.2, 8.8]]
tube(trunk_points, [.57, .43, .32, .28, .25, .22, .18, .14, .095, .05, .012], 12)
# Buttress roots connect the closed trunk to the soil rather than a black decal.
for i in range(5):
    a = i*math.tau/5+.2
    tube([Vector((math.cos(a)*.17, math.sin(a)*.17, .55)), Vector((math.cos(a)*.60, math.sin(a)*.60, .13)), Vector((math.cos(a)*1.08, math.sin(a)*1.08, -.025))], [.19, .14, .025], 6)

# Overlapping, asymmetric bough volumes form a broad crown with a raised trunk.
lobes = [((-1.65,-.65,6.1),(1.95,1.65,1.55)), ((1.60,-.50,6.5),(1.95,1.65,1.65)), ((-.95,1.10,7.1),(1.85,1.65,1.70)), ((1.20,1.12,7.4),(1.80,1.65,1.65)), ((-.35,-1.15,7.6),(1.80,1.45,1.65)), ((.00,.12,8.15),(1.80,1.60,1.65))]
for group, (center, radius) in enumerate(lobes):
    center, radius = Vector(center), Vector(radius)
    branch_base = Vector((0, 0, 3.25 + group*.42))
    tube([branch_base, branch_base.lerp(center, .48)+Vector((0,0,-.35)), center], [.16-group*.013, .075, .022], 7)
    # 16 sprays per bough; leaves stay small even on a ten metre tree.
    for shoot in range(16):
        t = (shoot+.5)/16
        zz = 1-2*t
        phi = shoot*2.399963+group*.78
        direction = Vector((math.sqrt(1-zz*zz)*math.cos(phi), math.sqrt(1-zz*zz)*math.sin(phi), zz))
        anchor = center + Vector(tuple(direction[j]*radius[j]*.70 for j in range(3)))
        tip = anchor + direction*.60 + Vector((0,0,.18))
        tube([center.lerp(anchor,.58), anchor, tip], [.018,.010,.002], 4)
        pose = Euler((rng.uniform(-.8,.8), rng.uniform(-.8,.8), phi), 'XYZ').to_matrix()
        for li in range(64):
            u = (li+.5)/64
            angle = li*2.399963
            radial = math.sqrt(u)
            local = Vector((math.cos(angle)*radial*.71, math.sin(angle)*radial*.64, rng.uniform(-.34,.34)))
            position = anchor + pose @ local
            leaf_pose = pose @ Euler((rng.uniform(-.8,.8), rng.uniform(-.8,.8), angle), 'XYZ').to_matrix()
            length = rng.uniform(.16,.26)
            width = length*rng.uniform(.42,.58)
            # A five-triangle fan keeps a curved ridge and pointed silhouette.
            shape = [(0,0,.012), (0,-length*.5,0), (width*.5,-length*.13,0), (width*.42,length*.25,-.005), (0,length*.5,-.008), (-width*.5,length*.08,0)]
            start = len(leaf_v)
            normal = (leaf_pose @ Vector((0,0,1))).normalized()
            dome = (position-(center-Vector((0,0,.8)))).normalized()
            normal = (normal*.72+dome*.28).normalized()
            tint = rng.uniform(.32,.68)
            for p in shape:
                leaf_v.append(tuple(position + leaf_pose @ Vector(p)))
                leaf_normals.append(tuple(normal))
                leaf_colors.append((1,tint,max(.05,min(1,(position.z-3)/7)),1))
            # Convex pentagon: a center fan with 5 triangles; no alpha sorting.
            for a,b in [(1,2),(2,3),(3,4),(4,5),(5,1)]:
                leaf_f.append((start,start+a,start+b))
                leaf_uv.append(tuple((shape[i][0]/width+.5,shape[i][1]/length+.5) for i in [0,a,b]))
            leaf_centers.append((position,normal))


def mesh_object(name, vertices, faces, uv_values, material):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    uv = mesh.uv_layers.new(name='UVMap')
    for poly, values in zip(mesh.polygons, uv_values):
        poly.use_smooth = True
        for li, value in zip(poly.loop_indices, values):
            uv.data[li].uv = value
    ob = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(ob)
    ob['role'] = 'benchmark_asset'
    mesh.materials.append(material)
    return ob


wood = mesh_object('Trunk_Branches_LOD0', wood_v, wood_f, wood_uv, bark_material)
leaves = mesh_object('LeafClump_Canopy', leaf_v, leaf_f, leaf_uv, leaf_material)
leaves['leaf_count'] = len(leaf_centers)
leaves.data.normals_split_custom_set_from_vertices(leaf_normals)
colors = leaves.data.color_attributes.new(name='AssetData', type='FLOAT_COLOR', domain='POINT')
# Local hemisphere visibility, used once for indirect AO. No fixed sun is baked.
bvh = BVHTree.FromPolygons(leaf_v+wood_v, leaf_f+[tuple(i+len(leaf_v) for i in f) for f in wood_f], all_triangles=False)
for index, (point, normal) in enumerate(leaf_centers):
    tangent = normal.cross(Vector((1,0,0)) if abs(normal.x)<.8 else Vector((0,1,0))).normalized()
    bitangent = normal.cross(tangent)
    visible = 0
    for ray in range(12):
        z = (ray+.5)/12
        a = ray*2.399963
        direction = (tangent*(math.sqrt(1-z*z)*math.cos(a))+bitangent*(math.sqrt(1-z*z)*math.sin(a))+normal*z).normalized()
        hit = bvh.ray_cast(point+normal*.035, direction, .85)[0]
        visible += hit is None
    for vi in range(6):
        data = list(leaf_colors[index*6+vi]); data[0] = visible/12
        colors.data[index*6+vi].color = data
leaves.data.color_attributes.active_color_name = 'AssetData'
scene['construction'] = 'Mature broadleaf: closed wood, six overlapping boughs, 96 small-leaf sprays. Local source assembly, not hand modeled.'
scene['leaf_count'] = len(leaf_centers)
scene['vertex_contract'] = 'R local BVH visibility, G neutral variation, B wind weight'
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'source/broadleaf_editable.blend'))

report = {'leaves':len(leaf_centers), 'height_m':max(v[2] for v in leaf_v+wood_v)-min(v[2] for v in leaf_v+wood_v), 'leaf_length_m':[.16,.26], 'ao':'12 local hemisphere visibility rays, .85m radius', 'lods':{}}
for level, stride in enumerate([1,2,6]):
    bpy.ops.object.select_all(action='DESELECT')
    copies = []
    for source in [wood, leaves]:
        ob = source.copy(); ob.data = source.data.copy()
        scene.collection.objects.link(ob)
        if source == leaves and stride > 1:
            import bmesh
            bm = bmesh.new(); bm.from_mesh(ob.data)
            # Keep complete leaves and their data; never collapse leaf edges.
            bmesh.ops.delete(bm, geom=[f for i,f in enumerate(bm.faces) if (i//5)%stride], context='FACES')
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
            bm.to_mesh(ob.data); bm.free()
            # Modest area compensation preserves crown weight at gameplay distance.
            vertices = list(ob.data.vertices)
            for start in range(0,len(vertices),6):
                vs = vertices[start:start+6]
                center = sum((v.co for v in vs),Vector())/6
                for v in vs: v.co = center+(v.co-center)*(1.30 if level==1 else 1.70)
        elif source == wood and level:
            bpy.context.view_layer.objects.active = ob
            ob.select_set(True)
            mod = ob.modifiers.new('Wood_LOD','DECIMATE'); mod.ratio = .65 if level==1 else .30
            bpy.ops.object.modifier_apply(modifier=mod.name)
            ob.data.validate()
            ob.select_set(False)
        ob.data.materials.clear()
        mat_name = 'Export_Leaf' if source==leaves else 'Export_Bark'
        mat = bpy.data.materials.get(mat_name) or bpy.data.materials.new(mat_name)
        ob.data.materials.append(mat)
        for p in ob.data.polygons:p.material_index=0
        copies.append(ob)
    # Stable exported names allow the existing external material packer to bind.
    wood.name='SOURCE_WOOD'; leaves.name='SOURCE_LEAVES'
    copies[0].name='Trunk_Branches_LOD0'; copies[1].name='LeafClump_Canopy'
    for ob in copies:ob.select_set(True)
    report['lods'][f'lod{level}'] = sum(sum(len(p.vertices)-2 for p in ob.data.polygons) for ob in copies)
    bpy.ops.export_scene.gltf(filepath=str(OUT/f'models/broadleaf_lod{level}.glb'), use_selection=True,use_active_scene=True,export_format='GLB',export_normals=True,export_tangents=True,export_vertex_color='ACTIVE',export_all_vertex_colors=False)
    for ob in copies:bpy.data.objects.remove(ob,do_unlink=True)
    wood.name='Trunk_Branches_LOD0'; leaves.name='LeafClump_Canopy'
(OUT/'reports/mature_geometry.json').write_text(json.dumps(report,indent=2))
print('MATURE_TREE_OK', json.dumps(report))
