# fmerge 编辑器扩展

上游：reqable/re-editor，pub.dev 0.10.0，保留 MIT LICENSE。

保持原始包文件结构与风格，不批量格式化上游源码。

- code_diff.dart：CodeDiffLayout / CodeDiffRange，独立的文档行→显示行映射、整行背景、行内装饰和空白显示；新增隐藏行集合与折叠提示行，映射保持单调。
- code_line.dart / _code_line.dart：控制器公开布局属性，代理转发；绑定编辑视图时仅通知代理自身的监听者，不在布局阶段通知外部文档观察者。
- _code_editable.dart / _code_field.dart：布局传递；固定行高、无自动换行的 Diff 渲染；二分定位可见行；离屏跳转使用真实显示坐标；占位映射到邻近真实行。跳过隐藏行及行号绘制，显示未改动区提示。

文档、剪贴板、输入法、选择与撤销仍使用上游真实文本模型，虚拟占位不进入字符串。

验收入口：test/editable_diff_test.dart、test/context_rows_test.dart、test/workbench_test.dart 与 integration_test/desktop_test.dart。自动换行、语法折叠、极长行及 IME 的进一步人工验收不能由这些基础用例替代。

- code_scroll.dart / _code_field.dart：新增 `makeCenter` 主动导航接口，即使目标行已可见也居中；保留原有“不可见时才居中”的编辑器行为，复用换行和差异对齐坐标并限制在有效滚动范围。

- _code_indicator.dart：Diff 可见段落按真实文档索引绘制行号，跨省略区不再连续重编号；省略带延伸到行号栏，换行切换沿用实际显示坐标。
- code_diff.dart / _code_field.dart / _code_selection.dart：省略提示支持双行高度、配色、隐藏行数与原始行号范围；点击提示进入全文并定位所选区域，兼容鼠标和触摸，不改变文本和撤销记录。
- _consts.dart：平台判断使用 getter，避免首次读取平台后缓存，确保桌面/触摸回归用例按各自平台验证焦点和选区行为。
