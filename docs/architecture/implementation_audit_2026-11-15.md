# 声明式与自驱动架构实现审计

日期：2026-11-15。范围：最新架构文档、System/combat、正式技能接入和定向测试。此次不修复生产代码，不运行 VFX Lab 全库或全游戏回归。

## 结论

**尚未达到完整声明式、模块可插拔和生命周期自驱动要求。** 已有可运行的部分基础能力，并非“只有文档”；但原文“新运行时尚未实现”也已过时。现状应归类为“底座部分落地，生产试点与自主生命周期未闭环”。

| 能力 | 当前证据 | 判定 |
| --- | --- | --- |
| 配置定义 | Ability/Phase/Effect/Buff 等 Resource 已存在，轻量编译器可校验部分字段 | 部分实现 |
| 属性与控制 | AttributeService、ControlService、BuffService 租约；旧 move_speed Buff 已增加属性句柄桥接；眩晕使用控制租约 | 部分实现，基础用例通过 |
| 通用执行 | CombatTicker、AbilityRunner、Gate 和作用域已存在；SkillSystem 已有可选声明路径 | 部分实现，有时间推进缺口 |
| 正式技能迁移 | 在 System、Unit 的 .tres/.tscn 中搜索 `ability_definition =` 无结果；狐狸仍走 InnerHandler | 未完成试点切换 |
| 范围模块 | start 只记录上下文，notify_body_entered/exited 需要外部调用；未创建或接线物理 Area，半径/高度未用于检测 | 尚不自主检测 |
| 周期效果 | 定时发出 periodic_triggered，但生产代码未发现该信号的执行订阅 | 未形成自动执行闭环 |
| 动画表现 | 有动画倍率计算与播放，Gate 消费入口存在；测试手动 signal_gate | 缺少真实标记桥接与完整仲裁 |
| Lab 正式联调 | 保留预览参数和预设能力；未发现已实施的实时游戏配置通路 | 尚未实现 |

## 测试结果

原生 Forward+ 复核：

| 测试 | 结果 | 实际证明的范围 |
| --- | --- | --- |
| combat_wp1_smoke.gd | COMBAT_WP1_OK | 模拟目标上的最强减速/加速、幂等获取、显式释放、定时控制、免疫、周期信号、目标死亡清理 |
| combat_wp234_smoke.gd | COMBAT_WP234_OK | 部分编译诊断、AnimationPlayer 重入与倍率、手动 Gate、模拟目标投射物快照伤害、释放前控制打断 |
| tornado-fox | PASS | 旧狐狸处理器的成长、移动、伤害和清理等已有专项 |
| combat_architecture_audit.gd | **退出码 1：8 项检查中 4 项不满足** | 下述四个反例及四个阳性对照 |

headless 也运行了两组已有测试及初始探针，均出现仓库已知 custom_samplers Shader 编译诊断，因此最终结论采用原生复核。原生复核没有这些诊断；已有测试成功不等于架构验收通过。

狐狸专项没有创建 BuffSystem，也没有移动速度/减速恢复断言，不能作为实际范围减速接入的充分证明。WP1 主要使用 MockUnit，WP234 使用测试构造的定义及 MockTarget；它们不证明正式 .tres 已完成接入，也不证明动画标记和物理范围自动接线。

## 已复现的问题

### P1：范围来源删除后不自动恢复

步骤：移动速度 10，获取 WHILE_SOURCE_PRESENT 的 0.8 倍减速；删除来源 Node，等待帧并推进 BuffService。

期望：速度恢复 10。实际：仍为 8。显式 release 后能够恢复 10，说明恢复计算存在，但来源生命周期未自动连接。

证据：BuffService 仅把来源归一为 instance_id，并对目标安装死亡/退出钩子，没有来源退出钩子。AcquireBuffEffect.start 获取后未保存 Lease，也没有将其登记进 Scope 或在 dispose 释放。

位置：System/combat/buff_service.gd:291；System/combat/effects/acquire_buff_effect.gd:18。

### P1：clear_all 丢失记录但保留减速值

步骤：速度 10 应用减速后为 8，调用 BuffService.clear_all。

期望：目标仍存活时恢复 10。实际：仍为 8。BuffService、AttributeService 清空容器，未逐目标重新计算。ControlService.clear_all 也仅清表，没有像 clear_target 一样通知单位恢复；后者为静态审查发现，未作为本次四个数值反例之一。

位置：System/combat/buff_service.gd:214；System/combat/attribute_service.gd:88；System/combat/control_service.gd:102。

### P1：周期资源没有自主执行

步骤：配置 period=0.1、periodic_effects=[DamageEffect]，推进 0.21 秒。

期望：执行两次效果。实际：periodic_triggered 发出 2 次，目标效果执行次数 0。生产代码也未发现对该信号的执行订阅。

位置：System/combat/buff_service.gd:181。当前 WP1 仅断言信号次数，未断言效果执行。

### P1：跨阶段时间不守恒

步骤：阶段 A 时长 0.1 秒后进入 B，B 再经过 0.1 秒结束。

期望：一次 advance(0.3) 与三次 advance(0.1) 都结束。实际：细分推进已结束，大步长仅切到 B。

原因：advance 转换后直接返回，新阶段将 elapsed 归零，没有把剩余 delta 传递给后续阶段；跨阶段的持续效果也可能获得超过本阶段应有的 delta。

位置：System/combat/ability_runner.gd:70、141、177。

## 其他集成缺口与风险（代码审查，非上述反例）

- 狐狸仍手动维护 `_slowed`、调用 acquire_area_slow，并从 VFX.get_growth_fraction 读取玩法碰撞尺寸。尚未做到替换/缺失 VFX 不影响玩法。
- 通用 AreaEffectEmitter 只有人工通知接口与死亡目标校对，没有真实物理适配、重复碰撞体成员聚合或重叠校对闭环。
- PresentationPort 的优先级只是常量，anim_handle 仍为空；没有把 AnimationPlayer 标记接到 AbilityRunner.signal_gate。cast 分支读取 anim_attack 而非 anim_release。stop 仅处理 VFX，未释放动画所有权，audio/end_mode 未执行。
- compile 保存原 Definition/Phase 引用，尚无执行快照隔离；需要验证运行中修改资源不会改变已有施法。
- 两套系统分别推进 BuffService 和 CombatTicker，尚非文档描述的单一 CombatTicker 调度全部 Runtime。
- 新 DamageEffect 的模拟目标路径通过了测试，但未充分验证真实单位的暴击、目标减伤、归属反馈及来源删除后的完整伤害链。
- 未运行文档中的 200 敌人、3 区域、10 塔、60 秒性能基准，不能认定 Node 分配、孤立句柄或耗时预算达标。

## 后续优先级

1. 修复来源租约归属、全量清理还原、周期 Effect 执行和跨阶段剩余时间处理，先使本次审计用例通过。
2. 将通用范围模块接到真实物理检测及作用域；接通动画 action_handle/marker/stop；补真实单位伤害适配。
3. 迁移至少一份正式狐狸定义，删除专属阶段/减速维护；增加“关闭 VFX 和动画仍完成玩法”的集成用例，再评估自驱动程度。
4. 补表现配置联调与性能基准；维护文档中的实施状态。

## 重现与证据

新增审计用例：`tests/combat_architecture_audit.gd`。用 Godot 原生运行 `--path . --script tests/combat_architecture_audit.gd --log-file .godot/architecture_audit/recheck.log`。当前版本预期退出码为 1；修复后应达到 0。用例会创建自己的输出目录，不依赖旧缓存。

[原生审计日志](audit_evidence/audit-native.log)、[逐项 JSON](audit_evidence/audit-results.json)、[WP1 日志](audit_evidence/wp1-native.log)、[WP234 日志](audit_evidence/wp234-native.log)、[狐狸专项日志](audit_evidence/fox-native.log)。
