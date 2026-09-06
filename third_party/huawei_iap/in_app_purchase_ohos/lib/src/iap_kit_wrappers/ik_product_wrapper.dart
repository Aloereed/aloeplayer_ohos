// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:json_annotation/json_annotation.dart';
import 'enum_converters.dart';

// WARNING: Changes to `@JsonSerializable` classes need to be reflected in the
// below generated file. Run `flutter packages pub run build_runner watch` to
// rebuild and watch for further changes.
part 'ik_product_wrapper.g.dart';

/// Represents the response object returned by [IKRequestMaker.startProductRequest].
/// Contains information about a list of products and a list of invalid product identifiers.
@JsonSerializable()
@immutable
class IKProductResponseWrapper {
  /// Creates an [IKProductResponseWrapper] with the given product details.
  // TODO(stuartmorgan): Temporarily ignore const warning in other parts of the
  // federated package, and remove this.
  // ignore: prefer_const_constructors_in_immutables
  IKProductResponseWrapper(
      {required this.products, required this.invalidProductIdentifiers});

  /// Constructing an instance from a map from the Objective-C layer.
  ///
  /// This method should only be used with `map` values returned by [IKRequestMaker.startProductRequest].
  factory IKProductResponseWrapper.fromJson(Map<String, dynamic> map) {
    var maptt = _$SkProductResponseWrapperFromJson(map);
    return _$SkProductResponseWrapperFromJson(map);
  }

  /// Stores all matching successfully found products.
  ///
  /// One product in this list matches one valid product identifier passed to the [IKRequestMaker.startProductRequest].
  /// Will be empty if the [IKRequestMaker.startProductRequest] method does not pass any correct product identifier.
  @JsonKey(defaultValue: <IKProductWrapper>[])
  final List<IKProductWrapper> products;

  /// Stores product identifiers in the `productIdentifiers` from [IKRequestMaker.startProductRequest] that are not recognized by the AppGallery.
  /// Will be empty if all the product identifiers are valid.
  @JsonKey(defaultValue: <String>[])
  final List<String> invalidProductIdentifiers;

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is IKProductResponseWrapper &&
        const DeepCollectionEquality().equals(other.products, products) &&
        const DeepCollectionEquality()
            .equals(other.invalidProductIdentifiers, invalidProductIdentifiers);
  }

  @override
  int get hashCode => Object.hash(products, invalidProductIdentifiers);
}

/// Used as a property in the [IKProductSubscriptionPeriodWrapper]. Minimum is a day and maximum is a year.
// The values of the enum options are matching the [IKProductPeriodUnit]'s values. Should there be an update or addition
// in the [IKProductPeriodUnit], this need to be updated to match.
enum IKSubscriptionPeriodUnit {
  /// An interval lasting one day.
  @JsonValue(0)
  day,

  /// An interval lasting one month.
  @JsonValue(1)

  /// An interval lasting one week.
  week,
  @JsonValue(2)

  /// An interval lasting one month.
  month,

  /// An interval lasting one year.
  @JsonValue(3)
  year,
}

/// A period is defined by a [numberOfUnits] and a [unit], e.g for a 3 months period [numberOfUnits] is 3 and [unit] is a month.
/// It is used as a property in [IKProductDiscountWrapper] and [IKProductWrapper].
@JsonSerializable()
@immutable
class IKProductSubscriptionPeriodWrapper {
  /// Creates an [IKProductSubscriptionPeriodWrapper] for a `numberOfUnits`x`unit` period.
  // TODO(stuartmorgan): Temporarily ignore const warning in other parts of the
  // federated package, and remove this.
  // ignore: prefer_const_constructors_in_immutables
  IKProductSubscriptionPeriodWrapper(
      {required this.numberOfUnits, required this.unit});

  /// Constructing an instance from a map from the Objective-C layer.
  ///
  /// This method should only be used with `map` values returned by [IKProductDiscountWrapper.fromJson] or [IKProductWrapper.fromJson].
  factory IKProductSubscriptionPeriodWrapper.fromJson(
      Map<String, dynamic>? map) {
    if (map == null) {
      return IKProductSubscriptionPeriodWrapper(
          numberOfUnits: 0, unit: IKSubscriptionPeriodUnit.day);
    }
    return _$IKProductSubscriptionPeriodWrapperFromJson(map);
  }

  /// The number of [unit] units in this period.
  ///
  /// Must be greater than 0 if the object is valid.
  @JsonKey(defaultValue: 0)
  final int numberOfUnits;

  /// The time unit used to specify the length of this period.
  @IKSubscriptionPeriodUnitConverter()
  final IKSubscriptionPeriodUnit unit;

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is IKProductSubscriptionPeriodWrapper &&
        other.numberOfUnits == numberOfUnits &&
        other.unit == unit;
  }

  @override
  int get hashCode => Object.hash(numberOfUnits, unit);
}

/// This is used as a property in the [IKProductDiscountWrapper].
// The values of the enum options are matching the [IKProductDiscountPaymentMode]'s values. Should there be an update or addition
// in the [IKProductDiscountPaymentMode], this need to be updated to match.
enum IKProductDiscountPaymentMode {
  /// Allows user to pay the discounted price at each payment period.
  @JsonValue(0)
  payAsYouGo,

  /// Allows user to pay the discounted price upfront and receive the product for the rest of time that was paid for.
  @JsonValue(1)
  payUpFront,

  /// User pays nothing during the discounted period.
  @JsonValue(2)
  freeTrail,

  /// Unspecified mode.
  @JsonValue(-1)
  unspecified,
}

/// This is used as a property in the [IKProductDiscountWrapper].
/// The values of the enum options are matching the [IKProductDiscountType]'s
/// values.
///
/// Values representing the types of discount offers an app can present.
enum IKProductDiscountType {
  /// A constant indicating the discount type is an introductory offer.
  @JsonValue(0)
  introductory,

  /// A constant indicating the discount type is a promotional offer.
  @JsonValue(1)
  subscription,
}

/// Dart wrapper around IAP Kit [Product](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/iap-iap-V5#section346874219313).
///
/// A list of [IKProductWrapper] is returned in the [IKRequestMaker.startProductRequest] method, and
/// should be stored for use when making a payment.
@JsonSerializable()
@immutable
class IKProductWrapper {
  /// Creates an [IKProductWrapper] with the given product details.
  // TODO(stuartmorgan): Temporarily ignore const warning in other parts of the
  // federated package, and remove this.
  // ignore: prefer_const_constructors_in_immutables
  IKProductWrapper({
    required this.id,
    required this.type,
    required this.name,
    required this.description,
    required this.localPrice,
    required this.microPrice,
    required this.originalLocalPrice,
    required this.originalMicroPrice,
    required this.currency,
    this.status,
    // this.subscriptionInfo,
    // this.promotionalOffers,
    this.jsonRepresentation,
  });

  /// Constructing an instance from a map from the ets layer.
  ///
  /// This method should only be used with `map` values returned by [IKProductResponseWrapper.fromJson].
  factory IKProductWrapper.fromJson(Map<String, dynamic> map) {
    return _$IKProductWrapperFromJson(map);
  }

  /// 商品ID
  final String id;

  /// 商品类型
  final ProductType type;

  /// 商品名称，为配置商品信息时配置的名称。用于显示在应用内支付收银台
  final String name;

  /// 商品描述，即配置商品信息时配置的描述信息
  final String description;

  /// 商品的展示价格，包含商品币种和价格，格式为“币种+商品价格”，例如 EUR 0.15。部分国家/地区会返回“货币符号+商品价格”，例如中国大陆返回“￥0.15”。此价格含税。可选。
  final String localPrice;

  /// 商品实际价格乘以1,000,000后的微单位价格。例如某个商品实际价格是1.99美元，则该商品对应的微单位价格为：1.99*1000000=1990000。
  final int microPrice;

  /// 商品的原价，包含商品币种和价格，格式为“币种+商品价格”，例如 EUR 0.15。部分国家/地区会返回“货币符号+商品价格”，例如中国大陆返回“￥0.15”。此价格含税。
  final String originalLocalPrice;

  /// 商品原价的微单位价格。商品原价乘以1,000,000后的微单位价格。例如某个商品原价是1.99美元，则该商品对应的微单位价格为：1.99*1000000=1990000。
  final int originalMicroPrice;

  /// 用于支付该商品的币种，必须符合ISO 4217标准，例如USD、CNY、MYR。
  final String currency;

  /// 商品状态
  final ProductStatus? status;

  /// 自动续期订阅商品相关的信息。可选。
  // final SubscriptionInfo? subscriptionInfo;

  /// 订阅商品支持的优惠信息列表
  // final PromotionalOffer[]? promotionalOffers;

  /// 商品详细信息的原始JSON字符串
  final String? jsonRepresentation;
}

/// 商品状态枚举
enum ProductType {
  /// 消耗型商品
  @JsonValue(0)
  CONSUMABLE,

  /// 非消耗型商品
  @JsonValue(1)
  NONCONSUMABLE,

  /// 自动续期订阅商品
  @JsonValue(2)
  AUTORENEWABLE,

  /// 非续期订阅商品
  @JsonValue(3)
  NONRENEWABLE,
}

/// 商品状态枚举
enum ProductStatus {
  /// 有效状态。
  @JsonValue(0)
  VALID,

  /// 取消状态，即删除。此状态的商品不可续订，也不可订阅。
  @JsonValue(1)
  CANCELED,

  /// 下线状态，不能订阅，但老用户仍可续订。
  @JsonValue(3)
  OFFLINE,
}
