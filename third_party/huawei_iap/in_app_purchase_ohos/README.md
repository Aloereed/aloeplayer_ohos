# in_app_purchase_ohos

本项目基于 [in_app_purchase](https://pub.dev/packages/in_app_purchase) 开发。

## 简介

in_app_purchase_ohos 是 in_app_purchase 在 OpenHarmony 平台上的 federated implementation。插件底层对接 OpenHarmony IAP Kit，并将购买能力映射为 Flutter 统一的内购接口。对业务应用来说，通常只需要依赖 in_app_purchase，在 OHOS 平台构建时会自动接入当前实现；只有在调试平台实现或需要使用平台扩展 API 时，才需要直接依赖 in_app_purchase_ohos。

## 下载安装

进入到工程目录并在 pubspec.yaml 中添加以下依赖，推荐业务应用优先依赖应用层包 in_app_purchase：

```yaml
dependencies:
  in_app_purchase:
    git:
      url: https://gitcode.com/CPF-Flutter/flutter_packages.git
      path: packages/in_app_purchase/in_app_purchase
      # ref: in_app_purchase_v3.2.3-ohos-1.0.1
      ref: TAG  #   请根据下方TAG版本对应表选择TAG
```

如果需要直接调试 OHOS 平台实现，或需要调用平台扩展 API，也可以直接依赖当前包：

```yaml
dependencies:
  in_app_purchase_ohos:
    git:
      url: https://gitcode.com/CPF-Flutter/flutter_packages.git
      path: packages/in_app_purchase/in_app_purchase_ohos
      # ref: in_app_purchase_v3.2.3-ohos-1.0.1
      ref: TAG  #   请根据下方TAG版本对应表选择TAG
```

执行命令

```bash
flutter pub get
```

**TAG 版本对应表**

| Flutter 框架版本 | TAG1 | TAG2 | 分支 |
| :--- | :--- | :--- | :--- |
| 3.41 | `-` | `in_app_purchase_v3.2.3-ohos-1.0.1` | `br_in_app_purchase-v3.2.3_ohos` |
| 3.35 | `-` | `in_app_purchase_v3.2.3-ohos-1.0.1` | `br_in_app_purchase-v3.2.3_ohos` |
| 3.27 | `-` | `in_app_purchase_v3.2.3-ohos-1.0.1` | `br_in_app_purchase-v3.2.3_ohos` |
| 3.22 | `-` | `in_app_purchase_v3.2.0-ohos-1.0.1` | `br_in_app_purchase-v3.2.0_ohos` |
| 3.7 | `-` | `in_app_purchase_v3.1.11-ohos-1.0.1` | `master` |

## 约束与限制

### 兼容性

在以下版本中已测试通过

1. Flutter: 3.35.8-ohos-0.0.3; SDK: 5.0.2(14); IDE: DevEco Studio: 6.1.2.268; ROM: 6.1.0.117;
2. Flutter: 3.41.10-ohos-0.0.1; SDK: 5.0.2(14); IDE: DevEco Studio: 6.1.1.268; ROM: 6.1.0.117;

### 前置条件

- 需要在 AppGallery Connect 中创建商品，并保证商品 ID 与代码中的查询 ID 完全一致。
- 需要完成应用签名、包名、支付环境和测试账号配置，否则 isAvailable 可能返回 false，或 queryProductDetails 返回 notFoundIDs。
- 需要设备具备可用的 IAP Kit / AppGallery 支付环境。

### 权限要求

插件模块本身未在 HAR 中声明额外权限；示例应用在 entry module 中声明了 ohos.permission.INTERNET。业务应用如果未具备联网权限，请在 entry/src/main/module.json5 中添加：

```json5
"requestPermissions": [
  {"name": "ohos.permission.INTERNET"}
]
```

## 使用示例

通过 in_app_purchase 使用统一接口，以下片段展示了最常见的商品查询与发起购买流程：

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

如果你是直接依赖 in_app_purchase_ohos，可在应用启动阶段手动注册平台实现：

```dart
import 'package:flutter/widgets.dart';
import 'package:in_app_purchase_ohos/in_app_purchase_ohos.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  InAppPurchaseOhosPlatform.registerPlatform();
  runApp(const Placeholder());
}
```

读取 OHOS 平台扩展收据数据示例：

> 当前 OHOS 原生侧尚未实现 `iap#refreshReceipt` 与有效收据返回，`refreshPurchaseVerificationData` 目前仅保留 Dart 层入口，不能视为可用的生产能力。以下代码仅用于说明接口形态。

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

## 使用说明

### 1. 初始化购买监听

在应用初始化阶段尽早订阅 purchaseStream，避免漏掉前一会话残留的购买更新。若应用直接依赖 in_app_purchase_ohos，则需要先调用 InAppPurchaseOhosPlatform.registerPlatform() 完成平台注册。

### 2. 检查支付环境

调用 isAvailable 确认当前设备支付环境可用后，再执行商品查询和购买流程。

### 3. 查询商品

使用 queryProductDetails 查询商品详情，传入的商品 ID 必须与 AppGallery Connect 中配置保持一致；若返回 productDetails 为空或 notFoundIDs 非空，请优先检查商品状态、测试账号和环境配置。

### 4. 发起与完成购买

可通过 buyNonConsumable 或 buyConsumable 发起购买。购买前应先完成商品查询以建立商品缓存。消耗型商品现已支持 autoConsume = true 和 autoConsume = false 两条路径；当 autoConsume = true 时，插件会在分发 purchased 更新前自动 finish 对应消耗型交易；当 autoConsume = false 时，购买结果会以 pendingCompletePurchase = true 的状态返回，待业务完成发货后再调用 completePurchase。completePurchase 现在会按传入的 transactionIdentifier 精确匹配并结束对应未完成订单。OHOS 实现同时已经识别 ProductType.NONRENEWABLE，并将其贯通到商品查询、购买、恢复和完成购买链路。

### 5. 读取平台扩展数据

InAppPurchaseOhosPlatformAddition.refreshPurchaseVerificationData 会触发 OHOS 原生侧的 iap#refreshReceipt，刷新并返回最近一次可用的 JWS 载荷作为 verificationData。该返回值为 best-effort，可能为空，且在不同 IAP 运行时对 NONRENEWABLE 的支持存在差异，因此不应作为生产环境验签的唯一依据。

## 接口说明

### API

> [!TIP]
> ohos Support 列为 yes 表示当前 OHOS 平台支持该接口，no 表示当前未支持。

#### 统一接口

| 名称 | 类型 | 参数类型 | 返回值 | ohos Support | 描述 |
| ---- | ---- | -------- | ------ | ------------ | ---- |
| purchaseStream | 属性 | / | Stream<List<PurchaseDetails>> | yes | 支持当前购买流程更新、恢复回调，并会在首个监听器建立时回放上一应用会话遗留的未完成订单。 |
| isAvailable() | 方法 | / | Future<bool> | yes | 检查当前设备是否具备可用支付环境。 |
| queryProductDetails() | 方法 | Set<String> identifiers | Future<ProductDetailsResponse> | yes | 查询商品信息并返回 ProductDetailsResponse。 |
| buyNonConsumable() | 方法 | PurchaseParam purchaseParam | Future<bool> | yes | 发起非消耗型商品购买；依赖已完成商品查询并建立商品缓存。 |
| buyConsumable() | 方法 | PurchaseParam purchaseParam, bool autoConsume = true | Future<bool> | yes | 发起消耗型商品购买；支持 autoConsume = true 和 autoConsume = false，两者共用统一下单链路。 |
| completePurchase() | 方法 | PurchaseDetails purchase | Future<void> | yes | 精确结束与传入 transactionIdentifier 匹配的未完成交易。 |
| restorePurchases() | 方法 | String? applicationUserName | Future<void> | yes | 通过 purchaseStream 恢复非消耗型、自动续期订阅和 NONRENEWABLE 订单。 |
| countryCode() | 方法 | / | Future<String> | yes | 返回 i18n.System.getSystemRegion() 作为 best-effort 国家码兜底值。 |

#### 平台扩展接口与类型

| 名称 | 类型 | 参数类型 | 返回值 | ohos Support | 描述 |
| ---- | ---- | -------- | ------ | ------------ | ---- |
| InAppPurchaseOhosPlatform.registerPlatform() | 静态方法 | / | void | yes | 手动将 OHOS 平台实现注册为默认实例。 |
| InAppPurchaseOhosPlatformAddition.refreshPurchaseVerificationData() | 方法 | / | Future<PurchaseVerificationData?> | yes | 触发 iap#refreshReceipt 并返回最新可用的 verificationData（best-effort，可能为空）。 |

## 遗留问题

- 订阅升级降级、兑换码等平台特有购买场景暂未支持。
- ohos侧countryCode返回的国家码和其它平台来源不一致，因为iap接口无法获取计费地区，因此使用系统地区作为兜底。

## 目录结构

```text
|---- example                     # 多平台示例应用
|     |---- integration_test      # 集成测试
|     |---- lib                   # 示例代码
|     |---- ohos                  # 示例 OpenHarmony 工程
|---- lib                         # Dart 入口与平台封装
|     |---- src                   # 平台实现、通道与类型定义
|     |---- iap_kit_wrappers.dart # IAP Kit 封装统一入口
|     |---- in_app_purchase_ohos.dart # 库主入口文件
|---- ohos                        # OpenHarmony 原生适配代码
|---- readme                      # 文档模板与说明材料
|---- CHANGELOG.md                # 更新日志
|---- README.md                   # 中文说明文档
|---- README.en.md                # 英文说明文档
|---- pubspec.yaml                # 配置文件
```

## 贡献代码

使用过程中发现任何问题都可以提 [Issue](https://gitcode.com/CPF-Flutter/flutter_packages/issues)，也欢迎提交 [PR](https://gitcode.com/CPF-Flutter/flutter_packages/pulls) 共建。

## 开源协议

本项目基于 [Apache 2.0 License](LICENSE)。
