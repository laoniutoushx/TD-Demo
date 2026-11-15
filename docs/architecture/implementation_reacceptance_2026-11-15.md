# 声明式架构第二次验收

日期：2026-11-15。依据当前源码及原生 Forward+ 重新运行的测试；本轮只增加验收用例和报告，没有修复生产代码，没有执行 VFX Lab 全库、完整关卡或性能基准。

## 结论

**上轮原用例全部通过；整体联动仍不通过。** 新增的正式狐狸定义和自动物理范围证明声明式玩法已开始真正落地，但时序边界和表现所有权仍有阻塞，不宜宣称完整自驱动系统已经完成。

## 已通过与实际进展

| 验证 | 结果 |
| --- | --- |
| 原架构审计 combat_architecture_audit | 8/8，退出码 0 |
| combat_wp1_smoke | COMBAT_WP1_OK，退出码 0 |
| combat_wp234_smoke | COMBAT_WP234_OK，退出码 0 |
| combat_declarative_fox_smoke | DECLARATIVE_FOX_OK，退出码 0 |
| 新增 combat_architecture_reacceptance | 3/7，退出码 1 |

以上均为原生模式，没有 headless Shader 诊断或孤立节点警告。

原四项的当前结果：来源删除减速恢复 10；clear_all 恢复速度 10；0.21 秒内两个周期效果确实执行；按 max_duration 超时的两个阶段可在一次 0.3 秒推进中结束。

正式资源 `tornado_fox.tres` 已绑定 `tornado_fox_ability.tres`。新增解析成长、解析移动效果和物理 Area3D 池；范围运行时自动接线 area_entered/exited，维护碰撞体计数。新的狐狸测试使用该正式定义，两次施法均能在无 PresentationPort 的情况下命中、减速并恢复，说明玩法已不再完全依赖旧专属处理器。

表现层也有进展：已增加简易动画优先级所有权，cast 使用 anim_release，动画结束可转发 release Gate。下面的新用例说明这些桥接尚不完善。

## 本轮阻塞

### P1：条件提前触发时仍丢失剩余时间

配置：A、B 各在 ELAPSED=0.1 秒转移，max_duration=1 秒。

- 三次 advance(0.1)：结束。
- 一次 advance(0.3)：未结束。

原修复只将步长截到 max_duration，没有截到转换条件的实际生效时刻。不能把原“超时阶段”用例通过视为所有阈值与 Gate 的帧步长独立性通过。

定位：`System/combat/ability_runner.gd:85`。修复需处理条件/Gate/解析阈值的跨越时间，将阶段应得的时间与后续剩余时间分开，避免给本阶段持续效果超额推进。

### P1：周期效果越过 Buff 到期时间执行

配置：TIMED、duration=0.15 秒、period=0.1 秒，推进 1 秒。

期望：只在 0.1 秒执行一次。实际：执行 10 次。

周期累积使用完整 delta，然后才扣除 remaining 并释放。应限制为该租约仍有效的时间窗口，并定义同一时刻到期/周期的顺序。

定位：`System/combat/buff_service.gd:189`。

### P1：不相关动画结束也能释放技能

配置：等待 cast 的 release Gate，超时为 10 秒。当前在播放 cast，发出 `animation_finished("unrelated")`，随后推进 0.01 秒。

期望：保持等待。实际：技能结束，Gate 被打开。

回调忽略 `_name`，仅验证阶段代次；没有验证对应动画名称及播放请求所有权。需要用 action_handle/播放代次校验，并让标记与完成事件具有明确语义，不能把任意动画结束等同 release。

定位：`System/combat/presentation_port.gd:182`。

### P1：狐狸推进阶段没有接续 VFX

使用正式狐狸定义和真实 PresentationPort：

- forming 时存在有效表现句柄。
- 推进 1.1 秒后已进入 advancing。
- advancing 时有效表现句柄数为 0。

原因：资源只在 forming 声明 Cue；阶段退出统一 stop 该 Cue 并回收 VFX，advancing 没有 Cue 接续。逻辑区域仍推进，但表现实体已经消失。dissipating 也没有对应的淡出表现声明。

定位：`System/skill_system/resources/damage/tornado_fox_ability.tres:57`、`:98`；`System/combat/ability_runner.gd:315`。

应将龙卷风表现句柄归属于跨 forming/advancing/dissipating 的效果实体作用域，并持续绑定位置、成长及消散进度；或者显式完成无缝所有权移交。不能只延长动画或增加不受管理的 VFX 副本。

## 验收边界

新狐狸 smoke 明确不传入 PresentationPort，因此它通过了“无表现也能完成玩法”的解耦测试，却没有覆盖实际推进表现。它也直接调用 CombatTicker，尚未覆盖真实 SkillSystem 的魔耗/冷却/技能数值注入、模型动画和完整伤害修饰链。

尚未充分验证：动画标记重入和抢占、来源删除后的真实单位伤害归属、Lab 正式实时联调、对象池跨代旧回调，以及文档规定的 60 秒性能基准。当前 compiled plan 仍引用原 Definition/Phase，也需要补活动施法与资源编辑隔离测试。

不应把这些未测项目标为失败，也不能认定已通过。

## 可重复运行

原审计：`tests/combat_architecture_audit.gd`，当前预期 0。

新增验收：`tests/combat_architecture_reacceptance.gd`，当前预期 1；它一次记录所有检查，不在首个失败处挂起。输出目录会自动创建。可用 Godot `--path . --script tests/combat_architecture_reacceptance.gd --log-file .godot/reaccept-extended.log` 重现。

证据：[原审计](reaccept_evidence/original-audit.log)、[WP1](reaccept_evidence/wp1.log)、[WP234](reaccept_evidence/wp234.log)、[声明式狐狸](reaccept_evidence/declarative-fox.log)、[扩展验收日志](reaccept_evidence/extended.log)、[扩展逐项结果](reaccept_evidence/extended-results.json)。

建议修复顺序：先修狐狸跨阶段表现和动画误释放，再修条件时间守恒及周期截止；全部验收通过后再做真实 SkillSystem/伤害链的端到端检查。
