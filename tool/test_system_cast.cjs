// Executes the production CastView lifecycle with mocked OHOS APIs, without
// importing ArkUI or contacting a device. ArkTS/UI validity is checked by Hvigor.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require(process.env.OHOS_TYPESCRIPT || 'E:/Huawei/DevEco_Studio/tools/hvigor/hvigor/node_modules/typescript');
let source = fs.readFileSync('ohos/entry/src/main/ets/entryability/CastView.ets', 'utf8');
source = source.replace(/^import .*;\r?\n/gm, '').replace(/@Component[\s\S]*?@Observed\s*/, '');
const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
const tick = () => new Promise(resolve => setImmediate(resolve));
class Events {
  listeners = new Map();
  on(name, ...args) { const fn = args.at(-1); if (!this.listeners.has(name)) this.listeners.set(name, new Set()); this.listeners.get(name).add(fn); }
  off(name, fn) { if (fn) this.listeners.get(name)?.delete(fn); else this.listeners.delete(name); }
  emit(name, ...args) { for (const fn of this.listeners.get(name) || []) fn(...args); }
}
class Receiver extends Events {
  items = []; commands = []; fail = false;
  async start(item) { if (this.fail) throw Object.assign(new Error('receiver rejected media'), { code: 77 }); this.items.push(item); }
  async sendControlCommand(command) { this.commands.push(command); }
}
class Session extends Events {
  sessionType = 'video'; destroyed = 0; stopped = 0; metadata = []; receiver = new Receiver();
  async activate() {}
  async setExtras() {}
  async setAVMetadata(data) { this.metadata.push(data); }
  async getController() { return { getAVMetadata: async () => ({ assetId: 'local', title: 'Local music' }) }; }
  async getAVCastController() { return this.receiver; }
  async stopCasting() { this.stopped++; }
  async destroy() { this.destroyed++; }
}
function fixture(existing, create) {
  const channels = [];
  class Channel {
    events = [];
    constructor() { channels.push(this); }
    setMethodCallHandler(handler) { this.handler = handler; }
    invokeMethod(method, data) { this.events.push({ method, ...JSON.parse(data) }); }
  }
  const api = {
    getAVSession: async () => { if (existing) return existing; throw Object.assign(new Error('missing'), { code: 6600102 }); },
    createAVSession: create || (async () => new Session()),
    ProtocolType: { TYPE_CAST_PLUS_STREAM: 1, TYPE_DLNA: 2 },
    ConnectionState: { STATE_CONNECTED: 1, STATE_DISCONNECTED: 0 },
    AVCastCategory: { CATEGORY_REMOTE: 1 },
    PlaybackState: { PLAYBACK_STATE_PLAY: 1, PLAYBACK_STATE_PAUSE: 2, PLAYBACK_STATE_STOP: 3 },
  };
  const context = { exports: {}, PlatformView: class {}, MethodChannel: Channel, StandardMethodCodec: { INSTANCE: {} }, avSession: api, console };
  vm.runInNewContext(compiled, context);
  const View = context.exports.CastView;
  const view = new View({}, 1, {}, {});
  const call = (method, payload = '') => new Promise((resolve, reject) => view.onMethodCall({ method, args: payload }, {
    success: resolve, error: (code, message) => reject(new Error(`${code}: ${message}`)), notImplemented: () => reject(new Error('not implemented')),
  }));
  const drain = async () => { await tick(); await View.operations; await tick(); };
  return { view, View, call, channels, api, drain };
}
const payload = (url = 'http://127.0.0.1:1234/media.mp4', positionMs = 30000) => JSON.stringify({ url, title: '中文 & 电影', mediaType: 'VIDEO', durationMs: 3600000, positionMs });
const connected = { devices: [{ castCategory: 1 }] };
(async () => {
  // Borrowed music session retains its real type and survives closing cast UI.
  const shared = new Session(); shared.sessionType = 'audio';
  const f = fixture(shared);
  await f.call('getMessageFromFlutterView', payload());
  assert.equal(f.view.ready, true); assert.equal(f.view.sessionType, 'audio');
  assert.equal(shared.listeners.get('outputDeviceChange').size, 1);
  shared.emit('outputDeviceChange', 1, connected); await f.drain();
  const description = shared.receiver.items[0].description;
  assert.equal(description.duration, 3600000); assert.equal(description.startPosition, 30000);
  assert.equal(description.title, '中文 & 电影'); assert.equal(description.mediaSize, undefined);
  shared.emit('outputDeviceChange', 1, connected); await f.drain();
  assert.equal(shared.receiver.items.length, 1, 'duplicate connection must not restart playback');
  assert.equal(f.channels[0].events.some(e => e.state === 'PLAYING'), false);
  shared.receiver.emit('playbackStateChange', { state: 1, position: { elapsedTime: 45000 } });
  assert.equal(f.channels[0].events.at(-1).state, 'PLAYING');
  assert.equal(f.channels[0].events.at(-1).positionMs, 45000);
  await f.call('newPlay', payload('https://example.com/next.mp4', 0));
  assert.equal(shared.receiver.items.at(-1).description.mediaUri, 'https://example.com/next.mp4');
  await f.call('seek', '60000'); assert.equal(shared.receiver.commands.at(-1).parameter, 60000);
  shared.receiver.emit('error', Object.assign(new Error('network lost'), { code: 88 }));
  assert.match(f.channels[0].events.at(-1).message, /88: network lost/);
  shared.receiver.fail = true;
  await assert.rejects(f.call('newPlay', payload()), /77: receiver rejected media/);
  f.view.dispose(); await f.drain();
  assert.equal(shared.destroyed, 0); assert.equal(shared.stopped, 1);
  assert.equal(shared.metadata.at(-1).title, 'Local music');
  assert.equal(shared.listeners.get('outputDeviceChange').size, 0);
  assert.equal(f.channels[0].handler, null);
  // Closing while session creation is unresolved cleans up the late session.
  let release;
  const created = new Session();
  const late = fixture(null, () => new Promise(resolve => { release = resolve; }));
  const pending = late.call('getMessageFromFlutterView', payload());
  await tick(); late.view.dispose(); release(created); await assert.rejects(pending, /页面已关闭/); await late.drain();
  assert.equal(created.destroyed, 1);
  assert.equal(late.channels[0].events.length, 0);
  assert.equal(late.view.ready, false);
  // Disconnection invalidates a delayed get-controller result before start.
  const delayedSession = new Session();
  let supplyController;
  delayedSession.getAVCastController = () => new Promise(resolve => { supplyController = resolve; });
  const stale = fixture(delayedSession);
  await stale.call('getMessageFromFlutterView', payload());
  delayedSession.emit('outputDeviceChange', 1, connected); await tick();
  delayedSession.emit('outputDeviceChange', 0, { devices: [] });
  supplyController(delayedSession.receiver); await stale.drain();
  assert.equal(delayedSession.receiver.items.length, 0);
  stale.view.dispose(); await stale.drain();
  console.log('PASS: borrowed session, matching picker type, actual metadata, receiver states/errors, new media, controls, late creation/disconnection, scoped cleanup');
})().catch(error => { console.error(error); process.exitCode = 1; });
