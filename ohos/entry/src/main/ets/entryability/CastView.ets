import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import PlatformView, { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import common from '@ohos.app.ability.common';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import StandardMethodCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMethodCodec';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import avSession from '@ohos.multimedia.avsession';
import { AVCastPicker } from '@kit.AVSessionKit';
import { BusinessError } from '@kit.BasicServicesKit';

interface CastMedia {
  url: string;
  title: string;
  mediaType: string;
  durationMs: number;
  positionMs: number;
}
interface CastStatus {
  state: string;
  positionMs: number;
  message: string;
}

@Component
struct ButtonComponent {
  @Prop params: Params;
  @State castView: CastView = this.params.platformView as CastView;
  @Builder
  pickerContent() {
    Row({ space: 10 }) {
      Image($r('app.media.cast_picker'))
        .width(24)
        .height(24)
      Text(this.castView.ready ? '选择投播设备' : '正在准备投播…')
        .fontSize(16)
        .fontColor(Color.White)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.castView.ready ? '#175CD3' : '#667085')
    .borderRadius(12)
  }
  build() {
    AVCastPicker({
      sessionType: this.castView.sessionType,
      customPicker: () => this.pickerContent()
    })
      .enabled(this.castView.ready)
      .width('100%')
      .height('100%')
  }
}
@Builder
function ButtonBuilder(params: Params) {
  ButtonComponent({ params: params })
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
}

@Observed
export class CastView extends PlatformView implements MethodCallHandler {
  // A closing view releases ownership before a new view borrows/creates a session.
  private static operations: Promise<void> = Promise.resolve();
  ready: boolean = false;
  sessionType: string = 'video';
  private readonly context: common.Context;
  private readonly channel: MethodChannel;
  private session: avSession.AVSession | undefined;
  private ownsSession: boolean = false;
  private castAssetId: string = '';
  private originalMetadata: avSession.AVMetadata | undefined;
  private controller: avSession.AVCastController | undefined;
  private disposed: boolean = false;
  private connectionRevision: number = 0;
  private connectedDevice: string = '';
  private media: CastMedia = { url: '', title: 'AloePlayer', mediaType: 'VIDEO', durationMs: 0, positionMs: 0 };

  constructor(context: common.Context, viewId: number, args: ESObject, messenger: BinaryMessenger) {
    super();
    this.context = context;
    this.channel = new MethodChannel(messenger, `com.aloereed.aloeplayer/castView${viewId}`, StandardMethodCodec.INSTANCE);
    this.channel.setMethodCallHandler(this);
    // Flutter sends metadata after installing its status listener.
  }
  private enqueue(operation: () => Promise<void>): Promise<void> {
    const next = CastView.operations.then(operation);
    CastView.operations = next.catch(() => {});
    return next;
  }
  private emit(state: string, message: string = '', positionMs: number = this.media.positionMs): void {
    if (this.disposed) return;
    const status: CastStatus = { state: state, message: message, positionMs: positionMs };
    this.channel.invokeMethod('castState', JSON.stringify(status));
  }
  private report(error: BusinessError): string {
    const message = `${error.code ?? 'CAST'}: ${error.message ?? '系统投播失败'}`;
    this.emit('ERROR', message);
    return message;
  }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    const supported = ['getMessageFromFlutterView', 'newPlay', 'play', 'pause', 'seek', 'setVolume', 'stopCasting'];
    if (!supported.includes(call.method)) { result.notImplemented(); return; }
    this.enqueue(async () => {
      if (this.disposed) throw new Error('投播页面已关闭');
      if (call.method === 'getMessageFromFlutterView' || call.method === 'newPlay') {
        this.readMedia(call.args as string);
        await this.initialize();
        if (this.disposed) throw new Error('投播页面已关闭');
        await this.session?.activate();
        await this.session?.setExtras({ requireAbilityList: ['url-cast'] });
        await this.setMetadata();
        this.ready = true;
        if (this.controller) await this.startMedia();
        else this.emit('READY');
      } else if (call.method === 'stopCasting') {
        await this.session?.stopCasting();
        this.connectionRevision++;
        this.connectedDevice = '';
        this.detachController();
        this.emit('STOPPED');
      } else {
        if (!this.controller) throw new Error('请先在系统选择器中连接设备');
        const command: avSession.AVCastControlCommand = { command: call.method as avSession.AVCastControlCommandType };
        if (call.method === 'seek' || call.method === 'setVolume') {
          const value = Number(call.args as string);
          if (!Number.isFinite(value) || value < 0) throw new Error('无效的投播控制参数');
          command.parameter = call.method === 'setVolume' ? Math.min(100, value) : value;
        }
        await this.controller.sendControlCommand(command);
      }
    }).then(() => result.success(true)).catch((error: BusinessError) => {
      result.error('CAST_ERROR', this.report(error), null);
    });
  }
  private readMedia(payload: string): void {
    if (payload.trim().startsWith('{')) this.media = JSON.parse(payload) as CastMedia;
    else {
      const parts = payload.split('|||');
      this.media = { url: parts.length > 1 ? parts[1] : parts[0], title: 'AloePlayer', mediaType: 'VIDEO', durationMs: 0, positionMs: 0 };
    }
    if (!/^https?:\/\//i.test(this.media.url)) throw new Error('接收端需要可访问的 HTTP 媒体地址');
    this.media.title = this.media.title || 'AloePlayer';
    this.media.mediaType = this.media.mediaType === 'AUDIO' ? 'AUDIO' : 'VIDEO';
    this.media.durationMs = Number.isFinite(this.media.durationMs) ? Math.max(0, this.media.durationMs) : 0;
    this.media.positionMs = Number.isFinite(this.media.positionMs) ? Math.max(0, this.media.positionMs) : 0;
    if (this.media.durationMs > 0) this.media.positionMs = Math.min(this.media.positionMs, this.media.durationMs);
  }
  private async initialize(): Promise<void> {
    if (this.session) return;
    // One ability may own only one AVSession. Borrow the AudioService/native
    // player session if present, and never destroy a borrowed session.
    let session: avSession.AVSession;
    try {
      session = await avSession.getAVSession(this.context);
      this.ownsSession = false;
    } catch (error) {
      const failure = error as BusinessError;
      if (failure.code !== 6600102) throw new Error(`${failure.code}: ${failure.message}`);
      session = await avSession.createAVSession(this.context, 'AloePlayer Cast', 'video');
      this.ownsSession = true;
    }
    this.session = session;
    this.sessionType = session.sessionType;
    if (!this.ownsSession) {
      try { this.originalMetadata = await (await session.getController()).getAVMetadata(); } catch (_) {}
    }
    session.on('outputDeviceChange', this.outputChanged);
  }
  private async setMetadata(): Promise<void> {
    const metadata: avSession.AVMetadata = {
      assetId: `aloe-cast-${Date.now()}`,
      title: this.media.title,
      subtitle: '由 AloePlayer 投播',
      filter: avSession.ProtocolType.TYPE_CAST_PLUS_STREAM | avSession.ProtocolType.TYPE_DLNA
    };
    if (this.media.durationMs > 0) metadata.duration = this.media.durationMs;
    await this.session?.setAVMetadata(metadata);
    this.castAssetId = metadata.assetId;
  }
  private outputChanged = (state: avSession.ConnectionState, output: avSession.OutputDeviceInfo): void => {
    if (this.disposed) return;
    const deviceKey = JSON.stringify(output.devices.map(device => device.deviceId));
    if (state === avSession.ConnectionState.STATE_CONNECTED && this.controller && this.connectedDevice === deviceKey) return;
    const revision = ++this.connectionRevision;
    if (state === avSession.ConnectionState.STATE_DISCONNECTED) {
      this.connectedDevice = '';
      this.detachController(); this.emit('DISCONNECTED'); return;
    }
    if (state !== avSession.ConnectionState.STATE_CONNECTED ||
      !output.devices.some(device => device.castCategory === avSession.AVCastCategory.CATEGORY_REMOTE)) return;
    this.emit('CONNECTING');
    this.enqueue(async () => {
      if (this.disposed || revision !== this.connectionRevision || !this.session) return;
      const controller = await this.session.getAVCastController();
      if (this.disposed || revision !== this.connectionRevision) return;
      this.detachController();
      this.controller = controller;
      this.connectedDevice = deviceKey;
      controller.on('playbackStateChange', 'all', this.playbackChanged);
      controller.on('endOfStream', this.ended);
      controller.on('error', this.failed);
      await this.startMedia();
    }).catch((error: BusinessError) => { this.report(error); });
  };
  private playbackChanged = (state: avSession.AVPlaybackState): void => {
    if (state.position) this.media.positionMs = Math.max(0, state.position.elapsedTime);
    if (state.state === avSession.PlaybackState.PLAYBACK_STATE_PLAY) this.emit('PLAYING');
    else if (state.state === avSession.PlaybackState.PLAYBACK_STATE_PAUSE) this.emit('PAUSED');
    else if (state.state === avSession.PlaybackState.PLAYBACK_STATE_STOP) this.emit('STOPPED');
  };
  private ended = (): void => { this.emit('COMPLETED'); };
  private failed = (error: BusinessError): void => { this.report(error); };
  private async startMedia(): Promise<void> {
    if (!this.controller || this.disposed) return;
    const description: avSession.AVMediaDescription = {
      assetId: `aloe-cast-${Date.now()}`,
      title: this.media.title,
      mediaUri: this.media.url,
      mediaType: this.media.mediaType,
      startPosition: this.media.positionMs,
      appName: 'AloePlayer'
    };
    // Unknown duration and size remain unknown; no blocking cover extraction.
    if (this.media.durationMs > 0) description.duration = this.media.durationMs;
    const item: avSession.AVQueueItem = { itemId: 0, description: description };
    this.emit('LOADING');
    await this.controller.start(item);
    // Only receiver playbackStateChange can confirm PLAYING.
  }
  private detachController(): void {
    try { this.controller?.off('playbackStateChange', this.playbackChanged); } catch (_) {}
    try { this.controller?.off('endOfStream', this.ended); } catch (_) {}
    try { this.controller?.off('error'); } catch (_) {}
    this.controller = undefined;
  }
  getView(): WrappedBuilder<[Params]> { return new WrappedBuilder(ButtonBuilder); }
  dispose(): void {
    this.disposed = true; this.ready = false; this.connectionRevision++;
    this.channel.setMethodCallHandler(null);
    this.enqueue(async () => {
      this.detachController();
      const session = this.session;
      this.session = undefined;
      if (!session) return;
      try { session.off('outputDeviceChange', this.outputChanged); } catch (_) {}
      try { await session.stopCasting(); } catch (_) {}
      if (this.ownsSession) await session.destroy();
      else if (this.originalMetadata && this.castAssetId) {
        const current = await (await session.getController()).getAVMetadata();
        if (current.assetId === this.castAssetId) await session.setAVMetadata(this.originalMetadata);
      }
    }).catch((error: BusinessError) => { console.warn(`Cast cleanup: ${error.code}`); });
  }
}
