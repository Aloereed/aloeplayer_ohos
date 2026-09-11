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
  test('no introductory offer uses live regular price regardless of eligibility', () {
    for (final eligibility in [null, false, true]) {
      for (final explicitNull in [false, true]) {
        final item = product(raw: jsonEncode({'subscriptionInfo': {
          'periodUnit': 2, 'periodCount': 1,
          if (eligibility != null) 'hasEligibilityForIntroOffer': eligibility,
          if (explicitNull) 'introductoryOffer': null,
        }}));
        final quote = IapPrice.forProduct(item);
        expect(quote.canPurchase, isTrue);
        expect(quote.displayPrice, item.price);
        expect(quote.explanation, isNull);
      }
    }
  });
  test('an empty or malformed offer is not treated as no offer', () {
    for (final offer in [<String, Object>{}, 'invalid']) {
      final quote = IapPrice.forProduct(product(raw: jsonEncode({'subscriptionInfo': {
        'periodUnit': 2, 'periodCount': 1,
        'hasEligibilityForIntroOffer': true, 'introductoryOffer': offer,
      }})));
      expect(quote.canPurchase, isFalse);
    }
  });
  test('eligible introductory price includes duration and renewal price', () {
    final price = IapPrice.forProduct(product());
    expect(price.displayPrice, '优惠价¥1.00');
    expect(price.explanation, contains('3个月'));
    expect(price.explanation, contains('之后每1个月续费¥6.00'));
  });
  test('eligibility flag never hides a returned annual offer or promises eligibility', () {
    for (final eligible in [false, null, true]) {
      final price = IapPrice.forProduct(annualProduct(eligible: eligible));
      expect(price.canPurchase, isTrue);
      expect(price.displayPrice, '优惠价¥36.00');
      expect(price.explanation, contains('符合优惠条件：首年优惠¥36.00'));
      expect(price.explanation, contains('第二年起每年自动续费¥72.00'));
      expect(price.explanation, contains('不符合条件按常规价¥72.00开通'));
    }
  });
  test('reviewed annual offer states first year and subsequent annual charge', () {
    final price = IapPrice.forProduct(annualProduct());
    expect(price.displayPrice, '优惠价¥36.00');
    expect(price.explanation, contains('首年优惠¥36.00，第二年起每年自动续费¥72.00'));
  });
  test('missing annual fields never manufacture a first year offer', () {
    for (final raw in ['{}', '{invalid']) {
      final price = IapPrice.forProduct(annualProduct(raw: raw));
      expect(price.canPurchase, isFalse);
      expect(price.displayPrice, '价格待确认');
      expect(price.explanation, isNot(contains('36')));
    }
    expect(IapPrice.forProduct(annualProduct(eligible: false)).displayPrice, '优惠价¥36.00');
  });
  test('live store price overrides the reviewed fallback', () {
    expect(IapPrice.forProduct(annualProduct(offerPrice: '¥40.00', offerAmount: 40000000)).displayPrice, '优惠价¥40.00');
    expect(IapPrice.forProduct(annualProduct(raw: '{}', regularAmount: 80000000)).canPurchase, isFalse);
  });
  test('SDK original JSON retains live offer information', () {
    final native = annualProduct(offerPrice: '¥40.00', offerAmount: 40000000).skProduct.jsonRepresentation;
    final price = IapPrice.forProduct(annualProduct(raw: jsonEncode({'jsonRepresentation': native})));
    expect(price.displayPrice, '优惠价¥40.00');
    expect(price.explanation, contains('首年优惠¥40.00'));
  });
  test('partial outer subscription info does not hide original JSON offer', () {
    final original = annualProduct(eligible: false).skProduct.jsonRepresentation;
    final item = annualProduct(raw: jsonEncode({
      'subscriptionInfo': {'periodUnit': 3, 'periodCount': 1},
      'jsonRepresentation': original,
    }));
    final price = IapPrice.forProduct(item);
    expect(price.displayPrice, '优惠价¥36.00');
    expect(price.explanation, contains('第二年起每年自动续费¥72.00'));
  });
  test('free trial explains later charge', () {
    final price = IapPrice.forProduct(product(mode: 1, amount: 0));
    expect(price.displayPrice, '免费试用（符合条件）'); expect(price.explanation, contains('续费¥6.00'));
  });
  test('up-front offer is labelled as total price', () {
    expect(IapPrice.forProduct(product(mode: 3)).explanation, contains('合计¥1.00'));
  });
  test('malformed or unsupported offer blocks checkout', () {
    for (final item in [product(raw: '{invalid'), product(mode: 99), product(amount: -1)]) {
      expect(IapPrice.forProduct(item).canPurchase, isFalse);
    }
  });
}

AppGalleryProductDetails annualProduct({bool? eligible = true, String? raw,
  String offerPrice = '¥36.00', int offerAmount = 36000000, int regularAmount = 72000000}) =>
    AppGalleryProductDetails.fromIKProduct(IKProductWrapper.fromJson({
      'id': 'premium_1year', 'type': 2, 'name': '年会员', 'description': '',
      'localPrice': '¥${(regularAmount / 1000000).toStringAsFixed(2)}', 'microPrice': regularAmount,
      'originalLocalPrice': '¥72.00', 'originalMicroPrice': 72000000, 'currency': 'CNY',
      'jsonRepresentation': raw ?? jsonEncode({'subscriptionInfo': {
        'periodUnit': 3, 'periodCount': 1, 'hasEligibilityForIntroOffer': eligible,
        'introductoryOffer': {'paymentMode': 3, 'periodUnit': 3, 'periodCount': 1,
          'localPrice': offerPrice, 'microPrice': offerAmount}}}),
    }));
