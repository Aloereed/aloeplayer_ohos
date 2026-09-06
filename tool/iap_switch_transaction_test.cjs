// Exercise actual ArkTS receipt mapping for immediate and deferred plan changes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require(process.argv[2]);
const source = fs.readFileSync('third_party/huawei_iap/in_app_purchase_ohos/ohos/src/main/ets/components/MethodCallHandlerImpl.ets', 'utf8');
const start = source.indexOf('  private buildTransactionMapFromPurchaseData(');
assert.ok(start >= 0);
const end = source.indexOf('\n  private ', start + 10);
const method = source.slice(start, end);
const script = ts.transpileModule(`class Handler { ${method} }; globalThis.Handler = Handler`, {
  compilerOptions: {target: ts.ScriptTarget.ES2020},
}).outputText;
const context = vm.createContext({iap: {ProductType: {AUTORENEWABLE: 2}},
  JWTUtil: {decodeJwtObj: value => value}, Log: {e() {}}, TAG: 'test'});
vm.runInContext(script, context);
const handler = new context.Handler();
handler.buildTransactionMap = (payment, state, id) => ({product: payment.get('productId'), id});
for (const current of ['premium_monthly', 'premium_1year']) {
  const requested = current === 'premium_monthly' ? 'premium_1year' : 'premium_monthly';
  const payment = new Map([['productId', requested]]);
  const receipt = JSON.stringify({type: 2, jwsSubscriptionStatus: JSON.stringify({lastSubscriptionStatus: {
    purchaseToken: 'token', lastPurchaseOrder: {productId: current, purchaseOrderId: 'current-order', purchaseTime: 1}}})});
  const result = handler.buildTransactionMapFromPurchaseData(receipt, 1, payment);
  assert.equal(result.product, current);
  assert.equal(result.id, 'current-order');
}
console.log('2 native subscription identity scenarios passed');
