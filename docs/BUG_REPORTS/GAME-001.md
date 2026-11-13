# GAME-001：换弹时卸下最后武器导致完成换弹访问空弹药项

类型：**真实产品脚本缺陷**，没有故障注入。严重程度S2 / 优先级P1。状态：独立最小补丁及自动化回归已通过，未合并到上游。

环境：macOS26 arm64，Godot4.6.stable.official.89cea1439，OpenFire `7259140487946532af8310723392cca34a4fb0bb`。

## 前置与复现

真实player场景，只有rifle，弹夹1/备用10，玩家有背包空间。

1. 调用真实 `weapons.reload()`。
2. 换弹尚未完成时，调用真实玩家 `unequip("gun1")`，将枪放回背包；生产路径内部调用remove_slot。
3. 推进真实武器 `_process(2.0)`，跨过1.9s换弹时间。

预期：已无武器，换弹取消，不能访问被删除的弹药项；无脚本异常。

实际：remove_slot移除枪和ammo后仍保留_reloading=true；到时 `_finish_reload()` 执行 `ammo[loadout[current_index]]`，loadout项为空，抛出 `Invalid access to property or key ... Dictionary`。

最小复现：`evidence/phase1/W14-repro.log` / `.json` / `W14-repro-report.json`，耗时0.667s、exit1。日志显示生产unequip后canceled_immediately=false，接着异常；测试没有写结果生命值或弹药来制造失败。

## 根因与修复

`remove_slot()` 只有“还有其他枪且当前枪被移除”才调用 `_equip()`；_equip会清_reloading，但“最后一把”分支只清模型和index，遗漏换弹状态。

`patches/002-cancel-unarmed-reload.patch` 只在 `not _has_weapon()` 分支加入 `_reloading=false`。不改变弹夹容量、备用数、伤害或换弹时间。

W14修复后canceled_immediately=true、ammo={}、跨过换弹结束时间无异常。完整32场景回归见 `evidence/acceptance/local-01` 至 `local-03`；含部分换弹、切枪中断、非法槽切换、无限手枪等关联规则。

可复现命令：

```bash
python3 scripts/run.py --suite combat --unpatched  # W14失败（真实上游逻辑）
python3 scripts/run.py --suite combat              # 应通过
```

机器证据是方法级稳定复现；尚未录制通过背包UI鼠标操作的视频，不将这项UI流程写为已验收。
