// Copyright (c) 2024 SwanLink (Jiangsu) Technology Development Co., LTD.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.

import { iap } from '@kit.IAPKit'
import { deviceInfo } from '@kit.BasicServicesKit';

export const ProductType: Array<iap.ProductType> = deviceInfo.sdkApiVersion >= 14 ? [
  iap.ProductType.CONSUMABLE,
  iap.ProductType.NONCONSUMABLE,
  iap.ProductType.AUTORENEWABLE,
  iap.ProductType.NONRENEWABLE
] : [
  iap.ProductType.CONSUMABLE,
  iap.ProductType.NONCONSUMABLE,
  iap.ProductType.AUTORENEWABLE,
  iap.ProductType.NONRENEWABLE
]