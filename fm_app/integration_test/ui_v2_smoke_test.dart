/// uiv2 冒烟测试 —— 验证「回响 Resonance」界面在真机/桌面端能实际渲染。
///
/// 运行方式（需要真机或桌面设备）：
///   flutter drive --driver=test_driver/integration_test.dart \
///                 --target=integration_test/ui_v2_smoke_test.dart \
///                 -d windows --dart-define=FM_DRIVER=true
///
/// 测试用文字定位（不依赖 uiv2 的内部类型），因此壳工程无需在 dev 依赖里暴露 UI 包。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('回响 Resonance（uiv2）', () {
    testWidgets('启动后渲染外壳与首页三块内容', (tester) async {
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 品牌标记（侧栏/窄轨都含「回响」二字）
      expect(find.text('回响'), findsWidgets, reason: '应渲染品牌名');

      // 首页页头
      expect(find.text('下午好，今天想听点什么？'), findsOneWidget);

      // 首页三个区块
      expect(find.text('最近播放'), findsWidgets);
      expect(find.text('推荐歌曲'), findsOneWidget);
      expect(find.text('我的歌单'), findsWidgets);
    });

    testWidgets('底部/侧栏可切换到搜索与音乐库', (tester) async {
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 搜索：点击「搜索」导航项（宽屏侧栏与窄屏底栏都是这个文案）
      await tester.tap(find.text('搜索').first);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('搜索歌曲'), findsWidgets);
      expect(find.text('推荐搜索'), findsOneWidget);

      // 音乐库
      await tester.tap(find.text('音乐库').first);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('按音乐源分栏浏览歌单，本地文件与在线曲目都在这里。'), findsOneWidget);
      expect(find.text('全部'), findsWidgets);
    });

    testWidgets('播放条常驻且显示初始文案', (tester) async {
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('未在播放'), findsWidgets);
      expect(find.text('选择一首歌曲开始'), findsWidgets);
    });

    testWidgets('滚动首页不出现溢出异常', (tester) async {
      await tester.pumpAndSettle(const Duration(seconds: 2));
      final scrollable = find.byType(Scrollable).first;
      await tester.drag(scrollable, const Offset(0, -400));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      // 没有抛异常即视为通过（Flutter 会在溢出时抛出并记录到 tester.takeException）
      expect(tester.takeException(), isNull);
    });
  });
}
