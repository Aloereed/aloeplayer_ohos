// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../iap_kit_wrappers.dart';

part 'enum_converters.g.dart';

/// Serializer for [IKPaymentTransactionStateWrapper].
///
/// Use these in `@JsonSerializable()` classes by annotating them with
/// `@IKTransactionStatusConverter()`.
class IKTransactionStatusConverter
    implements JsonConverter<IKPaymentTransactionStateWrapper, int?> {
  /// Default const constructor.
  const IKTransactionStatusConverter();

  @override
  IKPaymentTransactionStateWrapper fromJson(int? json) {
    if (json == null) {
      return IKPaymentTransactionStateWrapper.unspecified;
    }
    return $enumDecode<IKPaymentTransactionStateWrapper, dynamic>(
        _$IKPaymentTransactionStateWrapperEnumMap
            .cast<IKPaymentTransactionStateWrapper, dynamic>(),
        json);
  }

  /// Converts an [IKPaymentTransactionStateWrapper] to a [PurchaseStatus].
  PurchaseStatus toPurchaseStatus(
      IKPaymentTransactionStateWrapper object, IKError? error) {
    print('MethodCallHandlerImpl toPurchaseStatus. $object');
    switch (object) {
      case IKPaymentTransactionStateWrapper.purchasing:
      case IKPaymentTransactionStateWrapper.deferred:
        return PurchaseStatus.pending;
      case IKPaymentTransactionStateWrapper.purchased:
        return PurchaseStatus.purchased;
      case IKPaymentTransactionStateWrapper.restored:
        return PurchaseStatus.restored;
      case IKPaymentTransactionStateWrapper.failed:
        // According to the Apple documentation the error code "2" indicates
        // the user cancelled the payment (IKErrorPaymentCancelled) and error
        // code "15" indicates the cancellation of the overlay (IKErrorOverlayCancelled).
        if (error != null && (error.code == 2 || error.code == 15)) {
          return PurchaseStatus.canceled;
        }
        return PurchaseStatus.error;
      case IKPaymentTransactionStateWrapper.unspecified:
        return PurchaseStatus.error;
    }
  }

  @override
  int toJson(IKPaymentTransactionStateWrapper object) =>
      _$IKPaymentTransactionStateWrapperEnumMap[object]!;
}

/// Serializer for [IKSubscriptionPeriodUnit].
///
/// Use these in `@JsonSerializable()` classes by annotating them with
/// `@IKSubscriptionPeriodUnitConverter()`.
class IKSubscriptionPeriodUnitConverter
    implements JsonConverter<IKSubscriptionPeriodUnit, int?> {
  /// Default const constructor.
  const IKSubscriptionPeriodUnitConverter();

  @override
  IKSubscriptionPeriodUnit fromJson(int? json) {
    if (json == null) {
      return IKSubscriptionPeriodUnit.day;
    }
    return $enumDecode<IKSubscriptionPeriodUnit, dynamic>(
        _$IKSubscriptionPeriodUnitEnumMap
            .cast<IKSubscriptionPeriodUnit, dynamic>(),
        json);
  }

  @override
  int toJson(IKSubscriptionPeriodUnit object) =>
      _$IKSubscriptionPeriodUnitEnumMap[object]!;
}

/// Serializer for [IKProductDiscountPaymentMode].
///
/// Use these in `@JsonSerializable()` classes by annotating them with
/// `@IKProductDiscountPaymentModeConverter()`.
class IKProductDiscountPaymentModeConverter
    implements JsonConverter<IKProductDiscountPaymentMode, int?> {
  /// Default const constructor.
  const IKProductDiscountPaymentModeConverter();

  @override
  IKProductDiscountPaymentMode fromJson(int? json) {
    if (json == null) {
      return IKProductDiscountPaymentMode.payAsYouGo;
    }
    return $enumDecode<IKProductDiscountPaymentMode, dynamic>(
        _$IKProductDiscountPaymentModeEnumMap
            .cast<IKProductDiscountPaymentMode, dynamic>(),
        json);
  }

  @override
  int toJson(IKProductDiscountPaymentMode object) =>
      _$IKProductDiscountPaymentModeEnumMap[object]!;
}

// Define a class so we generate serializer helper methods for the enums
// See https://github.com/google/json_serializable.dart/issues/778
@JsonSerializable()
class _SerializedEnums {
  late IKPaymentTransactionStateWrapper response;
  late IKSubscriptionPeriodUnit unit;
  late IKProductDiscountPaymentMode discountPaymentMode;
}

/// Serializer for [IKProductDiscountType].
///
/// Use these in `@JsonSerializable()` classes by annotating them with
/// `@IKProductDiscountTypeConverter()`.
class IKProductDiscountTypeConverter
    implements JsonConverter<IKProductDiscountType, int?> {
  /// Default const constructor.
  const IKProductDiscountTypeConverter();

  @override
  IKProductDiscountType fromJson(int? json) {
    if (json == null) {
      return IKProductDiscountType.introductory;
    }
    return $enumDecode<IKProductDiscountType, dynamic>(
        _$IKProductDiscountTypeEnumMap.cast<IKProductDiscountType, dynamic>(),
        json);
  }

  @override
  int toJson(IKProductDiscountType object) =>
      _$IKProductDiscountTypeEnumMap[object]!;
}
