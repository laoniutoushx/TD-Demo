"""Offline texture baking and explicit whole-leaf LOD preparation in Blender."""
import bpy, bmesh, json, math
from pathlib import Path
from mathutils import Vector

OUT = Path(__file__).resolve().parents[1]
ROOT = OUT.parents[1]
bpy.ops.wm.open_mainfile(filepath=str(OUT / 'source/broadleaf_editable.blend'))
source_scene = bpy.context.scene
source_objects = [o for o in source_scene.objects if o.get('role') == 'benchmark_asset']
leaves = [o for o in source_objects if o.name.startswith('LeafClump')]

# Build a UV-space, light-independent leaf material. All nodes are retained.
bake_scene = bpy.data.scenes.new('Leaf_Texture_Bake_Source')
bpy.context.window.scene = bake_scene
mesh = bpy.data.meshes.new('Leaf_Texture_Canvas')
mesh.from_pydata([(-1, -1, 0), (1, -1, 0), (1, 1, 0), (-1, 1, 0)], [], [(0, 1, 2, 3)])
uv = mesh.uv_layers.new(name='UVMap')
for i, co in enumerate([(0, 0), (1, 0), (1, 1), (0, 1)]):
    uv.data[i].uv = co
plane = bpy.data.objects.new('Editable_UV_Bake_Canvas', mesh)
bake_scene.collection.objects.link(plane)
plane.select_set(True)
bpy.context.view_layer.objects.active = plane
material = bpy.data.materials.new('Editable_Leaf_Venation_and_Color')
material.use_nodes = True
plane.data.materials.append(material)
nt = material.node_tree
nt.nodes.clear()
out = nt.nodes.new('ShaderNodeOutputMaterial')
emit = nt.nodes.new('ShaderNodeEmission')
nt.links.new(emit.outputs[0], out.inputs['Surface'])
coord = nt.nodes.new('ShaderNodeTexCoord')
sep = nt.nodes.new('ShaderNodeSeparateXYZ')
nt.links.new(coord.outputs['UV'], sep.inputs[0])


def mathnode(op, a, b=None):
    n = nt.nodes.new('ShaderNodeMath')
    n.operation = op
    for i, v in enumerate([a, b]):
        if v is None:
            continue
        if isinstance(v, (int, float)):
            n.inputs[i].default_value = v
        else:
            nt.links.new(v, n.inputs[i])
    return n.outputs[0]


# Organic curved venation + base-to-tip & center-to-margin painterly gradient
x = mathnode('ABSOLUTE', mathnode('SUBTRACT', sep.outputs['X'], 0.5))
y_grad = sep.outputs['Y']
phase = mathnode('SUBTRACT', mathnode('MULTIPLY', y_grad, 22.0), mathnode('MULTIPLY', mathnode('POWER', x, 0.85), 16.0))
vein_wave = mathnode('SUBTRACT', 1.0, mathnode('MULTIPLY', mathnode('ABSOLUTE', mathnode('SINE', phase)), 1.0))
veins = mathnode('POWER', mathnode('MAXIMUM', vein_wave, 0.0), 6.0)
midrib = mathnode('SUBTRACT', 1.0, mathnode('MINIMUM', mathnode('DIVIDE', x, 0.035), 1.0))
midrib = mathnode('POWER', midrib, 2.5)
veins = mathnode('MAXIMUM', veins, midrib)

noise = nt.nodes.new('ShaderNodeTexNoise')
noise.inputs['Scale'].default_value = 14.0
noise.inputs['Detail'].default_value = 3.0
nt.links.new(coord.outputs['UV'], noise.inputs['Vector'])

edge_boost = mathnode('MULTIPLY', x, 0.35)
factor = mathnode('ADD', mathnode('MULTIPLY', noise.outputs['Fac'], 0.28), mathnode('MULTIPLY', y_grad, 0.48))
factor = mathnode('ADD', factor, edge_boost)
factor = mathnode('ADD', factor, mathnode('MULTIPLY', veins, 0.18))

ramp = nt.nodes.new('ShaderNodeValToRGB')
nt.links.new(factor, ramp.inputs[0])
nt.links.new(ramp.outputs['Color'], emit.inputs['Color'])
target = nt.nodes.new('ShaderNodeTexImage')
target.label = 'Active bake target'
nt.nodes.active = target
bake_scene.render.engine = 'CYCLES'
bake_scene.cycles.samples = 1
bake_scene.render.bake.margin = 16

# Multi-stop Concept Sheet palettes (sRGB converted to linear in Cycles Ramp)
ramp.color_ramp.elements.new(0.50)
textures = {}
palettes = [
    ('natural', [(0.0, (0.035, 0.095, 0.015, 1)), (0.52, (0.095, 0.215, 0.032, 1)), (1.0, (0.240, 0.380, 0.055, 1))]),
    ('painted', [(0.0, (0.048, 0.135, 0.024, 1)), (0.50, (0.135, 0.295, 0.045, 1)), (1.0, (0.360, 0.520, 0.082, 1))]),
]
for style, stops in palettes:
    for elem, (pos, col) in zip(ramp.color_ramp.elements, stops):
        elem.position = pos
        elem.color = col
    im = bpy.data.images.new('leaf_' + style, 1024, 1024, alpha=False)
    target.image = im
    bpy.ops.object.bake(type='EMIT')
    im.filepath_raw = str(OUT / f'textures/leaf_{style}_base.png')
    im.file_format = 'PNG'
    im.save()
    textures[style] = im

# Tangent normal from editable procedural veins, not painted illumination.
bs = nt.nodes.new('ShaderNodeBsdfPrincipled')
bump = nt.nodes.new('ShaderNodeBump')
bump.inputs['Strength'].default_value = 0.28
bump.inputs['Distance'].default_value = 0.015
nt.links.new(veins, bump.inputs['Height'])
nt.links.new(bump.outputs['Normal'], bs.inputs['Normal'])
nt.links.new(bs.outputs['BSDF'], out.inputs['Surface'])
normal = bpy.data.images.new('leaf_normal_gl', 1024, 1024, alpha=False)
normal.colorspace_settings.name = 'Non-Color'
target.image = normal
bpy.ops.object.bake(type='NORMAL')
normal.filepath_raw = str(OUT / 'textures/leaf_normal_gl.png')
normal.file_format = 'PNG'
normal.save()
bake_scene['instructions'] = 'Edit palette ramp / vein math, select target image, Cycles Bake Emit or Normal.'

bpy.context.window.scene = source_scene
for part in ('trunk',):
    for kind in ('base', 'normal', 'orm'):
        img = bpy.data.images.load(str(ROOT / f'atmosphere/textures/tree_{part}_{kind}.jpg'), check_existing=False)
        if kind != 'base':
            img.colorspace_settings.name = 'Non-Color'
        _ = img.pixels[0]
        img.scale(2048, 2048)
        img.filepath_raw = str(OUT / f'textures/bark_{kind}.png')
        img.file_format = 'PNG'
        img.save()

for ob in leaves:
    mat = bpy.data.materials.new('Leaf_PBR_Painted') if 'Leaf_PBR_Painted' not in bpy.data.materials else bpy.data.materials['Leaf_PBR_Painted']
    mat.use_nodes = True
    nt2 = mat.node_tree
    bs2 = nt2.nodes.get('Principled BSDF')
    if not any(n.type == 'TEX_IMAGE' for n in nt2.nodes):
        tx = nt2.nodes.new('ShaderNodeTexImage')
        tx.image = textures['painted']
        nt2.links.new(tx.outputs['Color'], bs2.inputs['Base Color'])
        bs2.inputs['Roughness'].default_value = 0.8
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    ob.data.color_attributes.active_color_name = 'AssetData'

source_scene['texture_method'] = 'Blender procedural UV bake, editable nodes. Not hand-painted or AI-generated.'
source_scene['leaf_count'] = sum(o.get('leaf_count', 24) for o in leaves)
for im in bpy.data.images:
    if im.filepath and Path(bpy.path.abspath(im.filepath)).is_file():
        try:
            im.source = 'FILE'
            im.reload()
            _ = im.pixels[0]
            im.pack()
        except RuntimeError:
            pass
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'source/broadleaf_editable.blend'))

canopy_core = Vector((0.0, 0.10, 2.55))


def export_lod(level):
    bpy.ops.object.select_all(action='DESELECT')
    copies = []
    names = {src: src.name for src in source_objects}
    for src, name in names.items():
        src.name = 'SOURCE_ONLY_' + name
    for src in source_objects:
        ob = src.copy()
        ob.data = src.data.copy()
        source_scene.collection.objects.link(ob)
        ob.name = names[src]
        if src in leaves and level == 2:
            bounds = [Vector(p) for p in src.bound_box]
            low = Vector(tuple(min(p[j] for p in bounds) for j in range(3)))
            high = Vector(tuple(max(p[j] for p in bounds) for j in range(3)))
            center = (low + high) * 0.5
            raw_r = (high - low) * 0.48
            radius = Vector((raw_r.x * 1.04, raw_r.y * 1.04, min(raw_r.z, max(raw_r.x, raw_r.y) * 0.68)))
            mesh = bpy.data.meshes.new(src.name + '_VolumeLOD')
            bm = bmesh.new()
            bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
            bm.to_mesh(mesh)
            bm.free()
            uv = mesh.uv_layers.new(name='UVMap')
            for poly in mesh.polygons:
                poly.use_smooth = True
                for li in poly.loop_indices:
                    v = mesh.vertices[mesh.loops[li].vertex_index].co
                    uv.data[li].uv = (0.5 + math.atan2(v.y, v.x) / math.tau, 0.5 + math.asin(max(-1.0, min(1.0, v.z))) / math.pi)
            lod2_normals = []
            for v in mesh.vertices:
                v.co = center + Vector(tuple(v.co[j] * radius[j] for j in range(3)))
                clump_dir = (v.co - (center - Vector((0, 0, 0.25)))).normalized()
                canopy_dir = (v.co - canopy_core).normalized()
                lod2_normals.append(tuple((clump_dir * 0.55 + canopy_dir * 0.45).normalized()))
            mesh.update()
            mesh.normals_split_custom_set_from_vertices(lod2_normals)
            attr = mesh.color_attributes.new(name='AssetData', type='FLOAT_COLOR', domain='POINT')
            for vi, col in enumerate(attr.data):
                pt = mesh.vertices[vi].co
                h_ao = max(0.32, min(1.0, (pt.z - 1.55) / 2.15))
                c_ao = max(0.38, min(1.0, 0.65 + 0.35 * ((pt.z - center.z) / max(radius.z, 0.15))))
                pal_g = max(0.12, min(0.94, h_ao * 0.65 + c_ao * 0.35))
                col.color = (h_ao * c_ao, pal_g, max(0.0, min(1.0, (pt.z - 1.0) / 3.2)), 1.0)
            mesh.color_attributes.active_color_name = 'AssetData'
            ob.data = mesh
        elif src in leaves and level == 1:
            n_leaves = ob.get('leaf_count', 24)
            v_per_leaf = len(ob.data.vertices) // max(n_leaves, 1)
            f_per_leaf = len(ob.data.polygons) // max(n_leaves, 1)
            low = Vector(tuple(min(v.co[j] for v in ob.data.vertices) for j in range(3)))
            high = Vector(tuple(max(v.co[j] for v in ob.data.vertices) for j in range(3)))
            for index in range(n_leaves):
                if index % 2:
                    continue
                verts = list(ob.data.vertices)[index * v_per_leaf : (index + 1) * v_per_leaf]
                center = sum((v.co for v in verts), Vector()) / max(len(verts), 1)
                for v in verts:
                    co = center + (v.co - center) * 1.32
                    v.co = Vector(tuple(max(low[j], min(high[j], co[j])) for j in range(3)))
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            bm.faces.ensure_lookup_table()
            divisor = 2
            bmesh.ops.delete(bm, geom=[f for i, f in enumerate(list(bm.faces)) if (i // f_per_leaf) % divisor != 0], context='FACES')
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
            bm.to_mesh(ob.data)
            bm.free()
        elif src not in leaves and level > 0:
            mod = ob.modifiers.new('LOD_Trunk_Decimation', 'DECIMATE')
            mod.ratio = 0.52 if level == 1 else 0.24
            bpy.context.view_layer.objects.active = ob
            ob.select_set(True)
            bpy.ops.object.modifier_apply(modifier=mod.name)
            ob.data.validate()
        ob.data.materials.clear()
        m = bpy.data.materials.get('Export_Leaf') if src in leaves else bpy.data.materials.get('Export_Bark')
        if m is None:
            m = bpy.data.materials.new('Export_Leaf' if src in leaves else 'Export_Bark')
        ob.data.materials.append(m)
        for poly in ob.data.polygons:
            poly.material_index = 0
        copies.append(ob)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in copies:
        ob.select_set(True)
    triangles = sum(sum(len(f.vertices) - 2 for f in ob.data.polygons) for ob in copies)
    bpy.ops.export_scene.gltf(
        filepath=str(OUT / f'models/broadleaf_lod{level}.glb'),
        use_selection=True,
        use_active_scene=True,
        export_format='GLB',
        export_normals=True,
        export_tangents=True,
        export_vertex_color='ACTIVE',
        export_all_vertex_colors=False,
    )
    for ob in copies:
        bpy.data.objects.remove(ob, do_unlink=True)
    for src, name in names.items():
        src.name = name
    return triangles


report = {f'lod{i}': export_lod(i) for i in range(3)}
(OUT / 'reports/lods.json').write_text(json.dumps(report, indent=2))
print('EXPLICIT_LODS', report)
