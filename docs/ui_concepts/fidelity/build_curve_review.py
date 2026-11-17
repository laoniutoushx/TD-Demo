"""Diagnostic corner crops. Reference uses one scale, native screenshots stay 1:1."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import argparse, json

parser = argparse.ArgumentParser()
parser.add_argument('--round', required=True)
parser.add_argument('--before-round', required=True)
args = parser.parse_args()
base = Path(__file__).parent
out, prior = base / args.round, base / args.before_round
root = base.parents[2]
scale = 0.874
ref = Image.open(root / 'docs/ui_concepts/material_alignment/reference_a.png').convert('RGB')
ref = ref.resize((round(ref.width*scale), round(ref.height*scale)), Image.Resampling.LANCZOS)
before = Image.open(prior / 'battle.png').convert('RGB')
actual = Image.open(out / 'battle.png').convert('RGB')
old = json.loads((prior / 'metrics.json').read_text(encoding='utf-8'))['actual']
new = json.loads((out / 'metrics.json').read_text(encoding='utf-8'))['actual']
font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 15)

def control_box(rect):
    x,y,w,h = rect
    return tuple(round(v) for v in (x,y,x+w,y+h))

def corner_box(rect, corner):
    x,y,r,b = rect
    return (x if 'L' in corner else r-32,
            y if 'T' in corner else b-32,
            x+32 if 'L' in corner else r,
            y+32 if 'T' in corner else b)

cases = [
    ('wave',(699,56,1025,112),old['wave_rect'],new['wave_rect']),
    ('skill',(372,508,724,672),old['container_frames']['SkillPanel']['drawn_frame'],new['container_frames']['SkillPanel']['drawn_frame']),
    ('item',(740,508,1133,671),old['container_frames']['ItemABuff']['drawn_frame'],new['container_frames']['ItemABuff']['drawn_frame'])]
edges_ref = ref.convert('L').filter(ImageFilter.FIND_EDGES)
edges_actual = actual.convert('L').filter(ImageFilter.FIND_EDGES)
for name, reference_rect, old_rect, new_rect in cases:
    ref_box = tuple(round(v*scale) for v in reference_rect)
    old_box, new_box = control_box(old_rect), control_box(new_rect)
    sheet = Image.new('RGB',(4*160,4*156+32),(19,23,19))
    draw = ImageDraw.Draw(sheet)
    for i,label in enumerate(['REFERENCE','BEFORE','CURRENT','EDGE R/C']):
        draw.text((i*160+6,6),label,font=font,fill=(235,229,205))
    for row,corner in enumerate(['TL','TR','BL','BR']):
        rb, ob, nb = [corner_box(box,corner) for box in [ref_box,old_box,new_box]]
        cyan = edges_ref.crop(rb)
        red = edges_actual.crop(nb)
        overlay = Image.merge('RGB',(red,cyan,cyan))
        crops = [ref.crop(rb),before.crop(ob),actual.crop(nb),overlay]
        for col,crop in enumerate(crops):
            x,y = col*160+16,row*156+56
            sheet.paste(crop.resize((128,128),Image.Resampling.NEAREST),(x,y))
            draw.text((col*160+6,row*156+34),corner,font=font,fill=(235,229,205))
    sheet.save(out / f'curves_{name}.png')
print('CURVE_REVIEW_EXPORTED: reference scale 0.874, native scale 1, corner zoom 4')
