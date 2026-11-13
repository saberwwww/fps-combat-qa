# GAME-002：客户端离开后主机保留玩家实体与计分行

类型：**真实产品联机生命周期缺陷**，没有故障注入。严重程度S2 / 优先级P1。状态：最小清理补丁及双进程回归已通过，未提交上游。

环境：macOS26 arm64、Godot4.6 stable、上游 `7259140487946532af8310723392cca34a4fb0bb`。本机ENet两个独立进程，arena/Deathmatch/0bot，关闭其他对局。

## 复现

1. 主机 host_game，客户端连接，确认两端名册/config一致。
2. 主机start_match，等待两端确实各有2个玩家实体。
3. 完成客户端切枪、主机→客户端24伤害、客户端→主机17伤害并比较两端结果。
4. 客户端真实disconnect_net；主机等待3秒并检查Net名册、world玩家和Game.scores。

预期：主机三者均只剩主机，不保留断开peer对应实体。

实际：名册1，世界玩家2，scores仍为主机+离线客户端。`evidence/network/cleanup-unpatched/host-report.json` 的N06失败，host进程exit1。N01—N05都通过，说明是在已正确进入并同步对局后发生。

原版未改的net_host/net_client还给出旁证：客户端结束后net_players=1、world_players=2，随后 bot 可能向离线peer触发unknown peer RPC。但该旁证本身不作为完整同步断言。

## 根因与修复

`Net._on_peer_disconnected()` 只从players删id并同步名单。world未监听这个变更，没有删除由MultiplayerSpawner生成的离线player，也没调用Game.unregister_combatant。

`patches/003-despawn-departed-player.patch` 在world连接players_changed，仅主机扫描其Combatants，发现player.combatant_id不在Net.players时unregister计分并queue_free节点。MultiplayerSpawner负责向仍在线的peer传播删除。本项目只验证一个客户端离开后主机状态；未用第三个在线客户端额外验收删除广播。

修复后N06名册1、world1、scores仅主机。证据 `evidence/network/fixed-first/combat/host-report.json`、`evidence/acceptance/local-*/network-combat/host-report.json`。客户端只移除自己的测试world，不碰主机world，断言不会被测试主动“清掉实际结果”掩盖。

```bash
python3 scripts/run.py --suite network --unpatched  # N06失败
python3 scripts/run.py --suite network              # N01—N07通过
```

范围限制：测试的是主动退出/ENet断连清理；不是丢包恢复、断线重连、服务器迁移或客户端预测问题。
