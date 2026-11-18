extends RefCounted
## Paths are the persistent identity. Legacy entries keep their original first 12 indices.
const LABELS = {
 "vfx_tornado_fox_running":"狐狸法师 · 聚风龙卷",
 "vfx_tornado_wind_running":"龙卷风 · 白风",
 "vfx_tornado_dark_red_running":"龙卷风 · 暗红邪风",
 "vfx_tornado_chaos_running":"龙卷风 · 黑白混沌",
 "vfx_tornado_violet_running":"龙卷风 · 紫色诅咒",
 "vfx_tornado_blue_running":"龙卷风 · 蓝色诅咒",
 "vfx_tornado_debris_running":"龙卷风 · 碎石风",
 "vfx_tornado_electric_running":"龙卷风 · 雷电风暴",
 "vfx_tornado_sand_running":"龙卷风 · 沙尘龙卷",
 "vfx_tornado_fire_running":"龙卷风 · 火焰龙卷",
 "vfx_tornado_wild_blue_running":"龙卷风 · 狂蓝风暴",
 "vfx_tornado_anime_running":"龙卷风 · 动漫白风",
 "vfx_tornado_green_running":"龙卷风 · 青绿风系",
 "vfx_blood_burning":"流血 · 原始粒子样例", "vfx_building_impact":"建造落地冲击", "vfx_build_located_running":"建造定位圈", "vfx_construction_circle":"施工法阵", "vfx_construction_dust":"施工扬尘",
 "vfx_energy_shield_running":"能量护盾", "vfx_force_field_running":"力场护盾", "vfx_funnel_tornado_running":"白风 · 白色丝带旋风", "vfx_funnel_tornado_volume_running":"漏斗龙卷风 · 体积烟尘", "vfx_laser_running":"闪电连线 / 激光（经典修复）", "vfx_chain_lightning_running":"闪电链 · 清晰主弧", "vfx_forked_lightning_running":"叉状闪电 · 多目标分叉",
 "vfx_leveling_up_arrow_running":"升级箭头", "vfx_leveling_up_circle_running":"升级圆环", "vfx_level_up_skill_burning":"技能升级光效", "vfx_level_up_tower_burning":"防御塔升级光效", "vfx_level_up_tower_no_ani_burning":"防御塔升级 · 粒子版",
 "vfx_lv_up_style_a_burning":"升级光效 A", "vfx_lv_up_style_b_burning":"升级光效 B", "vfx_lv_up_style_c_burning":"升级光效 C", "vfx_lv_up_style_d_burning":"升级光效 D", "vfx_lv_up_style_e_burning":"升级光效 E",
 "vfx_loot_drop_b_green":"绿色掉落光效", "vfx_healing_running":"治疗光柱", "vfx_peaceful_burning":"宁静恢复光环",
 "vfx_asif20_kunai_knife_running":"苦无 · 飞行", "vfx_black_bird_running":"黑紫弹 · 飞行", "vfx_default_running":"默认弹 · 飞行", "vfx_default_destory":"默认弹 · 命中", "vfx_electric_strike_running":"电枪 · 飞行",
 "vfx_fireball_running":"火球 · 原版飞行", "vfx_fireball_destory":"火球 · 命中", "vfx_fire_ball_standar_running":"标准火球 · 飞行", "vfx_fire_strike_running":"火焰枪 · 飞行", "vfx_fireball_another_running":"火焰雨弹体 · 飞行", "vfx_fireball_another_destory":"火焰雨弹体 · 命中", "fireball_another":"火焰雨弹体 · 资源变体",
 "vfx_hammer_running":"风暴之锤 · 飞行", "vfx_hammer_destory":"风暴之锤 · 命中", "vfx_ice_prise_running":"冰刺 · 飞行", "vfx_ice_prise_destory":"冰刺 · 命中",
 "vfx_missile_01_running":"子弹 01", "vfx_missile_02_running":"子弹 02", "vfx_missile_03_running":"子弹 03", "vfx_missile_07_running":"子弹 07", "vfx_missile_7_running":"子弹 7 · 资源变体",
 "vfx_scream_ball_running":"痛苦之球 · 飞行", "vfx_water_running":"水系弹 · 飞行", "vfx_water_another_running":"水系弹 · 备用款",
 "vfx_burn_decal":"地面焦痕", "vfx_scream_wave_running":"尖叫波", "vfx_scream_wave_dota2_running":"尖叫波 · Dota2 变体", "vfx_shockwave_running":"冲击波", "vfx_teleport_running":"传送法阵", "vfx_tornado_running":"龙卷风"
}

static func _collect(folder: String, paths: Array[String]) -> void:
 if folder == "res://VFX/lab": return
 var directory := DirAccess.open(folder)
 if directory == null or FileAccess.file_exists(folder.path_join(".gdignore")): return
 for child in directory.get_directories():
  if not child.begins_with("."): _collect(folder.path_join(child),paths)
 for file in directory.get_files():
  var path := folder.path_join(file)
  if file.get_extension().to_lower() in ["tscn","scn"]: paths.append(path)

static func discover(legacy: Array) -> Dictionary:
 var paths: Array[String] = []
 _collect("res://VFX",paths)
 paths.sort()
 var ordered: Array[String] = []
 var old_labels := {}
 for entry in legacy:
  if entry[1] in paths:
   ordered.append(entry[1])
   old_labels[entry[1]] = entry[0]
 for path in paths:
  if not path in ordered: ordered.append(path)
 var entries: Array[Dictionary] = []
 for path in ordered:
  var info := describe(path)
  if old_labels.has(path): info.label = old_labels[path]
  entries.append(info)
 var pairs := {}
 for i in entries.size():
  var basename: String = entries[i].base
  var other := ""
  if basename.ends_with("_running"): other = basename.trim_suffix("_running")+"_destory"
  elif basename.ends_with("_destory"): other = basename.trim_suffix("_destory")+"_running"
  elif basename.ends_with("_destroy"): other = basename.trim_suffix("_destroy")+"_running"
  if other.is_empty(): continue
  for j in entries.size():
   if entries[j].base == other and entries[j].path.get_base_dir() == entries[i].path.get_base_dir():
    pairs[i] = j
    break
 return {"entries":entries,"pairs":pairs}

static func describe(path: String) -> Dictionary:
 var base := path.get_file().get_basename().to_lower()
 var folder := path.trim_prefix("res://VFX/").get_slice("/",0)
 var category := "技能"
 if folder == "projectiles": category = "命中" if base.ends_with("_destory") or base.ends_with("_destroy") else "飞行"
 elif folder == "building": category = "建造"
 elif folder == "level_up": category = "升级"
 elif folder == "loot_drop": category = "掉落"
 elif folder == "scorch": category = "贴花"
 elif folder == "impact": category = "命中"
 elif folder == "peaceful": category = "治疗"
 elif folder in ["stun","blood","force_field","energy_shield"]: category = "状态"
 var ground: bool = folder in ["building","level_up","loot_drop","scorch","teleport","tornado","funnel_tornado","shockwave","scream_wave","thunderclap","peaceful"]
 var span := 5.0 if folder in ["building","level_up","teleport","shockwave","scream_wave"] else (8.0 if "tornado" in folder else 2.5)
 if "level_up_tower" in base: span = 12.0
 if folder == "peaceful": span = 8.0
 var cycle := 6.5 if folder == "scorch" else (3.0 if ground else (1.2 if category == "命中" else 2.0))
 var beam := folder in ["laser","lightning_arc"]
 var empty := false
 if path.ends_with(".tscn"):
  var source := FileAccess.get_file_as_string(path)
  empty = source.count("[node ") == 1 and source.contains('type="Node3D"') and not source.contains("script =") and not source.contains("instance=")
 if empty: category = "占位"
 return {"path":path,"base":base,"label":LABELS.get(base,base.trim_prefix("vfx_").replace("_"," ")),"category":category,"empty":empty,"ground":ground,"span":span,"cycle":cycle,"beam":beam,"reference":path.contains("/reference_set/"),"keywords":LABELS.get(base,"")}
