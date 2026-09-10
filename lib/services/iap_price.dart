import 'dart:convert';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_ohos/in_app_purchase_ohos.dart';

/// Presentation only; checkout and entitlement still use Huawei's signed result.
class IapPrice {
  final String displayPrice;
  final String? originalPrice;
  final String? explanation;
  const IapPrice(this.displayPrice, {this.originalPrice, this.explanation});

  static String? _period(Object? unit, Object? count) {
    const units = {0: '天', 1: '周', 2: '个月', 3: '年'};
    if (count is! int || count <= 0 || !units.containsKey(unit)) return null;
    return '$count${units[unit]}';
  }

  static IapPrice forProduct(ProductDetails product) {
    if (product is! AppGalleryProductDetails) return IapPrice(product.price);
    final native = product.skProduct;
    final original = native.originalMicroPrice > native.microPrice && native.originalLocalPrice.isNotEmpty
        ? native.originalLocalPrice : null;
    final regular = IapPrice(product.price, originalPrice: original);
    try {
      var data = jsonDecode(native.jsonRepresentation ?? '{}');
      // Some SDK responses expose optional fields only in their original JSON.
      for (var depth = 0; depth < 2 && data is Map && data['subscriptionInfo'] == null; depth++) {
        final nested = data['jsonRepresentation'];
        if (nested is! String || nested.isEmpty) break;
        data = jsonDecode(nested);
      }
      final info = data is Map ? data['subscriptionInfo'] : null;
      if (info is! Map) return _annualOfferFallback(product, regular);
      if (info['hasEligibilityForIntroOffer'] == false) return regular;
      final eligible = info['hasEligibilityForIntroOffer'] == true;
      final offer = info['introductoryOffer'];
      if (offer is! Map) return _annualOfferFallback(product, regular);
      final duration = _period(offer['periodUnit'], offer['periodCount']);
      final renewal = _period(info['periodUnit'], info['periodCount']);
      final mode = offer['paymentMode'];
      final amount = offer['microPrice'];
      final formatted = offer['localPrice'];
      if (duration == null || renewal == null || amount is! num || amount < 0 ||
          !const [1, 2, 3].contains(mode)) return regular;
      final afterwards = '之后每$renewal续费${product.price}';
      if (mode == 1 && amount == 0 && eligible) {
        return IapPrice('免费试用', explanation: '免费试用$duration，$afterwards');
      }
      if (mode == 1 || formatted is! String || formatted.isEmpty) return regular;
      final firstYear = info['periodUnit'] == 3 && info['periodCount'] == 1 &&
          offer['periodUnit'] == 3 && offer['periodCount'] == 1;
      final details = firstYear ? '首年优惠$formatted，第二年起每年自动续费${product.price}' : mode == 3
          ? '前$duration合计$formatted，$afterwards'
          : '优惠期$duration，每期$formatted，$afterwards';
      return IapPrice(eligible ? formatted : '$formatted / ${product.price}',
          explanation: eligible ? details : '符合首购优惠条件：$details；不符合条件按${product.price}开通。优惠资格由华为账号确认。');
    } catch (_) {
      return _annualOfferFallback(product, regular);
    }
  }

  // Reviewed CNY annual offer (2026-09-10). Some store responses omit
  // subscriptionInfo/eligibility. Disclose both outcomes, never promise eligibility.
  static IapPrice _annualOfferFallback(ProductDetails product, IapPrice regular) {
    if (product.id != 'premium_1year' || product.currencyCode != 'CNY' || product.rawPrice != 72) return regular;
    return IapPrice('¥36 / ${product.price}', explanation:
        '符合首年优惠条件：首年¥36，第二年起每年自动续费${product.price}；不符合条件按${product.price}开通并每年续费。优惠资格由华为账号确认。');
  }
}
