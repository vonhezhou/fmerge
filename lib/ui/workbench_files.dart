part of 'workbench.dart';

/// 文件入口与恢复流程集中在此，所有会话替换仍经过未保存保护。
extension _WorkbenchFiles on _WorkbenchState {
  Future<void> _openMerge() async {
    if (_opening || _saving || _choosingFiles) return;
    _update(() => _choosingFiles = true);
    LaunchOptions? options;
    try {
      final paths = <String>[];
      for (final label in ['选择共同祖先', '选择左侧输入', '选择右侧输入']) {
        final file = await openFile(confirmButtonText: label);
        if (file == null || !mounted) return;
        paths.add(file.path);
        if (widget.nativeWindow) {
          await DirectoryAccess.rememberFiles([file.path]);
        }
      }
      final output = await getSaveLocation(
        suggestedName: 'merged-${p.basename(paths[1])}',
        confirmButtonText: '选择合并结果位置',
      );
      if (output == null || !mounted) return;
      options = LaunchOptions(
        base: paths[0],
        left: paths[1],
        right: paths[2],
        output: output.path,
      );
    } catch (e) {
      _message('选择合并文件失败：$e');
    } finally {
      if (mounted) _update(() => _choosingFiles = false);
    }
    if (options != null && mounted) await _open(options: options);
  }

  Future<void> _gitReview() async {
    final s = session;
    if (s == null || s.isMerge || s.readOnly || _staging || _saving) return;
    final side = _active == 0 ? 0 : 1;
    final file = side == 0 ? s.left : s.right;
    if (file.path == null || (side == 0 ? s.leftDirty : s.rightDirty)) {
      _message('请先保存当前文件，再查看 Git 暂存预览');
      return;
    }
    _update(() => _staging = true);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            GitReviewDialog(path: file.path!, encoding: file.encoding),
      );
    } finally {
      if (mounted) _update(() => _staging = false);
    }
  }

  Widget _dropArea() => LayoutBuilder(
    builder: (context, constraints) => DropTarget(
      enable:
          !_opening &&
          !_saving &&
          !_choosingFiles &&
          ModalRoute.of(context)?.isCurrent != false,
      onDragDone: (details) => _handleDrop(
        details,
        details.localPosition.dx < constraints.maxWidth / 2 ? 0 : 1,
      ),
      child: session == null ? _welcome() : _workspace(),
    ),
  );

  Future<void> _handleDrop(DropDoneDetails details, int side) async {
    final scopes = <Uint8List>[];
    try {
      if (widget.nativeWindow && Platform.isMacOS) {
        for (final item in details.files) {
          final bookmark = item.extraAppleBookmark;
          if (bookmark != null &&
              bookmark.isNotEmpty &&
              await DesktopDrop.instance.startAccessingSecurityScopedResource(
                bookmark: bookmark,
              )) {
            scopes.add(bookmark);
          }
        }
      }
      await _dropFiles(details.files.map((f) => f.path).toList(), side);
    } catch (e) {
      _message('拖放授权失败：$e');
    } finally {
      for (final bookmark in scopes) {
        await DesktopDrop.instance.stopAccessingSecurityScopedResource(
          bookmark: bookmark,
        );
      }
    }
  }

  Future<void> _dropFiles(List<String> paths, int side) async {
    if (_opening || _saving || _choosingFiles) return;
    if (paths.isEmpty || paths.length > 2) {
      _message('请拖入一个或两个文本文件');
      return;
    }
    try {
      if (paths.any(
        (path) => FileSystemEntity.typeSync(path) != FileSystemEntityType.file,
      )) {
        _message('拖放仅支持一个或两个文本文件');
        return;
      }
      if (widget.nativeWindow) await DirectoryAccess.rememberFiles(paths);
      if (paths.length == 2) {
        await _open(
          options: LaunchOptions(left: paths[0], right: paths[1]),
        );
        return;
      }
      final s = session;
      if (s == null) {
        final file = await _readInput(paths.single, null);
        if (file == null || !mounted || session != null) return;
        _update(
          () => _attach(
            CompareSession(
              side == 0 ? file : TextFile.empty(),
              side == 1 ? file : TextFile.empty(),
            ),
          ),
        );
        return;
      }
      if (s.isMerge || s.output != null) {
        _message('当前会话有合并或指定输出，请拖入两个文件开始新比较');
        return;
      }
      if (!mounted) return;
      if (side == 0 ? s.leftDirty : s.rightDirty) {
        final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('替换此侧文件？'),
            content: const Text('此侧未保存修改会被丢弃，另一侧保持不变。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('丢弃并替换'),
              ),
            ],
          ),
        );
        if (discard != true || !mounted) return;
      }
      final revision = s.revision;
      _update(() => _opening = true);
      try {
        final file = await _readInput(paths.single, null);
        if (file == null || !mounted || !identical(s, session)) return;
        if (s.revision != revision) {
          _message('读取期间有新的修改，已保留当前内容');
          return;
        }
        s.reloadInput(side, file);
      } finally {
        if (mounted) _update(() => _opening = false);
      }
    } catch (e) {
      _message('拖放文件失败：$e');
    }
  }

  void _scheduleRecovery() {
    if (!widget.nativeWindow || !settings.persist) return;
    final s = session;
    final state = (s, s?.revision, s?.dirty ?? false, settings.crashRecovery);
    if (_recoveryState == state) return;
    _recoveryState = state;
    _recoveryTimer?.cancel();
    if (!settings.crashRecovery || s?.dirty != true) {
      unawaited(_clearRecovery(includeAdopted: s?.dirty != true));
      return;
    }
    _recoveryTimer = Timer(const Duration(milliseconds: 900), () async {
      if (!mounted || !identical(session, s) || !settings.crashRecovery) return;
      try {
        await _recovery.save(s!.recoverySnapshot());
      } catch (e) {
        if (mounted) _message('保存恢复快照失败：$e');
      }
    });
  }

  Future<void> _clearRecovery({bool includeAdopted = true}) async {
    final adopted = includeAdopted ? _adoptedRecovery : null;
    if (includeAdopted) _adoptedRecovery = null;
    try {
      await _recovery.remove();
      if (adopted != null) await _recovery.remove(adopted);
    } catch (e) {
      if (mounted) _message('清理恢复记录失败：$e');
    }
  }

  Future<void> _recoveryNotice() async {
    try {
      final records = await _recovery.list();
      if (mounted && records.isNotEmpty) {
        _update(
          () => _notice = '发现 ${records.length} 份未保存会话，可从“文件 → 恢复未保存会话”恢复或删除。',
        );
      }
    } catch (e) {
      _message('读取恢复记录失败：$e');
    }
  }

  Future<void> _recoverSession() async {
    if (_opening || _saving || _choosingFiles) return;
    if (!settings.persist) {
      _message('当前未启用持久化存储');
      return;
    }
    _update(() => _choosingFiles = true);
    try {
      final records = (await _recovery.list())
          .where((r) => r.id != _recovery.id)
          .toList();
      if (!mounted) return;
      if (records.isEmpty) {
        _message('没有可恢复的历史会话');
        return;
      }
      final selected = await showDialog<RecoveryRecord>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('恢复未保存会话'),
            content: SizedBox(
              width: 640,
              height: 360,
              child: ListView.builder(
                itemCount: records.length,
                itemBuilder: (context, i) {
                  final record = records[i];
                  return ListTile(
                    title: Text(
                      '${(record.data['right'] as Map?)?['path'] ?? '未命名文本'}',
                    ),
                    subtitle: Text('${record.data['savedAt']}'),
                    onTap: () => Navigator.pop(context, record),
                    trailing: IconButton(
                      tooltip: '删除恢复记录',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await _recovery.remove(record.id);
                        if (context.mounted) {
                          update(() => records.remove(record));
                        }
                      },
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      );
      if (selected == null || !mounted || !await _leave() || !mounted) return;
      final current = session, revision = session?.revision;
      final next = await CompareSession.recover(selected.data);
      if (!mounted ||
          !identical(current, session) ||
          current?.revision != revision) {
        next.dispose();
        return;
      }
      _update(() => _attach(next));
      _adoptedRecovery = selected.id;
      // 先持久化接管的快照，再移除旧记录，避免恢复期间再次崩溃丢失。
      if (settings.crashRecovery) {
        await _recovery.save(next.recoverySnapshot());
        await _recovery.remove(selected.id);
        _adoptedRecovery = null;
      }
      _message('已恢复编辑内容；保存前仍会检查原文件是否发生外部修改');
    } catch (e) {
      _message('恢复失败，原记录保留：$e');
    } finally {
      if (mounted) _update(() => _choosingFiles = false);
    }
  }
}
