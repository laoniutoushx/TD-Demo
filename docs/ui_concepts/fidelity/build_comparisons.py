"""Deterministic UI evidence crops: no generated pixels, no nonuniform resizing."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json, shutil, argparse
parser=argparse.ArgumentParser()
parser.add_argument("--round",default="round_02")
parser.add_argument("--before-round")
args=parser.parse_args()
ROOT=Path(__file__).resolve().parents[3]
OUT=Path(__file__).parent/args.round
OUT.mkdir(exist_ok=True)
metrics=json.loads((ROOT/'.godot/ui_material_review/1080x768_metrics.json').read_text(encoding='utf-8'))
actual=Image.open(ROOT/'.godot/ui_material_review/1080x768_battle.png').convert('RGB')
reference=Image.open(ROOT/'docs/ui_concepts/material_alignment/reference_a.png').convert('RGB')
before=Image.open(ROOT/'docs/ui_concepts/fidelity/battle.png').convert('RGB')
before_frame=(125,488,830,270)
if args.before_round:
 prior=Path(__file__).parent/args.before_round
 before=Image.open(prior/'battle.png').convert('RGB')
 before_frame=json.loads((prior/'metrics.json').read_text(encoding='utf-8'))['actual_visible_frame']
W=874
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',15)
def align(image,frame):
 x,y,w,h=frame
 scale=W/w
 # All axes share exactly the same scale; whitespace preserves height differences.
 crop=image.crop((round(x-40/scale),round(y-20/scale),round(x+w+20/scale),round(y+h+20/scale)))
 crop=crop.resize((round(crop.width*scale),round(crop.height*scale)),Image.Resampling.LANCZOS)
 canvas=Image.new('RGB',(934,360),(19,23,19))
 canvas.paste(crop,(0,0))
 return canvas
frame=metrics['bar_rect'][:]
frame[3]-=6 # Bottom margin is not part of the visible stone frame.
planes=[align(reference,(350,444,1000,236)),align(before,before_frame),align(actual,frame)]
regions=[('01_frame',(-40,-20,894,320)),('02_left_leaves',(-40,-8,72,176)),('03_top_vine',(-2,-18,265,46)),('04_units',(0,0,175,58)),('05_skills',(18,52,320,210)),('06_items',(335,52,655,160)),('07_buffs',(350,145,650,210)),('08_talent',(690,48,860,210)),('09_bottom_moss',(125,177,315,225)),('10_copper_corner',(834,166,880,212)),('15_bottom_leaf_cluster',(635,180,735,220)),('16_stone_surface',(100,10,250,45)),('17_frame_rail',(180,-3,660,10)),('18_skill_inset',(14,52,330,205)),('19_item_inset',(328,52,690,205)),('20_talent_mount',(685,52,858,205))]
labels=['REFERENCE','BEFORE','CURRENT']
def save_sheet(name, crops):
 # Padding keeps narrow corner crops legible without changing their pixel scale.
 width=max(112,max(c.width for c in crops))
 height=max(c.height for c in crops)
 sheet=Image.new('RGB',(3*width+24,height+30),(19,23,19))
 draw=ImageDraw.Draw(sheet)
 for i,(label,crop) in enumerate(zip(labels,crops)):
  x=i*(width+8)
  sheet.paste(crop,(x+(width-crop.width)//2,30))
  draw.text((x+4,5),label,font=font,fill=(235,229,205))
 sheet.save(OUT/(name+'.png'))
 sheet.resize((sheet.width*4,sheet.height*4),Image.Resampling.NEAREST).save(OUT/(name+'_4x.png'))
for name,box in regions:
 crops=[im.crop(tuple(v+(40 if i%2==0 else 20) for i,v in enumerate(box))) for im in planes]
 save_sheet(name,crops)
actual.save(OUT/'battle.png')
for n in ['1080x768_multiselect','1080x768_unselected','unit_details','1920x1080_battle','2560x1080_battle']:
 shutil.copyfile(ROOT/f'.godot/ui_material_review/{n}.png',OUT/f'{n}.png')
(OUT/'metrics.json').write_text(json.dumps({'actual':metrics,'reference_frame':[350,444,1000,236],'reference_scaled_frame':[874,236*0.874],'actual_visible_frame':frame,'rule':'uniform scale by frame width, common top-left frame origin'},indent=2),encoding='utf-8')
print(f'{len(regions)} aligned bottom-bar sheets + 4x evidence exported')

# Header reference uses the same 0.874 scale as the bottom bar; actual/before retain native pixels.
for name,rbox,abox,bbox,width in [
 ('11_avatar',(295,28,430,156),(45,26,165,146),(14,18,154,158),120),
 ('12_wave',(676,45,1048,120),(367,45,717,120),(367,45,717,120),350),
 ('13_resources',(1074,50,1418,118),(724,50,1028,114),(780,44,1068,116),304),
 ('14_header',(263,18,1453,168),(20,24,1060,154),(20,24,1060,154),1040)]:
 if args.before_round:
  bbox=abox
  if name in ['11_avatar','13_resources']:
   key='avatar' if name=='11_avatar' else 'resources'
   fallback=[20,24,128,128] if key=='avatar' else [788,52,272,56]
   r=json.loads((prior/'metrics.json').read_text(encoding='utf-8'))['actual'].get('header_rects',{}).get(key,fallback)
   pad=6 if key=='avatar' else 8
   bbox=(r[0]-pad,r[1]-pad,r[0]+r[2]+pad,r[1]+r[3]+pad)
 imgs=[]
 for im,box in [(reference,rbox),(before,bbox),(actual,abox)]:
  c=im.crop(box)
  if im is reference:
   c=c.resize((round(c.width*0.874),round(c.height*0.874)),Image.Resampling.LANCZOS)
  imgs.append(c)
 save_sheet(name,imgs)
print(f'{len(regions)+4} comparison regions completed')
