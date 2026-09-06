// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ik_product_wrapper.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

IKProductResponseWrapper _$SkProductResponseWrapperFromJson(Map json) =>
    IKProductResponseWrapper(
      products: (json['products'] as List<dynamic>?)
              ?.map((e) => IKProductWrapper.fromJson(
                  Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      invalidProductIdentifiers:
          (json['invalidProductIdentifiers'] as List<dynamic>?)
                  ?.map((e) => e as String)
                  .toList() ??
              [],
    );

IKProductSubscriptionPeriodWrapper _$IKProductSubscriptionPeriodWrapperFromJson(
        Map json) =>
    IKProductSubscriptionPeriodWrapper(
      numberOfUnits: json['numberOfUnits'] as int? ?? 0,
      unit: const IKSubscriptionPeriodUnitConverter()
          .fromJson(json['unit'] as int?),
    );

IKProductWrapper _$IKProductWrapperFromJson(Map json) => IKProductWrapper(
      id: json['id'] as String? ?? '',
      type: _$IKProductTypeFromInt(json['type'] as int? ?? 0),
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      localPrice: json['localPrice'] as String? ?? '',
      microPrice: json['microPrice'] as int? ?? 0,
      originalLocalPrice: json['originalLocalPrice'] as String? ?? '',
      originalMicroPrice: json['originalMicroPrice'] as int? ?? 0,
      currency: json['currency'] as String? ?? '',
      status: _$IKProductStatusFromInt(json['status'] as int? ?? 0),
      jsonRepresentation: json['jsonRepresentation'] as String?,
    );

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

ProductStatus _$IKProductStatusFromInt(int type) {
  switch (type) {
    case 0:
      return ProductStatus.VALID;
    case 1:
      return ProductStatus.CANCELED;
    case 3:
      return ProductStatus.OFFLINE;
    default:
      return ProductStatus.VALID;
  }
}
