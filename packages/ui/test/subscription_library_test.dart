/// SubscriptionLibrary 纯逻辑单元测试
///
/// 对应 lib/src/providers/subscription_library.dart。
/// 仅测试不依赖文件系统/网络/Provider 的静态纯函数：
/// - parseMfGroupEntries：MusicFree 插件订阅组两种合法格式解析
///   （裸 List 与官方 {"plugins":[...]}），非法内容抛 FormatException
///
/// 模拟数据来源：内联 JSON 字符串（与真实 myPlugins.json 结构一致）。
/// 完整订阅流程（拉取→落盘→注册）依赖 path_provider/网络，属集成范畴，
/// 此处不覆盖。

import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

void main() {
  group('SubscriptionLibrary.parseMfGroupEntries', () {
    test('裸 List 格式解析出条目', () {
      const raw = '[{"name":"A","url":"https://a.com/x.js"},'
          '{"name":"B","url":"https://b.com/y.js"}]';
      final entries = SubscriptionLibrary.parseMfGroupEntries(raw);
      expect(entries.length, 2);
      expect((entries[0] as Map)['name'], 'A');
      expect((entries[1] as Map)['url'], 'https://b.com/y.js');
    });

    test('官方 {"plugins":[...]} 格式解析出条目', () {
      // 与 fastly.jsdelivr.net/.../myPlugins.json 实际结构一致
      const raw = '{"plugins":[{"name":"小秋音乐",'
          '"url":"https://x.com/xiaoqiu.js","version":"0.3.0"}]}';
      final entries = SubscriptionLibrary.parseMfGroupEntries(raw);
      expect(entries.length, 1);
      expect((entries[0] as Map)['name'], '小秋音乐');
    });

    test('plugins 为空数组返回空列表', () {
      final entries = SubscriptionLibrary.parseMfGroupEntries('{"plugins":[]}');
      expect(entries, isEmpty);
    });

    test('非法 JSON 抛 FormatException', () {
      expect(
        () => SubscriptionLibrary.parseMfGroupEntries('not json'),
        throwsFormatException,
      );
    });

    test('非 List/无 plugins 键的 Map 抛 FormatException', () {
      // 边界：{ "foo": 1 } 既不是 List 也没有 plugins 键
      expect(
        () => SubscriptionLibrary.parseMfGroupEntries('{"foo":1}'),
        throwsFormatException,
      );
    });

    test('plugins 键非 List 抛 FormatException', () {
      // 边界：{"plugins": "oops"} 类型不对
      expect(
        () => SubscriptionLibrary.parseMfGroupEntries('{"plugins":"oops"}'),
        throwsFormatException,
      );
    });
  });
}
