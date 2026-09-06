// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ik_payment_transaction_wrappers.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

IKPaymentTransactionWrapper _$IKPaymentTransactionWrapperFromJson(Map json) =>
    IKPaymentTransactionWrapper(
      payment: IKPaymentWrapper.fromJson(
          Map<String, dynamic>.from(json['payment'] as Map)),
      transactionState: const IKTransactionStatusConverter()
          .fromJson(json['transactionState'] as int?),
      originalTransaction: json['originalTransaction'] == null
          ? null
          : IKPaymentTransactionWrapper.fromJson(
              Map<String, dynamic>.from(json['originalTransaction'] as Map)),
      transactionTimeStamp: (json['transactionTimeStamp'] as num?)?.toDouble(),
      transactionIdentifier: json['transactionIdentifier'] as String?,
      receiptData: json['receiptData'] as String?,
      error: json['error'] == null
          ? null
          : IKError.fromJson(Map<String, dynamic>.from(json['error'] as Map)),
    );

Map<String, dynamic> _$IKPaymentTransactionWrapperToJson(
        IKPaymentTransactionWrapper instance) =>
    <String, dynamic>{
      'transactionState': const IKTransactionStatusConverter()
          .toJson(instance.transactionState),
      'payment': instance.payment,
      'originalTransaction': instance.originalTransaction,
      'transactionTimeStamp': instance.transactionTimeStamp,
      'transactionIdentifier': instance.transactionIdentifier,
      'receiptData': instance.receiptData,
      'error': instance.error,
    };
