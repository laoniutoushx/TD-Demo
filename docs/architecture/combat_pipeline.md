# 系统契约

## 当前接缝

SkillMetaResource 已有资源字段、skill_script 和 skill_buff_config；SkillSystem 初始化技能并挂载脚本，释放入口播放动画并等待 start_time。Skill 自己发出技能释放事件、启动冷却及 cast_duration 回调。这些入口保留为旧路径。

BuffSystem.apply/remove 管理 Buff。每个 Buff 是一个 Node，依赖 `_ready/_exit_tree`；`Buff.gd` 通过 `unit.get(prop)`/`unit.set(prop, …)` 修改属性并记录增量，多来源叠加时恢复顺序会互相覆盖。眩晕脚本直接切换 Enemy/Turret 状态、创建 VFX，退出时固定写 WALKING/IDLE。`BaseUnit.move_speed` 的 setter 联动 `_anim_speed`，`enemy.gd` 每帧直接读取 `move_speed`。BaseUnit.play_action_animation 临时关闭 AnimationTree，动画结束后恢复。VFXSystem 已有资源工厂与对象池；Lab 已有导出属性和 Shader 参数描述。

新架构通过适配器连接这些能力，不再让每个技能重复实现生命周期。

## 数据与编译

定义资源不可存储目标集合、计时器、活动 Node 或句柄。每次执行分配独立 Runtime。

### 类骨架（首版）

首版不建立独立的模块注册表和版本迁移系统：模块即 Resource 子类，通过虚方法创建运行实例。`schema_version` 字段保留，升级工具推迟到第一次破坏性变更时实现。

```gdscript
class_name AbilityDefinition extends Resource
@export var schema_version: int = 1
@export var ability_id: StringName
@export var phases: Array[PhaseDefinition]
@export var entry_phase: StringName
@export var wave_count: int = 1                  # 对应旧 Skill.wave
@export var wave_interval: float = 0.0            # 对应旧 Skill.internal_time
@export var interrupt_controls: Array[StringName] = [&"CanCast"] # 释放点前可取消施法的控制项
@export var charge_on_accept: bool = true         # 接受施放时扣费；false 可延后至释放点
@export var refund_on_interrupt: bool = false     # 中断时是否返还已付消耗
@export var max_phase_hops: int = 16              # 运行时阶段跳转上限，防止环路死循环

class_name PhaseDefinition extends Resource
@export var phase_id: StringName
@export var on_enter: Array[EffectDefinition]
@export var sustained: Array[EffectDefinition]    # 有界持续动作
@export var on_exit: Array[EffectDefinition]
@export var transitions: Array[TransitionDefinition]
@export var max_duration: float                   # 必填，> 0
@export var timeout_target: StringName            # 必填：phase_id、&"end" 或 &"cancel"
@export var cues: Array[PresentationDefinition]

class_name TransitionDefinition extends Resource
@export var target_phase: StringName
@export var condition: ConditionDefinition        # All/Any/Gate/阈值

class_name EffectDefinition extends Resource      # 模块基类
@export var effect_id: StringName
@export var targets: TargetSelector
func create_runtime(ctx: ExecutionContext) -> EffectRuntime: return null
func validate(diag: Diagnostics) -> void: pass

class_name TargetSelector extends Resource
@export var team: TeamFilter                      # ENEMY/ALLY/ANY，相对来源快照阵营
@export var exclude_source: bool = true
@export var require_alive: bool = true
@export var required_tags: Array[StringName]
@export var max_targets: int = 0                  # 0 = 不限

class_name BuffDefinition extends Resource
@export var buff_id: StringName
@export var group_id: StringName
@export var modifiers: Array[AttributeModifierDef]
@export var controls: Array[StringName]           # &"CanMove" 等
@export var lifetime_mode: LifetimeMode           # TIMED / WHILE_SOURCE_PRESENT
@export var duration: float
@export var period: float = 0.0                   # > 0 且 periodic_effects 非空时启用周期触发
@export var stacking: StackingPolicy
@export var max_stacks: int = 1
@export var tags: Array[StringName]               # 供免疫/驱散匹配
@export var periodic_effects: Array[EffectDefinition]
@export var cues: Array[PresentationDefinition]

class_name AttributeModifierDef extends Resource
@export var attribute: StringName                 # 首批仅 &"move_speed"
@export var op: ModOp                             # FLAT_ADD/PERCENT_ADD/MULTIPLY
@export var value: float

class_name PresentationDefinition extends Resource
@export var cue_id: StringName
@export var anim_semantic: StringName             # &"cast"、&"stunned"
@export var vfx: PackedScene
@export var audio: AudioStream
@export var attach_point: StringName              # &"head"、&"origin"
@export var bindings: Dictionary                  # 简单键值映射：{source_key: target_param}
@export var end_mode: CueEndMode                  # ON_STOP/NATURAL/FADE
```

阶段及动作使用资源内稳定可读 ID。跨资源引用使用 Resource；跨阶段引用使用 phase_id，编译时解析。未来图布局单独存储，不参与编译结果。

### 校验与编译

统一入口：`validate(definition)` 返回带资源/阶段/动作/字段定位的诊断；`compile(definition)` 返回执行计划或错误。首版 `compile()` 只做轻量静态检查：解析 `phase_id`、检查重复 ID、检查每个阶段有 `max_duration > 0` 与 `timeout_target`、检查 `StrongestMagnitude` 同组 `op` 与正负向一致性。运行时不解释任意字符串代码，不进行任意对象路径赋值。

参数绑定使用简单的 `{source_key: target_param}` 键值映射（例如 `growth -> scale`），由表现适配器直接读取，首版不构建通用的语义路径表达式编译器。防死循环由“每阶段必填 `max_duration` + 运行时 `max_phase_hops` 上限”共同兜底，无需图环路分析器或独立的 `Repeat` 循环子图模块；多波次施放直接使用 `wave_count` / `wave_interval`。

## 时钟

所有 Runtime 由单一 `CombatTicker` 在 `_physics_process(delta)` 中推进；该 delta 已包含 `Engine.time_scale`，暂停时不推进。Runtime 不各自建立 Timer 或 `_process`。

位移、成长等连续量必须按解析式计算（例如匀加速 `s(t) = v0·t + ½·a·t²`，阈值穿越时刻反解），不能逐帧欧拉累加，保证不同帧分割得到相同终点和相同阈值时刻。

## 执行实例与句柄

ExecutionContext 包含 session_id、cast_id、phase_generation、释放位置/方向、来源弱引用、来源快照及参数快照。共享定义不修改。

模块运行实例（RefCounted）提供 `start(context)`、`advance(delta)`、`cancel(reason)`、`dispose()`。异步完成、动画事件及回调必须携带执行身份；过期 session、阶段代次或已消费事件被丢弃。dispose 幂等且允许部分初始化失败。

所有句柄（Lease、表现句柄、动画 action_handle）均为 `{id, generation}` 值对象。对象池实例每次出池递增 generation；句柄 generation 不匹配时任何操作为空操作，防止停止或修改已被复用的实例。

Scope 管理获取的句柄，退出时反向释放：停止检测与新效果、释放范围 Buff 来源、终止绑定、回收表现。句柄不得借助来源 Node 的强引用延长来源寿命。世界退出清理所有作用域。

释放点前：实例属于施法者作用域，`interrupt_controls` 声明的控制（默认 `&"CanCast"` / 眩晕、死亡、删除）可取消。释放点后：投射物或区域转交世界效果作用域，独立结束。

### 来源快照

快照字段逐项声明取值时刻，未声明者编译报错：

| 字段 | 默认时刻 | 说明 |
| --- | --- | --- |
| 阵营、归属玩家、来源等级 | 释放时 | 决定目标筛选与结算归属 |
| 基础伤害、暴击率/暴击倍率 | 释放时 | 已承诺参数，来源 Buff 在弹道飞行中过期不影响 |
| 目标防御/减伤修饰 | 命中时 | 读取目标当前值 |
| 反击/吸血等来源反馈 | 命中时 | 先检查来源弱引用，失效则跳过，不复活节点 |

命中只要求目标有效。

### 扣费、元信息与旧信号

冷却、魔耗、图标、释放类型与 UI 禁用检查等技能元信息仍由 `SkillMetaResource` 唯一持有；`AbilityDefinition` 只描述施放接受之后的阶段编排、效果与表现，不重复配置冷却与魔耗。

旧 skill_damage 入口保留；新效果上下文入口支持来源快照。资源消耗默认在接受施放时支付一次（`charge_on_accept = true`），冷却同时启动；已支付消耗默认不因中断返还（`refund_on_interrupt = false`）。旧 skill_released 事件与新入口之间只能有一个扣费责任方，使用 release_id/cost_paid 去重。

新执行器必须发出与旧 Skill 相同的对外信号（释放、冷却开始/结束、施法结束），供 UI 冷却等现有订阅者使用；兼容清单在工作包 4 列出并逐项测试。

## 范围与 Buff

AreaEffectEmitter 只负责检测、目标筛选、进入/离开和持有来源句柄。可以挂在单位、投射物、地面区域或技能实体上，也可独立测试。碰撞几何来自玩法配置，不读取 VFX 网格大小。开关 `monitoring` 等物理属性在物理回调中使用 `set_deferred`。

同目标的多个 Area 聚合为一个成员关系；全部退出才移除。成员由进入/离开事件维护；目标或区域 `tree_exiting` 时标记脏，下一个物理步只对脏区域调用 `get_overlapping_bodies` 校对。此外每 0.5 秒对全部活动区域做一次低频全量校对，覆盖漏发退出事件。不在每个物理步对所有区域全量校对。

### BuffService

接口：`acquire(definition, source_token, target, context) -> Lease`；`release(lease)`；`release_scope(scope)`。同一来源重复获取必须幂等。生效失败（目标免疫、已死亡）不登记成功来源，返回无效 Lease。

Buff 运行实例为 RefCounted，由 BuffRuntime 统一调度；只有表现层创建 Node。目标死亡或离开场景树时 BuffRuntime 释放该目标上的全部 Lease。

生命周期模式为 `Timed` 或 `WhileSourcePresent`；来源拥有关系与生命周期分离。只要 `period > 0` 且 `periodic_effects` 非空，即在任意生命周期上独立启用周期触发。叠加策略按显式 group_id 聚合：

| 策略 | 语义 |
| --- | --- |
| Refresh | 单一实例；新来源把剩余时间重置为 `duration` |
| LongestRemaining | 每个来源独立到期时间；组生效期为所有来源的并集；不累加强度 |
| Stack | 每个来源一层，上限 `max_stacks`，修饰值乘层数 |
| StrongestMagnitude | 组内只取最强一项参与计算 |
| Independent | 每个来源独立实例，互不聚合 |

StrongestMagnitude 的比较方向由修饰器 op 决定：MULTIPLY 取离 1 最远者（减速取最小值，加速取最大值）；FLAT_ADD/PERCENT_ADD 取绝对值最大者。同一 group_id 内混用不同 op 或同时含增益与减益为校验错误。

最后一个来源移除才结束聚合效果；来源变化但仍有效时发出 `updated`，不重复触发首次 `applied`。周期调度由 BuffRuntime 管理，普通刷新不重置周期相位，除非定义明确要求。

免疫：目标声明 `immune_tags`（如 Boss 的 `&"control"`）；`acquire` 时 Buff 的 tags 与之相交则拒绝并返回无效 Lease。递减机制首版不实现，仅保留该检查点。

范围减速配置为 move_slow 组、StrongestMagnitude、WhileSourcePresent、MULTIPLY 0.8。同组取最强减速；较强来源离开后重新选取剩余来源。死亡、退出场景和作用域取消均撤销句柄。

### AttributeService

属性服务返回修饰器句柄，禁止 Buff 保存旧速度后整体覆盖恢复。首批只迁移 move_speed：

- BaseUnit 新增 `base_move_speed`，由单位资源初始化，升级等永久变化只改它。
- `move_speed` 变为有效值，只由 AttributeService 写入（通过现有 setter，因此 `_anim_speed` 联动保持）。其他代码只读；测试断言除服务外无写入。
- 有效值：`clamp((base + Σflat_add) * (1 + Σpercent_add) * Πmultiply, min, max)`，`min` 默认为 0。最强策略先在组内选出有效项，再进入计算。基础值或任一句柄变化时重算；移除一个句柄不影响其他来源。

兼容适配将旧 move_speed Buff 的 VALUE 映射为 flat_add，PERCENT 映射为 percent_add；旧的顺序依赖百分比计算与新公式可能不同，必须记录对照结果并显式验收后迁移，不能声称完全等价。迁移同一属性时同时移除该属性的旧直接写入路径，避免两种模型并行修改；其他属性暂走旧路径。

### ControlService

`ControlService.acquire(capability, source) -> Lease`。CanMove/CanAttack/CanCast 等能力由有效句柄聚合：存在任一有效限制即禁用。Buff 不直接调用 EnemyState.STUN 或 TurretState.FREEZEING；单位适配器订阅聚合变化，映射到自己的 FSM，并在限制全部解除后重新仲裁状态（不固定写 WALKING/IDLE；`Turret` 适配器需保留 `BUILDING` / `building_level_up` 等非控制来源的冻结状态）。

## 表现与动画事件

PresentationPort 提供 `emit(cue, context) -> handle`、`update(handle, bindings)`、`stop(handle, reason)`。首版仅包含 `VFXAdapter`（复用 `VFXSystem` 对象池，并可选附带 `AudioStreamPlayer3D` 池播放 `audio`）与 `AnimationAdapter`（适配 `BaseUnit` 的 `_ap`/`_at`），不单独建设空壳音频系统。缺少表现资源产生诊断，不破坏玩法清理。

动画请求返回 action_handle，`marker(action_handle, name)`、`finished(action_handle, reason)` 是唯一的运行时反馈入口。旧动画方法轨道先经适配器转换为带身份的事件，不允许方法轨道直接调用伤害或 BuffSystem。

等待动画事件使用有界 Gate：事件早到可锁存；重复或迟到仅消费一次；超时打开声明的兜底分支。All 条件中动画兜底只满足动画条件，不能越过成长或其他玩法门槛；若玩法条件在阶段 `max_duration` 内仍未满足，则走 `timeout_target`。

动画所有权采用优先级句柄：死亡 100、眩晕 80、施法 60、攻击 40、移动 10。释放一个句柄后重新仲裁，不直接恢复旧动画；死亡与仍有效的行为限制不能被低优先级恢复覆盖。移动动画速度读取有效 move_speed。

### 攻击频率与动画同步

现有路径中 `turret.gd` 将 `attack_speed` 当作间隔（秒/次），而 `CommonUtil.play_attack_animation_with_reset_v1` 将其当作频率（次/秒），`BaseUnit.play_action_animation` 又固定 `_ap.speed_scale = 1.0` 且不复位，同时 `DamageSystem.attack_delay` 仍读取 `speed_scale = 1.0` 而非 `custom_speed`，导致高频攻击时动画与逻辑前摇完全脱节。新架构按以下契约统一：

- **单一周期真相**：玩法时钟（`CombatTicker`）唯一决定攻击周期 $T_{\text{atk}}$（统一以 `attack_interval` 秒/次表达，若配置为 `attack_rate` 次/秒则唯一换算为 $1.0 / \text{attack\_rate}$）；动画绝不反向阻塞下一轮攻击计时。
- **周期对齐与重入复位**：设动画原长为 $L_{\text{raw}}$，目标适配时长 $T_{\text{fit}} = \min(L_{\text{raw}}, T_{\text{atk}} \times 0.95)$，有效播放倍率 $s = L_{\text{raw}} / T_{\text{fit}}$（$T_{\text{atk}} \times 0.95 \ge L_{\text{raw}}$ 时 $s = 1.0$）。每次攻击请求进入 `AnimationAdapter` 时必须更新主体与火力点的有效倍率，并在同动画重入时显式 `seek(0, true)`（或 `AnimationTree` `OneShot` 重触发），保证每击从第 0 帧起手。
- **高攻速上限与前摇同步**：设置 `max_anim_speed_scale`（默认 `4.0`）；超过上限时优先切换可选循环连射动画语义（如 `attack_loop`），或封顶倍率并允许下一击直接截断后摇。`launch` 阶段的前摇延迟与动画 `fire` Gate 超时阈值必须按 $\min(\text{配置值}, T_{\text{atk}} \times 0.5)$ 随攻击周期等比缩放，确保逻辑前摇与真实播放倍率严格一致。

VFX 与动画通过阶段进度和语义 Cue 联动。逻辑成长曲线同时绑定碰撞和表现；换 VFX 不改变释放门槛。VFX 自然播放结束默认不结束 Buff；Buff 的终止通知表现适配器淡出或回收。

## 可观测性

每个执行实例输出按 cast_id 归档的追踪记录：阶段进入/退出及原因、Gate 锁存/超时/丢弃、Lease 获取/释放、过期回调丢弃。追踪默认在调试构建开启、发布构建关闭，测试可读取追踪做断言，agent 修改配置后可用追踪定位行为差异。

## 配置联调与编辑器独立性

参数描述声明类型、范围及 Live/NextSpawn/SkillOwned。Lab 和未来编辑器/agent 复用描述、校验器及保存器。

正式配置按完整资源路径寻址；场景默认 → 保存配置 → 临时联调覆盖。旋转/流速可 Live，重建型参数 NextSpawn，伤害/碰撞/阶段输入 SkillOwned。舞台与预览播放参数不发布。

Lab 实时联调与正式保存尚未实现：后续复用表现参数服务，不能直接改执行上下文快照。沿用已确认的跨进程暂存通路、手动保存与失联撤销方案。对局中的结构与玩法参数不被热改。
