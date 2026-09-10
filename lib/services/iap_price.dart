import 'dart:convert';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_ohos/in_app_purchase_ohos.dart';

/// Presentation only; checkout and entitlement still use Huawei's signed result.
class IapPrice {
  final String displayPrice;
  final String? originalPrice;
  final String? explanation;
  final bool canPurchase;
  const IapPrice(this.displayPrice, {this.originalPrice, this.explanation, this.canPurchase = true});

  static String? _period(Object? unit, Object? count) {
    const units = {0: '天', 1: '周', 2: '个月', 3: '年'};
    if (count is! int || count <= 0 || !units.containsKey(unit)) return null;
    return '$count${units[unit]}';
  }

  static IapPrice forProduct(ProductDetails product) {
    if (product is! AppGalleryProductDetails) return IapPrice(product.price);
    const unavailable = IapPrice('价格待确认', canPurchase: false,
        explanation: '华为商品价格或优惠资格信息不完整，请点击“重新加载”后再购买。');
    final native = product.skProduct;
    if (product.price.trim().isEmpty || !product.rawPrice.isFinite || product.rawPrice <= 0) return unavailable;
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
      if (info is! Map) return unavailable;
      if (_period(info['periodUnit'], info['periodCount']) == null) return unavailable;
      if (info['hasEligibilityForIntroOffer'] == false) return regular;
      final eligible = info['hasEligibilityForIntroOffer'] == true;
      if (!eligible) return unavailable;
      final offer = info['introductoryOffer'];
      if (offer is! Map) return unavailable;
      final duration = _period(offer['periodUnit'], offer['periodCount']);
      final renewal = _period(info['periodUnit'], info['periodCount']);
      final mode = offer['paymentMode'];
      final amount = offer['microPrice'];
      final formatted = offer['localPrice'];
      if (duration == null || renewal == null || amount is! num || amount < 0 ||
          !const [1, 2, 3].contains(mode)) return unavailable;
      final afterwards = '之后每$renewal续费${product.price}';
      if (mode == 1 && amount == 0 && eligible) {
        return IapPrice('免费试用', explanation: '免费试用$duration，$afterwards');
      }
      if (mode == 1 || formatted is! String || formatted.trim().isEmpty) return unavailable;
      final firstYear = info['periodUnit'] == 3 && info['periodCount'] == 1 &&
          offer['periodUnit'] == 3 && offer['periodCount'] == 1;
      final details = firstYear ? '首年优惠$formatted，第二年起每年自动续费${product.price}' : mode == 3
          ? '前$duration合计$formatted，$afterwards'
          : '优惠期$duration，每期$formatted，$afterwards';
      return IapPrice(formatted, explanation: details);
    } catch (_) {
      return unavailable;
    }
  }

}
