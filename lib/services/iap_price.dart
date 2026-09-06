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
      final data = jsonDecode(native.jsonRepresentation ?? '{}');
      final info = data is Map ? data['subscriptionInfo'] : null;
      if (info is! Map || info['hasEligibilityForIntroOffer'] != true) return regular;
      final offer = info['introductoryOffer'];
      if (offer is! Map) return regular;
      final duration = _period(offer['periodUnit'], offer['periodCount']);
      final renewal = _period(info['periodUnit'], info['periodCount']);
      final mode = offer['paymentMode'];
      final amount = offer['microPrice'];
      final formatted = offer['localPrice'];
      if (duration == null || renewal == null || amount is! num || amount < 0 ||
          !const [1, 2, 3].contains(mode)) return regular;
      final afterwards = '之后每$renewal续费${product.price}';
      if (mode == 1 && amount == 0) {
        return IapPrice('免费试用', explanation: '免费试用$duration，$afterwards');
      }
      if (mode == 1 || formatted is! String || formatted.isEmpty) return regular;
      return IapPrice(formatted, explanation: mode == 3
          ? '前$duration合计$formatted，$afterwards'
          : '优惠期$duration，每期$formatted，$afterwards');
    } catch (_) {
      return regular;
    }
  }
}
