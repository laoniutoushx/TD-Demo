"""Keep one editable bake scene, local packed textures and named source palettes."""
import bpy
from pathlib import Path
from mathutils import Vector
OUT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(OUT/'source/broadleaf_editable.blend'))
scenes=[s for s in bpy.data.scenes if s.name.startswith('Leaf_Texture_Bake_Source')]
keep=sorted(scenes,key=lambda s:s.name)[-1]
for s in scenes:
    if s!=keep:bpy.data.scenes.remove(s)
keep.name='Leaf_Texture_Bake_Source'
local={}
for name in ['bark_base','bark_normal','bark_orm','leaf_natural_base','leaf_painted_base','leaf_normal_gl']:
    im=bpy.data.images.load(str(OUT/f'textures/{name}.png'),check_existing=False)
    if 'normal' in name or 'orm' in name:im.colorspace_settings.name='Non-Color'
    _=im.pixels[0];im.pack();local[name]=im
for mat in bpy.data.materials:
    if not mat.use_nodes:continue
    for node in mat.node_tree.nodes:
        if node.type!='TEX_IMAGE' or not node.image:continue
        name=node.image.name
        if 'tree_trunk' in name or 'tree_branch' in name:
            kind='base' if 'base' in name else ('normal' if 'normal' in name else 'orm')
            node.image=local['bark_'+kind]
        for key in ['leaf_natural_base','leaf_painted_base','leaf_normal_gl']:
            if key in name:node.image=local[key]
    if mat.name=='Leaf_PBR_Painted':
        nt=mat.node_tree;bs=nt.nodes.get('Principled BSDF')
        for node in nt.nodes:
            if node.type=='TEX_IMAGE':
                is_normal=any(link.to_node.type=='NORMAL_MAP' for link in node.outputs['Color'].links)
                node.image=local['leaf_normal_gl'] if is_normal else local['leaf_painted_base']
        normal=next((n for n in nt.nodes if n.type=='NORMAL_MAP'),None)
        if normal is None:
            tx=nt.nodes.new('ShaderNodeTexImage');tx.image=local['leaf_normal_gl']
            normal=nt.nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.18
            nt.links.new(tx.outputs['Color'],normal.inputs['Color']);nt.links.new(normal.outputs['Normal'],bs.inputs['Normal'])
        mat.diffuse_color=(.23,.42,.07,1)
        natural=bpy.data.materials.get('Leaf_PBR_Natural')
        if natural is None:natural=mat.copy();natural.name='Leaf_PBR_Natural';natural.use_fake_user=True
        for node in natural.node_tree.nodes:
            if node.type=='TEX_IMAGE' and node.image==local['leaf_painted_base']:node.image=local['leaf_natural_base']
for ob in keep.objects:
    if ob.type!='MESH':continue
    mat=ob.active_material;nt=mat.node_tree
    frame=nt.nodes.new('NodeFrame');frame.label='BAKED OUTPUTS / repaint or rebake'
    for i,key in enumerate(['leaf_natural_base','leaf_painted_base','leaf_normal_gl']):
        node=nt.nodes.new('ShaderNodeTexImage');node.image=local[key];node.label=key;node.parent=frame;node.location=(i*300,-400)
    ramp=nt.nodes.new('ShaderNodeValToRGB');ramp.label='Natural palette alternative'
    ramp.color_ramp.elements[0].color=(.055,.135,.018,1);ramp.color_ramp.elements[1].color=(.19,.32,.045,1)
    for index,node in enumerate(nt.nodes):
        if node.parent is None:node.location=((index%5)*260,(index//5)*-210)
for sc in bpy.data.scenes:
    if any(o.get('role')=='benchmark_asset' for o in sc.objects):bpy.context.window.scene=sc;break
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_location=Vector((0,0,2.1))
            area.spaces.active.region_3d.view_distance=8
bpy.data.orphans_purge(do_recursive=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'source/broadleaf_editable.blend'))
print('SOURCE_CHECK',len(bpy.data.scenes),'scenes',[(im.name,bool(im.packed_file),tuple(im.size)) for im in bpy.data.images])
