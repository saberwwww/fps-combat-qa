# 证据目录说明

所有游戏日志均来自真实子进程；没有手写通过日志或伪造视频。一次传输错误日志含临时签名URL，其公开副本明确标注了query脱敏，原始副本保留本地；详见cloud/transport-log-redactions.json。目录中包含预期失败、初期测试布置错误和环境失败，不是“每个日志都应绿”。

- phase1：clone/下载/引擎校验/环境失败/主场景/未修复Smoke及net/原型combat/W14复现。早期clone JSON没有UTC字段，后续capture统一记录UTC；原始文件不补造时间。
- exit-code：明确强制布尔失败的Smoke对照，以及修复host缺客户端。
- combat / network：专项与收尾清理诊断；未修复N06的失败、修复后结果和资源泄漏定位均保留。
- acceptance：正常完整门禁及标注mutation=true的负向门禁；以summary.json/provenance.json为可追溯入口。
- guards：真实引擎语法/运行时异常、timeout与缺失报告拦截，单独计数。
- 已完成的云端链接与原始artifact见 docs/TEST_REPORT.md 与 evidence/cloud/。

每个*-process.json记录实际command、cwd、UTC开始、墙钟耗时、原始exit、是否超时；同名log为stdout+stderr。报告包含case id、expected、actual、passed。源码/patch SHA256以及引擎与上游版本见provenance.json；早期实验尚未有统一provenance，结合固定上游、补丁和命令阅读。

本机文件中的绝对路径只用于记录已发生的命令；运行脚本动态计算项目根目录，换机器不需要复用这些绝对路径。
