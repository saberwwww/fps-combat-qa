# 执行报告

日期：2026-11-13（Asia/Shanghai）。代码与引擎见README/锁文件；原始时间戳为UTC，完整命令/实际耗时/退出码在各进程JSON。

## 验收结果

| 轮次 | 游戏场景 | 断言失败 | 基础设施错误 | 结果 |
|---|---:|---:|---:|---|
| `evidence/acceptance/local-01` | 32 | 0 | 0 | 通过 |
| `evidence/acceptance/local-02` | 32 | 0 | 0 | 通过 |
| `evidence/acceptance/local-03` | 32 | 0 | 0 | 通过 |
| `evidence/acceptance/local-final`（最终代码） | 32 | 0 | 0 | 通过 |
| `evidence/acceptance/mutation-01`（受控注入） | 25 | 6 | exit1 | 正确拦截，预期失败 |

正常每轮16武器+9伤害+7联机，独立运行副本恢复；N07重新建立另一对进程。正常门禁同时检查无SCRIPT ERROR/ERROR、退出0、未超时、报告完整。没有把基础设施实验、参数化四枪或循环20次输入计入32场景。

受控变异只在运行副本将扣弹1改为2，未改预期。W09/W10/W11/D04/D05/D06失败，具体actual/expected见mutation-01报告。不是发现6个真实产品Bug。

`evidence/guards/verification.json`：真实运行时字典访问异常和语法错误均出现Godot退出0，但错误扫描成功检出；超时进程真实被终止；缺失报告也被拒绝。4类基础设施实验单独记录，不计为玩法。

## 原始基线与修复

原始Smoke：20.472s、DONE false、exit0；原net_host缺客户端：15.366s、FAIL、exit0。受控强制Smoke失败原版exit0，补丁后exit1；修复net_host缺客户端exit1。见 [INFRA-001](BUG_REPORTS/INFRA-001.md)。原Smoke仍有导航/资源等错误，本项目没有宣称修复了整个大Smoke。

W14最小复现：生产unequip→未取消reload→完成时空key异常，0.667s、exit1。局部修复及完整玩法回归通过，见 [GAME-001](BUG_REPORTS/GAME-001.md)。

N06未修复：名册1、world2、score2，host exit1；修复后1/1/1。双向伤害分别观察客户端76HP、主机83HP；双方一致。见 [GAME-002](BUG_REPORTS/GAME-002.md)。

## 测试自身问题与修正记录

初版combat-unpatched 25项有3失败：W14为真实产品异常；D02从低处射向头先被躯干挡住，D08因此首发未致死。这两项是测试几何前置问题，改为相机与命中部位等高，伤害期望不变。原始失败保留，不将其算作游戏Bug。

初版退出会销毁仍等待0.7秒的血花节点，产生资源警告；联机过早移除peer导致minimap查询错误，音乐流还在播放。测试收尾现在等待真实FX、先销毁客户端world再断peer、停止Music后退出。`evidence/combat/cleanup-fixed.log` 与 `evidence/network/resource-diagnostic/` 保留定位过程；正常验收日志无ERROR。没有加入错误白名单来放行这些问题。

## 云端CI

实际已完成，平台Ubuntu24.04，测试提交`75bd637227256d4275e752b1615e8576ccced1a9`。以下是两个独立真实运行，不是截图或人工生成的结果：

| 运行 | 触发 | 断言 | Workflow结果 | 证据上传 |
|---|---|---|---|---|
| [43374453786](https://github.com/saberwwww/fps-combat-qa/actions/runs/43374453786) | push | **32/32**，无基础设施ERROR | **success** | success |
| [43374544299](https://github.com/saberwwww/fps-combat-qa/actions/runs/43374544299) | workflow_dispatch，inject_failure=true | 26通过、**6失败** | **failure**（回归步骤失败） | **success** |

已下载两次原始artifact到`evidence/cloud/normal`和`mutation`，作业/步骤元数据和完整作业日志在同目录上层。`verification.json`验证数字、失败ID和上传步骤；本地最终版与正常CI的测试/脚本/补丁SHA256完全一致。变异artifact ZIP的SHA256与GitHub上传日志摘要一致。

仓库已公开：[fps-combat-qa](https://github.com/saberwwww/fps-combat-qa)，默认分支`codex/fps-qa`。后续提交仅补交云端证据和文档，不改变已验证测试代码。前期Git TLS/EOF失败和重试如实记录；云端运行最后实际完成。一次下载错误含短期签名地址，公开副本明确标注去掉签名query，原始传输错误日志保留于忽略的`.runtime/private-transfer-logs`，未修改任何游戏运行结果。

## 限制

只验证固定4.6 stable/macOS以及后续明确记录的CI平台；上游release为4.6.3。主菜单headless启动可加载，ComfyUI gate存在，未下载多GB模型，未人工完成图形游玩或录制游戏录像。暂停AI的确定性环境不验证AI行为；联网hit直调不代表联网完整射线开枪已覆盖。射程测两侧而非精确浮点端点。未测试弱网、重连、压力、预测、反作弊或全模式；N07只测大厅断开网络对象清理。
