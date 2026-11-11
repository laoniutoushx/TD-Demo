"""Offline, editable leaf-spray study and crown replacement; no runtime generation.

Run with --sample first. Full mode rebuilds closed wood and twig-connected sprays,
retains bark textures, and samples actual BVH visibility for vertex AO.
"""
import bpy, bmesh, math, random, json, sys
from pathlib import Path
from mathutils import Vector, Euler
from mathutils.bvhtree import BVHTree

OUT=Path(__file__).resolve().parents[1]
SAMPLE='--sample' in sys.argv
rng=random.Random(263)
bpy.ops.wm.open_mainfile(filepath=str(OUT/'source/broadleaf_editable.blend'))
scene=bpy.context.scene
leaf_material=bpy.data.materials.get('Leaf_PBR_Painted')
bark_material=next(m for m in bpy.data.materials if 'trunk' in m.name and m.use_nodes)
if SAMPLE:
    scene=bpy.data.scenes.new('Branch_Two_Leaf_Sprays')
    bpy.context.window.scene=scene
    canopy=scene.collection
else:
    canopy=bpy.data.collections['02_Canopy_30_Editable_Clumps']
    for ob in list(canopy.objects):bpy.data.objects.remove(ob,do_unlink=True)
    for ob in list(scene.objects):
        if ob.name.startswith('TwigBranches'):bpy.data.objects.remove(ob,do_unlink=True)
    # The old clipped scan exposed open, flattened stumps in the full orbit.
    # Replace that lower section with an editable, closed twelve-sided trunk with 5-lobed root buttresses.
    trunk=next(o for o in scene.objects if o.name=='Trunk_Branches_LOD0')
    root_vertices=[];root_faces=[]
    TRUNK_RINGS=9
    TRUNK_HEIGHT=1.42
    for ring in range(TRUNK_RINGS):
        z=ring*TRUNK_HEIGHT/(TRUNK_RINGS-1)
        center=Vector((.035*math.sin(z*1.9),.022*(math.cos(z*2.6)-1),z))
        radius=.132+.115*math.exp(-z/.22)
        for side in range(12):
            angle=side*math.tau/12
            lobe=(1+.28*math.cos(angle*5+.35)*math.exp(-z/.32)+.10*math.sin(angle*3-.4)*math.exp(-z/.45))
            r=radius*lobe
            root_vertices.append(tuple(center+Vector((r*math.cos(angle),r*math.sin(angle),0))))
    for ring in range(TRUNK_RINGS-1):
        for side in range(12):
            a=ring*12+side;b=ring*12+(side+1)%12
            root_faces.append((a,b,b+12,a+12))
    for s in range(1,11):
        root_faces.append((0,s+1,s))
    top_start=(TRUNK_RINGS-1)*12
    for s in range(1,11):
        root_faces.append((top_start,top_start+s,top_start+s+1))
    root_mesh=bpy.data.meshes.new('Closed_Root_Trunk')
    root_mesh.from_pydata(root_vertices,[],root_faces);root_mesh.update()
    uv=root_mesh.uv_layers.new(name='UVMap')
    for face in root_mesh.polygons:
        face.use_smooth=len(face.vertices)==4
        seam=max(v%12 for v in face.vertices)-min(v%12 for v in face.vertices)>6
        for li in face.loop_indices:
            index=root_mesh.loops[li].vertex_index
            u=(index%12)/12
            if seam and u==0:u=1
            uv.data[li].uv=(u,root_mesh.vertices[index].co.z/TRUNK_HEIGHT)
    trunk.data=root_mesh;trunk.data.materials.append(bark_material)
    trunk.matrix_world.identity()
    trunk['source']='Closed editable root geometry with 5-lobed root flare; Poly Haven bark maps reused'
    base=Vector((.035*math.sin(TRUNK_HEIGHT*1.9),.022*(math.cos(TRUNK_HEIGHT*2.6)-1),TRUNK_HEIGHT))
    for ob in list(scene.objects):
        if ob.name.startswith(('Primary_Branch','Leader_Branch')):bpy.data.objects.remove(ob,do_unlink=True)
    def core(z):
        co=base.lerp(Vector((.02,0,1.95)),max(0,min(1,(z-TRUNK_HEIGHT)/.53)))
        co.z=z;return co
    paths=[
      ('Leader_Branch',[base-Vector((0,0,.06)),core(1.85),Vector((.01,.02,2.48))],[.135,.095,.048]),
      ('Primary_Branch_00',[core(1.38),Vector((-.64,-.18,1.68)),Vector((-1.12,-.30,1.94))],[.095,.058,.026]),
      ('Primary_Branch_01',[core(1.42),Vector((.66,-.16,1.72)),Vector((1.16,-.26,1.98))],[.095,.058,.026]),
      ('Primary_Branch_02',[core(1.48),Vector((-.52,.36,1.88)),Vector((-.90,.68,2.34))],[.082,.050,.022]),
      ('Primary_Branch_03',[core(1.52),Vector((.54,.34,1.92)),Vector((.92,.66,2.38))],[.082,.050,.022]),
      ('Primary_Branch_04',[core(1.56),Vector((.22,-.48,1.88)),Vector((.38,-.82,2.24))],[.068,.042,.020]),
      ('Primary_Branch_05',[Vector((-.64,-.18,1.68)),Vector((-.82,-.46,1.82)),Vector((-.98,-.68,1.96))],[.056,.036,.016]),
      ('Primary_Branch_06',[Vector((.66,-.16,1.72)),Vector((.84,-.42,1.86)),Vector((1.02,-.64,2.00))],[.056,.036,.016]),
      ('Primary_Branch_07',[core(1.82),Vector((-.28,.18,2.18)),Vector((-.52,.34,2.46))],[.058,.036,.016]),
      ('Primary_Branch_08',[core(1.86),Vector((.28,.16,2.22)),Vector((.52,.32,2.50))],[.058,.036,.016]),
      ('Primary_Branch_09',[Vector((.01,.02,2.12)),Vector((-.02,-.24,2.42)),Vector((-.04,-.42,2.68))],[.050,.032,.014])]
    def build_collar_branch(name,pts,rads):
        # Continuous cylindrical bark UV along the branch axis + swollen collar at ring 0
        b_verts=[];b_faces=[];SIDES=6;RINGS=5
        arc=0.0;ring_v=[0.0]
        sampled=[]
        for ri in range(RINGS):
            t=ri/(RINGS-1)
            # Quadratic bezier interpolation across the 3 control points
            p=(1-t)**2*pts[0]+2*(1-t)*t*pts[1]+t**2*pts[2]
            r=(1-t)*rads[0]+t*rads[2] if ri>0 else rads[0]*1.26
            if ri==0:p=p-(pts[1]-pts[0]).normalized()*.035
            sampled.append((p,r))
            if ri>0:
                arc+=(sampled[ri][0]-sampled[ri-1][0]).length
                ring_v.append(arc/.95)
        for ri,(p,r) in enumerate(sampled):
            tan=(sampled[min(ri+1,RINGS-1)][0]-sampled[max(0,ri-1)][0]).normalized()
            up_ref=Vector((0,0,1)) if abs(tan.z)<.9 else Vector((1,0,0))
            side_v=tan.cross(up_ref).normalized()
            up_v=side_v.cross(tan).normalized()
            for s in range(SIDES):
                a=s*math.tau/SIDES
                b_verts.append(tuple(p+(side_v*math.cos(a)+up_v*math.sin(a))*r))
        for ri in range(RINGS-1):
            for s in range(SIDES):
                a=ri*SIDES+s;b=ri*SIDES+(s+1)%SIDES
                b_faces.append((a,b,b+SIDES,a+SIDES))
        for s in range(1,SIDES-1):
            b_faces.append((0,s+1,s))
        ts=(RINGS-1)*SIDES
        for s in range(1,SIDES-1):
            b_faces.append((ts,ts+s,ts+s+1))
        bm_mesh=bpy.data.meshes.new(name)
        bm_mesh.from_pydata(b_verts,[],b_faces);bm_mesh.update()
        buv=bm_mesh.uv_layers.new(name='UVMap')
        for f in bm_mesh.polygons:
            f.use_smooth=len(f.vertices)==4
            seam=max(v%SIDES for v in f.vertices)-min(v%SIDES for v in f.vertices)>3
            for li in f.loop_indices:
                vi=bm_mesh.loops[li].vertex_index
                u=(vi%SIDES)/SIDES
                if seam and u==0:u=1.0
                buv.data[li].uv=(u,ring_v[vi//SIDES])
        ob=bpy.data.objects.new(name,bm_mesh);scene.collection.objects.link(ob)
        ob['role']='benchmark_asset';ob.data.materials.append(bark_material)
    for name,points,radii in paths:
        build_collar_branch(name,points,radii)

stem_vertices=[];stem_faces=[];stem_uv=[]
leaf_records=[]
# Ten boundary segments preserve a rounded, natural ovate leaf at mature tree scale.
outline=[(0,-.155)]
for j in range(1,5):
    t=j/5;outline.append((.098*math.sin(math.pi*(t**.86))**.72,-.155+.335*t))
outline.append((0,.180))
for j in range(4,0,-1):
    t=j/5;outline.append((-.098*math.sin(math.pi*(t**.86))**.72,-.155+.335*t))
prototype=[Vector((0,.005,.020))]+[Vector((x,y,-.011*(y/.180)**2)) for x,y in outline]
uvs=[(.5,.5)]+[(x/.20+.5,(y+.165)/.355) for x,y in outline]
faces=[(0,1+i,1+(i+1)%10) for i in range(10)]
LEAVES_PER_SPRAY=22
leaf_base=prototype[1]

def tube(points,radii,cap_base=True):
    start=len(stem_vertices)
    for ring,(p,r) in enumerate(zip(points,radii)):
        tangent=(points[min(ring+1,len(points)-1)]-points[max(0,ring-1)]).normalized()
        up_ref=Vector((0,0,1)) if abs(tangent.z)<.9 else Vector((1,0,0))
        side=tangent.cross(up_ref).normalized()
        up=tangent.cross(side).normalized()
        for j in range(3):
            a=j*math.tau/3
            stem_vertices.append(tuple(p+(side*math.cos(a)+up*math.sin(a))*r))
    for ring in range(len(points)-1):
        for j in range(3):
            a=start+ring*3+j;b=start+ring*3+(j+1)%3;c=a+3;d=b+3
            stem_faces.extend([(a,b,d),(a,d,c)])
            stem_uv.extend([(j/3,ring*.5),((j+1)/3,ring*.5),((j+1)/3,(ring+1)*.5),(j/3,ring*.5),((j+1)/3,(ring+1)*.5),(j/3,(ring+1)*.5)])
    if cap_base:
        stem_faces.append((start+2,start+1,start))
        stem_uv.extend([(0,0),(.33,0),(.66,0)])
    tip=start+(len(points)-1)*3
    stem_faces.append((tip,tip+1,tip+2))
    stem_uv.extend([(0,1),(.33,1),(.66,1)])

def spray(index,anchor,yaw,tilt,size=1,tier_tint=.5):
    pose=Euler((tilt,rng.uniform(-.15,.15),yaw),'XYZ').to_matrix()
    # Compound branched twig (main stem + lateral side-shoot) breaks single-stick repetition.
    def world(p):return anchor+pose@(p*size)
    curve_x=rng.uniform(-.07,.07)
    arch_z=rng.uniform(-.04,.05)
    p0=Vector((0,0,0))
    p1=Vector((curve_x*.5,.44,.05+arch_z*.5))
    p2=Vector((curve_x,.88,.06+arch_z))
    tube([world(p0),world(p1),world(p2)],[.013*size,.0075*size,.0028*size],cap_base=True)
    # Lateral fork shoot on alternating side
    fork_side=-1 if index%2 else 1
    f0=Vector((curve_x*.32,.28,.035))
    f1=Vector((curve_x*.32+fork_side*.28,.64,.05+arch_z*.6))
    if index%2==0:
        tube([world(f0),world(f1)],[.007*size,.0025*size],cap_base=False)
    vertices=[];polygons=[];normals=[];colors=[];all_uv=[]
    base_tint=max(.08,min(.92,tier_tint+rng.uniform(-.06,.06)))
    for leaf in range(LEAVES_PER_SPRAY):
        if leaf<14:
            # 14 leaves along the primary curving twig
            terminal=(leaf==13)
            u_t=(leaf//2)/6.0 if not terminal else 1.0
            station=.08+.78*u_t
            side=-1 if leaf%2 else 1
            attach=(1-u_t)**2*p0+2*(1-u_t)*u_t*p1+u_t**2*p2
            yaw_off=(side*rng.uniform(.78,1.32)) if not terminal else rng.uniform(-.16,.16)
        elif leaf<18:
            # 4 leaves fanning out on the lateral fork shoot
            sub_i=leaf-14
            u_t=(sub_i+1)/4.0
            side=-1 if sub_i%2 else 1
            attach=f0.lerp(f1,u_t)
            yaw_off=fork_side*.58+(side*rng.uniform(.65,1.15) if sub_i<3 else 0.0)
        else:
            # 4 opposite counter-fan leaves for a broad, full 3D botanical cluster
            sub_i=leaf-18
            u_t=(sub_i+1)/4.0
            side=-1 if sub_i%2 else 1
            opp_end=Vector((curve_x*.4-fork_side*.25,.60,.06))
            attach=Vector((curve_x*.25,.24,.03)).lerp(opp_end,u_t)
            yaw_off=-fork_side*.55+(side*rng.uniform(.65,1.15) if sub_i<3 else 0.0)
        pitch_l=rng.uniform(-.36,.32)
        roll_l=rng.uniform(-.38,.38)
        leaf_rot=Euler((pitch_l,roll_l,yaw_off),'XYZ').to_matrix()
        scale=rng.uniform(1.02,1.32)*(1.10 if leaf in (13,17,21) else 1.0)
        offset=len(vertices)
        normal=(pose@leaf_rot@Vector((0,0,1))).normalized()
        leaf_tint=max(.05,min(.96,base_tint+(attach.y/.88)*.16+rng.uniform(-.04,.04)))
        for vi,p in enumerate(prototype):
            co=world(attach+leaf_rot@((p-leaf_base)*scale))
            vertices.append(tuple(co))
            local_dome=(co-(anchor+pose@Vector((0,.42,-.28)))).normalized()
            normals.append(tuple((normal*.68+local_dome*.32).normalized()))
            colors.append((1,leaf_tint,max(0,min(1,(co.z-.6)/3.2))*uvs[vi][1],1))
        for face in faces:
            polygons.append(tuple(offset+i for i in face));all_uv.extend(uvs[i] for i in face)
        leaf_records.append((index,leaf,Vector(vertices[offset]),normal))
    mesh=bpy.data.meshes.new('SprayMesh_%02d'%index)
    mesh.from_pydata(vertices,[],polygons);mesh.update()
    for f in mesh.polygons:f.use_smooth=True
    mesh.normals_split_custom_set_from_vertices(normals)
    uv=mesh.uv_layers.new(name='UVMap')
    for i,value in enumerate(all_uv):uv.data[i].uv=value
    attr=mesh.color_attributes.new(name='AssetData',type='FLOAT_COLOR',domain='POINT')
    for i,value in enumerate(colors):attr.data[i].color=value
    mesh.color_attributes.active_color_name='AssetData'
    ob=bpy.data.objects.new('LeafClump_%02d'%index,mesh);canopy.objects.link(ob)
    ob.data.materials.append(leaf_material)
    ob['role']='benchmark_asset';ob['leaf_count']=LEAVES_PER_SPRAY;ob['normal_blend']=.32
    ob['construction']='22 individual leaves anchored to a real branched twig; no shell-shingle distribution'
    return ob

sprays=[]
if SAMPLE:
    sprays.append(spray(0,Vector((-.12,0,.1)),-.65,.18,1,.42))
    sprays.append(spray(1,Vector((.12,.30,.18)),.70,.28,.95,.68))
    tube([Vector((0,-.35,.02)),Vector((0,.05,.1)),Vector((.12,.30,.18))],[.025,.015,.007])
else:
    # Six major bough systems organized into a 3-tier rounded dome (lower skirt,
    # mid-crown shoulders, and tall central dome) while closing the top-down center.
    forms=[
      # Tier 1 (0 & 1): Wide lower-left and lower-right sweeping skirt boughs
      ((-.48,-.16,1.56),(-1.28,-.34,2.02),1.05,.14),
      ((.50,-.14,1.60),(1.32,-.30,2.06),1.05,.18),
      # Tier 2 (2, 3, 4): Mid-crown billowing shoulder boughs (front, back-left, back-right)
      ((.18,-.34,1.72),(.44,-.96,2.38),1.04,.42),
      ((-.44,.28,1.76),(-1.04,.78,2.48),1.06,.46),
      ((.46,.26,1.80),(1.06,.76,2.52),1.06,.50),
      # Tier 3 (5): Upper-central summit dome crowning the tree top
      ((-.04,-.04,2.15),(.02,.06,2.98),1.08,.80)]
    for main,(begin,end,size,tier_base) in enumerate(forms):
        begin=Vector(begin);end=Vector(end)
        outward=math.atan2(-end.x,end.y) if Vector((end.x,end.y)).length>.2 else 0.0
        for sub in range(5):
            if main<2:
                # Lower tier: sub 0 bridges upward, sub 1..4 fan wide with gentle upward arch
                yaw_offsets=[math.pi*.78,-1.02,1.02,-.36,.36]
                tilt_vals=[.44,.28,.26,.18,.12]
                t_along=[.28,.50,.68,.86,1.0][sub]
                t_tint=tier_base+[.20,-.02,.02,-.04,.06][sub]
            elif main<5:
                # Mid-shoulder tier: stronger upward dome arch to build the rounded mid-crown
                yaw_offsets=[math.pi*.80,-.94,.94,-.34,.34]
                tilt_vals=[.48,.36,.34,.24,.18]
                t_along=[.26,.48,.66,.85,1.0][sub]
                t_tint=tier_base+[.22,.02,.04,.0,.08][sub]
            else:
                # Upper-central crown leader: 5 radiating summit sprays forming a rounded apex dome
                yaw_offsets=[0.0,1.25,-1.25,2.50,-2.50]
                tilt_vals=[.38,.42,.44,.50,.54]
                t_along=[.24,.44,.64,.82,1.0][sub]
                t_tint=tier_base+[-.06,-.02,.02,.08,.14][sub]
            yaw=outward+yaw_offsets[sub]+rng.uniform(-.10,.10)
            tilt=tilt_vals[sub]+rng.uniform(-.05,.05)
            anchor=begin.lerp(end,t_along)
            sprays.append(spray(main*5+sub,anchor,yaw,tilt,size*rng.uniform(.96,1.06),t_tint))

mesh=bpy.data.meshes.new('TwigBranches');mesh.from_pydata(stem_vertices,[],stem_faces);mesh.update()
twig_uv=mesh.uv_layers.new(name='UVMap')
for i,uv_co in enumerate(stem_uv):twig_uv.data[i].uv=uv_co
twig=bpy.data.objects.new('TwigBranches_LOD0',mesh);scene.collection.objects.link(twig)
twig['role']='benchmark_asset';twig.data.materials.append(bark_material)
for f in mesh.polygons:f.use_smooth=True

objects=[o for o in scene.objects if o.get('role')=='benchmark_asset']
verts=[];polys=[];owners=[]
for ob in objects:
    start=len(verts);verts.extend(tuple(ob.matrix_world@v.co) for v in ob.data.vertices)
    for f in ob.data.polygons:
        polys.append(tuple(start+i for i in f.vertices))
        owners.append((ob.name,f.index//10 if ob in sprays else -1))
bvh=BVHTree.FromPolygons(verts,polys,all_triangles=False,epsilon=.0001)
ao_values=[]
for group,leaf,point,normal in leaf_records:
    tangent=normal.cross(Vector((1,0,0)) if abs(normal.x)<.8 else Vector((0,1,0))).normalized()
    bitangent=normal.cross(tangent).normalized()
    visible=0
    for ray in range(24):
        z=(ray+.5)/24;r=math.sqrt(1-z*z);a=ray*2.399963
        direction=(tangent*(r*math.cos(a))+bitangent*(r*math.sin(a))+normal*z).normalized()
        origin=point+normal*.008;remaining=1.0;blocked=False
        for crossing in range(6):
            hit,_,face,distance=bvh.ray_cast(origin,direction,remaining)
            if hit is None:break
            if owners[face]!=(sprays[group].name,leaf):blocked=True;break
            remaining-=distance+.004;origin=hit+direction*.004
            if remaining<=0:break
        if not blocked:visible+=1
    ao=visible/24;ao_values.append(ao)
    data=sprays[group].data.color_attributes['AssetData'].data
    for i in range(len(prototype)):
        entry=data[leaf*len(prototype)+i];color=list(entry.color);color[0]=ao;entry.color=color

scene['construction']='Offline editable branch-spray refinement. Not represented as manual UI modeling.'
scene['vertex_contract']='R BVH hemisphere visibility (24 rays/leaf, 1m radius), G neutral color variation, B tip wind weight'
scene['leaf_count']=len(leaf_records)
report={'leaves':len(leaf_records),'clumps':len(sprays),'leaf_triangles':10,'triangles':sum(sum(len(f.vertices)-2 for f in o.data.polygons) for o in objects),'ao_method':'24 actual BVH visibility rays per leaf; no height-based AO','ao_min':min(ao_values),'ao_mean':sum(ao_values)/len(ao_values),'ao_max':max(ao_values),'process':'offline editable Blender assembly'}
if SAMPLE:
    for other in list(bpy.data.scenes):
        if other!=scene:bpy.data.scenes.remove(other)
    bpy.data.orphans_purge(do_recursive=True)
    path=OUT/'source/leaf_spray_study.blend'
else:
    # Update the editable leaf modules instead of leaving obsolete half-meter templates.
    mods=bpy.data.collections.get('91_Leaf_Modules_NO_EXPORT')
    if mods:
        for ob in list(mods.objects):bpy.data.objects.remove(ob,do_unlink=True)
        for i in range(4):
            me=bpy.data.meshes.new('Leaf_Module_%02d'%i);me.from_pydata(prototype,[],faces);me.update()
            ob=bpy.data.objects.new(me.name,me);mods.objects.link(ob);ob.hide_viewport=True;ob.hide_render=True
            uv=me.uv_layers.new(name='UVMap')
            for f in me.polygons:
                for li in f.loop_indices:uv.data[li].uv=uvs[me.loops[li].vertex_index]
    guides=bpy.data.collections.get('90_Editable_Form_Guides_NO_EXPORT')
    if guides:
        for ob in list(guides.objects):
            if ob.name.startswith(('FormGuide','SprayHub')):bpy.data.objects.remove(ob,do_unlink=True)
        for i,(begin,end,size,*_) in enumerate(forms):
            guide=bpy.data.objects.new('SprayHub_%02d'%i,None);guides.objects.link(guide)
            guide.location=end;guide.empty_display_type='ARROWS';guide.empty_display_size=.2
            guide['note']='Branch graft point; not an occlusion or shadow proxy'
    path=OUT/'source/broadleaf_editable.blend'
if not SAMPLE:
    check=bmesh.new();check.from_mesh(trunk.data)
    report['root_closed']=all(edge.is_manifold for edge in check.edges)
    assert report['root_closed'],'Root must be a closed volume'
    check.free()
scene['lod0_triangles']=report['triangles']
bpy.ops.wm.save_as_mainfile(filepath=str(path))
bpy.ops.object.select_all(action='DESELECT')
for ob in objects:
    ob.select_set(True)
    ob.data.materials.clear()
    m=bpy.data.materials.get('Study_Leaf' if ob in sprays else 'Study_Bark')
    if m is None:m=bpy.data.materials.new('Study_Leaf' if ob in sprays else 'Study_Bark')
    ob.data.materials.append(m)
    for f in ob.data.polygons:f.material_index=0
target=OUT/'models/leaf_spray_study.glb' if SAMPLE else OUT/'models/broadleaf_lod0.glb'
bpy.ops.export_scene.gltf(filepath=str(target),use_selection=True,use_active_scene=True,export_format='GLB',export_normals=True,export_tangents=True,export_vertex_color='ACTIVE',export_all_vertex_colors=False)
(OUT/'reports'/('spray_study.json' if SAMPLE else 'geometry.json')).write_text(json.dumps(report,indent=2))
print('SPRAY_REFINEMENT',report)
