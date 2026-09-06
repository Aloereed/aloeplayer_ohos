import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aloeplayer/services/membership_service.dart';

class UnavailableStore extends InAppPurchasePlatform {
  @override
  Future<bool> isAvailable() async => false;
}

void main() {
  testWidgets('membership changes rebuild observers without reopening the page', (tester) async {
    SharedPreferences.setMockInitialValues({'membership_status': MembershipStatus.premium.index,
      'membership_expiry_date': DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
      'subscription_name': '年会员'});
    InAppPurchase.instance;
    InAppPurchasePlatform.instance = UnavailableStore();
    final membership = MembershipService();
    await membership.initialize();
    await tester.pumpWidget(MaterialApp(home: ListenableBuilder(listenable: membership,
      builder: (_, __) => Text(membership.isPremium ? membership.subscriptionName! : '未开通'))));
    expect(find.text('年会员'), findsOneWidget);
    await membership.clearMembership();
    await tester.pump();
    expect(find.text('未开通'), findsOneWidget);
  });
}
