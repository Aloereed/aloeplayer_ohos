import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aloeplayer/membership_details.dart';
import 'package:aloeplayer/services/membership_service.dart';
import 'package:aloeplayer/services/ohos_iap_service.dart';
import 'ohos_iap_service_test.dart' show Store;

void main() {
  testWidgets('checkout stays on screen when details expand on narrow, large-text and short displays', (tester) async {
    SharedPreferences.setMockInitialValues({});
    InAppPurchase.instance;
    final store = Store();
    InAppPurchasePlatform.instance = store;
    final iap = OhosIapService.instance;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final scenario in [(const Size(320, 640), 1.0), (const Size(320, 640), 1.6), (const Size(640, 360), 1.0)]) {
      tester.view.physicalSize = scenario.$1;
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scenario.$2)), child: child!),
        home: Scaffold(body: MembershipDetailsDialog(membershipService: MembershipService())),
      ));
      await tester.pumpAndSettle();
      final product = ProductDetails(id: 'premium_monthly', title: '月会员', description: '详细商品介绍', price: '¥12.00', rawPrice: 12, currencyCode: 'CNY');
      iap.products..clear()..add(product);
      iap.serverReady = true;
      iap.selectProduct(product.id);
      await tester.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, '开通月会员');
      final before = tester.getRect(button);
      expect(before.top, greaterThanOrEqualTo(0));
      expect(before.bottom, lessThanOrEqualTo(scenario.$1.height));
      await tester.ensureVisible(find.text('权益与订阅说明'));
      await tester.tap(find.text('权益与订阅说明'));
      await tester.pumpAndSettle();
      final after = tester.getRect(button);
      expect(after.bottom, lessThanOrEqualTo(scenario.$1.height));
      expect(button.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
    iap.dispose();
    await store.updates.close();
  });
}
