// Execute the actual ArkTS query method with a mocked Huawei service.
// Usage: node tool/iap_product_query_test.cjs <path-to-typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2]);
const source = fs.readFileSync(path.join(__dirname,
  '../third_party/huawei_iap/in_app_purchase_ohos/ohos/src/main/ets/components/MethodCallHandlerImpl.ets'), 'utf8');
const method = source.slice(source.indexOf('  queryProductDetails('), source.indexOf('  purchaseGoods('));
assert.ok(method.includes('iap.queryProducts'), 'Native query method must be extracted');
const compiled = ts.transpileModule(`class Handler { ${method} }; globalThis.Handler = Handler;`, {
  compilerOptions: { target: ts.ScriptTarget.ES2020 },
}).outputText;

async function query(outcomes, order, ids = ['premium_monthly']) {
  const pending = new Map();
  const context = vm.createContext({
    ProductType: [0, 1, 2, 3], HashMap: Map,
    ObjToMap: value => new Map(Object.entries(value)),
    Log: { e() {} }, TAG: 'test',
    iap: { queryProducts: (_, params) => new Promise((resolve, reject) => {
      pending.set(params.productType, { resolve, reject });
    }) },
  });
  vm.runInContext(compiled, context);
  const handler = new context.Handler();
  handler.productDetailsMap = new Map();
  const replies = [];
  handler.queryProductDetails(ids, {
    success: value => replies.push({ value }),
    error: (code, message) => replies.push({ code, message }),
  });
  for (const type of order) {
    const item = outcomes[type];
    if (Array.isArray(item)) pending.get(type).resolve(item);
    else pending.get(type).reject(item);
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.equal(replies.length, 1, 'Exactly one platform response');
  return replies[0];
}

(async () => {
  const missing = { code: 1001860003, message: 'Invalid product information' };
  const denied = { code: 1001860002, message: 'Not authorized' };
  const monthly = { id: 'premium_monthly', type: 2 };
  for (const order of [[2, 0, 1, 3], [0, 1, 3, 2]]) {
    const result = await query([missing, missing, [monthly], missing], order);
    assert.equal(result.value.get('products')[0].get('id'), monthly.id);
    assert.equal(result.value.get('invalidProductIdentifiers').length, 0);
  }
  const failed = await query([denied, denied, denied, denied], [0, 1, 2, 3]);
  assert.equal(failed.code, '1001860002');
  const emptyWithError = await query([missing, [], [], []], [0, 1, 2, 3]);
  assert.equal(emptyWithError.code, '1001860003');
  const empty = await query([[], [], [], []], [0, 1, 2, 3]);
  assert.deepEqual(Array.from(empty.value.get('invalidProductIdentifiers')), ['premium_monthly']);
  const partial = await query([missing, missing, [monthly], missing], [0, 1, 2, 3], ['premium_monthly', 'absent']);
  assert.deepEqual(Array.from(partial.value.get('invalidProductIdentifiers')), ['absent']);
  console.log('PASS: six native product query scenarios');
})().catch(error => { console.error(error); process.exitCode = 1; });
