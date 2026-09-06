// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

import '../../iap_kit_wrappers.dart';

/// The class represents the information of a product as registered in the AppGallery Connect
/// AppGallery.
class AppGalleryProductDetails extends ProductDetails {
  /// Creates a new AppStore specific product details object with the provided
  /// details.
  AppGalleryProductDetails({
    required super.id,
    required super.title,
    required super.description,
    required super.price,
    required super.rawPrice,
    required super.currencyCode,
    required this.skProduct,
    required super.currencySymbol,
  });

  factory AppGalleryProductDetails.fromIKProduct(IKProductWrapper product) {
    return AppGalleryProductDetails(
      id: product.id,
      title: product.name,
      description: product.description,
      price: product.localPrice,
      rawPrice: product.microPrice / 1000000.0,
      currencyCode: product.currency,
      currencySymbol: product.localPrice.isNotEmpty
          ? product.localPrice.replaceAll(RegExp(r'[0-9.]+'), "")
          : product.currency,
      skProduct: product,
    );
  }

  /// Points back to the [IKProductWrapper] object that was used to generate
  /// this [AppGalleryProductDetails] object.
  final IKProductWrapper skProduct;
}
