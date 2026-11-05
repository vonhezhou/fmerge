import '../core/access.dart';
import '../core/files.dart';
import '../core/launch.dart';
import '../session.dart';

/// 打开、重新加载与编码切换共用读取和权限流程，界面只负责选择与确认。
class SessionFiles {
  static Future<CompareSession?> open(
    LaunchOptions options, {
    required Future<TextFile?> Function(String, TextEncoding?) read,
    required bool native,
    CompareSession? previous,
    int? encodingSide,
    TextEncoding? encoding,
  }) async {
    if (native) {
      for (final path in [options.left!, options.right!, ?options.base]) {
        await DirectoryAccess.read(path);
      }
      if (options.output != null) await DirectoryAccess.write(options.output!);
    }
    final left = await read(
      options.left!,
      encodingSide == 0 ? encoding : previous?.left.encoding,
    );
    if (left == null) return null;
    final right = await read(
      options.right!,
      encodingSide == 1 ? encoding : previous?.right.encoding,
    );
    if (right == null) return null;
    final base = options.base == null
        ? null
        : await read(
            options.base!,
            encodingSide == 3 ? encoding : previous?.base?.encoding,
          );
    if (options.base != null && base == null) return null;
    final next = await CompareSession.open(
      options,
      inputs: [left, right, ?base],
      outputEncoding: previous?.output?.encoding,
    );
    if (previous != null) {
      next.leftEditor.displayTabSize = previous.leftEditor.displayTabSize;
      next.rightEditor.displayTabSize = previous.rightEditor.displayTabSize;
      next.resultEditor?.displayTabSize =
          previous.resultEditor?.displayTabSize ?? 4;
      next.leftLanguage = previous.leftLanguage;
      next.rightLanguage = previous.rightLanguage;
      next.baseLanguage = previous.baseLanguage;
      next.resultLanguage = previous.resultLanguage;
    }
    return next;
  }
}
