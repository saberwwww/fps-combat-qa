# 基于开源 FPS 游戏的战斗玩法测试与自动化回归体系

**FPS Combat QA & Regression Testing** · 游戏测试 / 测试开发实习项目

面向第三方游戏 **[OpenFire](https://github.com/rokasjasonas/openfire)** 建立可复现的玩法与联机回归，不包含自主开发 FPS 游戏的声明。重点是规则核实、跨状态测试、实际缺陷闭环和可信的自动化门禁。

## 已验证的成果

- **32 个新增独立场景**：16 个武器状态、9 个伤害战斗、7 个双进程联机检查；参数化枪械仍按一个场景计数。
- macOS 完整门禁连续 3 轮 **32/32**，没有脚本或引擎 ERROR；原始过程日志、逐项 JSON 和 JUnit 全部保留。后续验证状态以 [测试报告](docs/TEST_REPORT.md) 为准。
- **2 个真实产品问题 + 1 个测试基础设施问题**：换弹时卸载最后武器异常、离线玩家残留、失败退出码为 0。原始上游、补丁、复现和回归分开保存。
- 检查实际 ENet 两进程的配置、实例身份/权限、切枪状态、双向伤害和断连清理，不能只靠 DONE 文本通过。
- 注入“每发扣两颗子弹”后，25 个玩法场景中 **6 项失败**，门禁返回 1。额外验证脚本异常/语法错误即使退出码 0 也会被拦截，以及超时和缺失报告。
- GitHub Actions 执行入口已配置，固定引擎及 Actions 提交，自动保留失败证据。云端实际运行链接见测试报告；没有链接的状态不算云端成功。

## 被测系统与归属

| 项目 | 固定值 |
|---|---|
| 上游 | https://github.com/rokasjasonas/openfire |
| Commit | `7259140487946532af8310723392cca34a4fb0bb` |
| 游戏版本 | `0.2.29` |
| 本项目引擎 | `4.6.stable.official.89cea1439`，官方包 SHA512 锁定 |
| 上游要求 / release workflow | Godot 4.6 / 4.6.3；本项目未宣称使用 4.6.3 |
| 游戏代码 | MIT，© 2026 OpenFire contributors |
| 素材 | 上游声明 Kenney CC0，保留 LICENSE/CREDITS |
| 本项目新增内容 | 测试源码、运行器、缺陷补丁、证据和中文交接资料；使用 AI 辅助实现 |

[第三方声明](THIRD_PARTY_NOTICES.md) · [版本锁](upstream.lock.json) · [引擎锁](engine.lock.json)

## 一键运行

需要 Python **3.11+**、Git、curl；支持 macOS universal / Linux x86_64。无需 pip 包、GdUnit、导出模板或 ComfyUI 模型。

```bash
git clone --recurse-submodules https://github.com/saberwwww/fps-combat-qa.git
cd fps-combat-qa
python3 scripts/run.py
```

第一次联网下载固定 Godot，引擎存于 `.runtime/`。后续输出到新的 `evidence/runs/<UTC时间>/`，不覆盖旧证据。成功返回 0；断言失败、引擎错误、超时、缺失或重复场景均返回非零。macOS 的 `user://` 使用专用 `FPSCombatQA/20261113` 用户目录；编辑器缓存使用本地 portable 目录。Codex 沙箱内运行需要允许引擎写入这个专用目录和使用本机 UDP。

```bash
python3 scripts/run.py --suite combat
python3 scripts/run.py --suite network
# 明确的受控故障注入，预期退出 1；不会修改 upstream
python3 scripts/run.py --suite combat --inject-failure
# 未打补丁的原始逻辑，预期 W14、N06 失败
python3 scripts/run.py --unpatched
```

`.runtime/game/` 是每次从固定子模块生成的可丢弃副本，仅对该副本应用 `patches/`。不要同时执行多个运行器，它们共用这个副本。原有 Smoke 与退出码实验不是默认通过门禁的一部分；重现命令见缺陷报告。

## 阅读顺序

1. [可行性报告](docs/FEASIBILITY.md)：真实环境与上游基线。
2. [测试计划](docs/TEST_PLAN.md) / [场景矩阵](docs/CASE_MATRIX.md)：规则与覆盖依据。
3. [测试架构](docs/ARCHITECTURE.md) / [上游审计](docs/UPSTREAM_AUDIT.md)。
4. [缺陷报告](docs/BUG_REPORTS/) / [执行报告](docs/TEST_REPORT.md)。
5. [面试交接：20 问及简历描述](docs/INTERVIEW_HANDOFF.md)。

## 真实边界

原始大 Smoke 本机汇总失败，未被包装为通过。主菜单依赖 ComfyUI 就绪，本项目只验证其 headless 加载；独立场景直接执行真实战斗代码。未验证完整图形游玩、弱网、反作弊、客户端预测、多人压力、移动平台或 AI 体验。伤害联网场景直接调用生产 `hit()` 来隔离 RPC/权限/血量同步；联网端到端瞄准开枪未覆盖。本地伤害场景使用真实射线与真实 hitbox，固定种子；这不是对全部随机散布的统计验证。
