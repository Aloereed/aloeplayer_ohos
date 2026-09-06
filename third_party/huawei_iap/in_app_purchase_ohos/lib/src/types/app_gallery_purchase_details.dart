// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

import '../../iap_kit_wrappers.dart';
import '../../in_app_purchase_ohos.dart';
import '../iap_kit_wrappers/enum_converters.dart';

/// The class represents the information of a purchase made with the IAP Kit
/// AppGallery.
class AppGalleryPurchaseDetails extends PurchaseDetails {
  /// Creates a new AppStore specific purchase details object with the provided
  /// details.
  AppGalleryPurchaseDetails({
    super.purchaseID,
    required super.productID,
    required super.verificationData,
    required super.transactionDate,
    required this.ikPaymentTransaction,
    required PurchaseStatus status,
  }) : super(status: status) {
    this.status = status;
  }

  factory AppGalleryPurchaseDetails.fromIKTransaction(
    IKPaymentTransactionWrapper transaction,
    String base64EncodedReceipt,
  ) {
    print('MethodCallHandlerImpl AppGalleryPurchaseDetails.fromIKTransaction ');
    final AppGalleryPurchaseDetails purchaseDetails = AppGalleryPurchaseDetails(
      productID: transaction.payment.productId,
      purchaseID: transaction.transactionIdentifier,
      ikPaymentTransaction: transaction,
      status: const IKTransactionStatusConverter()
          .toPurchaseStatus(transaction.transactionState, transaction.error),
      transactionDate: transaction.transactionTimeStamp != null
          ? (transaction.transactionTimeStamp! * 1000).toInt().toString()
          : null,
      verificationData: PurchaseVerificationData(
          localVerificationData: transaction.receiptData ?? '',
          serverVerificationData: transaction.receiptData ?? '',
          source: kIAPSource),
    );
    if (purchaseDetails.status == PurchaseStatus.error ||
        purchaseDetails.status == PurchaseStatus.canceled) {
      purchaseDetails.error = IAPError(
        source: kIAPSource,
        code: kPurchaseErrorCode,
        message: transaction.error?.domain ?? '',
        details: transaction.error?.userInfo,
      );
    }
    return purchaseDetails;
  }

  /// Points back to the [IKPaymentTransactionWrapper] which was used to
  /// generate this [AppStorePurchaseDetails] object.
  final IKPaymentTransactionWrapper ikPaymentTransaction;

  late PurchaseStatus _status;

  /// The status that this [PurchaseDetails] is currently on.
  @override
  PurchaseStatus get status => _status;

  @override
  set status(PurchaseStatus status) {
    _pendingCompletePurchase =
        status == PurchaseStatus.purchased || status == PurchaseStatus.restored;
    _status = status;
  }

  bool _pendingCompletePurchase = false;

  @override
  bool get pendingCompletePurchase => _pendingCompletePurchase;

  /// Marks that the platform-specific completion step has already been handled.
  void markCompletePurchaseHandled() {
    _pendingCompletePurchase = false;
  }
}
