/// 播放页手势 flow：拖动进度与松手判定
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/components/now_playing_flow.dart';

void main() {
  testWidgets('拖拽跟手：上滑增加进度、下滑减少，松手可撤回', (tester) async {
    final flow = NowPlayingFlow();
    flow.attach(const TestVSync());
    addTearDown(flow.dispose);

    flow.beginDrag();
    flow.dragBy(-110, 550); // 上滑 110 / 行程 550 = 20%
    expect(flow.value, closeTo(0.2, 1e-6));
    flow.dragBy(55, 550); // 再下滑 55 → 10%
    expect(flow.value, closeTo(0.1, 1e-6));

    // 位移不足但速度大：快速上扫也算展开
    expect(flow.endDrag(-700), isTrue);
    flow.setValue(0);
    // 反向：大于半屏但慢速下滑 → 收起
    flow.beginDrag();
    flow.dragBy(-300, 550); // ~55%
    expect(flow.endDrag(200), isTrue);
    flow.setValue(0);
    flow.beginDrag();
    flow.dragBy(-100, 550); // ~18%
    expect(flow.endDrag(0), isFalse);
    flow.setValue(0);
    await tester.pump();
  });
}
