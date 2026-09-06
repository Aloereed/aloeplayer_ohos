// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

import 'channel.dart';
import '../iap_kit_wrappers.dart';
import '../in_app_purchase_ohos.dart';

/// [IAPError.code] code for failed purchases.
const String kPurchaseErrorCode = 'purchase_error';

/// [IAPError.code] code for auto-consume failures.
const String kAutoConsumeErrorCode = 'consume_purchase_error';

/// Indicates store front is AppGallery.
const String kIAPSource = 'app_gallery';

/// An [InAppPurchasePlatform] that wraps IAP Kit.
///
/// This translates various `IAP Kit` calls and responses into the
/// generic plugin API.
class InAppPurchaseOhosPlatform extends InAppPurchasePlatform {
  /// Creates an [InAppPurchaseOhosPlatform] object.
  ///
  /// This constructor should only be used for testing, for any other purpose
  /// get the connection from the [instance] getter.
  @visibleForTesting
  InAppPurchaseOhosPlatform();

  static late IKPaymentQueueWrapper _skPaymentQueueWrapper;
  static late _TransactionObserver _observer;
  static final Set<String> _productIdsToAutoConsume = <String>{};

  @override
  Stream<List<PurchaseDetails>> get purchaseStream =>
      _observer.purchaseUpdatedController.stream;

  /// Callback handler for transaction status changes.
  @visibleForTesting
  static IKTransactionObserverWrapper get observer => _observer;

  /// Registers this class as the default instance of [InAppPurchasePlatform].
  static void registerPlatform() {
    // Register the [InAppPurchaseOhosPlatformAddition] containing
    // IapKit-specific functionality.
    InAppPurchasePlatformAddition.instance =
        InAppPurchaseOhosPlatformAddition();

    // Register the platform-specific implementation of the idiomatic
    // InAppPurchase API.
    InAppPurchasePlatform.instance = InAppPurchaseOhosPlatform();

    _skPaymentQueueWrapper = IKPaymentQueueWrapper();

    // Create a purchaseUpdatedController and notify the native side when to
    // start of stop sending updates.
    final StreamController<List<PurchaseDetails>> updateController =
        StreamController<List<PurchaseDetails>>.broadcast(
      onListen: () {
        _startObservingTransactionQueue();
      },
      onCancel: () => _skPaymentQueueWrapper.stopObservingTransactionQueue(),
    );
    _observer = _TransactionObserver(
      updateController,
      _skPaymentQueueWrapper,
      _productIdsToAutoConsume,
    );
    _skPaymentQueueWrapper.setTransactionObserver(observer);
  }

  static Future<void> _startObservingTransactionQueue() async {
    try {
      await _skPaymentQueueWrapper.startObservingTransactionQueue();
      await _observer.syncTransactions();
    } catch (_) {
      // Best-effort replay of unfinished purchases should not fail stream setup.
    }
  }

  @override
  Future<bool> isAvailable() => IKPaymentQueueWrapper.queryEnvironmentStatus();

  IKPaymentWrapper _paymentFromPurchaseParam(PurchaseParam purchaseParam) {
    final ProductType? productType =
        purchaseParam.productDetails is AppGalleryProductDetails
            ? (purchaseParam.productDetails as AppGalleryProductDetails)
                .skProduct
                .type
            : null;
    return IKPaymentWrapper(
      productId: purchaseParam.productDetails.id,
      productType: productType,
      applicationUserName: purchaseParam.applicationUserName,
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    try {
      await _skPaymentQueueWrapper.addPayment(
        _paymentFromPurchaseParam(purchaseParam),
      );
      return true; // There's no error feedback from ohos here to return.
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  }) {
    if (autoConsume) {
      _productIdsToAutoConsume.add(purchaseParam.productDetails.id);
    }
    return buyNonConsumable(purchaseParam: purchaseParam);
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) {
    assert(
      purchase is AppGalleryPurchaseDetails,
      'On ohos, the `purchase` should always be of type `AppGalleryPurchaseDetails`.',
    );

    return _skPaymentQueueWrapper.finishTransaction(
      (purchase as AppGalleryPurchaseDetails).ikPaymentTransaction,
    );
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    return _observer
        .restoreTransactions(
            queue: _skPaymentQueueWrapper,
            applicationUserName: applicationUserName)
        .whenComplete(() => _observer.cleanUpRestoredTransactions());
  }

  @override
  Future<String> countryCode() async =>
      (await channel.invokeMethod<String>('iap#countryCode')) ?? '';

  /// Query the product detail list.
  ///
  /// This method only returns [ProductDetailsResponse].
  /// To get detailed Store Kit product list, use [SkProductResponseWrapper.startProductRequest]
  /// to get the [IKProductResponseWrapper].
  @override
  Future<ProductDetailsResponse> queryProductDetails(
      Set<String> identifiers) async {
    final IKRequestMaker requestMaker = IKRequestMaker();
    IKProductResponseWrapper response;
    PlatformException? exception;
    try {
      response = await requestMaker.startProductRequest(identifiers.toList());
      print('InAppPurchasePlugin productDetailResponse response');
    } on PlatformException catch (e) {
      exception = e;
      response = IKProductResponseWrapper(
          products: const <IKProductWrapper>[],
          invalidProductIdentifiers: identifiers.toList());
    }
    List<AppGalleryProductDetails> productDetails =
        <AppGalleryProductDetails>[];
    productDetails = response.products
        .map((IKProductWrapper productWrapper) =>
            AppGalleryProductDetails.fromIKProduct(productWrapper))
        .toList();
    List<String> invalidIdentifiers = response.invalidProductIdentifiers;
    if (productDetails.isEmpty) {
      invalidIdentifiers = identifiers.toList();
    }
    final ProductDetailsResponse productDetailsResponse =
        ProductDetailsResponse(
      productDetails: productDetails,
      notFoundIDs: invalidIdentifiers,
      error: exception == null
          ? null
          : IAPError(
              source: kIAPSource,
              code: exception.code,
              message: exception.message ?? '',
              details: exception.details),
    );
    return productDetailsResponse;
  }
}

enum _TransactionRestoreState {
  notRunning,
  waitingForTransactions,
  receivedTransaction,
}

class _TransactionObserver implements IKTransactionObserverWrapper {
  _TransactionObserver(
    this.purchaseUpdatedController,
    this._queue,
    this._productIdsToAutoConsume,
  );

  final StreamController<List<PurchaseDetails>> purchaseUpdatedController;
  final IKPaymentQueueWrapper _queue;
  final Set<String> _productIdsToAutoConsume;
  final Set<String> _observedTransactionIds = <String>{};

  Completer<void>? _restoreCompleter;
  late String _receiptData;
  _TransactionRestoreState _transactionRestoreState =
      _TransactionRestoreState.notRunning;

  Future<void> restoreTransactions({
    required IKPaymentQueueWrapper queue,
    String? applicationUserName,
  }) {
    _transactionRestoreState = _TransactionRestoreState.waitingForTransactions;
    final Completer<void> restoreCompleter = Completer<void>();
    _restoreCompleter = restoreCompleter;
    queue
        .restoreTransactions(applicationUserName: applicationUserName)
        .then((_) {
      if (_transactionRestoreState ==
          _TransactionRestoreState.waitingForTransactions) {
        purchaseUpdatedController.add(<PurchaseDetails>[]);
      }
      _transactionRestoreState = _TransactionRestoreState.notRunning;
      if (!restoreCompleter.isCompleted) {
        restoreCompleter.complete();
      }
    }).catchError((Object error, StackTrace stackTrace) {
      _transactionRestoreState = _TransactionRestoreState.notRunning;
      if (!restoreCompleter.isCompleted) {
        restoreCompleter.completeError(error, stackTrace);
      }
    });
    return restoreCompleter.future;
  }

  void cleanUpRestoredTransactions() {
    _transactionRestoreState = _TransactionRestoreState.notRunning;
    _restoreCompleter = null;
  }

  Future<void> syncTransactions() async {
    try {
      final List<IKPaymentTransactionWrapper> transactions =
          await _queue.transactions();
      final List<IKPaymentTransactionWrapper> newTransactions =
          transactions.where(_isUnobservedTransaction).toList();
      if (newTransactions.isEmpty) {
        return;
      }
      _rememberTransactions(newTransactions);
      await _handleTransationUpdates(newTransactions);
    } catch (_) {
      // Native queue replay is best-effort and should not break listeners.
    }
  }

  @override
  void updatedTransactions(
      {required List<IKPaymentTransactionWrapper> transactions}) {
    _rememberTransactions(transactions);
    _handleTransationUpdates(transactions);
  }

  @override
  void removedTransactions(
      {required List<IKPaymentTransactionWrapper> transactions}) {
    _forgetTransactions(transactions);
  }

  bool _isUnobservedTransaction(IKPaymentTransactionWrapper transaction) {
    final String? transactionId = transaction.transactionIdentifier;
    return transactionId == null ||
        transactionId.isEmpty ||
        !_observedTransactionIds.contains(transactionId);
  }

  void _rememberTransactions(List<IKPaymentTransactionWrapper> transactions) {
    for (final IKPaymentTransactionWrapper transaction in transactions) {
      final String? transactionId = transaction.transactionIdentifier;
      if (transactionId == null || transactionId.isEmpty) {
        continue;
      }
      _observedTransactionIds.add(transactionId);
    }
  }

  void _forgetTransactions(List<IKPaymentTransactionWrapper> transactions) {
    for (final IKPaymentTransactionWrapper transaction in transactions) {
      final String? transactionId = transaction.transactionIdentifier;
      if (transactionId == null || transactionId.isEmpty) {
        continue;
      }
      _observedTransactionIds.remove(transactionId);
    }
  }

  Future<String> getReceiptData() async {
    try {
      _receiptData = await IKReceiptManager.retrieveReceiptData();
    } catch (e) {
      _receiptData = '';
    }
    return _receiptData;
  }

  Future<void> _handleTransationUpdates(
      List<IKPaymentTransactionWrapper> transactions) async {
    print('MethodCallHandlerImpl _handleTransationUpdates ');
    if (_transactionRestoreState ==
            _TransactionRestoreState.waitingForTransactions &&
        transactions.any((IKPaymentTransactionWrapper transaction) =>
            transaction.transactionState ==
            IKPaymentTransactionStateWrapper.restored)) {
      _transactionRestoreState = _TransactionRestoreState.receivedTransaction;
    }

    final String receiptData = await getReceiptData();
    final List<PurchaseDetails> purchases = await Future.wait(
      transactions.map((IKPaymentTransactionWrapper transaction) async {
        final AppGalleryPurchaseDetails purchase =
            AppGalleryPurchaseDetails.fromIKTransaction(
          transaction,
          receiptData,
        );
        return _maybeAutoConsumePurchase(purchase);
      }),
    );
    purchaseUpdatedController.add(purchases);
  }

  Future<PurchaseDetails> _maybeAutoConsumePurchase(
    AppGalleryPurchaseDetails purchaseDetails,
  ) async {
    if (purchaseDetails.status != PurchaseStatus.purchased ||
        purchaseDetails.ikPaymentTransaction.payment.productType !=
            ProductType.CONSUMABLE ||
        !_productIdsToAutoConsume.contains(purchaseDetails.productID)) {
      return purchaseDetails;
    }

    try {
      await _queue.finishTransaction(purchaseDetails.ikPaymentTransaction);
      purchaseDetails.markCompletePurchaseHandled();
    } on PlatformException catch (error) {
      purchaseDetails.status = PurchaseStatus.error;
      purchaseDetails.error = IAPError(
        source: kIAPSource,
        code: kAutoConsumeErrorCode,
        message: error.message ?? error.code,
        details: error.details,
      );
    } catch (error) {
      purchaseDetails.status = PurchaseStatus.error;
      purchaseDetails.error = IAPError(
        source: kIAPSource,
        code: kAutoConsumeErrorCode,
        message: error.toString(),
      );
    } finally {
      _productIdsToAutoConsume.remove(purchaseDetails.productID);
    }

    return purchaseDetails;
  }
}
