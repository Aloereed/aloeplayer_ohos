// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

import '../iap_kit_wrappers.dart';
import '../in_app_purchase_ohos.dart';

/// Contains InApp Purchase features that are only available on ohos.
class InAppPurchaseOhosPlatformAddition
    extends InAppPurchasePlatformAddition {

  /// Retry loading purchase data after an initial failure.
  ///
  /// If no results, a `null` value is returned.
  Future<PurchaseVerificationData?> refreshPurchaseVerificationData() async {
    await IKRequestMaker().startRefreshReceiptRequest();
    try {
      final String receipt = await IKReceiptManager.retrieveReceiptData();
      return PurchaseVerificationData(
          localVerificationData: receipt,
          serverVerificationData: receipt,
          source: kIAPSource);
    } catch (e) {
      // ignore: avoid_print
      print(
          'Something is wrong while fetching the receipt, this normally happens when the app is '
          'running on a simulator: $e');
      return null;
    }
  }
}
