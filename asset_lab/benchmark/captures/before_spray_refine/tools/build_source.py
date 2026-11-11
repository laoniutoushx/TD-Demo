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

# 1. Reuse the source trunk and sculpt a sturdy, readable broadleaf trunk with organic root buttresses
bpy.ops.import_scene.gltf(filepath=str(ROOT / 'atmosphere/assets/tree_mid_geometry.glb'))
trunk = next(o for o in scene.objects if o.type == 'MESH')
trunk.name = 'Trunk_Branches_LOD0'
bm = bmesh.new()
bm.from_mesh(trunk.data)
# Remove thin twig/leaf geometry and any stray high twig faces that poke outside the canopy
remove = [
    f for f in bm.faces
    if any(k in trunk.data.materials[f.material_index].name for k in ('leaves', 'branches'))
    or f.calc_center_median().z > 2.15
    or Vector((f.calc_center_median().x, f.calc_center_median().y)).length > 0.85
]
bmesh.ops.delete(bm, geom=remove, context='FACES')
bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
bm.to_mesh(trunk.data)
bm.free()
trunk.data.validate()

lowest = min(v.co.z for v in trunk.data.vertices)
root_verts = [v.co for v in trunk.data.vertices if v.co.z < lowest + 0.08]
origin = sum(root_verts, Vector()) / max(len(root_verts), 1)
for v in trunk.data.vertices:
    v.co -= Vector((origin.x, origin.y, lowest))
    z = max(0.0, v.co.z)
    ang = math.atan2(v.co.y, v.co.x)
    # Sturdy lower trunk girth + 5-lobed root buttress flare at the ground contact
    trunk_thick = 1.32 * max(0.0, 1.0 - z / 1.85) + 0.25
    buttress = (0.48 + 0.22 * math.cos(ang * 5.0 + 0.4)) * (max(0.0, 1.0 - z / 0.42) ** 1.6)
    flare = max(1.05, trunk_thick + buttress) if z < 1.75 else 1.05
    v.co.x *= flare
    v.co.y *= flare
for face in trunk.data.polygons:
    face.use_smooth = True
for c in list(trunk.users_collection):
    c.objects.unlink(trunk)
collection.objects.link(trunk)
trunk['source'] = 'Poly Haven tree_small_02 mid: sturdy flared trunk with 5-lobed root buttresses'


def plain(name, color):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    bs = m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = (*color, 1)
    bs.inputs['Roughness'].default_value = 0.8
    return m


gray = plain('Gray_Structure_Check', (0.32, 0.36, 0.31))
leaf_mat = plain('Leaves_Editable_PBR_Source', (0.24, 0.43, 0.075))
helpers = bpy.data.collections.new('90_Editable_Form_Guides_NO_EXPORT')
scene.collection.children.link(helpers)
canopy = bpy.data.collections.new('02_Canopy_30_Editable_Clumps')
scene.collection.children.link(canopy)
modules = bpy.data.collections.new('91_Leaf_Modules_NO_EXPORT')
scene.collection.children.link(modules)

# 2. Broad, rounded-shoulder 8-segment (8 triangles) cupped ovate leaf module for cohesive broadleaf domes
SEGMENTS = 8
outline = [(0.0, -0.24)]
for j in range(1, 4):
    t = j / 4.0
    # Wide rounded upper shoulders (sin^0.55 biased toward tip) so silhouettes read as soft broadleaf clusters, not spikes
    half_w = 0.235 * (math.sin(math.pi * (t ** 0.82)) ** 0.58)
    outline.append((half_w, -0.24 + 0.54 * t))
outline.append((0.0, 0.30))
for j in range(3, 0, -1):
    t = j / 4.0
    half_w = 0.235 * (math.sin(math.pi * (t ** 0.82)) ** 0.58)
    outline.append((-half_w, -0.24 + 0.54 * t))
prototype = [Vector((0.0, 0.02, 0.052))] + [
    Vector((x, y, 0.018 * (1.0 - (x / 0.24) ** 2) - 0.038 * max(0.0, y / 0.30) ** 1.4))
    for x, y in outline
]
faces = [(0, 1 + i, 1 + (i + 1) % SEGMENTS) for i in range(SEGMENTS)]
uvs = [(0.5, 0.50)] + [(x / 0.48 + 0.5, (y + 0.25) / 0.56) for x, y in outline]

for variant in range(4):
    me = bpy.data.meshes.new('Leaf_Module_%02d' % variant)
    verts = [(v.x * (0.92 + variant * 0.06), v.y * (0.92 + variant * 0.06), v.z * (0.85 + variant * 0.15)) for v in prototype]
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new(me.name, me)
    modules.objects.link(ob)
    uv = me.uv_layers.new(name='UVMap')
    for poly in me.polygons:
        for li in poly.loop_indices:
            uv.data[li].uv = uvs[me.loops[li].vertex_index]
    ob.data.materials.append(leaf_mat)
    ob.hide_render = True
    ob.hide_viewport = True

# 3. Three-tier broad umbrella canopy architecture (10 macro domes x 3 sub-clumps = 30 clumps)
# Remember: Godot Camera 1 (+6, +4.5, +8) views from (+X, -Y) in Blender coordinates.
forms = [
    # Tier 1: Lower outer umbrella rim (5 domes around perimeter, Z = 2.08 ~ 2.24m)
    (-1.32, -0.52, 2.08, 0.96, 0.20),
    (1.36, -0.42, 2.12, 0.96, 0.22),
    (0.18, -1.28, 2.18, 0.94, 0.25),
    (-1.12, 0.96, 2.14, 0.95, 0.24),
    (1.16, 0.92, 2.16, 0.95, 0.26),
    # Tier 2: Mid full canopy body (3 large overlapping domes, Z = 2.68 ~ 2.86m)
    (-0.78, -0.48, 2.72, 1.04, 0.54),
    (0.82, -0.44, 2.76, 1.04, 0.58),
    (0.02, 0.78, 2.74, 1.04, 0.52),
    # Tier 3: Upper crown cap (2 overlapping summit domes, Z = 3.24 ~ 3.48m)
    (-0.32, 0.12, 3.26, 1.02, 0.82),
    (0.18, -0.14, 3.46, 1.05, 0.94),
]

canopy_core = Vector((0.0, -0.05, 2.48))
all_clumps = []
LEAVES_PER_CLUMP = 23  # 30 clumps * 23 leaves * 8 tris = 5,520 leaf tris + ~1,880 bark tris = ~7,404 total tris!

for main, (fx, fy, fz, f_scale, tier_val) in enumerate(forms):
    guide_center = Vector((fx, fy, fz))
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, location=(fx, fy, fz))
    guide = bpy.context.object
    guide.name = 'FormGuide_%d' % main
    guide.scale = (1.08 * f_scale, 1.05 * f_scale, 0.76 * f_scale)
    for c in list(guide.users_collection):
        c.objects.unlink(guide)
    helpers.objects.link(guide)
    guide.hide_render = True
    guide.hide_viewport = True

    for sub in range(3):
        clump_idx = main * 3 + sub
        a = sub * math.tau / 3.0 + main * 0.62
        sub_off = Vector((math.cos(a) * 0.38 * f_scale, math.sin(a) * 0.38 * f_scale, [0.12, -0.08, 0.18][sub] * f_scale))
        center = guide_center + sub_off
        vs = []
        fs = []
        loop_uvs = []
        colors = []
        ns = []

        # Cohesive clump-level color value (G channel: 0.15 dark inner -> 0.94 bright top)
        clump_jitter = rng.uniform(-0.05, 0.05)
        sub_height_bias = [0.04, -0.06, 0.08][sub]
        group_tint = max(0.10, min(0.95, tier_val + sub_height_bias + clump_jitter))

        for leaf in range(LEAVES_PER_CLUMP):
            # Layered spherical shell shingle distribution: inner core filler + outer overlapping dome petals
            is_inner = (leaf < 6)
            ring_t = (leaf / float(LEAVES_PER_CLUMP))
            theta = leaf * 2.399963 + main * 0.47 + sub * 0.85
            radius = (0.08 + 0.25 * math.sqrt(ring_t)) if is_inner else (0.16 + 0.44 * math.sqrt(ring_t))
            radius *= f_scale
            z_dome = math.cos(ring_t * math.pi * 0.52) * 0.30 * f_scale + rng.uniform(-0.05, 0.05)
            off = Vector((math.cos(theta) * radius, math.sin(theta) * radius, z_dome))

            # Negative pitch around local X tilts the +Y leaf tip DOWNWARD along the spherical dome surface (shingle drape!)
            pitch = -(0.10 + 0.56 * ring_t) + rng.uniform(-0.10, 0.10)
            roll = rng.uniform(-0.20, 0.20)
            yaw = theta - math.pi / 2.0 + rng.uniform(-0.18, 0.18)
            rot = Euler((pitch, roll, yaw), 'XYZ').to_matrix()
            scale = rng.uniform(1.05, 1.34) * f_scale * (1.15 if is_inner else 1.0)

            start = len(vs)
            for vi, v in enumerate(prototype):
                local = rot @ Vector((v.x * (0.96 + (leaf % 3) * 0.06) * scale, v.y * scale, v.z * scale))
                point = center + off + local
                vs.append(tuple(point))

                # Spherized clump + canopy normal (86% radial dome blend for smooth, puffy cloud-like leaf masses)
                original = (rot @ Vector((0, 0, 1))).normalized()
                clump_radial = (point - (center - Vector((0, 0, 0.32)))).normalized()
                canopy_radial = (point - canopy_core).normalized()
                canopy_radial = Vector((canopy_radial.x, canopy_radial.y, max(canopy_radial.z, 0.18))).normalized()
                dome_normal = (clump_radial * 0.58 + canopy_radial * 0.42).normalized()
                normal = (original * 0.14 + dome_normal * 0.86).normalized()
                ns.append(tuple(normal))

                # True 3D spatial AO in R channel (core depth * clump vertical * leaf base)
                dist_from_core = (point - canopy_core).length
                core_ao = max(0.20, min(1.0, (dist_from_core - 0.52) / 1.48))
                height_ao = max(0.32, min(1.0, (point.z - 1.55) / 2.15))
                clump_local_z = (point.z - center.z) / max(0.42 * f_scale, 0.2)
                clump_ao = max(0.38, min(1.0, 0.66 + 0.34 * clump_local_z))
                leaf_tip_ao = 0.80 + 0.20 * uvs[vi][1]
                final_ao = max(0.16, min(1.0, (core_ao * 0.42 + height_ao * 0.32 + clump_ao * 0.26) * leaf_tip_ao))
                if is_inner:
                    final_ao *= 0.65

                # G channel: 5-stop palette index driver (combines group tier + local dome top)
                vert_palette = max(0.06, min(0.96, group_tint * 0.66 + max(0.0, clump_local_z) * 0.24 + (uvs[vi][1] - 0.5) * 0.10))
                if is_inner:
                    vert_palette *= 0.60

                wind_weight = max(0.0, min(1.0, (point.z - 0.5) / 3.6)) * uvs[vi][1]
                colors.append((final_ao, vert_palette, wind_weight, 1.0))

            for f in faces:
                fs.append(tuple(start + i for i in f))
                loop_uvs.extend(uvs[i] for i in f)

        me = bpy.data.meshes.new('LeafClump_%02d' % clump_idx)
        me.from_pydata(vs, [], fs)
        me.update()
        for poly in me.polygons:
            poly.use_smooth = True
        me.normals_split_custom_set_from_vertices(ns)
        uv = me.uv_layers.new(name='UVMap')
        for i, val in enumerate(loop_uvs):
            uv.data[i].uv = val
        attr = me.color_attributes.new(name='AssetData', type='FLOAT_COLOR', domain='POINT')
        for i, val in enumerate(colors):
            attr.data[i].color = val
        ob = bpy.data.objects.new(me.name, me)
        canopy.objects.link(ob)
        ob.data.materials.append(leaf_mat)
        ob['cluster_id'] = clump_idx
        ob['leaf_count'] = LEAVES_PER_CLUMP
        ob['normal_blend'] = 0.86
        all_clumps.append(ob)

# 4. Sculpt sturdy, curved primary & secondary branches that terminate cleanly inside the 10 macro domes
branches = []


def branch(name, points, radii):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.resolution_u = 3
    curve.bevel_depth = 1.0
    curve.bevel_resolution = 2
    curve.use_fill_caps = True
    spline = curve.splines.new('BEZIER')
    spline.bezier_points.add(len(points) - 1)
    for p, co, rad in zip(spline.bezier_points, points, radii):
        p.co = co
        p.handle_left_type = 'AUTO'
        p.handle_right_type = 'AUTO'
        p.radius = rad
    ob = bpy.data.objects.new(name, curve)
    collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.convert(target='MESH')
    ob = bpy.context.object
    for poly in ob.data.polygons:
        poly.use_smooth = True
    branches.append(ob)


branch_specs = [
    # 4 Primary cylindrical boughs forking cleanly from the upper trunk (Z=1.22..1.42m)
    ([Vector((-0.05, -0.02, 1.22)), Vector((-0.58, -0.22, 1.62)), Vector((-1.10, -0.42, 2.04))], [0.088, 0.056, 0.026]),
    ([Vector((0.05, -0.02, 1.26)), Vector((0.60, -0.18, 1.66)), Vector((1.14, -0.36, 2.08))], [0.088, 0.056, 0.026]),
    ([Vector((-0.04, 0.04, 1.36)), Vector((-0.48, 0.42, 1.74)), Vector((-0.94, 0.80, 2.10))], [0.078, 0.050, 0.024]),
    ([Vector((0.04, 0.04, 1.40)), Vector((0.50, 0.40, 1.78)), Vector((0.96, 0.76, 2.12))], [0.078, 0.050, 0.024]),
    # 6 Secondary forks branching naturally from the primary boughs into the mid & upper domes
    ([Vector((0.28, -0.12, 1.48)), Vector((0.22, -0.62, 1.78)), Vector((0.16, -1.04, 2.14))], [0.052, 0.036, 0.018]),
    ([Vector((-0.48, -0.18, 1.56)), Vector((-0.62, -0.32, 2.12)), Vector((-0.72, -0.42, 2.66))], [0.055, 0.038, 0.018]),
    ([Vector((0.50, -0.16, 1.60)), Vector((0.66, -0.30, 2.16)), Vector((0.76, -0.38, 2.70))], [0.055, 0.038, 0.018]),
    ([Vector((0.0, 0.24, 1.62)), Vector((0.02, 0.48, 2.16)), Vector((0.02, 0.68, 2.68))], [0.054, 0.036, 0.018]),
    ([Vector((-0.24, 0.04, 1.78)), Vector((-0.26, 0.08, 2.52)), Vector((-0.28, 0.10, 3.18))], [0.048, 0.032, 0.016]),
    ([Vector((0.24, -0.04, 1.82)), Vector((0.20, -0.08, 2.62)), Vector((0.16, -0.12, 3.36))], [0.048, 0.032, 0.016]),
]

for i, (pts, rads) in enumerate(branch_specs):
    branch('Primary_Branch_%02d' % i, pts, rads)

# 5. Source bark maps remain explicit in Blender and are packed into the source file.
for mat in trunk.data.materials:
    part = 'branch' if 'branch' in mat.name else 'trunk'
    if 'leaves' in mat.name:
        continue
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    bs = nt.nodes.new('ShaderNodeBsdfPrincipled')
    nt.links.new(bs.outputs['BSDF'], out.inputs['Surface'])
    for kind in ('base', 'normal', 'orm'):
        image = bpy.data.images.load(str(ROOT / f'atmosphere/textures/tree_{part}_{kind}.jpg'), check_existing=True)
        tex = nt.nodes.new('ShaderNodeTexImage')
        tex.image = image
        tex.label = kind
        if kind == 'base':
            nt.links.new(tex.outputs['Color'], bs.inputs['Base Color'])
        else:
            image.colorspace_settings.name = 'Non-Color'
            if kind == 'normal':
                normal = nt.nodes.new('ShaderNodeNormalMap')
                nt.links.new(tex.outputs['Color'], normal.inputs['Color'])
                nt.links.new(normal.outputs['Normal'], bs.inputs['Normal'])
            else:
                sep = nt.nodes.new('ShaderNodeSeparateColor')
                nt.links.new(tex.outputs['Color'], sep.inputs['Color'])
                nt.links.new(sep.outputs['Green'], bs.inputs['Roughness'])

for ob in branches:
    ob.data.materials.append(next(m for m in trunk.data.materials if 'trunk' in m.name))
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(island_margin=0.025)
    bpy.ops.object.mode_set(mode='OBJECT')

bpy.ops.object.select_all(action='DESELECT')
visible = [trunk] + branches + all_clumps
for o in visible:
    o.select_set(True)
bpy.context.view_layer.objects.active = trunk
for obj in visible:
    obj['role'] = 'benchmark_asset'
scene['construction'] = 'Offline initial assembly; all meshes editable. Not represented as manual UI work.'
scene['vertex_contract'] = 'R local AO (1 unoccluded), G variation (.5 neutral), B wind weight'
scene['lod0_triangles'] = sum(sum(len(f.vertices) - 2 for f in o.data.polygons) for o in visible)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'source/broadleaf_editable.blend'))

bark_export = plain('Bark', (0.24, 0.16, 0.095))
for obj in [trunk] + branches:
    obj.data.materials.clear()
    obj.data.materials.append(bark_export)
    for poly in obj.data.polygons:
        poly.material_index = 0
bpy.ops.export_scene.gltf(
    filepath=str(OUT / 'models/broadleaf_lod0.glb'),
    use_selection=True,
    export_format='GLB',
    export_normals=True,
    export_tangents=True,
    export_all_vertex_colors=True,
)
report = {
    'triangles': scene['lod0_triangles'],
    'leaves': 30 * LEAVES_PER_CLUMP,
    'clumps': 30,
    'leaf_triangles': SEGMENTS,
    'source': 'Poly Haven tree_small_02',
    'process': 'offline assembly, editable Blender meshes',
    'height': max(v.co.z for o in all_clumps for v in o.data.vertices),
}
(OUT / 'reports/geometry.json').write_text(json.dumps(report, indent=2))
print('BENCHMARK_GEOMETRY', report)
