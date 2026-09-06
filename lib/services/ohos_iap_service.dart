import 'package:in_app_purchase_ohos/in_app_purchase_ohos.dart' show AppGalleryProductDetails;
import 'package:in_app_purchase_ohos/iap_kit_wrappers.dart' show ProductType;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'membership_service.dart';

/// Only the server grants membership; the store is acknowledged afterwards.
class OhosIapService extends ChangeNotifier {
  static final instance = OhosIapService();
  static const productId = 'premium_monthly';
  final Future<Map<String, dynamic>> Function() configuration;
  final Future<void> Function(PurchaseDetails) verify;
  OhosIapService({Future<Map<String, dynamic>> Function()? configuration,
    Future<void> Function(PurchaseDetails)? verify})
      : configuration = configuration ?? MembershipService().iapConfiguration,
        verify = verify ?? MembershipService().verifyIapPurchase;

  ProductDetails? product;
  bool busy = false;
  bool pendingVerification = false;
  bool serverReady = false;
  bool _restoring = false;
  String? message;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Future<void> _updates = Future.value();
  final Map<String, PurchaseDetails> _pending = {};
  InAppPurchase get _store => InAppPurchase.instance;

  void start() {
    _subscription ??= _store.purchaseStream.listen((purchases) {
      _updates = _updates.then((_) async {
        for (final purchase in purchases) { await _handle(purchase); }
      }).catchError((Object error) {
        message = '订单处理暂未完成，请恢复购买重试'; busy = false; notifyListeners();
      });
    }, onError: (Object error) {
      busy = false; message = '支付连接中断，请恢复购买重试'; notifyListeners();
    });
  }

  Future<void> _handle(PurchaseDetails purchase) async {
    if (purchase.productID != productId) return;
    if (purchase.status == PurchaseStatus.pending) {
      busy = true; message = '等待支付结果'; notifyListeners(); return;
    }
    if (purchase.status == PurchaseStatus.canceled || purchase.status == PurchaseStatus.error) {
      busy = false;
      message = purchase.status == PurchaseStatus.canceled ? '已取消购买'
        : '购买未完成：${purchase.error?.message ?? purchase.error?.code ?? '请重试'}';
      notifyListeners(); return;
    }
    if (purchase.status != PurchaseStatus.purchased && purchase.status != PurchaseStatus.restored) return;
    final id = purchase.purchaseID;
    if (id == null || id.isEmpty || purchase.verificationData.serverVerificationData.isEmpty) {
      busy = false; pendingVerification = true;
      message = '订单凭证不完整，请恢复购买，请勿重复支付'; notifyListeners(); return;
    }
    _pending[id] = purchase;
    pendingVerification = true; busy = true; message = '正在验证订单'; notifyListeners();
    var stage = 'verify';
    try {
      await verify(purchase);
      stage = 'complete';
      if (purchase.pendingCompletePurchase) await _store.completePurchase(purchase);
      _pending.remove(id);
      message = '月会员已到账';
    } catch (error) {
      // Log only stage/status, never credentials, receipt bodies or purchase tokens.
      final status = error is DioException ? error.response?.statusCode : null;
      debugPrint('[AloeIAP] stage=$stage failed type=${error.runtimeType} http=${status ?? 0}');
      if (stage == 'complete') {
        message = '会员已验证，商店确认暂未完成，请恢复购买重试；请勿重复支付';
      } else if (status == 401 || status == 403) {
        message = '登录已失效，请重新登录购买时的应用账号，再恢复购买；请勿重复支付';
      } else if (status == 422) {
        message = '后端未能验证购买凭证，或订阅已过期（422），请恢复购买重试；请勿重复支付';
      } else if (status == 409) {
        message = '订阅状态或账号关联需要确认（409），请使用购买时的账号恢复购买；请勿重复支付';
      } else if (status == 503) {
        message = '后端验单服务暂不可用（503），请稍后恢复购买；请勿重复支付';
      } else {
        message = '订单验证暂未完成，请检查网络后恢复购买；请勿重复支付';
      }
    } finally {
      pendingVerification = _pending.isNotEmpty;
      busy = false; notifyListeners();
    }
  }

  Future<void> load() async {
    if (busy || _restoring) return;
    busy = true; message = null; product = null; serverReady = false; notifyListeners();
    try {
      start();
      if (!await _store.isAvailable().timeout(const Duration(seconds: 30))) {
        message = '华为支付暂不可用，请检查设备账号、商店配置和网络'; return;
      }
      final response = await _store.queryProductDetails({productId}).timeout(const Duration(seconds: 30));
      if (response.error != null) throw StateError(response.error!.message);
      for (final item in response.productDetails) { if (item.id == productId) product = item; }
      if (product == null) { message = '暂未找到月会员商品，请检查商店配置后重试'; return; }
      if (product is AppGalleryProductDetails &&
          (product as AppGalleryProductDetails).skProduct.type != ProductType.AUTORENEWABLE) {
        product = null; message = '月会员商品类型应配置为自动续期订阅'; return;
      }
      try {
        final config = await configuration();
        serverReady = config['product_id'] == productId && (config['account_binding'] as String? ?? '').isNotEmpty;
        if (!serverReady) message = '支付服务尚未就绪，请稍后重试';
      } catch (_) { message = '请先登录应用账号；若已登录，请稍后重试支付服务'; }
    } catch (_) { message = '暂时无法加载商品，请检查支付环境后重试'; }
    finally { busy = false; notifyListeners(); }
  }

  Future<void> purchase() async {
    if (busy || _restoring || product == null || !serverReady || pendingVerification) return;
    busy = true; message = '正在打开华为支付'; notifyListeners();
    try {
      // Recheck server and account immediately before opening checkout.
      final config = await configuration();
      if (config['product_id'] != productId) throw StateError('Wrong product');
      final binding = config['account_binding'] as String;
      if (binding.isEmpty) throw StateError('Missing account');
      final launched = await _store.buyNonConsumable(purchaseParam:
        PurchaseParam(productDetails: product!, applicationUserName: binding));
      if (!launched) { busy = false; message = '未能打开支付，请重试'; }
      // Success means checkout was launched, never that membership was granted.
    } catch (_) { busy = false; message = '未能发起购买，请检查登录和支付服务后重试'; }
    notifyListeners();
  }

  Future<void> restore() async {
    if (busy || _restoring) return;
    _restoring = true;
    busy = true; message = '正在恢复购买'; notifyListeners();
    try {
      start();
      for (final item in _pending.values.toList()) { await _handle(item); }
      await _store.restorePurchases();
      await _updates;
      if (message == '正在恢复购买') message = '恢复查询已完成';
    } catch (_) { message = '暂时无法恢复购买，请检查网络和账号后重试'; }
    finally { _restoring = false; busy = false; notifyListeners(); }
  }

  Future<void> manage() async {
    try { await const MethodChannel('plugins.flutter.io/in_app_purchase').invokeMethod<void>('aloeManageSubscriptions'); }
    catch (_) { message = '无法打开订阅管理，请在华为账号的付款与账单中管理订阅'; notifyListeners(); }
  }

  @override
  void dispose() { _subscription?.cancel(); super.dispose(); }
}
