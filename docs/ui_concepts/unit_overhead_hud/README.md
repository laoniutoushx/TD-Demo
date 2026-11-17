# 单位头顶 HUD：A 紧凑铭牌

选定方向：[A 概念](A_compact.png)。[当前原生截图](implemented.png)。B/C 作为方案留档。

由现有屏幕空间血条画布统一绘制，选中事件同步单位列表，读取实时生命、魔法和等级；无等级组件时显示 1。HP 填充高度 8 px，MP 填充高度 4 px，严格 2:1。总宽 128 px，左侧等级牌 28 px，石材底、铜色双层边线。屏幕外、相机后方和死亡单位不绘制。

替代已注册单位的旧 Sprite3D 血条/蓝条/等级牌，避免重复。弱引用不延长单位生命周期；边框样式缓存复用。既有敌人受伤显示条件保留，满血选中单位也显示。

验证：原生 Forward+ 三分辨率 UI_MATERIAL_VIEW_OK、SELECTION_STATES_OK、UNIT_DETAILS_REACTIVE_OK、SLOT_STATES_OK、ALL_UI_PAGES_OK、UI_MATERIAL_REVIEW_OK，退出码 0。日志 `.godot/ui-unit-hud-review.log`。既有 Fox_Mega UID 回退警告保留。

清理：删除误解需求时生成的屏幕 HUD 三版图片及导入文件；保留其他工作区改动与未确认用途的文件。

品质限制：这是 A 版结构与配色的原生实现；苔藓、立体铜饰及局部磨损尚非概念图 1:1，不能宣称该艺术目标完成。概念图场景为生成示意，implemented.png 为真实游戏截图。
