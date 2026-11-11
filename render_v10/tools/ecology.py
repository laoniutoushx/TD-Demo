"""Bake world-space road, canopy and height data for the playable scene."""
import re
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
BOUNDS = (-136.0, -88.0, 272.0, 176.0)


def bake():
    scene = (ROOT / 'Levels/level_1/Level1.tscn').read_text(encoding='utf-8')
    points = re.search(r'"points": PackedVector3Array\((.*?)\)', scene)[1]
    controls = np.array([float(v) for v in points.split(',')]).reshape(-1, 3, 3)
    route = []
    for a, b in zip(controls[:-1], controls[1:]):
        for t in np.linspace(0, 1, 60, endpoint=False):
            route.append((1-t)**3*a[2] + 3*(1-t)**2*t*(a[2]+a[1]) + 3*(1-t)*t*t*(b[2]+b[0]) + t**3*b[2])
    route.append(controls[-1, 2])
    x, z = np.meshgrid(BOUNDS[0]+(np.arange(512)+.5)*BOUNDS[2]/512,
                       BOUNDS[1]+(np.arange(512)+.5)*BOUNDS[3]/512)
    distance = np.full_like(x, 1e6)
    for a, b in zip(route[:-1], route[1:]):
        dx, dz = b[0]-a[0], b[2]-a[2]
        fraction = np.clip(((x-a[0])*dx+(z-a[2])*dz)/max(dx*dx+dz*dz, 1e-8), 0, 1)
        distance = np.minimum(distance, np.hypot(x-a[0]-fraction*dx, z-a[2]-fraction*dz))
    clearance = distance - 2.3
    cells = [int(v) for v in re.search(r'"cells": PackedInt32Array\((.*?)\)', scene)[1].split(',')]
    def signed(v):
        return (v & 65535) - (65536 if v & 32768 else 0)
    for i in range(0, len(cells), 3):
        cx, cz = (signed(cells[i])+.5)*4, (signed(cells[i+1])+.5)*4
        # Wider than the interaction footprint so bilinear samples stay flat at its edge.
        rect_distance = np.maximum(abs(x-cx)-3.0, abs(z-cz)-3.0)
        clearance = np.minimum(clearance, rect_distance)
    cover = np.zeros_like(x)
    layout = (ROOT/'render_v10/scenery_layout.tscn').read_text(encoding='utf-8')
    items = []
    for block in re.split(r'(?=\[node )', layout)[1:]:
        kind = re.search(r'metadata/kind = "(.*?)"', block)
        if not kind:
            continue
        pos = re.search(r'position = Vector3\((.*?), (.*?), (.*?)\)', block)
        height = re.search(r'metadata/target_height = ([\d.]+)', block)
        width = float(re.search(r'metadata/target_size = ([\d.]+)', block)[1])
        item = {'kind':kind[1], 'x':float(pos[1]), 'z':float(pos[3]), 'size':width}
        if height: item['height'] = float(height[1])
        items.append(item)
        if not (kind[1].startswith('tree') or kind[1]=='shrub'):
            continue
        radius = float(height[1])*.45 if height else width*.6+1
        cover = np.maximum(cover, np.clip(1-np.hypot(x-float(pos[1]), z-float(pos[3]))/radius, 0, 1))
    ramp = np.clip(clearance/2.0, 0, 1)
    ramp = ramp*ramp*(3-2*ramp)
    height = ramp * np.clip(cover*2, 0, 1) * (.27+.08*np.sin(x*.21)+.05*np.cos(z*.31))
    pixels = np.stack([np.uint8(np.clip(distance/25,0,1)*255),
                       np.uint8(cover*255), np.uint8(height/.5*255)], axis=-1)
    Image.fromarray(pixels).save(ROOT/'render_v10/textures/road_distance_level1.png')
    manifest_path = ROOT/'render_v10/layout_manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    manifest['items'] = items
    manifest['tree_count'] = sum(item['kind'].startswith('tree') for item in items)
    manifest['height_max_m'] = float(height.max())
    manifest_path.write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')


if __name__ == '__main__':
    bake()
