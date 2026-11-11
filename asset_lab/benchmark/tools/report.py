"""Generate review artifacts from the latest native geometry and Godot audit."""
from pathlib import Path
import json
from PIL import Image, ImageDraw

out = Path(__file__).resolve().parents[1]
r = out / 'reports'
data = json.loads((r / 'validation.json').read_text(encoding='utf-8'))
g = json.loads((r / 'geometry.json').read_text(encoding='utf-8'))
stats = json.loads((r / 'lods.json').read_text(encoding='utf-8'))
perf = data['performance']
assert data['triangles'] == [stats[f'lod{i}'] for i in range(3)]
styles = ['写实 PBR', '风格化 PBR（节点烘焙底色）', '俯视卡通']
sheet = Image.new('RGB', (1152, 2160), '#eeeeea')
draw = ImageDraw.Draw(sheet)
for light in range(3):
    for camera in range(3):
        row = light * 3 + camera
        for style in range(3):
            with Image.open(r / f'style{style}_light{light}_camera{camera}.png') as im:
                tile = im.convert('RGB').resize((384, 216))
            sheet.paste(tile, (style * 384, row * 240 + 24))
            draw.text((style * 384 + 8, row * 240 + 5), f'Style {style+1} | Light {light+1} | Camera {camera+1}', fill='black')
sheet.save(r / 'contact_sheet.jpg', quality=95)


def figure(name, caption):
    return f'<figure><img loading="lazy" src="reports/{name}.png" alt="{caption}"><figcaption>{caption}</figcaption></figure>'


performance = f'单树180帧、无帧率上限、采样段无截图读回：GPU P95 {perf["gpu_p95_ms"]:.3f} ms，帧间隔 P95 {perf["wall_p95_ms"]:.3f} ms。2560×1440，MSAA 4×，RTX 3060。不能代表整张游戏地图性能。'
changes = f'''<ul><li>30组复合分叉叶梢，660片几何叶，每片10三角面；叶柄接入真实主/侧细枝，并按三层圆顶宽冠收拢俯视中央开窗。</li><li>主干重建为5瓣板根闭合网格，主梢与10条分叉改用带枝领膨胀（Collar）的连续柱面UV，替代碎裂的Smart UV投射。</li><li>①②恢复引擎默认GGX；③接收真实灯色、能量与阴影。新增Voronoi色块烘焙与三层冷暗部→暖冠顶色彩递进，AO由24条BVH射线采样且间接光只应用一次。</li><li>移除固定接地暗片；实测太阳角直径引入半影颗粒，本验收台改用零角直径加过滤阴影，未取消真实投影。</li><li>LOD统计来自真实网格，UI、源文件和记录保持一致。LOD0/1/2为{stats["lod0"]}/{stats["lod1"]}/{stats["lod2"]}三角面，43个网格表面。</li></ul>'''
remaining = '''<ul><li><b>树冠团块与概念原画仍有差距：</b>本轮已扩展为三层宽冠并闭合俯视中央空洞，但概念图级别的团块雕塑感与疏密节奏仍需美术手工微调。</li><li>复合分叉小枝改善了单棒排布，但近景仍可见局部插片交叠；枝干交界若做英雄近景还可做拓扑焊接。</li><li>节点烘焙底色加入Voronoi笔触色块与四段冷暖渐变，但仍属程序化烘焙，不冒充手工绘制的Krita源稿。</li><li>LOD2为实心三维叶团简化，在近距离会明显变胖；仅适合远景，仍需按实际游戏投影尺寸校准，滞回不等于无跳变。</li><li>43个表面便于单独修改，但大量植树前仍需合并静态木质表面、实例化和整场景性能测试。</li></ul>'''
html = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>阔叶树 · 本轮实机对照</title><style>
body{max-width:1440px;margin:32px auto;padding:0 24px;font:16px/1.65 system-ui;background:#ece9df;color:#25352a}section{margin:32px 0}article,.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}.pair{grid-template-columns:repeat(2,1fr)}figure{margin:0;background:#fff;padding:8px;border-radius:8px}img,video{width:100%;display:block}figcaption{padding:8px}select{font:inherit;padding:6px;margin:8px}.note{background:#fff9d9;padding:16px;border-left:4px solid #a48c3a}a{color:#31683b}@media(max-width:800px){article,.grid,.pair{grid-template-columns:1fr}}</style>
<h1>阔叶树 · 自然叶梢与真实受光</h1><p>2026-11-07 · Godot 4.7.2 Forward+ / Vulkan · 参考评审板的修正验证</p>
<p class="note"><b>本轮状态：可编辑 WIP，技术检查通过，概念美术尚未通过。</b>初始制作采用离线 Blender 辅助组装与节点烘焙。没有冒充手工建模、手绘成品，也不以技术PASS给出概念相似度百分比。</p>
<section><h2>本轮前后（同一斜视机位，材质也有改动）</h2><article class="pair">BEFORE_AFTER</article><p>旧版为本轮开始时的工作区快照：叠瓦式大叶、重复AO与固定接地暗片；不是概念图。下方分别看结构和受光证据。</p></section>
<section><h2>从小枝样板到整树</h2><article>STUDY</article><p>小枝44片叶、489三角面；整树660片叶、30组复合叶梢。每片叶由几何形成轮廓，运行时不生成模型。</p>CHANGES</section>
<section><h2>同一几何，三种材质</h2><article>STYLES</article></section>
<section><h2>三风格同屏</h2><article class="pair">SBS</article></section>
<section><h2>27组固定对照</h2><label>风格<select id="style"><option value="0">写实</option><option value="1" selected>风格化 PBR</option><option value="2">卡通</option></select></label><label>光照<select id="light"><option value="0">午后</option><option value="1">中性</option><option value="2">阴天</option></select></label><label>相机<select id="camera"><option value="0">整体</option><option value="1">俯视</option><option value="2">近景</option></select></label><img id="preview" alt="选择条件对应的Godot截图" src="reports/style1_light0_camera0.png"><a href="reports/contact_sheet.jpg">27图联系表</a></section>
<section><h2>阴影颗粒定位</h2><article class="pair">SHADOWS</article><p>固定几何和相机。单改法线偏移0.025→8仍有颗粒；角直径0.3→0消除所见的半影黑点。保留阴影贴图与过滤，不用整体模糊或固定黑圆掩盖。此结论限于本验收配置，不代表所有黑影都由同一原因造成。接口说明见<a href="https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html">Godot灯光与阴影文档</a>。</p></section>
<section><h2>连续环绕与轻风</h2><video controls preload="metadata" src="reports/orbit.mp4"></video><p>240个连续引擎输出帧，前半静态、后半轻风，按30FPS编码；播放帧率不是游戏帧率。风动使用引擎实际时间。</p></section>
<section><h2>显式LOD与关灯检查</h2><article>LODS</article><p>LOD2是三维体积，无整树billboard。自动距离14m/28m，±8%滞回。</p><article>ENERGY</article></section>
<section><h2>验收范围与剩余差距</h2><p>PERF</p><p>15个旧参考组合、9个风格/LOD组合的外部材质与纹理、顶点色、快捷键、Home复位、重复切换节点数量、7组LOD滞回通过。27张图与240帧环绕经渲染输出，图像仍需要艺术评审，不是自动视觉PASS。</p>REMAINING<p>日志含系统证书、用户目录/冷Shader缓存写入权限提示；最终渲染与资源检查完成，未将环境错误称为零错误运行。</p><p><a href="reports/validation.json">Godot原始记录</a> · <a href="reports/geometry.json">原生几何与采样记录</a> · <a href="walkthrough.md">8项诊断复核</a></p></section>
<p><a href="leaf_study.tscn">小枝场景</a> · <a href="source/broadleaf_editable.blend">可编辑Blender工程</a> · <a href="制作与跟做.md">人工跟做教程</a></p>
<script>for(const el of document.querySelectorAll('select'))el.addEventListener('change',()=>{document.querySelector('#preview').src=`reports/style${document.querySelector('#style').value}_light${document.querySelector('#light').value}_camera${document.querySelector('#camera').value}.png`;});</script></html>'''
replacements = {
    'BEFORE_AFTER': figure('before_refine_oblique', '本轮开始：旧版叠瓦树冠') + figure('style1_light0_camera0', '本轮结果：真实枝梢与几何叶'),
    'STUDY': ''.join(figure(f'spray_study_style{s}_view0', styles[s] + ' · 小枝样板') for s in range(3)),
    'STYLES': ''.join(figure(f'style{s}_light0_camera0', styles[s]) for s in range(3)),
    'SBS': figure('sbs_benchmark_oblique', '三种材质 · 斜视') + figure('sbs_benchmark_topdown', '三种材质 · 俯视'),
    'SHADOWS': figure('shadow_normal_bias_0.025', '太阳角直径0.3：叶面半影颗粒') + figure('leaf_diag_hard_shadow', '太阳角直径0：保留真实过滤投影'),
    'LODS': ''.join(figure(f'lod_{i}', f'LOD{i} · {stats[f"lod{i}"]:,} tris') for i in range(3)),
    'ENERGY': ''.join(figure(f'sun_energy_{e:.1f}', f'太阳能量 {e:.1f}') for e in [0., .5, 1.5]),
    'CHANGES': changes, 'REMAINING': remaining, 'PERF': performance,
}
for key, value in replacements.items():
    html = html.replace(key, value)
(out / 'review.html').write_text(html, encoding='utf-8')
(r / 'FINAL.md').write_text(f'''# 本轮修正与验收

本轮重建自然叶梢与闭合木质结构，保留原树皮纹理。修正标准GGX、单次间接光AO、真实接地阴影、动态LOD计数；不是只改后处理。

几何：{stats}。{g['clumps']}组叶梢、{g['leaves']}片叶、每片{g['leaf_triangles']}三角面，43个表面。闭合根部={g['root_closed']}，总高约{g['height']:.2f}m。AO：24条实际BVH可见性射线/叶，1m半径，R均值{g['ao_mean']:.3f}；不是离线完整GI。

阴影诊断：法线偏移加大不能解决当前半影颗粒；零太阳角直径+过滤阴影改善叶面，仍保留几何投影。参数写进Sun节点，Inspector可改。

{performance}

测试：27组固定图；15个旧参考组合；9个新组合外部材质/贴图/颜色数据；240帧环绕；7组LOD滞回；快捷键、复位、节点数量。技术通过，艺术评审分开记录。日志有证书/用户目录与冷Shader缓存权限错误，已如实保留。

交付：原生Blender整树/烘焙源，小枝工程与场景，外部材质，3套灯光资源，9个显式LOD场景，人工跟做教程，review.html和walkthrough.md。运行预览不执行制作脚本。初始制作使用离线辅助组装与节点烘焙，未声称手工建模或人工笔触。

艺术状态：WIP。冠形仍窄、枝间空隙偏大、叶片相对树体偏大、分叉UV和根部仍需精修，真正手绘底稿缺失。LOD2近看明显鼓团，尚未完成整地图性能/商业成品验收。不给概念图相似度百分比。

范围仅asset_lab；V9与默认入口不在本轮修改范围。小枝阶段提交c812a65；本记录随整树阶段资源提交。
''', encoding='utf-8')
print('Wrote factual review:', stats, 'snapshots', len(data['snapshots']))
