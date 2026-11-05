# fmerge

原生 Flutter 桌面文本比较与三方合并工具，不使用 WebView / Electron。支持可编辑双栏 Diff、三方合并、无损编码保存、Git 外部工具接入和按块暂存，交互参考 TortoiseGitMerge。

当前版本为 **0.1.0 预览版**。macOS 已有本地运行验证；Windows / Linux 提供 runner 和 CI 构建入口，尚未完成对应平台人工验收。

## 功能

- 双栏文本比较、行内高亮、移动代码识别、同步滚动和差异导航。
- 三方合并、冲突选择与手工编辑，未确认冲突禁止保存。
- UTF-8、UTF-16 与多种旧编码；保存前检查无损往返、外部修改与未保存状态。
- 同目录临时文件替换、可选备份、保留换行与符号链接目标。
- Git difftool / mergetool、按选中代码所在差异块暂存。
- 亮暗主题、自定义主题、快捷键、自动换行及只看差异。

详细操作和边界见 [使用指南](docs/usage.md)，性能数据与方法见 [性能评估](docs/performance.md)。

## 从源码运行

使用 **Flutter 3.47.9 stable / Dart 3.13.7**，与 CI 保持一致。需要本平台的 Flutter 桌面构建工具链；Git 功能另需安装 Git。

```sh
# 在仓库根目录执行，依赖使用 https://pub.dev
flutter --version
flutter --no-version-check pub get --enforce-lockfile
flutter --no-version-check run -d macos
```

Windows / Linux 分别把设备名替换为 `windows` / `linux`。如果本地设置了 `PUB_HOSTED_URL` 镜像，请先切回官方源，或自行维护本地依赖配置。

```sh
python3 tool/check.py
# 构建本平台 Release；macOS 可另加 --native 运行原生集成
python3 tool/check.py --build
python3 tool/package.py
```

打包结果位于 `dist/`，版本号读取自 `pubspec.yaml`，同时生成 `SHA256SUMS.txt`。macOS 可打开 `build/macos/Build/Products/Release/fmerge.app`。当前打包脚本不签名、不公证、不上传发布。

## 命令行与 Git

```sh
./tool/fmerge LEFT RIGHT
./tool/fmerge --base BASE --local LOCAL --remote REMOTE --output MERGED
./tool/fmerge --help
```

Windows 可直接调用 `fmerge.exe` 或 `tool/fmerge.ps1`；包装脚本默认目录适用于 x64，其他架构可通过 `FMERGE_BINARY` 指定可执行文件。

Git 配置可在“设置 → Git 集成”复制；应用不会自动修改全局 Git 配置。合并只有在最终结果已保存且没有待处理冲突时才返回 0。完整配置示例见 [Git 接入](docs/usage.md#命令行与-git)。

## 已知限制

- 单文件读取上限 32 MiB；语法高亮上限 4 MiB；极长行显示截断不影响源文件。
- macOS 保留 App Sandbox，首次保存或 Git 接入可能要求目录授权；现有本地构建仅使用 ad-hoc 签名。
- 系统目录授权与书签跨启动恢复、真实中文输入法、Windows / Linux、极端大文件及无障碍仍需验收。
- 不提供目录比较、补丁创建 / 应用、统一单栏视图、EditorConfig、完整 GB18030 或 EUC-KR。
- 原子替换不保证保留扩展属性、ACL、硬链接关系；与不合作的外部写入程序仍存在极短竞争窗口。

公开源码与二进制发布的验证要求见 [发布验收清单](docs/releasing.md)。

## 贡献与许可

提交问题时请说明系统、Flutter 版本、复现步骤和最小输入样例，避免附带私有文件内容。修改前请阅读 [贡献指南](CONTRIBUTING.md)，历史记录见 [CHANGELOG.md](CHANGELOG.md)。

项目原创代码采用 [MIT License](LICENSE)。项目内编辑器和 VS Code Myers 移植保留上游声明，详见 [第三方许可](THIRD_PARTY_NOTICES.md)。未复制 TortoiseGitMerge 的程序代码、图标或商标资源。
