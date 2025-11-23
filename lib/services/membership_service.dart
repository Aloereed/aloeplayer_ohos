import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MembershipStatus {
  free, // 免费用户
  premium, // 付费会员
  expired, // 已过期
}

class MembershipService {
  static const String _membershipStatusKey = 'membership_status';
  static const String _expiryDateKey = 'membership_expiry_date';
  static const String _purchaseTokenKey = 'purchase_token';
  
  static final MembershipService _instance = MembershipService._internal();
  factory MembershipService() => _instance;
  MembershipService._internal();

  late final InAppPurchase _inAppPurchase;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  
  // 产品ID列表 - 需要在应用商店配置
  static const Set<String> _productIds = {
    'premium_monthly',    // 月度会员
    'premium_yearly',     // 年度会员
    'premium_lifetime',   // 终身会员
  };

  MembershipStatus _currentStatus = MembershipStatus.free;
  DateTime? _expiryDate;
  String? _purchaseToken;
  List<ProductDetails> _products = [];
  bool _isAvailable = false;
  bool _isLoading = false;

  // Getters
  MembershipStatus get currentStatus => _currentStatus;
  DateTime? get expiryDate => _expiryDate;
  String? get purchaseToken => _purchaseToken;
  List<ProductDetails> get products => _products;
  bool get isAvailable => _isAvailable;
  bool get isLoading => _isLoading;
  bool get isPremium => _currentStatus == MembershipStatus.premium;
  bool get isExpired => _currentStatus == MembershipStatus.expired;

  // 初始化服务
  Future<void> initialize() async {
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
    } catch (e, stackTrace) {
      print('初始化 MembershipService 失败: $e');
      print('堆栈跟踪: $stackTrace');
      _isAvailable = false;
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
      }
    } catch (e) {
      print('保存会员状态失败: $e');
    }
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

  // 加载产品信息
  Future<void> _loadProducts() async {
    try {
      _isLoading = true;
      final ProductDetailsResponse response = await _inAppPurchase.queryProductDetails(_productIds);
      
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
  Future<void> _verifyAndActivatePurchase(PurchaseDetails purchaseDetails) async {
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
  Future<void> _activateMembership(String productId, DateTime expiryDate, String? purchaseToken) async {
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
  //   //   );
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

      final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
      final bool success = await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
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
          if (daysRemaining > 365 * 10) {
            return '终身会员';
          }
          return '付费会员 (剩余${daysRemaining}天)';
        }
        return '付费会员';
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
}
