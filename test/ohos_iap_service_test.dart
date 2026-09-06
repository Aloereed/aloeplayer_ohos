import 'package:in_app_purchase_ohos/in_app_purchase_ohos.dart';
import 'package:in_app_purchase_ohos/iap_kit_wrappers.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:aloeplayer/services/ohos_iap_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

class Store extends InAppPurchasePlatform {
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  final completed = <String>[];
  int launches = 0;
  @override Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;
  @override Future<bool> isAvailable() async => true;
  @override Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    expect(ids, {'premium_monthly'});
    return ProductDetailsResponse(productDetails: [ProductDetails(id: 'premium_monthly',
      title: '月会员', description: '月会员', price: '¥6.00', rawPrice: 6, currencyCode: 'CNY')], notFoundIDs: []);
  }
  @override Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    expect(purchaseParam.applicationUserName, 'bound-account'); launches++; return true;
  }
  @override Future<void> completePurchase(PurchaseDetails purchase) async { completed.add(purchase.purchaseID!); }
  @override Future<void> restorePurchases({String? applicationUserName}) async {}
}

PurchaseDetails receipt(String id, {PurchaseStatus status = PurchaseStatus.purchased}) => PurchaseDetails(
  purchaseID: id, productID: 'premium_monthly', transactionDate: '1000', status: status,
  verificationData: PurchaseVerificationData(localVerificationData: 'receipt-$id',
    serverVerificationData: 'receipt-$id', source: 'huawei'))..pendingCompletePurchase = true;

void main() {
  group('receipt serialization', () {
  test('each restored transaction keeps its own receipt', () {
    for (final id in ['first', 'second']) {
      final transaction = IKPaymentTransactionWrapper.fromJson({
        'payment': {'productId': 'premium_monthly', 'productType': 2},
        'transactionState': 3, 'transactionIdentifier': id, 'receiptData': 'signed-$id',
      });
      final purchase = AppGalleryPurchaseDetails.fromIKTransaction(transaction, 'wrong-global-receipt');
      expect(purchase.verificationData.serverVerificationData, 'signed-$id');
    }
  });

  });
  TestWidgetsFlutterBinding.ensureInitialized();
  group('checkout lifecycle', () {
  late Store store;
  late OhosIapService service;
  setUp(() { debugDefaultTargetPlatformOverride = TargetPlatform.windows; InAppPurchase.instance; store = Store(); InAppPurchasePlatform.instance = store; });
  tearDown(() async { debugDefaultTargetPlatformOverride = null; service.dispose(); await store.updates.close(); });
  test('only verified delivery completes purchase and launch alone never grants', () async {
    final verification = Completer<void>();
    service = OhosIapService(configuration: () async => {'product_id': 'premium_monthly', 'account_binding': 'bound-account'},
      verify: (_) => verification.future);
    await service.load(); await service.purchase(); await service.purchase();
    expect(store.launches, 1); expect(store.completed, isEmpty);
    store.updates.add([receipt('one')]); await Future<void>.delayed(Duration.zero);
    expect(store.completed, isEmpty); expect(service.pendingVerification, isTrue);
    verification.complete(); await Future<void>.delayed(Duration.zero);
    expect(store.completed, ['one']); expect(service.pendingVerification, isFalse);
  });
  test('verification failure stays recoverable and never acknowledges', () async {
    var fail = true;
    service = OhosIapService(configuration: () async => {'product_id': 'premium_monthly', 'account_binding': 'bound-account'},
      verify: (_) async { if (fail) throw StateError('offline'); });
    await service.load(); store.updates.add([receipt('retry')]); await Future<void>.delayed(Duration.zero);
    expect(store.completed, isEmpty); expect(service.pendingVerification, isTrue);
    await service.purchase(); expect(store.launches, 0);
    fail = false; await service.restore();
    expect(store.completed, ['retry']); expect(service.pendingVerification, isFalse);
  });
  test('server unavailable prevents checkout; cancellation is not delivery', () async {
    service = OhosIapService(configuration: () async => throw StateError('not configured'), verify: (_) async {});
    await service.load(); await service.purchase(); expect(store.launches, 0);
    store.updates.add([receipt('canceled', status: PurchaseStatus.canceled)]);
    await Future<void>.delayed(Duration.zero);
    expect(store.completed, isEmpty); expect(service.busy, isFalse);
  });
  });
}
