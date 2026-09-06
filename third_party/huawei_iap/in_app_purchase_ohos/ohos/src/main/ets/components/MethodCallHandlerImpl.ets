/*
* Copyright (c) 2024 SwanLink (Jiangsu) Technology Development Co., LTD.
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import { MethodCall, MethodCallHandler, MethodChannel, MethodResult, Log, Any } from '@ohos/flutter_ohos';
import { MethodNames } from './MethodNames';
import { iap } from '@kit.IAPKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import i18n from '@ohos.i18n';
import { ProductType } from './ProductType';
import { JWTUtil } from '../common/JWTUtil';
import { PurchaseOrderPayload, PurchaseSubGroupStatusPayload } from './PurchaseOrderPayload';
import { HashMap } from '@kit.ArkTS';
import { TransactionState } from './TransactionState';
import { PurchaseData } from './PurchaseData';
import { ObjToMap } from '../common/TsUtil';
import { deviceInfo } from '@kit.BasicServicesKit';

const TAG = "MethodCallHandlerImpl"

interface QueryPurchaseResultLike {
  purchaseDataList?: string[]
  continuationToken?: string
  nextPageToken?: string
}

interface QueryPurchasesParameterCompat extends iap.QueryPurchasesParameter {
  continuationToken?: string
}

export class IKError {
  code: number = 0
  domain: string = ''
  userInfo: Map<String, Any> = new Map()
}

export class MethodCallHandlerImpl implements MethodCallHandler {
  private context: common.UIAbilityContext | null = null
  private methodChannel: MethodChannel
  private observer: MethodChannel | null = null
  private productDetailsMap: HashMap<string, iap.Product> = new HashMap()
  private latestVerificationData: string = ''
  private latestVerificationDataUpdateSeq: number = 0
  private verificationDataUpdateSeqSeed: number = 0

  private isUnsupportedNonrenewableTypeError(
    productType: iap.ProductType,
    err: BusinessError,
  ): boolean {
     if (deviceInfo.sdkApiVersion < 14) {
 	       console.error('Verification is required on devices with an API level of 14 or higher.')
 	     }
    return productType === iap.ProductType.NONRENEWABLE && err.code === 401
  }

  constructor(context: common.Context, methodChannel: MethodChannel) {
    this.methodChannel = methodChannel
  }

  setContext(context: common.UIAbilityContext | null) {
    this.context = context
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'aloeManageSubscriptions':
        iap.showManagedSubscriptions(this.context, { windowScreenMode: iap.WindowScreenMode.DIALOG_BOX })
          .then(() => result.success(null))
          .catch((error: BusinessError) => result.error(String(error.code), 'Subscription management unavailable', null));
        break;
      case MethodNames.START_OBSERVING_TRANSACTION_QUEUE:
        this.startObserver()
        break;
      case MethodNames.STOP_OBSERVING_TRANSACTION_QUEUE:
        this.stopObserver()
        break;
      case MethodNames.TRANSACTIONS:
        void this.transactions(result)
        break;
      case MethodNames.QUERY_ENVIRONMENT_STATUS:
        this.isFeatureSupported(result)
        break;
      case MethodNames.COUNTRY_CODE:
        result.success(i18n.System.getSystemRegion())
        break;
      case MethodNames.QUERY_PRODUCTS:
        let productList: Array<string> = call.args as Array<string> ?? []
        this.queryProductDetails(productList, result)
        break;
      case MethodNames.CREATE_PURCHASE:
        this.purchaseGoods(call.args, result)
        break;
      case MethodNames.RETRIEVE_RECEIPT_DATA:
        result.success(this.latestVerificationData)
        break;
      case MethodNames.REFRESH_RECEIPT:
        void this.refreshReceipt(result)
        break;
      case MethodNames.FINISH_PURCHASE:
        this.iapFinishPurchase(call, result)
        break;
      case MethodNames.RESTORE_TRANSACTIONS:
        void this.restoreTransactions(result)
        break;
      default:
        result.notImplemented();
    }
  }

  isFeatureSupported(result: MethodResult): void {
    try {
      iap.queryEnvironmentStatus(this.context).then(() => {
        result.success(true);
      }).catch((err: BusinessError) => {
        Log.e(TAG, `Failed to query environment status. Code is ${err.code}, message is ${err.message}`);
        result.success(false);
      })
    } catch (e) {
      Log.e(TAG, `Failed to query environment status. err: ${JSON.stringify(e)}`);
      result.success(false);
    }
  }

  queryProductDetails(list: Array<string>, result: MethodResult) {
    let productList: Array<Map<string, Object>> = []
    let count: number = 0
    let validProductsList: Array<string> = []
    let invalidProductIdentifiers: Array<string> = []
    let firstError: BusinessError | null = null
    ProductType.forEach((type) => {
      const queryProductParam: iap.QueryProductsParameter = {
        productType: type,
        productIds: list
      };
      iap.queryProducts(this.context, queryProductParam).then((result) => {
        let resultTemp = result.map((value) => {
          validProductsList.push(value.id)
          this.productDetailsMap.set(value.id, value)
          return ObjToMap(value)
        })
        productList.push(...resultTemp)
      }).catch((err: BusinessError) => {
        Log.e(TAG, `Failed to query products of type ${type}. Code is ${err.code}, message is ${err.message}`);
        if (!firstError) {
          firstError = err
        }
      }).finally(() => {
        count++
        if (count === ProductType.length) {
          // A product belongs to one type. Failed probes for the other types
          // must not discard products returned by a successful query.
          if (firstError && productList.length === 0) {
            result.error('' + firstError.code, firstError.message, firstError)
            return
          }

          let productDetailsResponse: HashMap<String, Object> = new HashMap()
          productDetailsResponse.set('products', productList)
          list.forEach((id) => {
            if (!validProductsList.includes(id)) {
              invalidProductIdentifiers.push(id)
            }
          })
          productDetailsResponse.set('invalidProductIdentifiers', invalidProductIdentifiers)
          result.success(productDetailsResponse)
        }
      })
    })
  }

  purchaseGoods(args: Any, result: MethodResult) {
    let map: Map<string, Object> = args as Map<string, Object>
    let id: string = map.get('productId') as string
    // 拉起支付接口前更新状态为支付中
    let mapRes: Map<string, Any> = new Map()
    mapRes.set('payment', args)
    mapRes.set('transactionState', TransactionState.purchasing)
    this.observer?.invokeMethod('updatedTransactions', [mapRes])
    this.createPurchase(id, map, result)
  }

  private extractVerificationData(purchaseData: string): string {
    try {
      let purchaseDataObj: PurchaseData = JSON.parse(purchaseData) as PurchaseData
      if (purchaseDataObj.jwsPurchaseOrder && purchaseDataObj.jwsPurchaseOrder.length > 0) {
        return purchaseDataObj.jwsPurchaseOrder
      }
      if (purchaseDataObj.jwsSubscriptionStatus && purchaseDataObj.jwsSubscriptionStatus.length > 0) {
        return purchaseDataObj.jwsSubscriptionStatus
      }
    } catch (err) {
      Log.e(TAG, `Failed to extract verification data. err: ${JSON.stringify(err)}`)
    }
    return purchaseData
  }

  private beginVerificationDataUpdateScope(): number {
    this.verificationDataUpdateSeqSeed += 1
    return this.verificationDataUpdateSeqSeed
  }

  private updateLatestVerificationData(purchaseData: string, updateSeq: number): void {
    let verificationData = this.extractVerificationData(purchaseData)
    if (verificationData.length > 0 && updateSeq >= this.latestVerificationDataUpdateSeq) {
      this.latestVerificationDataUpdateSeq = updateSeq
      this.latestVerificationData = verificationData
    }
  }

  private buildPaymentMap(productId: string, productType: iap.ProductType): Map<string, Object> {
    let payment: Map<string, Object> = new Map()
    payment.set('productId', productId)
    payment.set('productType', productType)
    return payment
  }

  private buildTransactionMap(
    payment: Map<string, Object>,
    transactionState: TransactionState,
    purchaseOrderId?: string,
    purchaseToken?: string,
    purchaseTime?: number,
    receiptData?: string,
  ): Map<string, Object> {
    let transaction: Map<string, Object> = new Map()
    if (receiptData) transaction.set('receiptData', receiptData)
    transaction.set('payment', payment)
    transaction.set('transactionState', transactionState)
    if (purchaseOrderId && purchaseOrderId.length > 0) {
      transaction.set('transactionIdentifier', purchaseOrderId)
      transaction.set('purchaseOrderId', purchaseOrderId)
    }
    if (purchaseToken && purchaseToken.length > 0) {
      transaction.set('purchaseToken', purchaseToken)
    }
    if (purchaseTime && purchaseTime > 0) {
      transaction.set('transactionTimeStamp', purchaseTime / 1000)
    }
    return transaction
  }

  private buildTransactionMapFromPurchaseData(
    purchaseData: string,
    transactionState: TransactionState,
    paymentOverride?: Map<string, Object>,
  ): Map<string, Object> | null {
    try {
      let purchaseDataObj: PurchaseData = JSON.parse(purchaseData) as PurchaseData
      if (paymentOverride) {
        paymentOverride.set('productType', purchaseDataObj.type as iap.ProductType)
      }
      if (purchaseDataObj.type == iap.ProductType.AUTORENEWABLE) {
        let jwsSubscriptionStatus = purchaseDataObj.jwsSubscriptionStatus
        if (!jwsSubscriptionStatus) {
          Log.e(TAG, 'Missing jwsSubscriptionStatus while building transaction map.')
          return null
        }
        let purchaseStr = JWTUtil.decodeJwtObj(jwsSubscriptionStatus)
        let purchaseOrderPayload = JSON.parse(purchaseStr) as PurchaseSubGroupStatusPayload
        let lastSubscriptionStatus = purchaseOrderPayload.lastSubscriptionStatus
        const lastPurchaseOrder = lastSubscriptionStatus?.lastPurchaseOrder as PurchaseOrderPayload
        if (!lastSubscriptionStatus || !lastPurchaseOrder) {
          Log.e(TAG, 'Missing last subscription status while building transaction map.')
          return null
        }
        let payment = paymentOverride
          ? paymentOverride
          : this.buildPaymentMap(lastPurchaseOrder.productId, iap.ProductType.AUTORENEWABLE)
        return this.buildTransactionMap(
          payment,
          transactionState,
          lastPurchaseOrder.purchaseOrderId,
          lastSubscriptionStatus.purchaseToken,
          lastPurchaseOrder.purchaseTime,
          purchaseData,
        )
      }

      let jwsPurchaseOrder = purchaseDataObj.jwsPurchaseOrder
      if (!jwsPurchaseOrder) {
        Log.e(TAG, 'Missing jwsPurchaseOrder while building transaction map.')
        return null
      }
      let purchaseStr = JWTUtil.decodeJwtObj(jwsPurchaseOrder)
      let purchaseOrderPayload = JSON.parse(purchaseStr) as PurchaseOrderPayload
      let payment = paymentOverride
        ? paymentOverride
        : this.buildPaymentMap(
          purchaseOrderPayload.productId,
          purchaseOrderPayload.productType as iap.ProductType,
        )
      return this.buildTransactionMap(
        payment,
        transactionState,
        purchaseOrderPayload.purchaseOrderId,
        purchaseOrderPayload.purchaseToken,
        purchaseOrderPayload.purchaseTime,
        purchaseData,
      )
    } catch (err) {
      Log.e(TAG, `Failed to build transaction map from purchase data. err: ${JSON.stringify(err)}`)
      return null
    }
  }

  private async collectPurchaseDataListByType(
    productType: iap.ProductType,
    queryType: iap.PurchaseQueryType,
  ): Promise<string[]> {
    let purchaseDataList: string[] = []
    let continuationToken: string | undefined = undefined
    do {
      let parameter: QueryPurchasesParameterCompat = {
        productType: productType,
        queryType: queryType,
      }
      if (continuationToken && continuationToken.length > 0) {
        parameter.continuationToken = continuationToken
      }
      let queryPurchaseResult = await iap.queryPurchases(this.context, parameter)
      let queryPurchaseResultLike = queryPurchaseResult as QueryPurchaseResultLike
      if (queryPurchaseResultLike.purchaseDataList &&
          queryPurchaseResultLike.purchaseDataList.length > 0) {
        purchaseDataList.push(...queryPurchaseResultLike.purchaseDataList)
      }
      continuationToken = queryPurchaseResultLike.continuationToken ??
          queryPurchaseResultLike.nextPageToken
      if (continuationToken && continuationToken.length <= 0) {
        continuationToken = undefined
      }
    } while (continuationToken)

    return purchaseDataList
  }

  private async transactions(result: MethodResult): Promise<void> {
    if (!this.context) {
      result.success([])
      return
    }

    const updateSeq = this.beginVerificationDataUpdateScope()
    let pendingTransactions: Array<Map<string, Object>> = []
    let firstError: BusinessError | null = null
    const transactionTypes: Array<iap.ProductType> = deviceInfo.sdkApiVersion >= 14 ? [
  iap.ProductType.CONSUMABLE,
  iap.ProductType.NONCONSUMABLE,
  iap.ProductType.AUTORENEWABLE,
  iap.ProductType.NONRENEWABLE
] : [
  iap.ProductType.CONSUMABLE,
  iap.ProductType.NONCONSUMABLE,
  iap.ProductType.AUTORENEWABLE
]

    for (let i = 0; i < transactionTypes.length; i++) {
      try {
        let purchaseDataList = await this.collectPurchaseDataListByType(
          transactionTypes[i],
          iap.PurchaseQueryType.UNFINISHED,
        )
        purchaseDataList.forEach((purchaseData) => {
          this.updateLatestVerificationData(purchaseData, updateSeq)
          const transaction = this.buildTransactionMapFromPurchaseData(
            purchaseData,
            TransactionState.purchased,
          )
          if (transaction) {
            pendingTransactions.push(transaction)
          }
        })
      } catch (err) {
        const businessError: BusinessError = err as BusinessError
        if (this.isUnsupportedNonrenewableTypeError(transactionTypes[i], businessError)) {
          Log.i(TAG,
            'Skipping NONRENEWABLE unfinished query because the current IAP runtime does not support product type 3.')
          continue
        }
        if (!firstError) {
          firstError = businessError
        }
        Log.e(TAG,
          `Failed to query unfinished purchases for product type ${transactionTypes[i]}. Code is ${businessError.code}, message is ${businessError.message}`)
      }
    }

    if (pendingTransactions.length > 0 || !firstError) {
      result.success(pendingTransactions)
      return
    }

    result.error('' + firstError.code, firstError.message, firstError)
  }

  private async restoreTransactions(result: MethodResult): Promise<void> {
    if (!this.context) {
      result.error('UNAVAILABLE', 'context is null!', null)
      return
    }

    const updateSeq = this.beginVerificationDataUpdateScope()
    let restoredTransactions: Array<Map<string, Object>> = []
    let firstError: BusinessError | null = null
    const restoreTypes: Array<iap.ProductType> = deviceInfo.sdkApiVersion >= 14 ? [
      iap.ProductType.NONCONSUMABLE,
      iap.ProductType.AUTORENEWABLE,
      iap.ProductType.NONRENEWABLE,
    ] : [
      iap.ProductType.NONCONSUMABLE,
      iap.ProductType.AUTORENEWABLE,
    ]

    for (let i = 0; i < restoreTypes.length; i++) {
      try {
        let purchaseDataList = await this.collectPurchaseDataListByType(
          restoreTypes[i],
          iap.PurchaseQueryType.ALL,
        )
        purchaseDataList.forEach((purchaseData) => {
          this.updateLatestVerificationData(purchaseData, updateSeq)
          const transaction = this.buildTransactionMapFromPurchaseData(
            purchaseData,
            TransactionState.restored,
          )
          if (transaction) {
            restoredTransactions.push(transaction)
          }
        })
      } catch (err) {
        const businessError: BusinessError = err as BusinessError
        if (this.isUnsupportedNonrenewableTypeError(restoreTypes[i], businessError)) {
          Log.i(TAG,
            'Skipping NONRENEWABLE restore query because the current IAP runtime does not support product type 3.')
          continue
        }
        if (!firstError) {
          firstError = businessError
        }
        Log.e(TAG,
          `Failed to restore purchases for product type ${restoreTypes[i]}. Code is ${businessError.code}, message is ${businessError.message}`)
      }
    }

    if (restoredTransactions.length > 0) {
      this.observer?.invokeMethod('updatedTransactions', restoredTransactions)
      result.success(null)
      return
    }

    if (firstError) {
      result.error('' + firstError.code, firstError.message, firstError)
      return
    }

    result.success(null)
  }

  private async refreshReceipt(result: MethodResult): Promise<void> {
    if (!this.context) {
      result.error('UNAVAILABLE', 'context is null!', null)
      return
    }

    const updateSeq = this.beginVerificationDataUpdateScope()
    let firstError: BusinessError | null = null
    let hasUpdated: boolean = false
    const refreshTypes: Array<iap.ProductType> = deviceInfo.sdkApiVersion >= 14 ? [
      iap.ProductType.CONSUMABLE,
      iap.ProductType.NONCONSUMABLE,
      iap.ProductType.AUTORENEWABLE,
      iap.ProductType.NONRENEWABLE,
    ] : [
      iap.ProductType.CONSUMABLE,
      iap.ProductType.NONCONSUMABLE,
      iap.ProductType.AUTORENEWABLE,
    ]

    for (let i = 0; i < refreshTypes.length; i++) {
      try {
        let purchaseDataList = await this.collectPurchaseDataListByType(
          refreshTypes[i],
          iap.PurchaseQueryType.ALL,
        )
        if (purchaseDataList.length > 0) {
          purchaseDataList.forEach((purchaseData) => {
            this.updateLatestVerificationData(purchaseData, updateSeq)
          })
          hasUpdated = true
        }
      } catch (err) {
        const businessError: BusinessError = err as BusinessError
        if (this.isUnsupportedNonrenewableTypeError(refreshTypes[i], businessError)) {
          Log.i(TAG,
            'Skipping NONRENEWABLE refresh query because the current IAP runtime does not support product type 3.')
          continue
        }
        if (!firstError) {
          firstError = businessError
        }
        Log.e(TAG,
          `Failed to refresh purchase data for product type ${refreshTypes[i]}. Code is ${businessError.code}, message is ${businessError.message}`)
      }
    }

    if (hasUpdated || !firstError) {
      result.success(null)
      return
    }

    result.error('' + firstError.code, firstError.message, firstError)
  }

  createPurchase(id: string, args: Map<string, Object>, result: MethodResult) {
    if (!this.context) {
      result.error('UNAVAILABLE', 'context is null!', null)
      return
    }

    const updateSeq = this.beginVerificationDataUpdateScope()
    try {
      let type: iap.ProductType | undefined = undefined
      const requestType = args.get('productType') as number
      if (requestType !== undefined && requestType !== null) {
        type = requestType as iap.ProductType
      } else {
        const product = this.productDetailsMap.get(id)
        if (product) {
          type = product.type
        }
      }
      if (type === undefined) {
        result.error('UNAVAILABLE', 'productType is null!', null)
        return
      }

      let createPurchaseParam: iap.PurchaseParameter = {
        productId: id,
        productType: type,
        applicationUserName: args.get('applicationUserName') as string,
        developerPayload: args.get('applicationUserName') as string,
      }
      iap.createPurchase(this.context, createPurchaseParam).then(async (createPurchaseResult) => {
        this.updateLatestVerificationData(createPurchaseResult.purchaseData, updateSeq)
        const transaction = this.buildTransactionMapFromPurchaseData(
          createPurchaseResult.purchaseData,
          TransactionState.purchased,
          args,
        )
        if (transaction) {
          this.observer?.invokeMethod('updatedTransactions', [transaction])
          result.success(null)
          return
        }
        Log.e(TAG, 'Failed to parse purchase data after createPurchase; reporting failure to Flutter.')
        const parseError: BusinessError = {
          code: -1,
          message: 'Failed to parse purchase data.'
        } as BusinessError
        this.errorPurchase(args, parseError)
        result.success(null)
      }).catch((err: BusinessError) => {
        Log.e(TAG, `Failed to create purchase1. Code is ${err.code}, message is ${err.message}`);
        this.errorPurchase(args, err);
        result.success(null)
      })
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      const msg: string = `Failed to create purchase. Code is ${e.code}, message is ${e.message}`;
      Log.e(TAG, msg);
      this.errorPurchase(args, err);
      result.success(null)
    }
  }

  errorPurchase(args: Map<string, Object>, err: BusinessError) {
    let map: Map<string, Any> = new Map();
    let iKError: IKError = new IKError()
    if (err) {
      iKError.code = err.code
      iKError.domain = err.message
    }
    map.set('error', iKError)
    map.set('payment', args)
    map.set('transactionState', TransactionState.failed)
    this.observer?.invokeMethod('updatedTransactions', [map])
  }

  finishPurchase(
    productType: iap.ProductType,
    purchaseToken: string,
    purchaseOrderId: string,
    result?: MethodResult,
    removedTransaction?: Map<string, Object> | null,
  ) {
    let finishPurchaseParam: iap.FinishPurchaseParameter = {
      productType: productType,
      purchaseToken: purchaseToken,
      purchaseOrderId: purchaseOrderId
    };
    iap.finishPurchase(this.context, finishPurchaseParam).then(() => {
      Log.i(TAG, 'Succeeded in finishing purchase.');
      if (removedTransaction) {
        this.observer?.invokeMethod('removedTransactions', [removedTransaction])
      }
      result?.success(true);
    }).catch((err: BusinessError) => {
      Log.e(TAG, `Failed to finish purchase. Code is ${err.code}, message is ${err.message}`);
      result?.error('' + err.code, err.message, err);
    });
  }

  async queryPurchasesAsync(productType: iap.ProductType, transactionIdentifier: string, result: MethodResult) {
    try {
      let purchaseDataList: string[] = await this.collectPurchaseDataListByType(
        productType,
        iap.PurchaseQueryType.UNFINISHED,
      )
      if (purchaseDataList === undefined || purchaseDataList.length <= 0) {
        Log.i(TAG, 'No unfinished purchase matched while finishing purchase. Treating as already finished.');
        result.success(true);
        return;
      }
      this.purchaseCompletionByTypeProcessing(purchaseDataList, transactionIdentifier, result)
    } catch (err) {
      const businessError: BusinessError = err as BusinessError
      Log.e(TAG,
        `Failed to query purchases. Code is ${businessError.code}, message is ${businessError.message}`)
      result.error('' + businessError.code, businessError.message, businessError);
    }
  }

  purchaseCompletionByTypeProcessing(
    purchaseDataList: string[],
    transactionIdentifier: string,
    result: MethodResult,
  ) {
    for (let i = 0; i < purchaseDataList.length; i++) {
      let purchaseData = purchaseDataList[i];
      let type: number = JSON.parse(purchaseData).type
      let purchaseToken = ''
      let purchaseOrderId = ''
      //自动订阅类型
      if (type == iap.ProductType.AUTORENEWABLE) {
        let jwsSubscriptionStatus = (JSON.parse(purchaseData) as PurchaseData).jwsSubscriptionStatus;
        if (!jwsSubscriptionStatus) {
          Log.e(TAG, 'queryPurchases, jwsSubscriptionStatus invalid');
          continue;
        }
        let purchaseStr = JWTUtil.decodeJwtObj(jwsSubscriptionStatus);
        let purchaseOrderPayload = JSON.parse(purchaseStr) as PurchaseSubGroupStatusPayload;
        if (!purchaseOrderPayload.lastSubscriptionStatus) {
          Log.e(TAG, 'queryPurchases, lastSubscriptionStatus invalid');
          continue;
        }
        if (!purchaseOrderPayload.lastSubscriptionStatus.purchaseToken
          || purchaseOrderPayload.lastSubscriptionStatus.purchaseToken.length <= 0) {
          Log.e(TAG, 'queryPurchases, lastSubscriptionStatus.purchaseToken invalid');
          continue;
        }
        if (!purchaseOrderPayload.lastSubscriptionStatus.lastPurchaseOrder) {
          Log.e(TAG, 'queryPurchases, lastSubscriptionStatus.lastPurchaseOrder invalid');
          continue;
        }
        if (!purchaseOrderPayload.lastSubscriptionStatus.lastPurchaseOrder.purchaseOrderId
          || purchaseOrderPayload.lastSubscriptionStatus.lastPurchaseOrder.purchaseOrderId.length <= 0) {
          Log.e(TAG, 'queryPurchases, lastSubscriptionStatus.lastPurchaseOrder.purchaseOrderId invalid');
          continue;
        }
        purchaseToken = purchaseOrderPayload.lastSubscriptionStatus.purchaseToken
        purchaseOrderId = purchaseOrderPayload.lastSubscriptionStatus.lastPurchaseOrder.purchaseOrderId
      } else {
        //非自动订阅类型
        let jwsPurchaseOrder = (JSON.parse(purchaseData) as PurchaseData).jwsPurchaseOrder;
        if (!jwsPurchaseOrder) {
          Log.e(TAG, 'queryPurchases, jwsPurchaseOrder invalid');
          continue;
        }
        let purchaseStr = JWTUtil.decodeJwtObj(jwsPurchaseOrder);
        let purchaseOrderPayload = JSON.parse(purchaseStr) as PurchaseOrderPayload;
        purchaseToken = purchaseOrderPayload.purchaseToken
        purchaseOrderId = purchaseOrderPayload.purchaseOrderId
      }

      if (transactionIdentifier.length > 0 && purchaseOrderId !== transactionIdentifier) {
        continue
      }

      const removedTransaction = this.buildTransactionMapFromPurchaseData(
        purchaseData,
        TransactionState.purchased,
      )
      this.finishPurchase(
        type as iap.ProductType,
        purchaseToken,
        purchaseOrderId,
        result,
        removedTransaction,
      );
      return
    }

    Log.i(TAG,
      `No unfinished purchase matched transaction ${transactionIdentifier}. Treating as already finished.`)
    result.success(true)
  }

  iapFinishPurchase(call: MethodCall, result: MethodResult) {
    let finishPurchaseMap: Map<string, Object> = call.args as Map<string, Object>
    let transactionIdentifier: string = finishPurchaseMap.get('transactionIdentifier') as string
    if (!transactionIdentifier || transactionIdentifier.length <= 0) {
      result.error('UNAVAILABLE', 'transactionIdentifier is null!', null)
      return
    }

    let productType: iap.ProductType | undefined = undefined
    const requestType = finishPurchaseMap.get('productType') as number
    if (requestType !== undefined && requestType !== null) {
      productType = requestType as iap.ProductType
    } else {
      let productIdentifier: string = finishPurchaseMap.get('productIdentifier') as string
      let product: iap.Product = this.productDetailsMap.get(productIdentifier)
      if (!product) {
        Log.i(TAG, `Failed to get product for ${productIdentifier}.`);
        result.error('UNAVAILABLE', 'product is null!', null);
        return;
      }
      productType = product.type
    }
    if (productType === undefined) {
      Log.i(TAG, `Failed to get productType.`);
      result.error('UNAVAILABLE', 'productType is null!', null);
      return;
    } else {
      this.queryPurchasesAsync(productType, transactionIdentifier, result);
    }
  }

  startObserver() {
    this.observer = this.methodChannel
  }

  stopObserver() {
    this.observer = null
  }
}
