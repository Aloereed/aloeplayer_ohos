// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import '../channel.dart';

// ignore: avoid_classes_with_only_static_members
/// This class contains static methods to manage StoreKit receipts.
class IKReceiptManager {
  /// Retrieve the receipt data from your application's main bundle.
  static Future<String> retrieveReceiptData() async {
    return (await channel.invokeMethod<String>(
            'iap#retrieveReceiptData')) ??
        '';
  }
}
