import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import common from '@ohos.app.ability.common';
import { PiPWindow as pictureInPicture } from '@kit.ArkUI';
import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

import router from '@ohos.router';

export class PipSession implements MethodCallHandler {
  static active?: PipSession;
  onStatus?: (phase: string, ready: boolean, error: string) => void;
  private phase: string = '创建视频画面';
  private failure: string = '';
  private watchdog?: number;
  private closing: boolean = false;
  private pageVisible: boolean = false;
  private releasing?: Promise<void>;
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
  private headers: Record<string, string> = {};
  private lastCheckpoint: number = 0;
  private currentPosition: number = 0;
  private shouldPlay: boolean = true;
  private prepared: boolean = false;
  private context: common.Context;
  constructor(context: common.Context, args: ESObject, channel: MethodChannel) {
    this.context = context;
    const values = args as Map<string, Object>;
    this.uri = (values.get('uri') as string) ?? '';
    this.initialPosition = (values.get('positionMs') as number) ?? 0;
    this.currentPosition = this.initialPosition;
    this.shouldPlay = (values.get('playing') as boolean) ?? true;
    const headers = values.get('headers') as Map<string, string>;
    headers?.forEach((value: string, key: string) => { this.headers[key] = value; });
    this.channel = channel;
    this.requested = true;
    PipSession.active = this;
    this.watchdog = setTimeout(() => this.fail('准备超时：' + this.phase + '。可返回 mpv 继续播放。'), 30000);
  }
  surfaceReady(controller: XComponentController): void {
    this.component = controller;
    this.status('打开媒体');
    if (this.requested) this.open();
  }
  private async open(): Promise<void> {
    if (this.opened || !this.component || this.disposed) return;
    this.opened = true;
    try {
      const player = await media.createAVPlayer();
      if (this.disposed) { await player.release(); return; }
      this.player = player;
      player.on('error', (error: BusinessError) => { this.fail('系统解码失败（' + error.code + '），此格式可能仅受 mpv 支持'); });
      player.on('timeUpdate', (position: number) => {
        if (position > 0 || this.initialPosition === 0) this.currentPosition = position;
        if (Date.now() - this.lastCheckpoint >= 5000) this.emitPosition();
      });
      player.on('stateChange', async (state: string) => {
        if (this.disposed) return;
        if (state === 'playing' || state === 'paused' || state === 'completed') this.emitPosition();
        try {
          if (state === 'initialized') {
            this.status('准备系统解码器');
            player.surfaceId = this.component!.getXComponentSurfaceId();
            await player.prepare();
          } else if (state === 'prepared') {
            this.prepared = true;
            if (this.watchdog !== undefined) clearTimeout(this.watchdog);
            if (this.initialPosition > 0 && this.initialPosition < player.duration) player.seek(this.initialPosition);
            if (this.shouldPlay) await player.play();
            this.status('可以开启画中画');
            this.channel.invokeMethod('ready', player.duration);
            await this.start();
          } else if (state === 'completed') { this.shouldPlay = false; this.channel.invokeMethod('completed', this.currentPosition); }
        } catch (error) { this.fail('系统播放准备失败'); }
      });
      if (this.uri.startsWith('http://') || this.uri.startsWith('https://')) {
        await player.setMediaSource(media.createMediaSourceWithUrl(this.uri, this.headers));
      } else {
        const file = await fs.open(this.uri, fs.OpenMode.READ_ONLY);
        if (this.disposed) { await fs.close(file); return; }
        this.file = file;
        player.fdSrc = { fd: file.fd };
      }
    } catch (error) { this.fail('无法打开媒体，请返回 mpv 继续播放'); }
  }
  async start(): Promise<void> {
    if (this.disposed || this.closing) return;
    try {
      if (!pictureInPicture.isPiPEnabled() || !this.component || !this.player) {
        this.fail('此设备或当前窗口不支持画中画'); return;
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
      this.status('画中画已开启');
    } catch (error) { this.failure = '画中画启动失败，请检查系统画中画权限'; this.status(this.phase); }
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
    else if (call.method === 'startPiP') { this.start().then(() => result.success(null)); }
    else if (call.method === 'stopPiP') { this.stopPip(result); }
    else if (call.method === 'seek') {
      const position = call.argument('positionMs') as number;
      try {
        if (this.prepared && this.player) { this.currentPosition = position; this.player.seek(position); }
        result.success(null);
      } catch (error) { result.error('SEEK', '无法跳转到指定位置', null); }
    }
    else if (call.method === 'pause' || call.method === 'play') {
      this.shouldPlay = call.method === 'play'; this.changePlayback(); result.success(null);
    }
    else { result.notImplemented(); }
  }
  private emitPosition(): void {
    if (this.disposed) return;
    this.lastCheckpoint = Date.now();
    this.channel.invokeMethod('position', { positionMs: this.currentPosition, playing: this.player?.state === 'playing' });
  }
  private async changePlayback(): Promise<void> {
    try {
      if (this.shouldPlay && (this.player?.state === 'paused' || this.player?.state === 'prepared')) await this.player.play();
      else if (!this.shouldPlay && this.player?.state === 'playing') await this.player.pause();
    } catch (error) {}
  }
  dispose(): void {
    this.disposed = true;
    if (this.watchdog !== undefined) clearTimeout(this.watchdog);
    this.onStatus = undefined;
    if (PipSession.active === this) PipSession.active = undefined;
    this.release();
  }
  private status(phase: string): void {
    if (this.disposed || this.closing) return;
    this.phase = phase;
    this.onStatus?.(phase, this.prepared, this.failure);
    this.channel.invokeMethod('phase', phase);
  }
  refreshStatus(): void { this.status(this.phase); }
  pageMounted(): void { this.pageVisible = true; }
  private fail(message: string): void {
    if (this.disposed || this.closing) return;
    this.failure = message;
    this.prepared = false;
    if (this.watchdog !== undefined) clearTimeout(this.watchdog);
    this.status(this.phase);
    this.channel.invokeMethod('error', message);
    this.disposed = true;
    this.release();
  }
  async close(): Promise<void> {
    if (this.closing) return;
    this.closing = true;
    const playing = this.prepared && !this.disposed ? this.player?.state === 'playing' : this.shouldPlay;
    const position = this.currentPosition;
    this.disposed = true;
    if (this.watchdog !== undefined) clearTimeout(this.watchdog);
    await this.release();
    if (PipSession.active === this) PipSession.active = undefined;
    if (this.pageVisible) { this.pageVisible = false; router.back(); }
    this.channel.invokeMethod('closed', { positionMs: position, playing: playing });
    this.onStatus = undefined;
  }
  private async release(): Promise<void> {
    if (!this.releasing) this.releasing = this.releaseResources();
    await this.releasing;
  }
  private async releaseResources(): Promise<void> {
    try { await this.pip?.stopPiP(); } catch (error) {}
    const player = this.player;
    this.player = undefined;
    try { await player?.release(); } catch (error) {}
    if (this.file) { try { await fs.close(this.file); } catch (error) {} this.file = undefined; }
  }
}
