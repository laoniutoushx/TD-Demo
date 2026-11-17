"""Export actual UI captures and deterministic slot crops; no generated screenshots."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import argparse, json, shutil

parser = argparse.ArgumentParser()
parser.add_argument('--round', required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
source = root / '.godot/ui_material_review'
out = Path(__file__).parent / args.round
pages = out / 'pages'
pages.mkdir(parents=True, exist_ok=True)
font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 17)
names = ['menu', 'menu_focus', 'settings', 'settings_dropdown', 'choose_player',
         'battle', 'tooltip', 'talent_choice', 'victory', 'defeat']
for resolution in ['1080x768', '1920x1080', '2560x1080']:
    for name in names:
        shutil.copyfile(source / f'{resolution}_{name}.png', pages / f'{resolution}_{name}.png')
for path in source.glob('1080x768_slot_*.png'):
    shutil.copyfile(path, pages / path.name)
for name in ['1080x768_talent_hover', '1080x768_talent_cooldown']:
    shutil.copyfile(source / f'{name}.png', pages / f'{name}.png')

metrics = json.loads((source / '1080x768_metrics.json').read_text(encoding='utf-8'))
for kind, rect in metrics['slot_rects'].items():
    captures = [('NORMAL', source / '1080x768_battle.png')]
    if kind == 'talent':
        captures += [('HOVER', source / '1080x768_talent_hover.png'),
                     ('REAL COOLDOWN', source / '1080x768_talent_cooldown.png')]
    else:
        captures += [('HOVER', source / f'1080x768_slot_{kind}_hover.png'),
                     ('DISABLED DISPLAY', source / f'1080x768_slot_{kind}_disabled.png')]
        if kind in ['skill', 'item']:
            captures += [('MASK PREVIEW', source / f'1080x768_slot_{kind}_cooldown_preview.png')]
    x, y, w, h = rect
    width = max(180, round((w + 8) * 3))
    sheet = Image.new('RGB', (len(captures) * width, round((h + 8) * 3) + 32), (19, 23, 19))
    draw = ImageDraw.Draw(sheet)
    for i, (label, path) in enumerate(captures):
        crop = Image.open(path).convert('RGB').crop((round(x-4), round(y-4), round(x+w+4), round(y+h+4)))
        crop = crop.resize((crop.width * 3, crop.height * 3), Image.Resampling.NEAREST)
        sheet.paste(crop, (i * width + (width-crop.width)//2, 32))
        draw.text((i * width+4, 6), label, font=font, fill=(235, 229, 205))
    sheet.save(out / f'states_{kind}.png')

gallery_names = ['menu', 'settings', 'choose_player', 'battle', 'talent_choice', 'victory']
gallery = Image.new('RGB', (960, 3 * 372), (19, 23, 19))
draw = ImageDraw.Draw(gallery)
for i, name in enumerate(gallery_names):
    img = Image.open(source / f'1080x768_{name}.png').convert('RGB')
    img.thumbnail((480, 342), Image.Resampling.LANCZOS)
    x, y = (i % 2) * 480, (i // 2) * 372
    gallery.paste(img, (x, y + 30))
    draw.text((x+6, y+5), name.upper(), font=font, fill=(235, 229, 205))
gallery.save(out / 'pages_overview.png')
for name in ['menu', 'settings']:
    before = Image.open(root / f'.godot/round8_before/1080x768_{name}.png').convert('RGB')
    after = Image.open(source / f'1080x768_{name}.png').convert('RGB')
    sheet = Image.new('RGB', (2160, 800), (19, 23, 19))
    sheet.paste(before, (0, 32)); sheet.paste(after, (1080, 32))
    draw = ImageDraw.Draw(sheet)
    draw.text((8, 6), 'BEFORE', font=font, fill=(235, 229, 205))
    draw.text((1088, 6), 'CURRENT', font=font, fill=(235, 229, 205))
    sheet.save(out / f'page_compare_{name}.png')
print('PAGE_AND_SLOT_REVIEW_EXPORTED')
