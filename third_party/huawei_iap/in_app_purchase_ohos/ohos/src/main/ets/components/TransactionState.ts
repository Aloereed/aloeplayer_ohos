// Copyright (c) 2024 SwanLink (Jiangsu) Technology Development Co., LTD.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.

export enum TransactionState {
  purchasing = 0,
  purchased = 1,
  failed = 2,
  restored = 3,
  deferred = 4,
  unspecified = -1,
}
