// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ik_payment_queue_wrapper.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

IKError _$IKErrorFromJson(Map json) => IKError(
      code: json['code'] as int? ?? 0,
      domain: json['domain'] as String? ?? '',
      userInfo: (json['userInfo'] as Map?)?.map(
            (k, e) => MapEntry(k as String, e),
          ) ??
          {},
    );

IKPaymentWrapper _$IKPaymentWrapperFromJson(Map json) => IKPaymentWrapper(
      productId: json['productId'] as String? ?? '',
      productType: _$IKProductTypeFromInt(json['productType'] as int? ?? 0),
      developerPayload: json['developerPayload'] as String?,
      reservedInfo: json['reservedInfo'] as String?,
      promotionalOfferId: json['promotionalOfferId'] as String?,
      applicationUserName: json['applicationUserName'] as String?,
      jwsRepresentation: json['jwsRepresentation'] as String?,
    );

Map<String, dynamic> _$IKPaymentWrapperToJson(IKPaymentWrapper instance) =>
    <String, dynamic>{
      'productId': instance.productId,
      'productType': _productTypeToValue(instance.productType),
      'developerPayload': instance.developerPayload,
      'reservedInfo': instance.reservedInfo,
      'promotionalOfferId': instance.promotionalOfferId,
      'applicationUserName': instance.applicationUserName,
      'jwsRepresentation': instance.jwsRepresentation,
    };

ProductType _$IKProductTypeFromInt(int type) {
  switch (type) {
    case 0:
      return ProductType.CONSUMABLE;
    case 1:
      return ProductType.NONCONSUMABLE;
    case 2:
      return ProductType.AUTORENEWABLE;
    case 3:
      return ProductType.NONRENEWABLE;
    default:
      return ProductType.CONSUMABLE;
  }
}
