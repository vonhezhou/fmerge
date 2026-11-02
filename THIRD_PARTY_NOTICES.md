# 第三方代码与依赖

## VS Code MyersDiffAlgorithm 的 Dart 移植

`lib/core/myers.dart` 改编自 Microsoft VS Code：

- 仓库：https://github.com/microsoft/vscode
- 固定提交：`b7d40a42d807a505b4bb6b73058c09340c9dfac0`
- 源文件：`src/vs/editor/common/diff/defaultLinesDiffComputer/algorithms/myersDiffAlgorithm.ts`
- 链接：https://github.com/microsoft/vscode/blob/b7d40a42d807a505b4bb6b73058c09340c9dfac0/src/vs/editor/common/diff/defaultLinesDiffComputer/algorithms/myersDiffAlgorithm.ts
- 修改：Dart 泛型列表与 Map 代替上游序列接口、负索引数组；加入首尾裁剪及内循环时间检查；更改结果数据类型。

移植范围只有 Myers 核心，不包含 VS Code 的完整 Diff 优化管线、Monaco UI、Piece Tree、语法解析引擎或 Merge Editor。

### MIT License

Copyright (c) Microsoft Corporation.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

## 包依赖

依赖原许可证随包保留；完整版本见 `pubspec.lock`。

- Flutter：https://github.com/flutter/flutter （BSD-3-Clause）
- re_editor：https://github.com/reqable/re-editor （MIT）
- re_highlight：https://github.com/reqable/re-highlight （MIT）
- characters：https://pub.dev/packages/characters （BSD-3-Clause）
- file_selector：https://pub.dev/packages/file_selector （BSD-3-Clause）

file_selector 的依赖元数据包含 Web 平台实现；本项目只使用原生桌面 runner，未使用 WebView、Electron 或浏览器编辑器。

## 项目内编辑器扩展

`packages/re_editor` 基于 reqable/re-editor 0.10.0，保留其完整 MIT LICENSE。修改清单见 `packages/re_editor/FMERGE_CHANGES.md`。

正式应用另使用 window_manager（MIT）、path（BSD-3-Clause）和 crypto（BSD-3-Clause）；具体版本见 pubspec.lock。第三方声明随应用资源打包。
