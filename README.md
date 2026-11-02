# fmerge

不使用 WebView / Electron 的原生 Flutter 桌面文本比较与三方合并工具。交互参考 TortoiseGitMerge，首版范围是文本 Diff、三方 Merge、文件保存和 Git 外部工具接入；不包含补丁应用或 Git 客户端。

正式工程位于仓库根目录。

## 使用

macOS Release 构建后可直接打开 `build/macos/Build/Products/Release/fmerge.app`，或使用 `tool/fmerge`。

```sh
flutter --no-version-check pub get
flutter --no-version-check run -d macos
# 构建本平台应用
flutter --no-version-check build macos --release
python3 tool/package.py
```

Windows / Linux 已生成原生 runner 和 CI 构建入口，但本机没有完成这两个平台的构建与人工验收。不要把 macOS 测试等同于三平台验收。

## 文件比较

- 原生可编辑双栏，语法高亮、整行和行内差异、真实行号与同步滚动。
- 虚拟占位不进入文档、剪贴板或保存文件；不会为了对齐往文件插入空行。
- 右侧默认可编辑；左侧需点击“启用左侧编辑”。支持逐块采用左侧，或按两种顺序组合双方区块。
- F7 / Shift F7 跳转差异；⌘/Ctrl F 查找与替换；⌘/Ctrl G 跳转行。
- ⌘/Ctrl S 保存当前编辑目标；⌘/Ctrl Shift S 另存并选择编码和换行。
- 可忽略行尾空白、空格与 Tab、大小写及换行风格；忽略只影响显示，不改写源文档。

## 三方合并

- 输入共同祖先、本地、远端，分别显示双方相对祖先的差异，并共享同一视觉行映射。
- 独立修改自动合并；同一范围双方不一致时保守标记为冲突。
- 支持本地、远端、双方顺序组合、保留祖先，以及手工编辑后标记解决。
- 结果可直接编辑；冲突选择、手工修改和解决状态共用撤销/重做历史。
- 结果编辑之外的手工修改不会因重新选择其他冲突块而整份丢失。
- F8 / Shift F8 导航冲突；结果栏可打开共同祖先供参考。
- 未确认冲突禁止保存；关闭未保存结果需要确认。仅最终结果已保存且没有待处理冲突时，mergetool 返回 0。

三方输入保持只读；需要换输入时重新打开合并。合并判断始终使用精确文本，不受“忽略空白”等显示选项影响。

## 文件完整性与保存

- 自动识别 UTF-8、UTF-8 BOM、UTF-16 LE/BE BOM；可显式用 Latin-1 打开旧式西文文件。不支持 GBK / Shift-JIS 等其他编码，不用替换字符伪装读取成功。
- 原样保留未编辑文件、BOM 和末尾换行。混合换行中能对应的原始行保留各自换行，新行使用主导风格；另存可强制 LF / CRLF / CR。
- 同目录临时文件写入并刷新后 rename；写入失败保护原文件。保存前检测外部修改，要求另存或显式覆盖。
- 可保留 `.bak` 备份；保留 POSIX 权限位；通过符号链接保存时更新实际目标并保留链接。
- 原子替换可能改变 inode，不保证保留所有平台的扩展属性、ACL 或硬链接关系。并发写入不合作的外部程序仍有极短的检查与替换竞争窗口。
- 保存期间继续输入的新修改仍保持未保存，不会误报已保存。
- 文件读取上限 32 MiB；语法高亮上限 4 MiB；极长行有渲染限制。未完成极端大文件与无障碍审计。

## macOS 目录授权

保留 App Sandbox。系统文件选择器授予选中文件的权限；安全保存需要在同目录创建临时文件与备份，首次保存或通过 Git 接收外部路径时，可能要求选择所在目录或其父目录。

只记录用户明确选择的目录安全书签；下次启动恢复这些授权。“设置 → 撤销已授权目录”清除书签，重启后完全生效。没有自动授予整个磁盘访问。

设置和最近文件只保存偏好与路径，不保存文件正文。macOS 位于应用沙盒内的 `Library/Application Support/fmerge`；其他平台使用标准用户配置目录。

## 命令行与 Git

```sh
./tool/fmerge LEFT RIGHT
./tool/fmerge --base BASE --local LOCAL --remote REMOTE --output MERGED
./tool/fmerge --read-only LEFT RIGHT
./tool/fmerge --help
```

- `--wait`：默认等待当前窗口关闭，不会将进程启动成功当作合并成功。
- `--auto-close`：保存成功后尝试关闭；若保存期间又有修改，仍执行未保存保护。
- 兼容 `/base:... /mine:... /theirs:... /merged:...` 路径形式。
- `--output` 在比较模式指定右侧保存目标，避免意外覆盖临时输入。
- 退出码：0 = 比较正常结束，或合并最终结果已保存且冲突全部处理；1 = 合并取消/未完成；64 = 参数错误。
- 首次路径授权被取消或文件读取失败会明确报错，不会偷偷打开示例或空白内容。

以下配置仅供复制，应用不会替用户修改全局 Git 配置：

```sh
git config --global diff.tool fmerge
git config --global difftool.fmerge.cmd '"/Users/von/Codes/private/fmerge/tool/fmerge" "$LOCAL" "$REMOTE"'
git config --global merge.tool fmerge
git config --global mergetool.fmerge.cmd '"/Users/von/Codes/private/fmerge/tool/fmerge" --base "$BASE" --local "$LOCAL" --remote "$REMOTE" --output "$MERGED"'
git config --global mergetool.fmerge.trustExitCode true
```

安装到 Applications 后，可把命令路径换成 `/Applications/fmerge.app/Contents/MacOS/fmerge`。Windows 可直接使用 `fmerge.exe`，或用 `tool/fmerge.ps1` 保留参数和退出码。

## 验证与发布状态

```sh
python3 tool/check.py
python3 tool/check.py --native --build  # macOS，含真实原生集成
python3 tool/package.py
```

单元/界面测试覆盖算法随机重建、编码与换行、合并冲突与历史、外部修改保护、1100×760 / 920×680 界面，以及可编辑占位。真实 macOS 集成使用独立应用标识 `dev.fmerge.integration`，验证系统剪贴板（恢复所有原类型）、保存/备份、原生关闭和系统退出取消。

集成测试导出的预览是实际应用渲染帧，不是系统录屏截图。测试输入不等于人工中文输入法验收。系统目录授权面板与书签跨启动恢复、真实中文 IME、Windows/Linux、冷启动、稳定内存和滚动帧率仍需人工或对应平台验证。

当前是本地可用的 0.1.0 版本，仅有本地 ad-hoc 签名，未做开发者签名、公证或公开发布；不宣称与 TortoiseGitMerge 全功能逐项相同。首版没有补丁应用、目录比较、统一单栏视图、自动换行、未改动区折叠、EditorConfig 与 GBK 等编码。

## 实现与许可

- Flutter + 项目内 `packages/re_editor`，在 0.10.0 基础上扩展原生视觉行布局、差异背景、范围装饰和空白显示，并修正代理绑定时错误的外部通知。
- VS Code Myers 核心移植为 Dart；合并状态机、文件模型、保存保护、界面由本项目实现。
- 没有复制 TortoiseGitMerge 的程序代码、图标或商标资源。相关第三方许可证见 `THIRD_PARTY_NOTICES.md`；编辑器保留原 MIT LICENSE。

## 本轮实测（2026-10-31）

- `python3 tool/check.py --native --build` 通过：格式、静态检查、35 个单元/界面用例与 1 个真实 macOS 集成流程。
- 集成流程验证真实剪贴板（恢复原类型）、BOM/CRLF 保存、备份、原生菜单焦点、关闭与系统退出取消，以及一万行文件的远距离定位和同步滚动。不是滚动帧率基准，也不能代替真实中文 IME 验收。
- Release 包 46.1 MB（构建器输出）；压缩包约 18 MiB。包含 x86_64 与 arm64，只有当前 arm64 Mac 做了运行验收。
- 正式构建已核验沙盒开启、无调试附加权限、无集成测试注入入口；上游许可已打包。
- 实际启动 Release 的 `--help` / `--version` 返回 0，错误参数返回 64；POSIX Git 包装脚本也已执行验证。未改动用户全局 Git 配置。
- 欢迎页 Release 进程单次 RSS 145,296 KiB（约 142 MiB）；不是稳定内存或冷启动基准。
- Flutter 测试驱动输出过 `Failed to foreground app; open returned 1`，但应用内实际 macOS 流程和渲染成功；最终 Release 已另外正常打开。
- 发布包在 `dist/fmerge-0.1.0-macos.zip`，校验和见 `dist/SHA256SUMS.txt`。
