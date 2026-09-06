// Copyright (c) 2024 SwanLink (Jiangsu) Technology Development Co., LTD.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.

import { Any } from '@ohos/flutter_ohos';

export class PurchaseOrderPayload {
  applicationId: string = '';
  countryCode: string = '';
  environment: string = '';
  payOrderId: string = '';
  price: number = 0;
  productId: string = '';
  productType: number = 0;
  purchaseOrderId: string = '';
  purchaseTime: number = 0;
  purchaseToken: string = '';
  signedTime: number = 0;
}

export class PurchaseSubGroupStatusPayload {
  environment: string = '';
  applicationId: string = '';
  packageName: string = '';
  subGroupId: string = '';
  lastSubscriptionStatus?: PurchaseSubscriptionStatus;
  historySubscriptionStatusList?: Any[] = [];
}

export class PurchaseSubscriptionStatus {
  subGroupGenerationId: string = '';
  subscriptionId: string = '';
  purchaseToken: string = '';
  status: string = '';
  expiresTime: number = 0;
  lastPurchaseOrder?: Any = {};
  recentPurchaseOrderList?: Any[] = [];
  renewalInfo?: Any = {};
}