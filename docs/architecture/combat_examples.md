# 声明示例与复用验收

以下是强类型 Resource 的结构说明，不是已经可执行的新 DSL。未来 Inspector、agent 和图编辑器应编辑同一结构。

## 狐狸聚风龙卷

Ability ID：fox_tornado。保留旋转 5.6、流速 3.0、成长 1 秒、初始尺寸 18%、释放门槛 85%、加速 0.28 秒、射程 20 米、消散 0.35 秒。

| 阶段 | 进入及持续模块 | 转换 | max_duration / timeout_target |
| --- | --- | --- | --- |
| forming | 请求 cast 动画；创建逻辑成长曲线与效果实体；绑定成长 VFX，关闭范围 | All：逻辑尺寸达到 85%、release 动画标记已到或 Gate 兜底成立 | 1.5 秒 / cancel |
| advancing | 经过释放点，转交世界作用域；匀加速直线移动；开启 AreaEffectEmitter | 解析行进距离达到 20 米 | 3 秒 / dissipating |
| dissipating | 关闭区域并释放来源；发出淡出 Cue | 0.35 秒结束，回收实例 | 0.5 秒 / 结束 |

forming 的动画事件 Gate 最大等待 1 秒，超时满足动画分支；成长条件仍然必须满足。成长按解析曲线计算，85% 的穿越时刻可反解，不依赖帧率。若成长被异常阻断，1.5 秒后按 cancel 结束，不产生世界效果。

动画绑定通过片段标记或旁路标记资源声明 release 点，不能在动画中直接移动龙卷风。无标记时释放可能晚于原来的约 0.727 秒，迁移验收必须确认这一行为。

advancing 的位移用 `s(t) = v0·t + ½·a·t²`（加速段 0.28 秒）后接匀速，到达 20 米的时刻解析求出，不同帧分割终点一致。

AreaEffectEmitter：TargetSelector 为 ENEMY、排除来源、require_alive；圆柱半径 4、高 10，按逻辑成长同比变化。OnEnter 组合 DamageOncePerTarget（每波独立命中集合，伤害取释放时快照）与 AcquireBuff；OnExit 释放对应 Buff 来源。重新进入可以重新减速，不重复本波伤害。

减速定义：move_slow，MULTIPLY 0.8，WhileSourcePresent，StrongestMagnitude（MULTIPLY 取最小值）；减速本身不知道龙卷风、范围或狐狸。表现绑定提供旋转、纹理流速、烟尘、碎屑与音效；缺失任意表现模块时伤害和减速仍然成立。

## 眩晕

Buff ID：stun。group_id stun，Timed，默认 5 秒；叠加策略 LongestRemaining：每个来源独立保存到期时间，组生效期为所有存活来源的并集，不累加禁用强度。tags 含 `&"control"`，目标 `immune_tags` 包含该标签时 acquire 返回无效 Lease。

生效：获取 CanMove/CanAttack/CanCast 限制句柄；表现层响应聚合 active，显示单位头顶星轨（attach_point head）并请求 stunned 动画（优先级 80）。

更新：新增来源不重复创建星轨；较早来源到期但其他来源仍有效时保留限制与表现，发出 updated。

移除：最后来源结束释放限制，停止头顶 VFX（按句柄 generation 校验，不误停复用实例），释放 stunned 动画所有权。单位适配器重新仲裁状态；不直接写 WALKING/IDLE。死亡优先，不播放恢复动画覆盖死亡。

## 普攻投射物

塔的普通攻击（箭矢、炮弹、子弹）是数量最多的效果，复用同一组模块：

| 阶段 | 模块 | 转换 | max_duration / timeout_target |
| --- | --- | --- | --- |
| launch | 请求 attack 动画；Gate 等待 fire 标记（最大 0.5 秒） | Gate 打开 | 0.6 秒 / cancel |
| flight | 转交世界作用域；ProjectileMover（追踪或抛物线，解析计算）；绑定弹道 Cue；`on_exit` 执行 `DamageEffect`（攻击力、暴击取释放时快照，防御取命中时）、可选 `AcquireBuff`（Timed 减速）与命中 Cue | 命中目标或目标失效 | 按射程/速度推算 + 0.5 秒 / end |

目标在飞行中死亡：追踪弹落在最后已知位置触发命中 Cue，不结算伤害（可配置为改选最近目标）。弹道实体与拖尾由对象池提供，句柄带 generation。

高攻速场景（如 5~10 次/秒）：`AnimationAdapter` 按 `attack_interval` 自动缩放 `attack` 动画倍率并在重入时 `seek(0, true)` 复位；超过 `max_anim_speed_scale` 时切换 `attack_loop` 或封顶倍率截断后摇。`launch` 阶段的 `Gate` 最大等待时间同步按 `min(0.5s, attack_interval * 0.5)` 缩放，保证高频攻击不丢发射、不拖慢实际射速。

## 配置复用证明

- 将同一个 AreaEffectEmitter 挂到固定地面区域，换成 ALLY 筛选和加速 Buff（MULTIPLY 1.2，StrongestMagnitude 取最大值），不新增技能专属范围逻辑。
- 普通攻击命中使用同一个减速 Buff，声明 Timed 持续；无需创建范围组件。
- 换火焰 VFX 不改变区域几何、减速比例或释放条件。
- 后续周期伤害只需在 `Timed` 或 `WhileSourcePresent` 的 Buff 上配置 `period > 0` 与 `periodic_effects`（内含 `DamageEffect`），复用已有伤害入口，不在区域组件中编写灼烧伤害循环。

## 取消与并发

释放前眩晕：按 `interrupt_controls` 取消施法作用域，停止形成中的表现，不产生世界效果或减速。默认已付消耗不退（`refund_on_interrupt = false`）。

释放后死亡：世界效果继续，归属与伤害使用释放时快照；可选来源实体钩子仅在来源仍可用时调用。世界退出则全部结束。

两个来源重叠：移动速度只乘 0.8；退出一个仍为 0.8；最后一个退出撤销减速。其他修饰器及基础速度更新保持有效。

两个施法并发：各有 cast_id、命中集合、事件 Gate、来源租约和表现句柄。取消其中一个不影响另一个。
