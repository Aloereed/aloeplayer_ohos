import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_ohos/in_app_purchase_ohos.dart';
import 'package:in_app_purchase_ohos/iap_kit_wrappers.dart';
import 'package:aloeplayer/services/iap_price.dart';

AppGalleryProductDetails product({bool? eligible = true, int mode = 2, String raw = '', int amount = 1000000}) {
  final info = {'periodUnit': 2, 'periodCount': 1, 'hasEligibilityForIntroOffer': eligible,
    'introductoryOffer': {'paymentMode': mode, 'periodUnit': 2, 'periodCount': 3,
      'localPrice': '¥1.00', 'microPrice': amount}};
  return AppGalleryProductDetails.fromIKProduct(IKProductWrapper.fromJson({
    'id': 'premium_monthly', 'type': 2, 'name': '月会员', 'description': '',
    'localPrice': '¥6.00', 'microPrice': 6000000, 'originalLocalPrice': '¥6.00',
    'originalMicroPrice': 6000000, 'currency': 'CNY',
    'jsonRepresentation': raw.isEmpty ? jsonEncode({'subscriptionInfo': info}) : raw,
  }));
}

void main() {
  test('eligible introductory price includes duration and renewal price', () {
    final price = IapPrice.forProduct(product());
    expect(price.displayPrice, '¥1.00');
    expect(price.explanation, contains('3个月'));
    expect(price.explanation, contains('之后每1个月续费¥6.00'));
  });
  test('ineligible and unknown eligibility never advertise introductory price', () {
    for (final eligible in [false, null]) {
      final price = IapPrice.forProduct(product(eligible: eligible));
      expect(price.displayPrice, '¥6.00'); expect(price.explanation, isNull);
    }
  });
  test('free trial explains later charge', () {
    final price = IapPrice.forProduct(product(mode: 1, amount: 0));
    expect(price.displayPrice, '免费试用'); expect(price.explanation, contains('续费¥6.00'));
  });
  test('up-front offer is labelled as total price', () {
    expect(IapPrice.forProduct(product(mode: 3)).explanation, contains('合计¥1.00'));
  });
  test('malformed or unsupported offer falls back to regular price', () {
    for (final item in [product(raw: '{invalid'), product(mode: 99), product(amount: -1)]) {
      expect(IapPrice.forProduct(item).displayPrice, '¥6.00');
    }
  });
}
