import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/widgets/subscription_terms.dart';

void main() {
  testWidgets('each checkout requires explicit consent and shows charge details', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () async { result = await confirmSubscription(context, '开通时 ¥12，每月自动续费 ¥12'); }, child: const Text('购买'))))));
    await tester.tap(find.text('购买'));
    await tester.pumpAndSettle();
    expect(find.text('开通时 ¥12，每月自动续费 ¥12'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '同意并前往支付')).onPressed, isNull);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意并前往支付'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    await tester.tap(find.text('购买'));
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isFalse);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '同意并前往支付')).onPressed, isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
