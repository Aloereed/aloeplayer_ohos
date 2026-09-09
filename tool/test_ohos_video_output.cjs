// Run the actual ArkTS output class against a texture registry double.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.TYPESCRIPT_PATH || 'E:/Huawei/DevEco_Studio/tools/ohpm/node_modules/typescript');
const source = fs.readFileSync('third_party/media_kit_video/ohos/src/main/ets/com/alexmercerind/media_kit_video/VideoOutput.ets', 'utf8');
const output = ts.transpileModule(source, {compilerOptions: {module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020}}).outputText;
const sandbox = {exports: {}, require: () => ({default: {i() {}, e() {}}})};
vm.runInNewContext(output, sandbox);
const {VideoOutput} = sandbox.exports;
const active = new Map();
const released = [];
const registry = {
  setTextureBufferSize(id, w, h) {
    assert(active.has(id), `resized unregistered texture ${id}`);
    assert(w > 0 && h > 0);
    active.set(id, [w, h]);
  },
  unregisterTexture(id) {
    assert(active.delete(id), `double release ${id}`);
    released.push(id);
  },
};
function create(id, failOnDestroy = false) {
  active.set(id, []);
  const events = [];
  const instance = new VideoOutput(registry, {
    getTextureId: () => id, getSurfaceId: () => 10000 + id,
    release() { throw Error('OHOS release is not implemented'); },
  }, {onTextureUpdate(...event) {
    if (failOnDestroy && event[1] === 0) throw Error('channel unavailable');
    events.push(event);
  }});
  assert.deepEqual(events[0], [id, 10000 + id, 1, 1]);
  return {instance, events};
}
for (let id = 1; id <= 100; id += 2) {
  const old = create(id);
  old.instance.setSurfaceSize(1920, 1080);
  const next = create(id + 1, true);
  next.instance.setSurfaceSize(3840, 2160);
  old.instance.dispose();
  old.instance.dispose();
  old.instance.setSurfaceSize(640, 360);
  assert.deepEqual(active.get(id + 1), [3840, 2160]);
  next.instance.setSurfaceSize(0, 0);
  assert.deepEqual(active.get(id + 1), [3840, 2160]);
  next.instance.dispose();
  next.instance.dispose();
}
assert.equal(active.size, 0);
assert.equal(released.length, 100);
console.log('PASS: 100 texture lifetimes; valid initial size/ID, overlapping players, idempotent cleanup, late resize, channel failure');
