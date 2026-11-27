/// 大屏淡入路由与断点分派
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/route/card_page.dart';
import 'package:uiv2/src/route/fade_page.dart';
import 'package:uiv2/src/route/fade_page_route.dart';
import 'package:uiv2/src/route/page_for.dart';

void main() {
  test('FadePageRoute：200ms 进/出，原地淡入', () {
    final route = FadePageRoute<void>(builder: (_) => const SizedBox());
    expect(route.transitionDuration, const Duration(milliseconds: 200));
    expect(route.reverseTransitionDuration, const Duration(milliseconds: 200));
    route.dispose();
  });

  testWidgets('按断点分派：窄屏 CardPage，宽屏 FadePage', (tester) async {
    Future<Page<void>> pageAt(double width) async {
      late Page<void> page;
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          page = pageFor<void>(
            context: context,
            child: const SizedBox(),
            key: const ValueKey('x'),
          );
          return const SizedBox();
        }),
      ));
      return page;
    }

    expect(await pageAt(430), isA<CardPage<void>>());
    expect(await pageAt(900), isA<FadePage<void>>());
  });
}
