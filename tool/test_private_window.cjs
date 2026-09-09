const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('E:/Huawei/DevEco_Studio/tools/hvigor/hvigor/node_modules/typescript');
const source = fs.readFileSync('ohos/entry/src/main/ets/entryability/DeviceToolsPlugin.ets', 'utf8').replace(/^import .*;\r?\n/gm, '');
const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
let handler, fail = false; const enabled = [];
class Channel { setMethodCallHandler(value) { handler = value; } }
const sandbox = { exports: {}, console, MethodChannel: Channel, backgroundTaskManager: { on() {} }, window: { getLastWindow: async () => ({ setWindowPrivacyMode: async (value) => { if (fail) throw { code: 201 }; enabled.push(value); } }) } };
vm.runInNewContext(compiled, sandbox);
const plugin = new sandbox.exports.default({}); plugin.onAttachedToEngine({ getBinaryMessenger() {} });
function call(value) { return new Promise((resolve, reject) => handler.onMethodCall({ method: 'privateWindow', argument: () => value }, { success: resolve, error: (code) => reject(new Error(code)) })); }
(async () => { await call(true); await call(false); assert.deepEqual(enabled, [true, false]); fail = true; await assert.rejects(call(true), /PRIVACY/); console.log('PASS private window enable, restore and denied permission propagation'); })().catch(error => { console.error(error); process.exitCode = 1; });
