# 第十三轮：Slot 四角与分区石材

针对当前工作区新增的 v12 位图样式继续修复，不变更槽位布局和交互。

- 普通、空装备和悬停槽框取消固定 14 像素九宫格角区，改为整框等比缩放。避免小槽位继承大尺寸圆角，修正角区占比与直边衔接。
- 技能、装备次级容器由平滑的 v12 面板改回已有磨损石材资源，使用 20 像素九宫格保护转角，保留内容边距。
- 分区边框使用较低饱和度的灰铜、橄榄色，保留暗色凹槽和磨损高光。

## 实机证据

- [技能槽](05_skills.png) / [技能四角放大](curves_skill.png)
- [装备槽与分区纹理](19_item_inset.png) / [装备四角](curves_item.png)
- [技能状态](states_skill.png) / [Buff 状态](states_buff.png)
- [完整战斗截图](battle.png)

三列为参考、归档第十二轮、当前截图。注意：开始本轮时工作区样式已继续变化，已引用 slot_bevel_v12.png 和 action_*_inset_v12.png；因此归档第十二轮不能视为本轮开始前工作区的精确快照。四角叠图含图标、材质，并非纯几何误差。

原生 Forward+ 检查通过，退出码 0：三种分辨率 UI_MATERIAL_VIEW_OK、SLOT_STATES_OK、SELECTION_STATES_OK、UNIT_DETAILS_REACTIVE_OK、ALL_UI_PAGES_OK、UI_MATERIAL_REVIEW_OK。槽位四边像素可见性断言通过。日志 `.godot/ui-round13-review.log`；仅见已有 Fox_Mega UID 回退警告。

本轮未新增位图，复用既有资产。普通槽框的局部铜边磨损仍比参考均匀；叶片和布局比例也未在本轮调整，不能标为完全一致或达到 95%。
