import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum AppCommand {
  open,
  save,
  saveAs,
  reload,
  close,
  undo,
  redo,
  copy,
  cut,
  paste,
  selectAll,
  find,
  replace,
  goToLine,
  nextDiff,
  previousDiff,
  nextConflict,
  previousConflict,
  nextInlineDiff,
  previousInlineDiff,
  swapSides,
  takeLeft,
  takeRight,
  toggleLeftEdit,
  ignoreWhitespace,
  contextOnly,
  showWhitespace,
  stage,
  settings,
  gitSettings,
  toggleOverview,
  toggleLineDetails,
  toggleWordWrap,
  toggleWordDiff,
  toggleMovedBlocks,
}

extension AppCommandInfo on AppCommand {
  String get label => const {
    AppCommand.open: '打开比较',
    AppCommand.save: '保存',
    AppCommand.saveAs: '另存为',
    AppCommand.reload: '重新加载',
    AppCommand.close: '关闭窗口',
    AppCommand.undo: '撤销',
    AppCommand.redo: '重做',
    AppCommand.copy: '复制',
    AppCommand.cut: '剪切',
    AppCommand.paste: '粘贴',
    AppCommand.selectAll: '全选',
    AppCommand.find: '查找',
    AppCommand.replace: '替换',
    AppCommand.goToLine: '跳转到行',
    AppCommand.nextDiff: '下一处差异',
    AppCommand.previousDiff: '上一处差异',
    AppCommand.nextConflict: '下一处冲突',
    AppCommand.previousConflict: '上一处冲突',
    AppCommand.nextInlineDiff: '下一处行内差异',
    AppCommand.previousInlineDiff: '上一处行内差异',
    AppCommand.swapSides: '交换左右文件',
    AppCommand.takeLeft: '使用左侧差异块',
    AppCommand.takeRight: '使用右侧差异块',
    AppCommand.toggleLeftEdit: '切换左侧编辑',
    AppCommand.ignoreWhitespace: '忽略行首、行尾空白',
    AppCommand.contextOnly: '仅显示差异及附近行',
    AppCommand.showWhitespace: '显示空白字符',
    AppCommand.stage: '暂存所选代码块',
    AppCommand.settings: '设置',
    AppCommand.gitSettings: 'Git 集成',
    AppCommand.toggleOverview: '显示差异概览',
    AppCommand.toggleLineDetails: '显示行详情',
    AppCommand.toggleWordWrap: '长行自动换行',
    AppCommand.toggleWordDiff: '按单词显示行内差异',
    AppCommand.toggleMovedBlocks: '识别移动代码块',
  }[this]!;
  String get group => index <= AppCommand.close.index
      ? '文件'
      : index <= AppCommand.goToLine.index
      ? '编辑'
      : index <= AppCommand.previousInlineDiff.index
      ? '导航'
      : index <= AppCommand.toggleLeftEdit.index
      ? '差异操作'
      : '显示与工具';
}

bool get shortcutMacOS => defaultTargetPlatform == TargetPlatform.macOS;

class KeyBinding {
  const KeyBinding(
    this.key, {
    this.primary = false,
    this.shift = false,
    this.alt = false,
    this.control = false,
    this.meta = false,
  });
  final LogicalKeyboardKey key;
  final bool primary, shift, alt, control, meta;
  SingleActivator get activator => SingleActivator(
    key,
    control: control || primary && !shortcutMacOS,
    meta: meta || primary && shortcutMacOS,
    shift: shift,
    alt: alt,
  );
  String get signature {
    final a = activator;
    return '${key.keyId}:${a.control}:${a.meta}:$shift:$alt';
  }

  String get label => [
    if (activator.control) 'Ctrl',
    if (activator.meta) shortcutMacOS ? '⌘' : 'Meta',
    if (alt) shortcutMacOS ? '⌥' : 'Alt',
    if (shift) 'Shift',
    key.keyLabel == ',' ? ',' : key.keyLabel,
  ].join(' + ');
  Map<String, Object> toJson() => {
    'key': key.keyId,
    'primary': primary,
    'shift': shift,
    'alt': alt,
    'control': control,
    'meta': meta,
  };
  static KeyBinding? fromJson(Object? json) {
    if (json is! Map || json['key'] is! int) return null;
    final key = LogicalKeyboardKey.findKeyByKeyId(json['key'] as int);
    if (key == null) return null;
    return KeyBinding(
      key,
      primary: json['primary'] == true,
      shift: json['shift'] == true,
      alt: json['alt'] == true,
      control: json['control'] == true,
      meta: json['meta'] == true,
    );
  }

  static bool isModifier(LogicalKeyboardKey key) => {
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
  }.contains(key);
  static KeyBinding capture(LogicalKeyboardKey key) {
    final keyboard = HardwareKeyboard.instance;
    return KeyBinding(
      key,
      primary: shortcutMacOS
          ? keyboard.isMetaPressed
          : keyboard.isControlPressed,
      control: shortcutMacOS && keyboard.isControlPressed,
      meta: !shortcutMacOS && keyboard.isMetaPressed,
      shift: keyboard.isShiftPressed,
      alt: keyboard.isAltPressed,
    );
  }

  String? get invalidReason {
    if (isModifier(key) ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.tab) {
      return '请选择字母、数字或功能键作为主键';
    }
    final function =
        key.keyId >= LogicalKeyboardKey.f1.keyId &&
        key.keyId <= LogicalKeyboardKey.f24.keyId;
    if (!function && !activator.control && !activator.meta && !alt) {
      return '请搭配 ⌘ / Ctrl / Alt，避免覆盖正常输入';
    }
    if (key == LogicalKeyboardKey.keyQ &&
            activator.meta &&
            !alt &&
            !shift &&
            !activator.control ||
        key == LogicalKeyboardKey.f4 &&
            alt &&
            !activator.meta &&
            !activator.control ||
        key == LogicalKeyboardKey.delete && activator.control && alt) {
      return '该组合由系统保留，请选择其他快捷键';
    }
    return null;
  }
}

final defaultBindings = <AppCommand, KeyBinding>{
  AppCommand.toggleWordWrap: const KeyBinding(
    LogicalKeyboardKey.keyZ,
    primary: true,
    alt: true,
  ),
  AppCommand.toggleWordDiff: const KeyBinding(
    LogicalKeyboardKey.keyI,
    primary: true,
    alt: true,
  ),
  AppCommand.toggleMovedBlocks: const KeyBinding(
    LogicalKeyboardKey.keyM,
    primary: true,
    alt: true,
  ),
  AppCommand.toggleOverview: const KeyBinding(
    LogicalKeyboardKey.keyO,
    primary: true,
    alt: true,
  ),
  AppCommand.toggleLineDetails: const KeyBinding(
    LogicalKeyboardKey.keyL,
    primary: true,
    alt: true,
  ),
  AppCommand.nextInlineDiff: const KeyBinding(LogicalKeyboardKey.f7, alt: true),
  AppCommand.previousInlineDiff: const KeyBinding(
    LogicalKeyboardKey.f7,
    alt: true,
    shift: true,
  ),
  AppCommand.open: const KeyBinding(LogicalKeyboardKey.keyO, primary: true),
  AppCommand.save: const KeyBinding(LogicalKeyboardKey.keyS, primary: true),
  AppCommand.saveAs: const KeyBinding(
    LogicalKeyboardKey.keyS,
    primary: true,
    shift: true,
  ),
  AppCommand.reload: const KeyBinding(
    LogicalKeyboardKey.keyR,
    primary: true,
    shift: true,
  ),
  AppCommand.close: const KeyBinding(LogicalKeyboardKey.keyW, primary: true),
  AppCommand.undo: const KeyBinding(LogicalKeyboardKey.keyZ, primary: true),
  AppCommand.redo: const KeyBinding(
    LogicalKeyboardKey.keyZ,
    primary: true,
    shift: true,
  ),
  AppCommand.copy: const KeyBinding(LogicalKeyboardKey.keyC, primary: true),
  AppCommand.cut: const KeyBinding(LogicalKeyboardKey.keyX, primary: true),
  AppCommand.paste: const KeyBinding(LogicalKeyboardKey.keyV, primary: true),
  AppCommand.selectAll: const KeyBinding(
    LogicalKeyboardKey.keyA,
    primary: true,
  ),
  AppCommand.find: const KeyBinding(LogicalKeyboardKey.keyF, primary: true),
  AppCommand.replace: const KeyBinding(
    LogicalKeyboardKey.keyF,
    primary: true,
    alt: true,
  ),
  AppCommand.goToLine: const KeyBinding(LogicalKeyboardKey.keyG, primary: true),
  AppCommand.nextDiff: const KeyBinding(LogicalKeyboardKey.f7),
  AppCommand.previousDiff: const KeyBinding(LogicalKeyboardKey.f7, shift: true),
  AppCommand.nextConflict: const KeyBinding(LogicalKeyboardKey.f8),
  AppCommand.previousConflict: const KeyBinding(
    LogicalKeyboardKey.f8,
    shift: true,
  ),
  AppCommand.swapSides: const KeyBinding(
    LogicalKeyboardKey.keyX,
    primary: true,
    shift: true,
  ),
  AppCommand.takeLeft: const KeyBinding(
    LogicalKeyboardKey.arrowRight,
    alt: true,
  ),
  AppCommand.takeRight: const KeyBinding(
    LogicalKeyboardKey.arrowLeft,
    alt: true,
  ),
  AppCommand.toggleLeftEdit: const KeyBinding(
    LogicalKeyboardKey.keyE,
    primary: true,
    alt: true,
  ),
  AppCommand.ignoreWhitespace: const KeyBinding(
    LogicalKeyboardKey.keyW,
    primary: true,
    alt: true,
  ),
  AppCommand.contextOnly: const KeyBinding(
    LogicalKeyboardKey.keyD,
    primary: true,
    alt: true,
  ),
  AppCommand.showWhitespace: const KeyBinding(
    LogicalKeyboardKey.digit8,
    primary: true,
    shift: true,
  ),
  AppCommand.stage: const KeyBinding(
    LogicalKeyboardKey.keyS,
    primary: true,
    alt: true,
  ),
  AppCommand.settings: const KeyBinding(
    LogicalKeyboardKey.comma,
    primary: true,
  ),
  AppCommand.gitSettings: const KeyBinding(
    LogicalKeyboardKey.keyG,
    primary: true,
    alt: true,
  ),
};

class ShortcutPreferences {
  final overrides = <AppCommand, KeyBinding?>{};
  KeyBinding? operator [](AppCommand command) => overrides.containsKey(command)
      ? overrides[command]
      : defaultBindings[command];
  String? validate(AppCommand command, KeyBinding? binding) {
    if (binding == null) return null;
    if (binding.invalidReason != null) return binding.invalidReason;
    for (final other in AppCommand.values) {
      if (other != command && this[other]?.signature == binding.signature) {
        return '已用于“${other.label}”，请先修改或清除该快捷键';
      }
    }
    return null;
  }

  void assign(AppCommand command, KeyBinding? binding) {
    final error = validate(command, binding);
    if (error != null) throw ArgumentError(error);
    overrides[command] = binding;
  }

  Map<String, Object?> toJson() => {
    for (final entry in overrides.entries)
      entry.key.name: entry.value?.toJson(),
  };
  void load(Object? json) {
    overrides.clear();
    if (json is! Map) return;
    for (final command in AppCommand.values) {
      if (!json.containsKey(command.name)) continue;
      if (json[command.name] == null) {
        overrides[command] = null;
        continue;
      }
      final binding = KeyBinding.fromJson(json[command.name]);
      if (binding != null && binding.invalidReason == null) {
        overrides[command] = binding;
      }
    }
    // 先读取全部覆盖，再移除冲突，允许持久化配置中的合法键位互换。
    for (var pass = 0; pass < AppCommand.values.length; pass++) {
      final invalid = <AppCommand>{};
      for (final command in AppCommand.values) {
        final binding = this[command];
        if (binding == null) continue;
        for (final other in AppCommand.values) {
          if (command != other && this[other]?.signature == binding.signature) {
            if (overrides.containsKey(command)) invalid.add(command);
            if (overrides.containsKey(other)) invalid.add(other);
          }
        }
      }
      if (invalid.isEmpty) break;
      for (final command in invalid) {
        overrides.remove(command);
      }
    }
  }
}
