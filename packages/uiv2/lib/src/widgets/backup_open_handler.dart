/// 「用回响打开 .json」的接收器：包在应用最外层，监听壳工程推送的文件
///
/// 为什么放在这里：系统通过 Intent 把文件交给 App，壳工程把内容推进
/// [FilePickers.openedFiles]；本组件负责把它接到统一的导入流程（预览 -> 导入）。
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/file_pickers.dart';
import '../app_router.dart' show uiV2NavigatorKey;
import 'backup_flow.dart';

/// 打开文件接收器（无 UI）
class BackupOpenHandler extends ConsumerStatefulWidget {
  /// 被包裹的子树
  final Widget child;

  /// 构造
  const BackupOpenHandler({super.key, required this.child});

  @override
  ConsumerState<BackupOpenHandler> createState() => _BackupOpenHandlerState();
}

class _BackupOpenHandlerState extends ConsumerState<BackupOpenHandler> {
  StreamSubscription<OpenedFile>? _subscription;

  @override
  void initState() {
    super.initState();
    // 测试环境可能没有注入 picker：此时静默跳过，不影响页面渲染
    try {
      _subscription = ref
          .read(filePickersProvider)
          .openedFiles
          .listen((file) => _handle(file));
    } catch (_) {
      _subscription = null;
    }
  }

  Future<void> _handle(OpenedFile file) async {
    final context = uiV2NavigatorKey.currentContext;
    if (context == null) return;
    await importBackupFlow(context, ref, opened: file);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
