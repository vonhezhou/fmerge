class LaunchOptions {
  const LaunchOptions({
    this.left,
    this.right,
    this.base,
    this.output,
    this.readOnly = false,
    this.autoClose = false,
    this.help = false,
    this.version = false,
  });
  final String? left, right, base, output;
  final bool readOnly, autoClose, help, version;
  bool get merge => base != null;

  /// 生成可复制的 Git 配置；只展示，不修改用户的全局配置。
  static String gitConfiguration(String executable) {
    String quote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";
    final tool =
        '"${executable.replaceAll(r'\', r'\\').replaceAll(r'$', r'\$').replaceAll('`', r'\`').replaceAll('"', r'\"')}"';
    final diff = '$tool "\$LOCAL" "\$REMOTE"';
    final merge =
        '$tool --base "\$BASE" --local "\$LOCAL" --remote "\$REMOTE" --output "\$MERGED"';
    return '''git config --global diff.tool fmerge
git config --global difftool.fmerge.cmd ${quote(diff)}
git config --global merge.tool fmerge
git config --global mergetool.fmerge.cmd ${quote(merge)}
git config --global mergetool.fmerge.trustExitCode true''';
  }

  static LaunchOptions parse(List<String> args) {
    final values = <String, String>{};
    final positional = <String>[];
    var readOnly = false,
        autoClose = false,
        help = false,
        version = false,
        literal = false;
    const aliases = {
      'mine': 'local',
      'theirs': 'remote',
      'merged': 'output',
      'result': 'output',
    };
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (literal) {
        positional.add(arg);
        continue;
      }
      if (arg == '--') {
        literal = true;
        continue;
      }
      if (arg == '--help' || arg == '-h' || arg == '/?') {
        help = true;
        continue;
      }
      if (arg == '--version') {
        version = true;
        continue;
      }
      if (arg == '--read-only' || arg == '/readonly') {
        readOnly = true;
        continue;
      }
      if (arg == '--auto-close') {
        autoClose = true;
        continue;
      }
      if (arg == '--wait') continue;
      final slash = RegExp(r'^/(base|mine|theirs|merged):(.+)$')
          .firstMatch(arg);
      String key, value;
      if (slash != null) {
        key = slash[1]!;
        value = slash[2]!;
      } else if (arg.startsWith('--')) {
        final equal = arg.indexOf('=');
        key = arg.substring(2, equal < 0 ? null : equal);
        if (equal >= 0) {
          value = arg.substring(equal + 1);
        } else {
          if (i + 1 >= args.length || args[i + 1].startsWith('--')) {
            throw FormatException('缺少参数：$arg');
          }
          value = args[++i];
        }
      } else {
        positional.add(arg);
        continue;
      }
      key = aliases[key] ?? key;
      if (!{'base', 'local', 'remote', 'output'}.contains(key)) {
        throw FormatException('未知参数：$arg');
      }
      if (value.isEmpty || values.containsKey(key)) {
        throw FormatException('参数为空或重复：$key');
      }
      values[key] = value;
    }
    if (help || version) return LaunchOptions(help: help, version: version);
    if (positional.isNotEmpty &&
        (positional.length != 2 || values.keys.any((k) => k != 'output'))) {
      throw const FormatException(
        '比较需要两个文件；合并使用 --base --local --remote --output',
      );
    }
    if (values.containsKey('base') &&
        (!values.containsKey('local') || !values.containsKey('remote'))) {
      throw const FormatException('三方合并需要 base、local 和 remote 三个输入');
    }
    if (positional.isEmpty &&
        (values.containsKey('local') != values.containsKey('remote'))) {
      throw const FormatException('比较需要 local 与 remote 两个输入');
    }
    if (values.containsKey('output') &&
        positional.isEmpty &&
        !values.containsKey('local')) {
      throw const FormatException('输出参数需要搭配比较或合并输入');
    }
    return LaunchOptions(
      left: positional.isEmpty ? values['local'] : positional[0],
      right: positional.isEmpty ? values['remote'] : positional[1],
      base: values['base'],
      output: values['output'],
      readOnly: readOnly,
      autoClose: autoClose,
    );
  }

  static const usage = '''fmerge — 原生文本比较与三方合并

fmerge LEFT RIGHT
fmerge --base BASE --local LOCAL --remote REMOTE --output MERGED

--read-only    只读预览
--auto-close   保存成功后关闭窗口
--wait         等待窗口关闭（默认行为）
--help / --version

合并退出码：0 = 最终结果已保存且没有待处理冲突；1 = 取消或未完成；64 = 参数错误。
''';
}
