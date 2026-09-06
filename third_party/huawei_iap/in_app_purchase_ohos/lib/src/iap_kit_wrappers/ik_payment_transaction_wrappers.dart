// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:json_annotation/json_annotation.dart';

import 'enum_converters.dart';
import 'ik_payment_queue_wrapper.dart';
import 'ik_product_wrapper.dart';

part 'ik_payment_transaction_wrappers.g.dart';

int? _finishMapProductTypeValue(ProductType? productType) {
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

/// Callback handlers for transaction status changes.
abstract class IKTransactionObserverWrapper {
  /// Triggered when any transactions are updated.
  void updatedTransactions(
      {required List<IKPaymentTransactionWrapper> transactions});

  /// Triggered when any transactions are removed from the payment queue.
  void removedTransactions(
      {required List<IKPaymentTransactionWrapper> transactions});
}

/// The state of a transaction.
enum IKPaymentTransactionStateWrapper {
  /// Indicates the transaction is being processed in App Store.
  ///
  /// You should update your UI to indicate that you are waiting for the
  /// transaction to update to another state. Never complete a transaction that
  /// is still in a purchasing state.
  @JsonValue(0)
  purchasing,

  /// The user's payment has been succesfully processed.
  ///
  /// You should provide the user the content that they purchased.
  @JsonValue(1)
  purchased,

  /// The transaction failed.
  ///
  /// Check the [IKPaymentTransactionWrapper.error] property from
  /// [IKPaymentTransactionWrapper] for details.
  @JsonValue(2)
  failed,

  /// This transaction is restoring content previously purchased by the user.
  ///
  /// The previous transaction information can be obtained in
  /// [IKPaymentTransactionWrapper.originalTransaction] from
  /// [IKPaymentTransactionWrapper].
  @JsonValue(3)
  restored,

  /// The transaction is in the queue but pending external action. Wait for
  /// another callback to get the final state.
  ///
  /// You should update your UI to indicate that you are waiting for the
  /// transaction to update to another state.
  @JsonValue(4)
  deferred,

  /// Indicates the transaction is in an unspecified state.
  @JsonValue(-1)
  unspecified,
}

/// Created when a payment is added to the [IKPaymentQueueWrapper].
///
/// Transactions are delivered to your app when a payment is finished
/// processing. Completed transactions provide a receipt and a transaction
/// identifier that the app can use to save a permanent record of the processed
/// payment.
@JsonSerializable(createToJson: true)
@immutable
class IKPaymentTransactionWrapper {
  /// Creates a new [IKPaymentTransactionWrapper] with the provided information.
  // TODO(stuartmorgan): Temporarily ignore const warning in other parts of the
  // federated package, and remove this.
  // ignore: prefer_const_constructors_in_immutables
  IKPaymentTransactionWrapper({
    required this.payment,
    required this.transactionState,
    this.originalTransaction,
    this.transactionTimeStamp,
    this.transactionIdentifier,
    this.receiptData,
    this.error,
  });

  /// Constructs an instance of this from a key value map of data.
  ///
  /// The map needs to have named string keys with values matching the names and
  /// types of all of the members on this class. The `map` parameter must not be
  /// null.
  factory IKPaymentTransactionWrapper.fromJson(Map<String, dynamic> map) {
    return _$IKPaymentTransactionWrapperFromJson(map);
  }

  /// Current transaction state.
  @IKTransactionStatusConverter()
  final IKPaymentTransactionStateWrapper transactionState;

  /// The payment that has been created and added to the payment queue which
  /// generated this transaction.
  final IKPaymentWrapper payment;

  /// The original Transaction.
  ///
  /// Only available if the [transactionState] is [SKPaymentTransactionStateWrapper.restored].
  /// Otherwise the value is `null`.
  ///
  /// When the [transactionState]
  /// is [IKPaymentTransactionStateWrapper.restored], the current transaction
  /// object holds a new [transactionIdentifier].
  final IKPaymentTransactionWrapper? originalTransaction;

  /// The timestamp of the transaction.
  ///
  /// Seconds since epoch. It is only defined when the [transactionState] is
  /// [IKPaymentTransactionStateWrapper.purchased] or
  /// [IKPaymentTransactionStateWrapper.restored].
  /// Otherwise, the value is `null`.
  final double? transactionTimeStamp;

  /// The unique string identifer of the transaction.
  ///
  /// It is only defined when the [transactionState] is
  /// [IKPaymentTransactionStateWrapper.purchased] or
  /// [IKPaymentTransactionStateWrapper.restored]. You may wish to record this
  /// string as part of an audit trail for App Store purchases. The value of
  /// this string corresponds to the same property in the receipt.
  ///
  /// The value is `null` if it is an unsuccessful transaction.
  final String? transactionIdentifier;

  /// The signed receipt belonging to this transaction, never a global last receipt.
  final String? receiptData;

  /// The error object
  ///
  /// Only available if the [transactionState] is
  /// [IKPaymentTransactionStateWrapper.failed].
  final IKError? error;

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is IKPaymentTransactionWrapper &&
        other.payment == payment &&
        other.transactionState == transactionState &&
        other.originalTransaction == originalTransaction &&
        other.transactionTimeStamp == transactionTimeStamp &&
        other.transactionIdentifier == transactionIdentifier &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(payment, transactionState,
      originalTransaction, transactionTimeStamp, transactionIdentifier, error);

  @override
  String toString() => _$IKPaymentTransactionWrapperToJson(this).toString();

  /// The payload that is used to finish this transaction.
  Map<String, Object?> toFinishMap() => <String, Object?>{
        'transactionIdentifier': transactionIdentifier,
        'productIdentifier': payment.productId,
        'productType': _finishMapProductTypeValue(payment.productType),
      };
}
