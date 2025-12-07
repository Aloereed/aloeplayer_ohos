import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_huawei/sign_in_with_huawei.dart';
import 'package:dio/dio.dart';
import '../env/env.dart';

enum MembershipStatus {
  free, // 免费用户
  premium, // 付费会员
  expired, // 已过期
}

class MembershipService {
  static const String _membershipStatusKey = 'membership_status';
  static const String _expiryDateKey = 'membership_expiry_date';
  static const String _purchaseTokenKey = 'purchase_token';
  static const String _nicknameKey = 'user_nickname';
  static const String _subscriptionNameKey = 'subscription_name';
  static const String _isHuaweiLoginKey = 'is_huawei_login';
  static const String _apiTokenKey = 'api_token';

  // TODO: Replace with actual domain from configuration or environment
  static const String _apiBaseUrl = Env.apiBaseUrl;

  static final MembershipService _instance = MembershipService._internal();
  factory MembershipService() => _instance;
  MembershipService._internal();

  late final InAppPurchase _inAppPurchase;
  late StreamSubscription<List<PurchaseDetails>> _subscription;

  // 产品ID列表 - 需要在应用商店配置
  static const Set<String> _productIds = {
    'premium_monthly', // 月度会员
    'premium_yearly', // 年度会员
    'premium_lifetime', // 终身会员
  };

  MembershipStatus _currentStatus = MembershipStatus.free;
  DateTime? _expiryDate;
  String? _purchaseToken;
  String? _nickname;
  String? _subscriptionName;
  String? _apiToken;
  bool _isHuaweiLogin = false;
  List<ProductDetails> _products = [];
  bool _isAvailable = false;
  bool _isLoading = false;

  // Getters
  MembershipStatus get currentStatus => _currentStatus;
  DateTime? get expiryDate => _expiryDate;
  String? get purchaseToken => _purchaseToken;
  String? get nickname => _nickname;
  String? get subscriptionName => _subscriptionName;
  bool get isHuaweiLogin => _isHuaweiLogin;
  List<ProductDetails> get products => _products;
  bool get isAvailable => _isAvailable;
  bool get isLoading => _isLoading;
  bool get isPremium => _currentStatus == MembershipStatus.premium;
  bool get isExpired => _currentStatus == MembershipStatus.expired;

  bool _isInitialized = false;

  // 初始化服务
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await _loadMembershipStatus();
      await _checkMembershipExpiry();

      // 初始化 InAppPurchase 实例
      print('正在初始化 InAppPurchase 实例...');
      _inAppPurchase = InAppPurchase.instance;
      print('InAppPurchase 实例初始化成功');

      // 检查内购是否可用
      print('正在检查内购是否可用...');
      _isAvailable = await _inAppPurchase.isAvailable();
      print('内购是否可用: $_isAvailable');

      if (_isAvailable) {
        await _loadProducts();
        _listenToPurchaseUpdates();
      } else {
        print('警告: 内购功能在当前平台不可用');
      }
      _isInitialized = true;
    } catch (e, stackTrace) {
      print('初始化 MembershipService 失败: $e');
      print('堆栈跟踪: $stackTrace');
      _isAvailable = false;
      // Even on failure, we might want to mark as initialized to avoid loops, or retry.
      // For now, let's allow retry if it failed, so don't set _isInitialized = true here unless partial init is okay.
      // But _loadMembershipStatus is safe to retry.
    }
  }

  // 从本地存储加载会员状态
  Future<void> _loadMembershipStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final statusIndex = prefs.getInt(_membershipStatusKey) ?? 0;
      _currentStatus = MembershipStatus.values[statusIndex];

      final expiryTimestamp = prefs.getInt(_expiryDateKey);
      if (expiryTimestamp != null) {
        _expiryDate = DateTime.fromMillisecondsSinceEpoch(expiryTimestamp);
      }

      _purchaseToken = prefs.getString(_purchaseTokenKey);
      _nickname = prefs.getString(_nicknameKey);
      _subscriptionName = prefs.getString(_subscriptionNameKey);
      _apiToken = prefs.getString(_apiTokenKey);
      _isHuaweiLogin = prefs.getBool(_isHuaweiLoginKey) ?? false;
    } catch (e) {
      print('加载会员状态失败: $e');
    }
  }

  // 保存会员状态到本地存储
  Future<void> _saveMembershipStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_membershipStatusKey, _currentStatus.index);

      if (_expiryDate != null) {
        await prefs.setInt(_expiryDateKey, _expiryDate!.millisecondsSinceEpoch);
      }

      if (_purchaseToken != null) {
        await prefs.setString(_purchaseTokenKey, _purchaseToken!);
      } else {
        await prefs.remove(_purchaseTokenKey);
      }

      if (_nickname != null) {
        await prefs.setString(_nicknameKey, _nickname!);
      } else {
        await prefs.remove(_nicknameKey);
      }

      if (_subscriptionName != null) {
        await prefs.setString(_subscriptionNameKey, _subscriptionName!);
      } else {
        await prefs.remove(_subscriptionNameKey);
      }

      if (_apiToken != null) {
        await prefs.setString(_apiTokenKey, _apiToken!);
      } else {
        await prefs.remove(_apiTokenKey);
      }

      await prefs.setBool(_isHuaweiLoginKey, _isHuaweiLogin);
    } catch (e) {
      print('保存会员状态失败: $e');
    }
  }

  // 华为登录并连接后端
  Future<LoginResult> loginWithHuaweiAndBackend() async {
    try {
      // 1. Huawei SDK Auth
      final authResponse = await SignInWithHuawei.instance.authById(
        forceLogin: true,
        state: "palyer_login",
        nonce: "palyer_nonce",
        idTokenAlg: IdTokenSignAlgorithm.PS256,
      );

      if (authResponse == null || authResponse.idToken == null) {
        return LoginResult(
            success: false, message: 'Huawei auth cancelled or failed');
      }

      // 2. Backward Compatibility for existing logic - still useful
      _isHuaweiLogin = true;

      // 3. Backend Login
      try {
        final dio = Dio();
        final loginResponse = await dio.post(
          '$_apiBaseUrl/auth/login/huawei',
          data: {
            'openid': authResponse.openID,
            'unionid': authResponse.unionID,
            // Optional: pass access token if backend needs verification
            // 'access_token': authResponse.accessToken
          },
        );

        if (loginResponse.statusCode == 200) {
          final data = loginResponse.data;
          _apiToken = data['access_token'];

          // 4. Get User Info
          return await _fetchUserInfo();
        } else {
          _isHuaweiLogin = false;
          return LoginResult(
              success: false,
              message: 'Backend login failed: ${loginResponse.statusCode}');
        }
      } catch (e) {
        print('Backend login error: $e');
        _isHuaweiLogin = false; // Revert locally if backend fails
        return LoginResult(
            success: false, message: 'Backend connection failed: $e');
      }
    } catch (e) {
      print('Full login flow error: $e');
      return LoginResult(success: false, message: 'Login error: $e');
    }
  }

  // Fetch updated user info from backend
  Future<LoginResult> _fetchUserInfo() async {
    try {
      final dio = Dio();
      final response = await dio.get(
        '$_apiBaseUrl/auth/me',
        options: Options(
          headers: {'Authorization': 'Bearer $_apiToken'},
        ),
      );

      if (response.statusCode == 200) {
        final userData = response.data;
        final serverNickname =
            userData['user_nicename'] ?? userData['display_name'];
        // Or however the backend indicates uniqueness/defaults

        _nickname = serverNickname;
        await _saveMembershipStatus();

        // Check if nickname is same as openid (assuming user_login/username is partially derived from openid or logic provided)
        // For now, let's assume if it looks like a raw ID
        final bool needsUpdate = _looksLikeDefaultId(serverNickname);

        return LoginResult(
            success: true,
            nickname: _nickname,
            needsNicknameUpdate: needsUpdate);
      }
      return LoginResult(success: false, message: 'Failed to fetch user info');
    } catch (e) {
      return LoginResult(success: false, message: 'User info fetch error: $e');
    }
  }

  bool _looksLikeDefaultId(String? name) {
    if (name == null) return true;
    // Rough heuristic: if it's very long and mixed case/numbers, or just matches "openid" pattern
    // Adjust based on actual backend "openid" format.
    return name.length > 20 && name.contains(RegExp(r'[0-9]'));
  }

  // Update Nickname on Server
  Future<bool> updateNicknameOnServer(String newName) async {
    try {
      final dio = Dio();
      final response = await dio.put(
        '$_apiBaseUrl/auth/me/nickname',
        data: {'nickname': newName},
        options: Options(
          headers: {'Authorization': 'Bearer $_apiToken'},
        ),
      );

      if (response.statusCode == 200) {
        _nickname = newName;
        await _saveMembershipStatus();
        return true;
      }
      return false;
    } catch (e) {
      print('Update nickname error: $e');
      return false;
    }
  }

  // Deprecated: Old direct method
  // Future<HuaweiAuthByIdResponse?> loginWithHuawei() ...

  // 设置昵称
  Future<void> setNickname(String name) async {
    _nickname = name;
    await _saveMembershipStatus();
  }

  // 退出登录
  Future<void> logout() async {
    _isHuaweiLogin = false;
    _nickname = null;
    _apiToken = null;

    // 注意：这里我们不清除会员状态，因为会员可能是通过应用商店购买的
    // 如果需要清除会员状态，需要另外的逻辑

    await _saveMembershipStatus();
  }

  // 检查会员是否过期
  Future<void> _checkMembershipExpiry() async {
    if (_expiryDate != null && _currentStatus == MembershipStatus.premium) {
      if (DateTime.now().isAfter(_expiryDate!)) {
        _currentStatus = MembershipStatus.expired;
        await _saveMembershipStatus();
      }
    }
  }

  // 从服务器刷新订阅状态（联网时自动调用）
  Future<void> _refreshSubscriptionFromServer() async {
    try {
      print('尝试从服务器刷新订阅状态...');
      final subscriptions = await fetchMySubscriptions();

      if (subscriptions.isNotEmpty) {
        print('订阅状态已从服务器刷新');
      } else {
        print('服务器未返回订阅数据，保持本地状态');
      }
    } catch (e) {
      // 刷新失败时静默处理，保持本地缓存的状态
      print('从服务器刷新订阅状态失败（保持本地状态）: $e');
    }
  }

  // 加载产品信息
  Future<void> _loadProducts() async {
    try {
      _isLoading = true;
      final ProductDetailsResponse response =
          await _inAppPurchase.queryProductDetails(_productIds);

      if (response.notFoundIDs.isNotEmpty) {
        print('未找到的产品ID: ${response.notFoundIDs}');
      }

      _products = response.productDetails;
    } catch (e) {
      print('加载产品信息失败: $e');
    } finally {
      _isLoading = false;
    }
  }

  // 监听购买更新
  void _listenToPurchaseUpdates() {
    _subscription = _inAppPurchase.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _subscription.cancel(),
      onError: (error) => print('购买监听错误: $error'),
    );
  }

  // 处理购买更新
  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      _handlePurchase(purchaseDetails);
    }
  }

  // 处理单个购买
  Future<void> _handlePurchase(PurchaseDetails purchaseDetails) async {
    if (purchaseDetails.status == PurchaseStatus.pending) {
      // 购买待处理
      print('购买待处理: ${purchaseDetails.productID}');
    } else if (purchaseDetails.status == PurchaseStatus.error) {
      // 购买错误
      print('购买错误: ${purchaseDetails.error}');
    } else if (purchaseDetails.status == PurchaseStatus.purchased ||
        purchaseDetails.status == PurchaseStatus.restored) {
      // 购买成功或恢复购买
      await _verifyAndActivatePurchase(purchaseDetails);
    }

    // 完成购买流程
    if (purchaseDetails.pendingCompletePurchase) {
      await _inAppPurchase.completePurchase(purchaseDetails);
    }
  }

  // 验证并激活购买 - 完整流程,不可简化
  Future<void> _verifyAndActivatePurchase(
      PurchaseDetails purchaseDetails) async {
    try {
      // 步骤1: 验证购买凭证
      if (!_validatePurchaseDetails(purchaseDetails)) {
        print('购买凭证验证失败');
        return;
      }

      // 步骤2: 检查产品ID有效性
      final productId = purchaseDetails.productID;
      if (!_productIds.contains(productId)) {
        print('无效的产品ID: $productId');
        return;
      }

      // 步骤3: 验证购买令牌
      final purchaseToken = purchaseDetails.purchaseID;
      if (purchaseToken == null || purchaseToken.isEmpty) {
        print('购买令牌无效');
        return;
      }

      // 步骤4: 这里应该向服务器验证购买凭证
      // 在生产环境中,需要将购买凭证发送到后端服务器进行验证
      // final serverVerified = await _verifyPurchaseWithServer(purchaseDetails);
      // if (!serverVerified) {
      //   print('服务器验证失败');
      //   return;
      // }

      // 步骤5: 验证通过后,根据产品ID设置会员到期时间
      final now = DateTime.now();
      DateTime? expiryDate;

      switch (productId) {
        case 'premium_monthly':
          expiryDate = DateTime(now.year, now.month + 1, now.day);
          break;
        case 'premium_yearly':
          expiryDate = DateTime(now.year + 1, now.month, now.day);
          break;
        case 'premium_lifetime':
          expiryDate = DateTime(2100, 12, 31); // 终身会员设置为很远的未来
          break;
        default:
          print('未知的产品ID: $productId');
          return;
      }

      // 步骤6: 激活会员
      await _activateMembership(productId, expiryDate, purchaseToken);

      print('会员激活成功: $productId, 到期时间: $expiryDate');
    } catch (e) {
      print('验证并激活购买失败: $e');
      rethrow;
    }
  }

  // 验证购买详情的有效性
  bool _validatePurchaseDetails(PurchaseDetails purchaseDetails) {
    if (purchaseDetails.productID.isEmpty) {
      print('产品ID为空');
      return false;
    }

    if (purchaseDetails.status != PurchaseStatus.purchased &&
        purchaseDetails.status != PurchaseStatus.restored) {
      print('购买状态无效: ${purchaseDetails.status}');
      return false;
    }

    return true;
  }

  // 激活会员状态
  Future<void> _activateMembership(
      String productId, DateTime expiryDate, String? purchaseToken) async {
    _currentStatus = MembershipStatus.premium;
    _expiryDate = expiryDate;
    _purchaseToken = purchaseToken;

    await _saveMembershipStatus();
    print('会员状态已保存');
  }

  // 向服务器验证购买(预留接口,实际项目中需要实现)
  // Future<bool> _verifyPurchaseWithServer(PurchaseDetails purchaseDetails) async {
  //   // 实际项目中,这里需要将购买凭证发送到后端服务器进行验证
  //   // 示例:
  //   // try {
  //   //   final response = await http.post(
  //   //     Uri.parse('https://your-server.com/api/verify-purchase'),
  //   //     body: {
  //   //       'product_id': purchaseDetails.productID,
  //   //       'purchase_token': purchaseDetails.purchaseID,
  //   //       'platform': Platform.isIOS ? 'ios' : 'android',
  //   //     },
  //   //   //   );
  //   //   return response.statusCode == 200;
  //   // } catch (e) {
  //   //   print('服务器验证出错: $e');
  //   //   return false;
  //   // }
  //   return true;
  // }

  // 发起购买
  Future<bool> purchaseProduct(String productId) async {
    if (!_isAvailable || _isLoading) {
      print('购买失败: 插件未初始化或正在加载: $_isAvailable, $_isLoading');
      return false;
    }

    try {
      _isLoading = true;
      final ProductDetails product = _products.firstWhere(
        (product) => product.id == productId,
        orElse: () => throw Exception('产品未找到: $productId'),
      );

      final PurchaseParam purchaseParam =
          PurchaseParam(productDetails: product);
      final bool success =
          await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
      print('购买成功: $success');
      return success;
    } catch (e) {
      print('购买失败: $e');
      return false;
    } finally {
      _isLoading = false;
    }
  }

  // 恢复购买
  Future<bool> restorePurchases() async {
    if (!_isAvailable) {
      return false;
    }

    try {
      _isLoading = true;
      await _inAppPurchase.restorePurchases();
      return true;
    } catch (e) {
      print('恢复购买失败: $e');
      return false;
    } finally {
      _isLoading = false;
    }
  }

  // 获取会员状态描述
  String getMembershipStatusDescription() {
    switch (_currentStatus) {
      case MembershipStatus.free:
        return '免费用户';
      case MembershipStatus.premium:
        if (_expiryDate != null) {
          final daysRemaining = _expiryDate!.difference(DateTime.now()).inDays;
          String name = _subscriptionName ?? '付费会员';
          if (daysRemaining > 365 * 10) {
            return '终身会员';
          }
          return '$name (剩余${daysRemaining}天)';
        }
        return _subscriptionName ?? '付费会员';
      case MembershipStatus.expired:
        return '会员已过期';
    }
  }

  // 获取格式化的到期日期
  String getFormattedExpiryDate() {
    if (_expiryDate == null) return '无';

    if (_expiryDate!.year > 2100) {
      return '终身';
    }

    return '${_expiryDate!.year}-${_expiryDate!.month.toString().padLeft(2, '0')}-${_expiryDate!.day.toString().padLeft(2, '0')}';
  }

  // 检查是否需要显示续费提示
  bool shouldShowRenewalPrompt() {
    if (_currentStatus != MembershipStatus.premium || _expiryDate == null) {
      return false;
    }

    // 如果是终身会员，不需要续费提示
    if (_expiryDate!.year > 2100) {
      return false;
    }

    // 如果剩余时间少于7天，显示续费提示
    final daysRemaining = _expiryDate!.difference(DateTime.now()).inDays;
    return daysRemaining <= 7 && daysRemaining > 0;
  }

  // 清除会员状态（用于测试）
  Future<void> clearMembership() async {
    _currentStatus = MembershipStatus.free;
    _expiryDate = null;
    _purchaseToken = null;
    _nickname = null;
    _subscriptionName = null;
    _apiToken = null;
    _isHuaweiLogin = false;
    await _saveMembershipStatus();
  }

  // 释放资源
  void dispose() {
    // 清理资源
  }

  // 获取产品信息（用于UI显示）
  List<Map<String, dynamic>> getProductInfo() {
    return [
      {
        'id': 'premium_monthly',
        'name': '月度会员',
        'price': '¥12.00',
        'description': '享受1个月会员特权',
        'duration': '1个月',
      },
      {
        'id': 'premium_yearly',
        'name': '年度会员',
        'price': '¥98.00',
        'description': '享受12个月会员特权，节省¥46',
        'duration': '12个月',
        'badge': '最受欢迎',
      },
      {
        'id': 'premium_lifetime',
        'name': '终身会员',
        'price': '¥298.00',
        'description': '一次购买，永久享受',
        'duration': '永久',
        'badge': '超值',
      },
    ];
  }

  // 获取商品列表
  Future<List<Product>> fetchProducts() async {
    try {
      final dio = Dio();
      final response = await dio.get('$_apiBaseUrl/products');
      if (response.statusCode == 200) {
        final List<dynamic> items = response.data['items'];
        return items.map((e) => Product.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      print('Fetch products error: $e');
      return [];
    }
  }

  // 获取我的订阅
  Future<Map<String, List<Subscription>>> fetchMySubscriptions() async {
    if (_apiToken == null) return {};
    try {
      final dio = Dio();
      final response = await dio.get(
        '$_apiBaseUrl/orders/subscriptions/my',
        options: Options(
          headers: {'Authorization': 'Bearer $_apiToken'},
        ),
      );
      if (response.statusCode == 200) {
        final data = response.data;
        final active = (data['active_subscriptions'] as List)
            .map((e) => Subscription.fromJson(e))
            .toList();
        final expired = (data['expired_subscriptions'] as List)
            .map((e) => Subscription.fromJson(e))
            .toList();

        // Update local status based on server response
        if (active.isNotEmpty) {
          // Pick the one with furthest end date
          active.sort((a, b) => b.endDate.compareTo(a.endDate));
          final sub = active.first;
          _currentStatus = MembershipStatus.premium;
          _expiryDate = sub.endDate;
          _subscriptionName = sub.productName;
          await _saveMembershipStatus();
          print('订阅状态已更新: $_subscriptionName, 到期时间: $_expiryDate');
        } else if (expired.isNotEmpty) {
          // All subscriptions expired
          expired.sort((a, b) => b.endDate.compareTo(a.endDate));
          final lastSub = expired.first;
          _currentStatus = MembershipStatus.expired;
          _expiryDate = lastSub.endDate;
          _subscriptionName = lastSub.productName;
          await _saveMembershipStatus();
          print('订阅已过期: $_subscriptionName, 过期时间: $_expiryDate');
        } else {
          // No subscriptions at all - user is free
          _currentStatus = MembershipStatus.free;
          _expiryDate = null;
          _subscriptionName = null;
          await _saveMembershipStatus();
          print('无订阅记录，设置为免费用户');
        }

        return {
          'active_subscriptions': active,
          'expired_subscriptions': expired,
        };
      }
      return {};
    } catch (e) {
      print('Fetch subscriptions error: $e');
      return {};
    }
  }

  // 手动刷新订阅状态（可从UI调用）
  Future<bool> refreshSubscriptionStatus() async {
    if (!_isHuaweiLogin || _apiToken == null) {
      print('未登录，无法刷新订阅状态');
      return false;
    }

    try {
      await _refreshSubscriptionFromServer();
      return true;
    } catch (e) {
      print('刷新订阅状态失败: $e');
      return false;
    }
  }

  // 使用兑换码
  Future<RedeemResult> redeemCode(String code) async {
    if (_apiToken == null) {
      return RedeemResult(success: false, message: '请先登录');
    }
    try {
      final dio = Dio();
      final response = await dio.post(
        '$_apiBaseUrl/redeem-codes/redeem',
        data: {'code': code},
        options: Options(
          headers: {'Authorization': 'Bearer $_apiToken'},
        ),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = RedeemResult.fromJson(response.data);
        if (result.success) {
          // Refresh subscriptions to update status
          await fetchMySubscriptions();
        }
        return result;
      } else {
        return RedeemResult(
            success: false, message: response.data['message'] ?? '兑换失败');
      }
    } on DioException catch (e) {
      if (e.response != null) {
        return RedeemResult(
            success: false,
            message: e.response?.data['message'] ??
                '兑换失败: ${e.response?.statusCode}');
      }
      return RedeemResult(success: false, message: '网络错误: $e');
    } catch (e) {
      return RedeemResult(success: false, message: '兑换出错: $e');
    }
  }
}

class LoginResult {
  final bool success;
  final String? message;
  final String? nickname;
  final bool needsNicknameUpdate;

  LoginResult({
    required this.success,
    this.message,
    this.nickname,
    this.needsNicknameUpdate = false,
  });
}

class Subscription {
  final int id;
  final int userId;
  final int productId;
  final String productName;
  final String subscriptionPeriod;
  final int subscriptionDuration;
  final String status;
  final DateTime startDate;
  final DateTime endDate;
  final bool autoRenew;

  Subscription({
    required this.id,
    required this.userId,
    required this.productId,
    required this.productName,
    required this.subscriptionPeriod,
    required this.subscriptionDuration,
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.autoRenew,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) {
    return Subscription(
      id: json['id'],
      userId: json['user_id'],
      productId: json['product_id'],
      productName: json['product_name'],
      subscriptionPeriod: json['subscription_period'],
      subscriptionDuration: json['subscription_duration'],
      status: json['status'],
      startDate: DateTime.parse(json['start_date']),
      endDate: DateTime.parse(json['end_date']),
      autoRenew: json['auto_renew'] == 1 || json['auto_renew'] == true,
    );
  }
}

class Product {
  final int id;
  final String name;
  final String description;
  final String productType;
  final String price;
  final String subscriptionPeriod;
  final int subscriptionDuration;
  final bool isActive;

  Product({
    required this.id,
    required this.name,
    required this.description,
    required this.productType,
    required this.price,
    required this.subscriptionPeriod,
    required this.subscriptionDuration,
    required this.isActive,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      productType: json['product_type'],
      price: json['price'],
      subscriptionPeriod: json['subscription_period'],
      subscriptionDuration: json['subscription_duration'],
      isActive: json['is_active'],
    );
  }
}

class RedeemResult {
  final bool success;
  final String message;
  final Map<String, dynamic>? order;
  final Map<String, dynamic>? subscription;

  RedeemResult({
    required this.success,
    required this.message,
    this.order,
    this.subscription,
  });

  factory RedeemResult.fromJson(Map<String, dynamic> json) {
    return RedeemResult(
      success: json['success'],
      message: json['message'],
      order: json['order'],
      subscription: json['subscription'],
    );
  }
}
