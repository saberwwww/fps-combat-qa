# 第三方与贡献边界

OpenFire 来自 https://github.com/rokasjasonas/openfire，固定 SHA 见 `upstream.lock.json`。原始项目以 git 子模块保存，不修改其被跟踪文件。其 MIT License、Copyright (c) 2026 OpenFire contributors 与素材声明见 `upstream/openfire/LICENSE`、`CREDITS.md`。

上游将 art assets 声明为 Kenney CC0 1.0；本项目引用这项声明，不声称独立审计了每个资产的来源。NobodyWho 原生库未安装/分发；运行副本按上游发布脚本同样的降级方式移除其可选 `.gdextension` manifest。LLM、ComfyUI、生成式任务与素材服务不作为本测试范围。

Godot Engine 来自官方 godotengine/godot-builds，MIT，安装包保存在忽略的 `.runtime/`，不作为本仓库重新分发的二进制。下载的版本、URL、SHA512 见 `engine.lock.json`。GitHub 官方 checkout/upload-artifact 使用固定提交。

本仓库的贡献为 QA 设计、自动化断言、执行脚本、最小缺陷补丁与文档，包含 AI 辅助代码与整理。不得将上游枪械、模型、AI、地图或联机框架当作求职者个人开发成果。自动化证据说明机器实际做了什么，不等于作者个人独立完成全部编码。
