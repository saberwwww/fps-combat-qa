# INFRA-001：测试已检测失败，但进程退出码为0

类型：**真实测试基础设施缺陷**。严重程度S2 / 优先级P1（本项目评估）。状态：本地独立补丁已验证，未提交上游PR。

环境：macOS26 arm64，Godot4.6.stable.official.89cea1439，OpenFire `7259140487946532af8310723392cca34a4fb0bb`。

## 复现与结果

1. 在准备好的运行副本执行 `Godot --headless --path .runtime/game res://tests/smoke.tscn`。
2. 观察最终 `SMOKE: DONE ok=false`。
3. 从外部 subprocess 读取 returncode，实际为0，预期非零。

真实基线 `evidence/phase1/smoke-permitted.{log,json}`：20.472s，exit0。原始 Smoke fire_works=false 并有其他引擎错误，**不能判为通过**。

另一个无注入复现：只启动 `tests/net_host.tscn`、不启动客户端。15.366s 后打印 `NETHOST: no client connected — FAIL`，但exit0。证据 `evidence/phase1/net-host-no-client-baseline.*`。

## 受控失败对照（明确是注入）

`scripts/exit_experiment.py` 只在运行副本给最终布尔结果添加 `false and`，强制汇总失败；没有制造或宣称新的产品Bug。证据：

| 同一强制失败 | 最终结果 | exit | 耗时 |
|---|---|---:|---:|
| 原脚本 | ok=false | 0 | 20.720s |
| 修复脚本 | ok=false | 1 | 20.513s |
| 修复net_host，无客户端 | FAIL | 1 | 15.430s |

完整命令/日志：`evidence/exit-code/`。重现：`python3 scripts/exit_experiment.py`（需先bootstrap；实验日志默认固定目录，重跑前应另存旧证据）。

## 根因与修复

源码 `smoke.gd` 最后无参数quit；net_host失败分支同样无参数。Godot [SceneTree.quit](https://docs.godotengine.org/en/4.6/classes/class_scenetree.html) 默认 exit_code=0。

`patches/001-test-exit-codes.patch`：用同一表达式计算qa_ok，同时用于打印和 `quit(0 if qa_ok else 1)`；net_host失败分支显式quit(1)，不更改成功/失败预期。

上游 release.yml 已 grep `SMOKE: DONE ok=true`，这可以拦截布尔false。因此该问题证明“直接依赖进程码会假绿”，**不证明现有上游release gate漏检**。本项目的运行器另行检查脚本/引擎ERROR、超时和报告缺失，覆盖bool汇总不能捕获的异常。
