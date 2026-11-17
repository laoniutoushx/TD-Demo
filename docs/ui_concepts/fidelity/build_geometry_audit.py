"""Reference dimension checks; intentionally not an overall visual similarity score."""
from pathlib import Path
import argparse, json

parser = argparse.ArgumentParser()
parser.add_argument('--round', required=True)
args = parser.parse_args()
folder = Path(__file__).parent / args.round
metrics = json.loads((folder / 'metrics.json').read_text(encoding='utf-8'))
actual = metrics['actual']
scale = 0.874
# Manually annotated bounds in the approved concept board. Painted edges have
# an approximately 1-3 source-pixel ambiguity. Gameplay content is excluded.
cases = [
    ('bottom_frame', [1000,236], metrics['actual_visible_frame'][2:]),
    ('skill_container', [352,164], actual['container_frames']['SkillPanel']['drawn_frame'][2:]),
    ('item_container', [393,163], actual['container_frames']['ItemABuff']['drawn_frame'][2:]),
    ('wave', [326,56], actual['wave_rect'][2:]),
    ('avatar', [135,128], actual['header_rects']['avatar'][2:]),
    ('resources', [344,56], actual['header_rects']['resources'][2:]),
    ('unit_slot', [67,59], actual['slot_rects']['unit'][2:]),
    ('skill_slot', [74,74], actual['slot_rects']['skill'][2:]),
    ('item_slot', [106,106], actual['slot_rects']['item'][2:]),
    ('buff_slot', [39,39], actual['slot_rects']['buff'][2:]),
]
rows = []
for name, source, observed in cases:
    target = [v * scale for v in source]
    errors = [abs(a-b)/b for a,b in zip(observed,target)]
    rows.append(dict(element=name, reference_source_size=source,
        target_size=target, actual_size=observed,
        relative_dimension_errors=errors,
        within_ten_percent=all(e <= 0.10 for e in errors)))
result = dict(reference_scale=scale, annotation_uncertainty_source_pixels=3,
    scope='Width and height only; excludes position, material, foliage, typography and states.',
    overall_visual_similarity=None, visual_90_percent_certified=False, measurements=rows)
(folder/'geometry_audit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
lines = ['# Geometry audit', '', 'Dimensions only. This is not a visual similarity percentage.', '',
    '|Element|Reference scaled|Actual|Width error|Height error|Both within 10%|',
    '|---|---|---|---|---|---|']
for r in rows:
    fmt = lambda size: ' × '.join(f'{v:.1f}' for v in size)
    e = r['relative_dimension_errors']
    lines.append(f"|{r['element']}|{fmt(r['target_size'])}|{fmt(r['actual_size'])}|{e[0]:.1%}|{e[1]:.1%}|{r['within_ten_percent']}|")
lines += ['', 'Reference bounds are manually annotated, with about 1–3 source pixels of ambiguity.',
          'No average is published: passing these dimension checks does not certify texture or decorative fidelity.']
(folder/'geometry_audit.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('GEOMETRY_AUDIT_EXPORTED; overall visual score intentionally unset')
