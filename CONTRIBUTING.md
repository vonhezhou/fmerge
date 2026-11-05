# 贡献指南

使用 Flutter 3.47.9 stable（Dart 3.13.7），在仓库根目录执行：

```sh
flutter --no-version-check pub get --enforce-lockfile
python3 tool/check.py
```

保持修改聚焦，业务行为变化应补充直接相关的回归测试。涉及保存、编码、合并或 Git 索引时，请验证失败路径和原始数据保护。修改项目内 `packages/re_editor` 时保留上游风格与许可，并同步更新 `FMERGE_CHANGES.md`；不要批量格式化上游源码。

macOS 原生集成和 Release 构建使用：

```sh
python3 tool/check.py --native --build
```

原生测试会启动独立应用并操作窗口与剪贴板，请在可交互桌面环境运行。Windows / Linux 需在各自平台构建与验证，不以 macOS 结果代替。

提交问题请提供系统及架构、Flutter 版本、复现步骤、预期与实际结果。文本样例应尽量小且不包含私密信息；涉及编码时请注明编码和换行形式。

提交 PR 请说明行为变化及实际执行的验证。请保留第三方版权和许可声明，仅贡献你有权提供的代码。
