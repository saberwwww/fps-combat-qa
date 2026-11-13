# 自动化场景矩阵

共32个新增独立场景。W/D 实现在 `tests/combat.gd` 对应函数；N 实现在 `tests/network.gd`，计数清单由 `scripts/run.py` 强制核对。

共同前置：固定上游与引擎；W/D 每例新建真实玩家、重置 Game、seed=20261113、暂停输入/运动和bot AI；动作前设置弹药，动作后只读断言。D 中保留原武器散布，使用ADS和水平中心瞄准；N 保持真实玩家物理/同步运行。期望来自正式代码，W14/N06按不会访问不存在武器、离线实体应清理的质量要求作缺陷回归。

| ID | 优先级 | 专属前置 | 操作 | 断言 | 测试函数/阶段 | 生产代码入口 |
|---|---|---|---|---|---|---|
| W01 | P0 | rifle mag11/reserve40 | reload→完成 | 30/21，总量51；完成前不转移 | reload_partial | weapon_manager.reload/_process/_finish_reload |
| W02 | P0 | rifle 2/3 | reload→完成 | 5/0，总量5 | reload_shortage | _finish_reload |
| W03 | P1 | rifle 2/0 | reload→推进2s | 拒绝，2/0 | reload_zero | reload |
| W04 | P1 | rifle 30/120 | 请求换弹→推进2s | 拒绝，30/120 | reload_full | reload |
| W05 | P0 | rifle 0/7 | 按扳机→完成换弹 | 无射击，7/0 | empty_trigger | _fire/reload |
| W06 | P0 | rifle 5/20 | reload后按住0.2s | 仍换弹，mag5、shots0 | reload_blocks_fire | _process |
| W07 | P0 | rifle 5/20、shotgun6 | 换弹0.2s→切枪→等待→切回 | 取消、两枪弹药未转移 | switch_interrupt | switch_to/_equip |
| W08 | P0 | rifle 5/40 | 换弹0.4s后重复20次reload→完成 | 计时不重置，30/15 | reload_repeat | reload/_finish_reload |
| W09 | P1 | rifle满弹，自动 | 按住，推进0.001/0.05/0.07s | 冷却前29，后28，共2发 | automatic_hold | set_trigger/_process/_fire |
| W10 | P1 | pistol12，半自动 | 按住并过冷却→松开再按 | 按住11，重按10 | semi_hold | set_trigger/_process |
| W11 | P0 | rifle与shotgun满弹 | 步枪射击→立即切霰弹并按→过冷却再按 | 第一次阻止，随后消耗1壳 | cooldown_switch | _cooldown/switch_to |
| W12 | P1 | 空loadout | 开火、换弹、推进 | 无异常、无弹药、无发射 | unarmed | slot_filled/_fire/reload |
| W13 | P0 | pistol 0/0 infinite | 换弹→射击→过冷却→换弹 | mag恢复12，reserve始终0、实际发1枪 | infinite_pistol | reload/_finish_reload |
| W14 | P0 | 只有rifle 1/10、背包可容纳 | reload→玩家unequip gun1→推进2s | 立即取消、无弹药项、无异常 | remove_during_reload | player.unequip/remove_slot |
| W15 | P1 | rifle槽0、槽1空、正在换弹 | switch 1/-1/3 | 仍槽0并继续原换弹 | empty_slot_switch | switch_to |
| W16 | P1 | DM、步枪0/0、玩家满血 | PvP致死→respawn | 死过且复活HP100，30/120 | respawn_refill | player.receive_damage/respawn |
| D01 | P0 | 每枪fresh、近距bot躯干 | rifle/smg/pistol/sniper各一次真实射击 | 伤害17/12/24/95，合计一场景 | base_damage | WeaponDB/_fire/bot.hit |
| D02 | P0 | 步枪、相机与bot头中心等高 | 瞄头并真实射击 | HP57.5，17×2.5 | head_damage | Hitbox/_resolve_hit |
| D03 | P1 | 步枪、相机与bot腿中心等高 | 瞄腿并真实射击 | HP87.25，17×0.75 | leg_damage | Hitbox/_resolve_hit |
| D04 | P0 | bot前有world层静态墙 | 向目标发射 | mag29，目标HP100 | obstacle | intersect_ray/HIT_MASK |
| D05 | P0 | 同队bot挡在敌方bot前 | 向同队躯干发射 | 两者HP100、扣1发 | friendly_occlusion | team filter/intersect_ray |
| D06 | P1 | 种子固定、2m霰弹躯干 | 一次扳机 | 目标HP19，9×9；扣1壳、shots1 | shotgun | pellets/_fire |
| D07 | P1 | 狙击ADS、目标分别299/301m | 分别fresh后真实射击 | HP5/100；运行时躯干半深0.6m | range_boundary | WeaponDB.range/intersect_ray |
| D08 | P0 | 近距bot、狙击瞄头 | 致死射击→再次调用受伤 | HP0、dead、hitbox关、只加1杀 | bot_death | bot.receive_damage/_die/_set_dead_visual |
| D09 | P0 | 玩家真实受伤致死 | 按扳机 | mag30、shots0 | dead_shooter | _process dead guard |
| N01 | P0 | 两独立OS进程、空房 | 连接并请求双方快照 | peer id/名字/完整config一致 | run lobby | net.register/sync config |
| N02 | P0 | 同房、arena/0bot | 主机start_match、等待实际生成 | 两实际玩家，authority/team/name/HP/index一致 | run spawn | world._begin/MultiplayerSpawner |
| N03 | P1 | N02就绪 | 客户端switch_to pistol | 主机与客户端index=2 | command switch | MultiplayerSynchronizer |
| N04 | P0 | 客户端HP100 | 主机侧目标hit(24,1) | 客户端执行伤害，双方HP76 | run client_damage | player.hit/receive_damage/synchronizer |
| N05 | P0 | 主机HP100 | 客户端侧主机hit(17,clientid) | 主机执行伤害，双方HP83 | command damage_host | player.hit/receive_damage/synchronizer |
| N06 | P0 | 完成双端对局 | 客户端disconnect_net | 主机名册/世界/计分板只剩主机 | run leave | Net.players_changed/world pruning |
| N07 | P1 | 另起两进程、只建大厅 | 服务器disconnect_net | 客户端收到断开、peer=null、名册空 | run server-drop | Net._on_server_disconnected |

当前执行状态、实际值和失败历史见 `docs/TEST_REPORT.md` 与各运行JSON；矩阵描述覆盖，不代替运行证据。
