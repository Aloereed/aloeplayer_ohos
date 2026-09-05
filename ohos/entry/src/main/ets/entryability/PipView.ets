import PlatformView, { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import StandardMethodCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMethodCodec';
import common from '@ohos.app.ability.common';
import { PiPWindow as pictureInPicture } from '@kit.ArkUI';
import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

@Component
struct PipComponent {
  @Prop params: Params;
  private controller: XComponentController = new XComponentController();
  build() {
    XComponent({ type: XComponentType.SURFACE, controller: this.controller })
      .width('100%').height('100%')
      .onLoad(() => { (this.params.platformView as PipView).surfaceReady(this.controller); });
  }
}
@Builder
function PipBuilder(params: Params) { PipComponent({ params: params }); }

export class PipView extends PlatformView implements MethodCallHandler {
  private channel: MethodChannel;
  private player?: media.AVPlayer;
  private pip?: pictureInPicture.PiPController;
  private component?: XComponentController;
  private opened: boolean = false;
  private requested: boolean = false;
  private disposed: boolean = false;
  private file?: fs.File;
  private uri: string;
  private initialPosition: number;
  private headers: Record<string, string>;
  private currentPosition: number = 0;
  private shouldPlay: boolean = true;
  private prepared: boolean = false;
  private context: common.Context;
  constructor(context: common.Context, id: number, args: ESObject, messenger: BinaryMessenger) {
    super();
    this.context = context;
    this.uri = args['uri'] as string;
    this.initialPosition = args['positionMs'] as number;
    this.currentPosition = this.initialPosition;
    this.shouldPlay = args['playing'] as boolean;
    this.headers = args['headers'] as Record<string, string>;
    this.channel = new MethodChannel(messenger, `aloeplayer/pip-view/${id}`, StandardMethodCodec.INSTANCE);
    this.channel.setMethodCallHandler(this);
  }
  getView(): WrappedBuilder<[Params]> { return new WrappedBuilder(PipBuilder); }
  surfaceReady(controller: XComponentController): void {
    this.component = controller;
    if (this.requested) this.open();
  }
  private async open(): Promise<void> {
    if (this.opened || !this.component || this.disposed) return;
    this.opened = true;
    try {
      const player = await media.createAVPlayer();
      if (this.disposed) { await player.release(); return; }
      this.player = player;
      player.on('error', (error: BusinessError) => { if (!this.disposed) this.channel.invokeMethod('error', '系统播放器无法打开此文件，错误码 ' + error.code); });
      player.on('timeUpdate', (position: number) => { this.currentPosition = position; });
      player.on('stateChange', async (state: string) => {
        if (this.disposed) return;
        try {
          if (state === 'initialized') {
            player.surfaceId = this.component!.getXComponentSurfaceId();
            await player.prepare();
          } else if (state === 'prepared') {
            this.prepared = true;
            if (this.initialPosition > 0 && this.initialPosition < player.duration) player.seek(this.initialPosition);
            if (this.shouldPlay) await player.play();
            this.channel.invokeMethod('ready', player.duration);
          } else if (state === 'completed') { this.shouldPlay = false; this.channel.invokeMethod('completed', this.currentPosition); }
        } catch (error) { if (!this.disposed) this.channel.invokeMethod('error', '系统播放准备失败'); }
      });
      if (this.uri.startsWith('http://') || this.uri.startsWith('https://')) {
        await player.setMediaSource(media.createMediaSourceWithUrl(this.uri, this.headers));
      } else {
        this.file = await fs.open(this.uri, fs.OpenMode.READ_ONLY);
        player.fdSrc = { fd: this.file.fd };
      }
    } catch (error) { if (!this.disposed) this.channel.invokeMethod('error', '无法打开媒体，请返回原播放器'); }
  }
  private async startPip(result: MethodResult): Promise<void> {
    try {
      if (!pictureInPicture.isPiPEnabled() || !this.component || !this.player) {
        result.error('UNAVAILABLE', '此设备或当前窗口不支持画中画', null); return;
      }
      if (!this.pip) {
        this.pip = await pictureInPicture.create({ context: this.context, componentController: this.component,
          templateType: pictureInPicture.PiPTemplateType.VIDEO_PLAY, contentWidth: this.player.width || 1280, contentHeight: this.player.height || 720 });
        this.pip.on('controlPanelActionEvent', (event: pictureInPicture.PiPActionEventType, status?: number) => {
          if (event === 'playbackStateChanged') {
            this.shouldPlay = status === pictureInPicture.PiPControlStatus.PLAY;
            this.changePlayback();
          }
        });
      }
      await this.pip.startPiP();
      result.success(null);
    } catch (error) { result.error('PIP', '画中画启动失败，请检查系统设置', null); }
  }
  private async stopPip(result: MethodResult): Promise<void> {
    try { await this.pip?.stopPiP(); } catch (error) {}
    const playing = this.prepared ? this.player?.state === 'playing' : this.shouldPlay;
    this.shouldPlay = false;
    try { if (this.player?.state === 'playing') await this.player.pause(); } catch (error) {}
    result.success({ positionMs: this.currentPosition, playing: playing });
  }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'open') { this.requested = true; this.open(); result.success(null); }
    else if (call.method === 'startPiP') { this.startPip(result); }
    else if (call.method === 'stopPiP') { this.stopPip(result); }
    else if (call.method === 'pause' || call.method === 'play') {
      this.shouldPlay = call.method === 'play'; this.changePlayback(); result.success(null);
    }
    else { result.notImplemented(); }
  }
  private async changePlayback(): Promise<void> {
    try {
      if (this.shouldPlay && (this.player?.state === 'paused' || this.player?.state === 'prepared')) await this.player.play();
      else if (!this.shouldPlay && this.player?.state === 'playing') await this.player.pause();
    } catch (error) {}
  }
  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.channel.setMethodCallHandler(null);
    this.release();
  }
  private async release(): Promise<void> {
    try { await this.pip?.stopPiP(); } catch (error) {}
    try { await this.player?.release(); } catch (error) {}
    if (this.file) { try { await fs.close(this.file); } catch (error) {} this.file = undefined; }
  }
}
