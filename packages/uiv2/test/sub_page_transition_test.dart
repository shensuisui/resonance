/// 二级页转场「按屏宽分档」的回归测试
///
/// 现场：路由迁移后所有宽度都是横向滑入，平板/桌面下整块内容被推着走，
/// 而侧栏与播放条不动 —— 看起来像页面在壳子里滑动，很突兀。
/// 约定：窄屏（手机）保持横向滑入；≥768（含平板与桌面）水平位移必须为 0。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/app_router.dart';
import 'package:uiv2/src/design/tokens.dart';

void main() {
  test('窄屏：从右侧滑入（保留层级隐喻）', () {
    for (final width in <double>[360, 414, 444, 600, 767]) {
      final from = subPageSlideFrom(width);
      expect(from.dx, greaterThan(0), reason: '$width 宽应横向滑入');
      expect(from.dy, 0, reason: '$width 宽不应有纵向位移');
    }
  });

  test('大屏（含平板）与桌面：水平位移必须为 0，只轻微上浮', () {
    // 768 是平板起点；1024 桌面；1440 加宽 —— 一个都不能横向滑
    for (final width in <double>[768, 800, 900, 1023, 1024, 1280, 1440, 1920]) {
      final from = subPageSlideFrom(width);
      expect(from.dx, 0, reason: '$width 宽绝不能让内容横向位移');
      expect(from.dy, greaterThan(0), reason: '$width 宽应有轻微上浮');
      expect(from.dy, lessThan(0.1), reason: '$width 宽的上浮要「轻微」，不能变成纵向推页');
    }
  });

  test('分档边界正好落在 UiV2Breakpoints.wide（避免散落的魔数）', () {
    expect(subPageSlideFrom(UiV2Breakpoints.wide).dx, 0);
    expect(subPageSlideFrom(UiV2Breakpoints.wide - 1).dx, greaterThan(0));
  });
}
