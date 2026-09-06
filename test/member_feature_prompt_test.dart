import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aloeplayer/services/member_access.dart';
import 'package:aloeplayer/widgets/member_feature_prompt.dart';

void main() {
  testWidgets('no automatic prompt; dismissing preserves eligibility; explicit trial unlocks action', (tester) async {
    SharedPreferences.setMockInitialValues({});
    bool? allowed;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () async { allowed = await requestMemberFeature(context, MemberFeature.batchDownload); },
      child: const Text('批量下载'))))));
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text('批量下载'));
    await tester.pumpAndSettle();
    expect(find.text('免费体验 7 天'), findsOneWidget);
    await tester.tap(find.text('暂时不用'));
    await tester.pumpAndSettle();
    expect(allowed, isFalse);
    expect(MemberAccess.instance.canStartTrial, isTrue);
    await tester.tap(find.text('批量下载'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('免费体验 7 天'));
    await tester.pumpAndSettle();
    expect(allowed, isTrue);
    expect(MemberAccess.instance.trialActive, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
