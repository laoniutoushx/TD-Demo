# 分阶段实现与验收

## 当前交付

已完成仓库现状调查与设计契约。新资源类、执行器、动画适配、属性服务和实时联调尚未实现。本次不运行运行时测试，也不改写现有技能、Buff 或 VFX。

## 排序原则

Buff/属性/控制底座不依赖阶段执行器，且直接修复现存缺陷（`Buff.gd` 的 get/set 整体恢复、眩晕固定写 WALKING/IDLE、狐狸专属减速集合），因此最先实施。眩晕和狐狸减速在工作包 1 内即可迁移到新底座；阶段执行器在其后。

## 工作包顺序

### 1. Buff、属性与控制底座

实现 BuffDefinition、AttributeModifierDef、BuffService（Lease、叠加策略、持续模式、免疫检查）、BuffRuntime（RefCounted，统一调度）、AttributeService（首批 move_speed，新增 `base_move_speed`）、ControlService 与 Enemy/Turret 单位适配器。

迁移：
- `acquire_area_slow/release_area_slow` 内部改为 BuffService Lease（对外签名暂留，作为狐狸旧路径的薄适配），删除 `_area_slows` 专属集合。
- 眩晕改为 BuffDefinition + ControlService，删除对 Enemy/Turret 枚举的直接写入；`Turret` 适配器重新仲裁时需保留 `BUILDING` / 升级冻结（`building_level_up.gd`）约束，避免眩晕解除打断升级；头顶 VFX 暂经 VFXSystem 薄适配，工作包 4 再换成 PresentationPort。
- move_speed 的旧直接写入路径同时移除。

验收：多来源进入/离开/重入、目标死亡、来源删除；20% 不累乘，剩余来源降级；StrongestMagnitude 方向（减速取最小、加速取最大）；LongestRemaining 并集到期；免疫拒绝不登记来源；其他加减速与基础速度变化不被恢复操作覆盖；周期与持续时间无重复调度；除 AttributeService 外无 move_speed 写入；眩晕解除不覆盖死亡；旧 move_speed Buff 的计算差异有明确记录。

### 2. 数据与编译

实现 Ability/Phase/Transition/Effect/TargetSelector/Presentation 强类型资源（模块即 Resource 子类，不做独立注册表）、稳定 ID、参数描述、validate/compile。输出狐狸和普攻投射物两份可加载资源。`schema_version` 不支持时显式报错；升级工具推迟到首次破坏性变更。

验收：纯资源加载与往返保存；无效引用/重复 ID/缺失 max_duration 或 timeout_target 诊断带字段定位；两次编译结果一致；定义对象不包含运行数据；StrongestMagnitude 组内混用 op 报错；agent 修改与 Inspector 修改经过同一校验入口。

### 3. 独立执行器和作用域

实现 CombatTicker（单一物理时钟）、条件 Gate、阶段代次、模块运行实例、带 generation 的句柄、Scope 与取消、来源快照、执行追踪。先用无表现的测试模块运行完整生命周期。

验收：正常、失败、部分初始化、重复取消、会话切换、来源删除及超出 `max_phase_hops` 上限均清理一次；解析位移在不同帧分割下终点与阈值时刻一致；过期回调与 generation 不匹配句柄无效；并发实例不互相修改状态；追踪记录可被测试断言。

### 4. 效果、表现端口与试点

复用 DamageSystem 的计算链，增加来源快照入口（按字段声明取值时刻）；实现通用 AreaEffectEmitter（脏标记 + 0.5 秒低频校对）和 ProjectileMover。实现 VFX/动画/声音适配器、动画优先级与事件身份桥接。

SkillMetaResource 新增可选声明式定义；存在定义走新执行器，否则继续 skill_script。新路径接管动画与阶段后，禁止再进入旧 release 中的重复动画/等待逻辑。列出旧 Skill 对外信号清单（释放、冷却开始/结束、施法结束），新执行器逐项发出。

试点：狐狸龙卷风整体迁移，删除 InnerHandler 阶段逻辑与工作包 1 留下的薄适配；选一座塔的普攻迁移为投射物定义；眩晕头顶表现改走 PresentationPort。旧 Skill/Buff 资源引用保持可加载，未迁移内容走兼容路径。

验收：无动画/VFX 也能完成；早到、重复、迟到、缺失事件不双重释放；阶段超时走 timeout_target；释放后来源删除效果仍能伤害；飞行中来源 Buff 过期不改变已承诺伤害；魔耗与冷却仅触发一次；UI 冷却显示与旧路径一致；对象池复用实例不被旧句柄停止；高频攻击（如 5~10 次/秒）下动画倍率、重入复位与 `Gate` 超时随 `attack_interval` 同步，实际射速不被动画拖慢；旧资源可逐项回退到旧入口。

### 5. 实时表现配置

接通已确认的 Lab 联调方案：当前资源实时覆盖、手动保存正式配置、按路径隔离、同项目跨进程同步、关闭或失联撤销。服务复用参数描述和应用器，不复制另一套参数白名单。

验收：Live 更新活动实例，NextSpawn 不重建当前玩法实体；SkillOwned 字段不能被联调改写；对象池复用应用有效配置；保存后重启恢复；关闭联调回到正式配置；原始资源与共享材质不被直接改写。

### 6. 逐项迁移与可选编辑器

逐项建立旧行为基线，再迁移其他技能和 Buff。只有新旧对照通过或差异明确接受后才切换对应资源。不默认实施全部技能替换。

图编辑器若后续需要，仅增加资源编辑层、模块目录和诊断展示；不得新增另一套执行语义。布局变化不能改变编译结果。

## 性能预算

基准场景：200 个敌人、3 个重叠光环区域、每秒 2 次技能施放、10 座塔持续普攻，headless 运行 60 秒。

| 指标 | 上限 |
| --- | --- |
| CombatTicker + BuffRuntime 每物理帧耗时 | ≤ 1.0 ms |
| 区域校对每物理帧耗时 | ≤ 0.3 ms |
| 稳态每次施放新分配 Node | 0（VFX、`AreaEffectEmitter` 及投射物实体全部来自对象池） |
| 稳态每次 Lease 获取/释放分配 | 不创建 Node |
| 60 秒后孤立节点/未释放 Lease | 0 |

工作包 1 起每个工作包在基准场景中记录这些数值；超出上限视为未通过，并在报告中给出定位。

## 测试组织

拆分为 Buff/属性/控制、契约/编译、执行生命周期、表现适配、狐狸专项、投射物专项、眩晕专项、配置联调、性能基准九组。优先使用可控时钟与伪表现端口；真实物理 Area 和真实模型/动画在专项中验证。涉及全局自动加载的测试在主循环启动后运行时加载，避免本仓库已有的提前编译依赖问题。新增场景接入 `tests/run_game_checks.ps1` 的 `-Scenario` 参数。

不把 VFX Lab 全库扫描作为默认验收；不以截图替代伤害、属性、来源清理和事件去重断言。每个工作包保存失败定位、通过范围、行为差异和性能数值，不把尚未运行的验证标为通过。
