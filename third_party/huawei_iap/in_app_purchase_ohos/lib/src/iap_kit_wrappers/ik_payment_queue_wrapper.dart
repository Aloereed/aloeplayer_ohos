// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../iap_kit_wrappers.dart';
import '../channel.dart';
import '../in_app_purchase_ohos_platform.dart';

part 'ik_payment_queue_wrapper.g.dart';

int? _productTypeToValue(ProductType? productType) {
  switch (productType) {
    case ProductType.CONSUMABLE:
      return 0;
    case ProductType.NONCONSUMABLE:
      return 1;
    case ProductType.AUTORENEWABLE:
      return 2;
    case ProductType.NONRENEWABLE:
      return 3;
    case null:
      return null;
  }
}

class IKPaymentQueueWrapper {
  /// Returns the default payment queue.
  ///
  /// We do not support instantiating a custom payment queue, hence the
  /// singleton. However, you can override the observer.
  factory IKPaymentQueueWrapper() {
    return _singleton;
  }

  IKPaymentQueueWrapper._();

  static final IKPaymentQueueWrapper _singleton = IKPaymentQueueWrapper._();

  IKTransactionObserverWrapper? _observer;

  Future<List<IKPaymentTransactionWrapper>> transactions() async {
    return _getTransactionList(
        (await channel.invokeListMethod<dynamic>('iap#transactions'))!);
  }

  static Future<bool> queryEnvironmentStatus() async =>
      (await channel.invokeMethod<bool>('iap#queryEnvironmentStatus')) ?? false;

  void setTransactionObserver(IKTransactionObserverWrapper observer) {
    _observer = observer;
    channel.setMethodCallHandler(handleObserverCallbacks);
  }

  Future<void> startObservingTransactionQueue() =>
      channel.invokeMethod<void>('iap#startObservingTransactionQueue');

  Future<void> stopObservingTransactionQueue() =>
      channel.invokeMethod<void>('iap#stopObservingTransactionQueue');

  Future<void> addPayment(IKPaymentWrapper payment) async {
    assert(_observer != null,
        '[in_app_purchase]: Trying to add a payment without an observer. One must be set using `IKPaymentQueueWrapper.setTransactionObserver` before the app launches.');
    final Map<String, dynamic> requestMap = payment.toMap();
    await channel.invokeMethod<void>(
      'iap#createPurchase',
      requestMap,
    );
  }

  Future<void> finishTransaction(
      IKPaymentTransactionWrapper transaction) async {
    final Map<String, Object?> requestMap = transaction.toFinishMap();
    await channel.invokeMethod<void>(
      'iap#finishPurchase',
      requestMap,
    );
  }

  // 暂未实现
  Future<void> restoreTransactions({String? applicationUserName}) async {
    await channel.invokeMethod<void>(
        'iap#restoreTransactions', applicationUserName);
  }

  /// Triage a method channel call from the platform and triggers the correct observer method.
  ///
  /// This method is public for testing purposes only and should not be used
  /// outside this class.
  @visibleForTesting
  Future<dynamic> handleObserverCallbacks(MethodCall call) async {
    assert(_observer != null,
        '[in_app_purchase]: (Fatal)The observer has not been set but we received a purchase transaction notification. Please ensure the observer has been set using `setTransactionObserver`. Make sure the observer is added right at the App Launch.');
    print('MethodCallHandlerImpl handleObserverCallbacks : ' + call.method);
    final IKTransactionObserverWrapper observer = _observer!;
    switch (call.method) {
      case 'updatedTransactions':
        {
          print('MethodCallHandlerImpl   handleObserverCallbacks');
          final List<IKPaymentTransactionWrapper> transactions =
              _getTransactionList(call.arguments as List<dynamic>);
          return Future<void>(() {
            observer.updatedTransactions(transactions: transactions);
          });
        }
      case 'removedTransactions':
        {
          final List<IKPaymentTransactionWrapper> transactions =
              _getTransactionList(call.arguments as List<dynamic>);
          return Future<void>(() {
            observer.removedTransactions(transactions: transactions);
          });
        }
      default:
        break;
    }
    throw PlatformException(
        code: 'no_such_callback',
        message: 'Did not recognize the observer callback ${call.method}.');
  }

  // Get transaction wrapper object list from arguments.
  List<IKPaymentTransactionWrapper> _getTransactionList(
      List<dynamic> transactionsData) {
    return transactionsData.map<IKPaymentTransactionWrapper>((dynamic map) {
      return IKPaymentTransactionWrapper.fromJson(
          Map.castFrom<dynamic, dynamic, String, dynamic>(
              map as Map<dynamic, dynamic>));
    }).toList();
  }
}

@immutable
@JsonSerializable()
class IKError {
  /// Creates a new [IKError] object with the provided information.
  const IKError(
      {required this.code, required this.domain, required this.userInfo});

  /// Constructs an instance of this from a key-value map of data.
  ///
  /// The map needs to have named string keys with values matching the names and
  /// types of all of the members on this class. The `map` parameter must not be
  /// null.
  factory IKError.fromJson(Map<String, dynamic> map) {
    return _$IKErrorFromJson(map);
  }

  /// Error code
  @JsonKey(defaultValue: 0)
  final int code;

  /// Error
  @JsonKey(defaultValue: '')
  final String domain;

  /// A map that contains more detailed information about the error.
  @JsonKey(defaultValue: <String, dynamic>{})
  final Map<String, dynamic> userInfo;

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is IKError &&
        other.code == code &&
        other.domain == domain &&
        const DeepCollectionEquality.unordered()
            .equals(other.userInfo, userInfo);
  }

  @override
  int get hashCode => Object.hash(
        code,
        domain,
        userInfo,
      );
}

/// Dart wrapper around IAP Kit
/// [PurchaseParameter](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/iap-iap-V5#section1340120344598).
///
/// Used as the parameter to initiate a payment. In general, a developer should
/// not need to create the payment object explicitly; instead, use
/// [IKPaymentQueueWrapper.addPayment] directly with a product identifier to
/// initiate a payment.
@immutable
@JsonSerializable(createToJson: true)
class IKPaymentWrapper {
  /// Creates a new [IKPaymentWrapper] with the provided information.
  const IKPaymentWrapper({
    required this.productId,
    this.productType,
    this.developerPayload,
    this.reservedInfo,
    this.promotionalOfferId,
    this.applicationUserName,
    this.jwsRepresentation,
  });

  /// Constructs an instance of this from a key value map of data.
  ///
  /// The map needs to have named string keys with values matching the names and
  /// types of all of the members on this class. The `map` parameter must not be
  /// null.
  factory IKPaymentWrapper.fromJson(Map<String, dynamic> map) {
    return _$IKPaymentWrapperFromJson(map);
  }

  /// Creates a Map object describes the payment object.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'productId': productId,
      'productType': _productTypeToValue(productType),
      'developerPayload': developerPayload,
      'reservedInfo': reservedInfo,
      'promotionalOfferId': promotionalOfferId,
      'applicationUserName': applicationUserName,
      'jwsRepresentation': jwsRepresentation,
    };
  }

  /// 待支付的商品ID。商品ID来源于开发者在AppGallery Connect中配置商品信息时设置的“商品ID”，具体请参见配置商品信息。
  final String productId;

  /// 需要查询的商品类型
  final ProductType? productType;

  /// 商户侧保留信息
  final String? developerPayload;

  /// 要求JSON String格式，商户可以将额外需要传入的字段以key-value的形式设置在JSON String中，并通过该参数传入。
  final String? reservedInfo;

  /// 优惠ID。优惠ID来源于开发者在AppGallery Connect中配置商品信息时设置的促销优惠标识符，
  /// 具体请参见设置促销价格。传递该字段且要生效，需传递jwsRepresentation字段包含促销优惠信息。
  final String? promotionalOfferId;

  /// 用户账户相关联的混淆字符串，唯一标识用户。传递优惠ID场景，可以传递该字段。
  final String? applicationUserName;

  /// 包含购买参数信息的JWS格式签名数据。购买参数，如促销优惠等。
  final String? jwsRepresentation;

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is IKPaymentWrapper &&
        other.productId == productId &&
        other.productType == productType &&
        other.developerPayload == developerPayload &&
        other.reservedInfo == reservedInfo &&
        other.promotionalOfferId == promotionalOfferId &&
        other.applicationUserName == applicationUserName &&
        other.jwsRepresentation == jwsRepresentation;
  }

  @override
  int get hashCode => Object.hash(productId, productType, developerPayload,
      reservedInfo, promotionalOfferId);

  @override
  String toString() => _$IKPaymentWrapperToJson(this).toString();
}
