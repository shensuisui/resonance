/// 路由页必须自带不透明底色：过渡中两页同绘，否则会透出上一页
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/design/tokens.dart';
import 'package:uiv2/src/route/card_page.dart';
import 'package:uiv2/src/route/route_surface.dart';

void main() {
  testWidgets('CardPageRoute 页面铺主题底色（alpha=1）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () {
            Navigator.of(context).push(CardPageRoute<void>(
              builder: (_) => const SizedBox.expand(),
            ));
          },
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byType(RouteSurface), findsOneWidget);
    final ctx = tester.element(find.byType(RouteSurface));
    final expected = UiV2Theme.of(ctx).bg;
    final colored = tester.widget<ColoredBox>(
      find.descendant(of: find.byType(RouteSurface), matching: find.byType(ColoredBox)).first,
    );
    expect(colored.color, expected);
    expect(colored.color.a, 1.0);
  });
}
