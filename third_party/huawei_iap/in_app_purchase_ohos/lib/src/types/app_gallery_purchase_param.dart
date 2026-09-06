// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

/// Apple AppStore specific parameter object for generating a purchase.
class AppGalleryPurchaseParam extends PurchaseParam {
  /// Creates a new [AppGalleryPurchaseParam] object with the given data.
  AppGalleryPurchaseParam({
    required super.productDetails,
    super.applicationUserName,
    this.quantity = 1,
  });

  /// Quantity of the product user requested to buy.
  final int quantity;
}
