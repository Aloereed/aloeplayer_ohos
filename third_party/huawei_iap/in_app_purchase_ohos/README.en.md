# in_app_purchase_ohos

This project is developed based on [in_app_purchase](https://pub.dev/packages/in_app_purchase).

## Introduction

in_app_purchase_ohos is the federated implementation of in_app_purchase on the OpenHarmony platform. The plugin underlyingly integrates with the OpenHarmony IAP Kit and maps purchase capabilities to Flutter's unified in-app purchase interface. For business applications, typically you only need to depend on in_app_purchase; the current implementation will be automatically integrated at build time on OHOS. Only when debugging the platform implementation or using platform extension APIs do you need to directly depend on in_app_purchase_ohos.

## Installation

Enter the project directory and add the following dependency in pubspec.yaml. It is recommended that business applications prefer depending on the application-layer package in_app_purchase:

```yaml
dependencies:
  in_app_purchase:
    git:
      url: https://gitcode.com/CPF-Flutter/flutter_packages.git
      path: packages/in_app_purchase/in_app_purchase
      # ref: in_app_purchase_v3.2.3-ohos-1.0.1
      ref: TAG  #   Please select the TAG according to the TAG version table below
```

If you need to directly debug the OHOS platform implementation, or need to call platform extension APIs, you can also directly depend on this package:

```yaml
dependencies:
  in_app_purchase_ohos:
    git:
      url: https://gitcode.com/CPF-Flutter/flutter_packages.git
      path: packages/in_app_purchase/in_app_purchase_ohos
      # ref: in_app_purchase_v3.2.3-ohos-1.0.1
      ref: TAG  #   Please select the TAG according to the TAG version table below
```

Run the command

```bash
flutter pub get
```

**TAG Version Table**

| Flutter Version | TAG1 | TAG2 | Branch |
| :--- | :--- | :--- | :--- |
| 3.41 | `-` | `in_app_purchase_v3.2.3-ohos-1.0.1` | `br_in_app_purchase-v3.2.3_ohos` |
| 3.35 | `-` | `in_app_purchase_v3.2.3-ohos-1.0.1` | `br_in_app_purchase-v3.2.3_ohos` |
| 3.27 | `-` | `in_app_purchase_v3.2.3-ohos-1.0.1` | `br_in_app_purchase-v3.2.3_ohos` |
| 3.22 | `-` | `in_app_purchase_v3.2.0-ohos-1.0.1` | `br_in_app_purchase-v3.2.0_ohos` |
| 3.7 | `-` | `in_app_purchase_v3.1.11-ohos-1.0.1` | `master` |

## Constraints and Limitations

### Compatibility

Tested and passed on the following versions

1. Flutter: 3.35.8-ohos-0.0.3; SDK: 5.0.2(14); IDE: DevEco Studio: 6.1.2.268; ROM: 6.1.0.117;
2. Flutter: 3.41.10-ohos-0.0.1; SDK: 5.0.2(14); IDE: DevEco Studio: 6.1.1.268; ROM: 6.1.0.117;

### Prerequisites

- You need to create products in AppGallery Connect and ensure that the product IDs are exactly consistent with the query IDs in the code.
- You need to complete application signing, package name, payment environment, and test account configuration; otherwise isAvailable may return false, or queryProductDetails may return notFoundIDs.
- The device needs to have a usable IAP Kit / AppGallery payment environment.

### Permission Requirements

The plugin module itself does not declare additional permissions in the HAR; the example application declares ohos.permission.INTERNET in the entry module. If your business application does not have network permission, please add it in entry/src/main/module.json5:

```json5
"requestPermissions": [
  {"name": "ohos.permission.INTERNET"}
]
```

## Usage Example

Use the unified interface through in_app_purchase. The following snippet shows the most common product query and purchase initiation flow:

```dart
import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

final InAppPurchase _inAppPurchase = InAppPurchase.instance;
late final StreamSubscription<List<PurchaseDetails>> _subscription;

Future<void> initIap() async {
  _subscription = _inAppPurchase.purchaseStream.listen(
    (List<PurchaseDetails> purchases) {
      for (final PurchaseDetails purchase in purchases) {
        if (purchase.status == PurchaseStatus.purchased &&
            purchase.pendingCompletePurchase) {
          _inAppPurchase.completePurchase(purchase);
        }
      }
    },
  );

  final bool available = await _inAppPurchase.isAvailable();
  if (!available) {
    return;
  }

  final ProductDetailsResponse response =
      await _inAppPurchase.queryProductDetails({'consumable', 'upgrade'});
  if (response.productDetails.isEmpty) {
    return;
  }

  final ProductDetails product = response.productDetails.first;
  await _inAppPurchase.buyConsumable(
    purchaseParam: PurchaseParam(productDetails: product),
  );
}
```

If you are directly depending on in_app_purchase_ohos, you can manually register the platform implementation during the application startup phase:

```dart
import 'package:flutter/widgets.dart';
import 'package:in_app_purchase_ohos/in_app_purchase_ohos.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  InAppPurchaseOhosPlatform.registerPlatform();
  runApp(const Placeholder());
}
```

Example of reading OHOS platform extension receipt data:

> Currently, the OHOS native side has not yet implemented `iap#refreshReceipt` and valid receipt return. `refreshPurchaseVerificationData` currently only retains the Dart-layer entry point and cannot be considered a usable production capability. The following code is only for illustrating the interface shape.

```dart
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:in_app_purchase_ohos/in_app_purchase_ohos.dart';

Future<void> refreshReceipt() async {
  final InAppPurchaseOhosPlatformAddition addition =
      InAppPurchasePlatformAddition.instance
          as InAppPurchaseOhosPlatformAddition;
  final PurchaseVerificationData? data =
      await addition.refreshPurchaseVerificationData();
  if (data == null) {
    return;
  }
  print(data.serverVerificationData);
}
```

## Usage Instructions

### 1. Initialize Purchase Listening

Subscribe to purchaseStream as early as possible during application initialization to avoid missing purchase updates from a previous session. If the application directly depends on in_app_purchase_ohos, you need to first call InAppPurchaseOhosPlatform.registerPlatform() to complete platform registration.

### 2. Check Payment Environment

Call isAvailable to confirm that the current device's payment environment is available before performing product queries and purchase flows.

### 3. Query Products

Use queryProductDetails to query product details. The product IDs passed in must be consistent with those configured in AppGallery Connect; if productDetails is empty or notFoundIDs is non-empty, please first check the product status, test account, and environment configuration.

### 4. Initiate and Complete Purchase

You can initiate purchases via buyNonConsumable or buyConsumable. Before purchasing, you should complete the product query to establish the product cache. Consumable products now support both autoConsume = true and autoConsume = false paths; when autoConsume = true, the plugin will automatically finish the corresponding consumable transaction before distributing the purchased update; when autoConsume = false, the purchase result will be returned with pendingCompletePurchase = true, and the business should call completePurchase after delivery is completed. completePurchase now precisely matches and ends the corresponding unfinished order based on the passed transactionIdentifier. The OHOS implementation has also identified ProductType.NONRENEWABLE and threads it through the product query, purchase, restore, and complete purchase links.

### 5. Read Platform Extension Data

InAppPurchaseOhosPlatformAddition.refreshPurchaseVerificationData will trigger iap#refreshReceipt on the OHOS native side, refreshing and returning the most recent available JWS payload as verificationData. This return value is best-effort and may be empty, and support for NONRENEWABLE varies across IAP runtimes, so it should not be used as the sole basis for production-environment signature verification.

## Interface Description

### API

> [!TIP]
> The ohos Support column marked yes indicates that the current OHOS platform supports this interface; no indicates that it is not currently supported.

#### Unified Interface

| Name | Type | Parameter Type | Return Value | ohos Support | Description |
| ---- | ---- | -------- | ------ | ------------ | ---- |
| purchaseStream | Property | / | Stream<List<PurchaseDetails>> | yes | Supports current purchase flow updates, restore callbacks, and replays unfinished orders left over from the previous application session when the first listener is established. |
| isAvailable() | Method | / | Future<bool> | yes | Checks whether the current device has a usable payment environment. |
| queryProductDetails() | Method | Set<String> identifiers | Future<ProductDetailsResponse> | yes | Queries product information and returns a ProductDetailsResponse. |
| buyNonConsumable() | Method | PurchaseParam purchaseParam | Future<bool> | yes | Initiates a non-consumable product purchase; depends on a completed product query and established product cache. |
| buyConsumable() | Method | PurchaseParam purchaseParam, bool autoConsume = true | Future<bool> | yes | Initiates a consumable product purchase; supports autoConsume = true and autoConsume = false, both sharing the unified order placement link. |
| completePurchase() | Method | PurchaseDetails purchase | Future<void> | yes | Precisely ends the unfinished transaction matching the passed transactionIdentifier. |
| restorePurchases() | Method | String? applicationUserName | Future<void> | yes | Restores non-consumable, auto-renewable subscription, and NONRENEWABLE orders via purchaseStream. |
| countryCode() | Method | / | Future<String> | yes | Returns i18n.System.getSystemRegion() as the best-effort country code fallback value. |

#### Platform Extension Interfaces and Types

| Name | Type | Parameter Type | Return Value | ohos Support | Description |
| ---- | ---- | -------- | ------ | ------------ | ---- |
| InAppPurchaseOhosPlatform.registerPlatform() | Static Method | / | void | yes | Manually registers the OHOS platform implementation as the default instance. |
| InAppPurchaseOhosPlatformAddition.refreshPurchaseVerificationData() | Method | / | Future<PurchaseVerificationData?> | yes | Triggers iap#refreshReceipt and returns the latest available verificationData (best-effort, may be empty). |

## Known Issues

- Subscription upgrade/downgrade, redemption codes, and other platform-specific purchase scenarios are not yet supported.
- The country code returned by countryCode on the OHOS side is inconsistent with sources on other platforms, because the iap interface cannot obtain the billing region, so the system region is used as a fallback.

## Directory Structure

```text
|---- example                     # Multi-platform example application
|     |---- integration_test      # Integration tests
|     |---- lib                   # Example code
|     |---- ohos                  # Example OpenHarmony project
|---- lib                         # Dart entry and platform encapsulation
|     |---- src                   # Platform implementation, channels, and type definitions
|     |---- iap_kit_wrappers.dart # IAP Kit unified encapsulation entry
|     |---- in_app_purchase_ohos.dart # Library main entry file
|---- ohos                        # OpenHarmony native adaptation code
|---- readme                      # Document templates and explanatory materials
|---- CHANGELOG.md                # Update log
|---- README.md                   # Chinese documentation
|---- README.en.md                # English documentation
|---- pubspec.yaml                # Configuration file
```

## Contributing

If you encounter any issues during use, feel free to submit an [Issue](https://gitcode.com/CPF-Flutter/flutter_packages/issues). You are also welcome to submit a [PR](https://gitcode.com/CPF-Flutter/flutter_packages/pulls) to contribute.

## Open Source License

This project is based on [Apache 2.0 License](LICENSE).
