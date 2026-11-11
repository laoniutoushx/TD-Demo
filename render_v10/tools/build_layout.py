"""Author the Level1 scenery and pack its ecological mask. Run from project root."""
from pathlib import Path
import json
import re
import sys
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
LEVEL = ROOT / 'Levels/level_1/Level1.tscn'
REMOVED = [(-38,10),(-34,10),(-38,14),(22,2),(26,2),(26,-2),(-34,-10),(-38,-10),(-38,-14),(30,-22),(34,-22),(34,-26),(-14,14),(-10,14),(-10,10),(22,-42),(26,-38),(-18,18),(-2,18),(14,18)]

def author():
    text = LEVEL.read_text(encoding='utf-8')
    def trim_grid(match):
        values = [int(v) for v in match[1].split(',')]
        def signed(v):
            return (v & 65535) - (65536 if v & 32768 else 0)
        triples = [values[i:i+3] for i in range(0,len(values),3)]
        kept = [t for t in triples if ((signed(t[0])+.5)*4, (signed(t[1])+.5)*4) not in REMOVED]
        assert len(kept) == 180
        return '"cells": PackedInt32Array(' + ', '.join(str(v) for t in kept for v in t) + ')'
    text = re.sub(r'"cells": PackedInt32Array\((.*?)\)', trim_grid, text)
    blocks = re.split(r'(?=\[node )', text)
    blocks = [b for b in blocks if not (b.startswith('[node ') and ('instance=ExtResource("tree_' in b or '[node name="Rock2"' in b))]
    text = ''.join(blocks)
    if 'id="scenery_layout"' not in text:
        text = text.replace('[sub_resource type="ProceduralSkyMaterial"', '[ext_resource type="PackedScene" path="res://render_v10/scenery_layout.tscn" id="scenery_layout"]\n\n[sub_resource type="ProceduralSkyMaterial"',1)
        text += '\n[node name="SceneryLayout" parent="Environment" instance=ExtResource("scenery_layout")]\n'
        text = text.replace('load_steps=48', 'load_steps=49')
    text = text.replace('light_energy = 1.75', 'light_energy = 1.40').replace('ambient_light_energy = 0.36','ambient_light_energy = 0.48')
    for resource in re.findall(r'^\[ext_resource .*? id="([^"]+)"\]$', text, re.M):
        if f'ExtResource("{resource}")' not in text:
            text = re.sub(r'^\[ext_resource .*? id="'+re.escape(resource)+r'"\]\n', '', text, flags=re.M)
    steps = len(re.findall(r'^\[(?:ext_resource|sub_resource) ', text, re.M)) + 1
    text = re.sub(r'load_steps=\d+', f'load_steps={steps}', text, count=1)
    LEVEL.write_text(text, encoding='utf-8')
    resources = {'column':'meshy_assets/column.glb','fallen':'render_v10/assets/fallen_column.glb','rock':'render_v10/assets/rock_0_lod1.glb','pot':'meshy_assets/pot.glb','shrub':'meshy_assets/shrub_lod1.glb'}
    resources['brazier'] = 'render_v10/brazier.tscn'
    for i in range(5): resources[f'tree{i}'] = f'asset_lab/styles/tree_{i}_style_0.tscn'
    resources['tree0'] = 'asset_lab/benchmark/tree_style_0_lod_1.tscn'
    lines = [f'[gd_scene load_steps={len(resources)+1} format=3]']
    lines += [f'[ext_resource type="PackedScene" path="res://{path}" id="{name}"]' for name,path in resources.items()]
    lines += ['[node name="SceneryLayout" type="Node3D"]']
    items=[]
    def place(kind,x,z,size,angle=0):
        name=f'{kind}_{len(items):03d}'
        lines.extend([f'\n[node name="{name}" parent="." instance=ExtResource("{kind}")]',f'position = Vector3({x}, 0, {z})',f'rotation = Vector3({1.5708 if kind == "fallen" else 0}, {angle}, 0)', f'metadata/target_size = {float(size)}', f'metadata/kind = "{kind}"'])
        items.append({'kind':kind,'x':x,'z':z,'size':size})
    # Three trees per outer clump. Heights and silhouettes alternate within clumps.
    centers=[(-52,12),(-48,-9),(-48,-27),(-30,-44),(-12,-44),(8,-30),(30,-44),(42,-22),(42,1),(20,26)]
    for i,(x,z) in enumerate(centers):
        for j,(dx,dz) in enumerate([(-2,0),(1,2),(3,-2)]):
            place(f'tree{[0,1,0,2,1,0,4,1,0,3][i] if j == 2 else (i+j)%2}',x+dx,z+dz,5.0+j*.8,(i+j)*1.73)
    for i,(x,z) in enumerate([(-38,14),(26,2),(-38,-14),(34,-26),(22,-42),(26,-38),(-18,18),(14,18)]):
        place('tree0' if i%3 else 'tree1',x,z,2.8 if i<4 else 3.0,i*1.5)
    for x,z,height in [(-38,10,3.6),(-34,10,2.5),(22,2,3.2),(-34,-10,3.5),(30,-22,3.2),(-14,14,2.8)]:
        place('column',x,z,height,0.2)
    for x,z in [(-38,-10),(26,-2),(34,-22)]: place('fallen',x,z,2.3,.55)
    for i,(x,z) in enumerate(REMOVED[:15]):
        if (x,z) != (-10,14):
            place('rock',x+.7,z+.55,.65+(i%3)*.18,i*2.4)
            place('shrub',x-.2,z+.2,.8+(i%2)*.25,i)
    for x,z in [(-37.4,10.6),(22.7,2.5),(-33.5,-10.6),(30.6,-22.7),(-13.2,14.7)]: place('pot',x,z,.48,1.2)
    for x,z in [(-35.2,10.4),(23,2.9),(-34.7,-10.9)]: place('brazier',x,z,.55)
    (ROOT/'render_v10/scenery_layout.tscn').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    (ROOT/'render_v10/layout_manifest.json').write_text(json.dumps({'removed_centers':REMOVED,'items':items},indent=2),encoding='utf-8')

def bake():
    # Retain the existing distance data exactly in R. G follows the authored canopy.
    path=ROOT/'render_v10/textures/road_distance_level1.png'
    red=np.asarray(Image.open(path).convert('RGB'))[:,:,0]
    h,w=red.shape
    x,z=np.meshgrid(-80+(np.arange(w)+.5)*160/w,-70+(np.arange(h)+.5)*140/h)
    cover=np.zeros((h,w))
    scene=(ROOT/'render_v10/scenery_layout.tscn').read_text(encoding='utf-8')
    for block in re.split(r'(?=\[node )', scene)[1:]:
        kind=re.search(r'metadata/kind = "(.*?)"',block)
        if kind and (kind[1].startswith('tree') or kind[1]=='shrub'):
            position=re.search(r'position = Vector3\((.*?), (.*?), (.*?)\)',block)
            size=float(re.search(r'metadata/target_size = ([\d.]+)',block)[1])
            radius=size*.6+1.0
            falloff=np.clip(1-np.hypot(x-float(position[1]),z-float(position[3]))/radius,0,1)
            cover=np.maximum(cover,falloff)
    rgb=np.stack([red,np.uint8(cover*255),np.zeros_like(red)],axis=-1)
    Image.fromarray(rgb).save(path)

if __name__=='__main__':
    if '--bake-only' not in sys.argv: author()
    bake()
