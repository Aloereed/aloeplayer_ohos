// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enum_converters.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SerializedEnums _$SerializedEnumsFromJson(Map json) => _SerializedEnums()
  ..response =
      $enumDecode(_$IKPaymentTransactionStateWrapperEnumMap, json['response'])
  ..unit = $enumDecode(_$IKSubscriptionPeriodUnitEnumMap, json['unit'])
  ..discountPaymentMode = $enumDecode(
      _$IKProductDiscountPaymentModeEnumMap, json['discountPaymentMode']);

const _$IKPaymentTransactionStateWrapperEnumMap = {
  IKPaymentTransactionStateWrapper.purchasing: 0,
  IKPaymentTransactionStateWrapper.purchased: 1,
  IKPaymentTransactionStateWrapper.failed: 2,
  IKPaymentTransactionStateWrapper.restored: 3,
  IKPaymentTransactionStateWrapper.deferred: 4,
  IKPaymentTransactionStateWrapper.unspecified: -1,
};

const _$IKSubscriptionPeriodUnitEnumMap = {
  IKSubscriptionPeriodUnit.day: 0,
  IKSubscriptionPeriodUnit.week: 1,
  IKSubscriptionPeriodUnit.month: 2,
  IKSubscriptionPeriodUnit.year: 3,
};

const _$IKProductDiscountPaymentModeEnumMap = {
  IKProductDiscountPaymentMode.payAsYouGo: 0,
  IKProductDiscountPaymentMode.payUpFront: 1,
  IKProductDiscountPaymentMode.freeTrail: 2,
  IKProductDiscountPaymentMode.unspecified: -1,
};

const _$IKProductDiscountTypeEnumMap = {
  IKProductDiscountType.introductory: 0,
  IKProductDiscountType.subscription: 1,
};
