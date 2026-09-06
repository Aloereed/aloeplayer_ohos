// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/services.dart';

import '../channel.dart';
import 'ik_product_wrapper.dart';

/// A request maker that handles all the requests made by IKRequest subclasses.
class IKRequestMaker {
  /// Fetches product information for a list of given product identifiers.
  ///
  /// The `productIdentifiers` should contain legitimate product identifiers that you declared for the products in the iTunes Connect. Invalid identifiers
  /// will be stored and returned in [SkProductResponseWrapper.invalidProductIdentifiers]. Duplicate values in `productIdentifiers` will be omitted.
  /// If `productIdentifiers` is null, an `storekit_invalid_argument` error will be returned. If `productIdentifiers` is empty, a [SkProductResponseWrapper]
  /// will still be returned with [SkProductResponseWrapper.products] being null.
  ///
  /// [SkProductResponseWrapper] is returned if there is no error during the request.
  /// A [PlatformException] is thrown if the platform code making the request fails.
  Future<IKProductResponseWrapper> startProductRequest(
      List<String> productIdentifiers) async {
    final Map<String, dynamic>? productResponseMap =
        await channel.invokeMapMethod<String, dynamic>(
      'iap#queryProducts',
      productIdentifiers,
    );
    if (productResponseMap == null) {
      throw PlatformException(
        code: 'storekit_no_response',
        message: 'StoreKit: Failed to get response from platform.',
      );
    }
    return IKProductResponseWrapper.fromJson(productResponseMap);
  }

  Future<void> startRefreshReceiptRequest(
      {Map<String, dynamic>? receiptProperties}) {
    return channel.invokeMethod<void>(
      'iap#refreshReceipt',
      receiptProperties,
    );
  }
}
