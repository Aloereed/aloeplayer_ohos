/*
* Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
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

import MethodChannel, {
  MethodCallHandler,
  MethodResult
} from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import PlatformView, { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import common from '@ohos.app.ability.common';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import StandardMethodCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMethodCodec';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';

import audio from '@ohos.multimedia.audio';
import display from '@ohos.display';
import router from '@ohos.router';
import { Callback } from '@ohos.base';
import prompt from '@ohos.promptAction';
import { PlayStatus } from '../common/PlayStatus';
import { RouterParam } from './RouterParam';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import fs from '@ohos.file.fs';
import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';

@Component
struct ButtonComponent {
  @Prop params: Params
  hdrView: HdrView = this.params.platformView as HdrView
  xComponentController: XComponentController = new XComponentController()
  @StorageLink('videoAspectRatio') videoAspectRatio: number = 1.66666;
  @StorageLink('surfaceID') surfaceID: string = '';



  aboutToAppear() {
    console.log("[hdr] aboutToAppear");
    // this.avPlayer?.on('audioInterrupt', event);
    // let deviceChangeEvent: Callback<InterruptEvent> = (event) => {
    //   console.log(`deviceChange event: ${JSON.stringify(event)}`);
    //   if (event.reason === DeviceChangeReason.REASON_NEW_DEVICE_AVAILABLE) {
    //     this.pause();
    //   } else if (event.reason === DeviceChangeReason.REASON_OLD_DEVICE_UNAVAILABLE) {
    //     this.pause();
    //   } 
    // }
    // this.avPlayer?.on('deviceChange', deviceChangeEvent);
  }

  aboutToDisappear() {
    this.hdrView.avPlayer?.release();
    // this.avPlayer?.off('deviceChange');
  }
  build() {
    Column() {
      // 全屏播放器
      Stack({ alignContent: Alignment.Center }) {
        Column() {
          XComponent({
            type: XComponentType.SURFACE, controller: this.xComponentController
          })
            .onLoad((event?: object) => {
              this.surfaceID = this.xComponentController.getXComponentSurfaceId()

              console.log(`[hdr] new surfaceid: ${this.surfaceID}`)
              // this.hdrView.newPlay()

            })
            .onDestroy(() => { })
            .width('100%')
            .aspectRatio(this.videoAspectRatio)
            .id('xcomponentId')
        }
      .aspectRatio(this.videoAspectRatio)

      }
    .width('100%')
        .height('100%')
        .backgroundColor(Color.Black)

    }
  .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .direction(Direction.Ltr)
      .width('100%')
      .height('100%')
  }



}

@Builder
function ButtonBuilder(params: Params) {
  ButtonComponent({ params: params })
    .backgroundColor(Color.Yellow)
}

AppStorage.setOrCreate('numValue', 'test')
AppStorage.setOrCreate('hdr', 0)

@Observed
export class HdrView extends PlatformView implements MethodCallHandler {
  numValue: string = "test";
  hdr: number = 0;
  videoUrl: string = '';
  methodChannel: MethodChannel;
  avPlayer: media.AVPlayer | undefined = undefined
  playing: boolean = false
  playSpeed: number = 1.0
  last_speed: number = 1
  play_time: number = 0
  videoAspectRatio: number = 1.6666
  last_play_time: number = 0

  // 注册avplayer回调函数
  setAVPlayerCallback(avPlayer: media.AVPlayer, surfaceID: string) {
    let that = this;
    // startRenderFrame首帧渲染回调函数
    avPlayer.on('startRenderFrame', () => {
      console.info(`[hdr] AVPlayer start render frame`);
    });
    // seek操作结果回调函数
    avPlayer.on('seekDone', (seekDoneTime: number) => {
      console.info(`[hdr] AVPlayer seek succeeded, seek time is ${seekDoneTime}`);
    });
    // error回调监听函数,当avPlayer在操作过程中出现错误时调用reset接口触发重置流程
    avPlayer.on('error', (err: BusinessError) => {
      console.error(`[hdr] Invoke avPlayer failed, code is ${err.code}, message is ${err.message}`);
      avPlayer.reset(); // 调用reset重置资源，触发idle状态
    });
    // 状态机变化回调函数
    avPlayer.on('stateChange', async (state: string, reason: media.StateChangeReason) => {
      switch (state) {
        case 'idle': // 成功调用reset接口后触发该状态机上报
          console.info('[hdr] AVPlayer state idle called.');
          this.sendNotPrepared();
          avPlayer.release(); // 调用release接口销毁实例对象
          break;
        case 'initialized': // avplayer 设置播放源后触发该状态上报
          console.info('[hdr] AVPlayer state initialized called.');
          console.info(`[hdr] current surfaceid: ${surfaceID}`)
          avPlayer.surfaceId = surfaceID; // 设置显示画面，当播放的资源为纯音频时无需设置
          let playStrategy: media.PlaybackStrategy = {
            preferredHdr: true
          };
          avPlayer.setPlaybackStrategy(playStrategy);
          avPlayer.prepare();
          break;
        case 'prepared': // prepare调用成功后上报该状态机
          console.info('[hdr] AVPlayer state prepared called.');
          this.sendPrepared();
          avPlayer.audioInterruptMode = audio.InterruptMode.SHARE_MODE
          that.getVideoSize();
          that.avPlayer = avPlayer;
          avPlayer.play(); // 调用播放接口开始播放
          break;
        case 'playing': // play成功调用后触发该状态机上报
          console.info('[hdr] AVPlayer state playing called.');
          that.avPlayer = avPlayer;
          break;
        case 'paused': // pause成功调用后触发该状态机上报
          console.info('[hdr] AVPlayer state paused called.');
          break;
        case 'completed': // 播放结束后触发该状态机上报
          console.info('[hdr] AVPlayer state completed called.');
          avPlayer.stop(); //调用播放结束接口
          break;
        case 'stopped': // stop接口成功调用后触发该状态机上报
          console.info('[hdr] AVPlayer state stopped called.');
          avPlayer.reset(); // 调用reset接口初始化avplayer状态
          break;
        case 'released':
          console.info('[hdr] AVPlayer state released called.');
          break;
        default:
          console.info('[hdr] AVPlayer state unknown called.');
          break;
      }
    });
    avPlayer.on('timeUpdate', (time: number) => {
      that.sendCurrentPosition();
    });
    avPlayer.on('videoSizeChange', (VideoWidth: number, VideoHeight: number) => {
      console.info('[hdr] videoSizeChange called,and width is:' + VideoWidth + ', height is :' + VideoHeight)
      let VideoAspectRatio = VideoWidth / VideoHeight;
      console.log("[hdr] getVideoAspectRatio---" + VideoAspectRatio);
      if (!Number.isNaN(VideoAspectRatio)) {
        this.videoAspectRatio = VideoAspectRatio;
        let link4: SubscribedAbstractProperty<number> = AppStorage.link('videoAspectRatio');
        link4.set(this.videoAspectRatio);
      }
    })
  }


  constructor(context: common.Context, viewId: number, args: ESObject, message: BinaryMessenger) {
    super();
    // 注册消息通道
    let that = this;
    this.methodChannel = new MethodChannel(message, `com.aloereed.aloeplayer/hdrView${viewId}`, StandardMethodCodec.INSTANCE);
    this.methodChannel.setMethodCallHandler(this);
    this.numValue = args['initParams'] as string;
    this.videoUrl = this.numValue;
    console.log(`[hdr] init videourl: ${this.videoUrl}`)


  }

  private completionNum(num: number): string | number {
    if (num < 10) {
      return '0' + num;
    } else {
      return num;
    }
  }

  private stringForTime(timeMs: number): string {
    let totalSeconds: number | string = (timeMs / 1000);
    let newSeconds: number | string = totalSeconds % 60;
    let minutes: number | string = (totalSeconds / 60) % 60;
    let hours: number | string = totalSeconds / 3600;
    console.log("[hdr] stringForTime hours:" + hours + ",minutes:" + minutes + ",seconds:" + newSeconds);
    hours = this.completionNum(Math.floor(Math.floor(hours * 100) / 100));
    minutes = this.completionNum(Math.floor(Math.floor(minutes * 100) / 100));
    newSeconds = Math.floor(Math.floor(newSeconds * 100) / 100)
    // if (this.isCurrentTime) {
    //   if (this.oldSeconds < newSeconds || newSeconds === 0 || this.isSeekTo) {
    //     this.oldSeconds = newSeconds
    //   } else {
    //     newSeconds = this.oldSeconds
    //   }
    // }
    newSeconds = this.completionNum(newSeconds);
    if (hours > 0) {
      return hours + ":" + minutes + ":" + newSeconds;
    } else {
      return minutes + ":" + newSeconds;
    }
  }


  private async play(url: string) {
    let that = this;
    this.sendNotPrepared();
    that.avPlayer?.release();
    // that.showLoadIng();
    console.log("[hdr] new play private url:" + url)
    //设置XComponent回调的context

    that.avPlayer = await media.createAVPlayer();
    let link3: SubscribedAbstractProperty<string> = AppStorage.link('surfaceID');
    // 创建状态机变化回调函数
    this.setAVPlayerCallback(that.avPlayer!, link3.get());
    // 如果url以"file://"开头
    if (url.startsWith("file://")) {
      that.avPlayer!.fdSrc = fs.openSync(url);
    } else {
      that.avPlayer!.url = url;
    }



    that.avPlayer?.play();
  }

  async newPlay() {
    await this.play(this.videoUrl);
  }

  private getVideoSize() {
    let VideoWidth = this.avPlayer?.width;
    console.log("[hdr] getVideoWidth---" + VideoWidth);

    let VideoHeight = this.avPlayer?.height;
    console.log("[hdr] getVideoHeight---" + VideoHeight);

    if (VideoWidth != null && VideoHeight != null && VideoWidth != undefined && VideoHeight != undefined) {
      let VideoAspectRatio = VideoWidth / VideoHeight;
      console.log("[hdr] getVideoAspectRatio---" + VideoAspectRatio);
      if (!Number.isNaN(VideoAspectRatio)) {
        this.videoAspectRatio = VideoAspectRatio;
        let link4: SubscribedAbstractProperty<number> = AppStorage.link('videoAspectRatio');
        link4.set(this.videoAspectRatio);
      }

    }
  }


  private pause() {
    if (this.avPlayer?.state == 'playing') {
      this.avPlayer?.pause();

    }
  }

  private stop() {
    // this.CONTROL_PlayStatus = PlayStatus.INIT;
    this.avPlayer?.stop();
    this.avPlayer?.release();
  }

  private seekTo(value: number) {
    this.avPlayer?.seek(value);

  }




  onMethodCall(call: MethodCall, result: MethodResult): void {
    // 接受Dart侧发来的消息
    let method: string = call.method;
    // let link1: SubscribedAbstractProperty<number> = AppStorage.link('hdr');
    // let link2: SubscribedAbstractProperty<string> = AppStorage.link('videoUrl');
    // let link3: SubscribedAbstractProperty<PlayStatus> = AppStorage.link('CONTROL_PlayStatus');
    // let link2: SubscribedAbstractProperty<string> = AppStorage.link('numValue');
    switch (method) {
      case 'getMessageFromFlutterView2':
        console.log("[hdr] nodeController receive start");
        let value: ESObject = call.args;
        this.hdr = parseFloat(value);
        // link1.set(parseFloat(value));
        console.log("[hdr] nodeController receive message from dart: " + this.hdr);
        result.success(true);
        break;
      case 'getMessageFromFlutterView':
        console.log("[hdr] nodeController receive start getMessageFromFlutterView");
        let value2: ESObject = call.args;
        this.numValue = value2 as string;
        this.videoUrl = this.numValue
        console.log("[hdr] nodeController receive message from dart: " + this.numValue);
        setTimeout(() => {
          this.play(this.videoUrl)
        }, 1000);
        //单例模式
        result.success(true);
        break;
      case 'newPlay':
        console.log("[hdr] nodeController receive start: newPlay");
        let value3: ESObject = call.args;
        this.videoUrl = value3 as string;
        setTimeout(() => {
          this.play(this.videoUrl)
        }, 1000);
        console.log("[hdr] nodeController receive message new play: " + this.videoUrl);
        //单例模式
        result.success(true);
        break;
      case 'resume':
        console.log("[hdr] nodeController receive start: resume");
        this.avPlayer?.play();
        console.log("[hdr] nodeController receive message from dart: " + this.videoUrl);
        //单例模式
        result.success(true);
        break;
      case 'pause':
        console.log("[hdr] nodeController receive start: pause");
        this.avPlayer?.pause();
        console.log("[hdr] nodeController receive message from dart: " + this.videoUrl);
        //单例模式
        result.success(true);
        break;
      case 'stop':
        console.log("[hdr] nodeController receive start: stop");
        this.avPlayer?.stop();
        console.log("[hdr] nodeController receive message from dart: " + this.videoUrl);
        //单例模式
        result.success(true);
        break;
      case 'seekTo':
        console.log("[hdr] nodeController receive start: seekTo");
        let value4: ESObject = call.args;
        this.avPlayer?.seek(parseInt(value4 as string));
        console.log("[hdr] nodeController receive message from dart: " + this.videoUrl);
        //单例模式
        result.success(true);
        break;
      case 'setSpeed':
        console.log("[hdr] nodeController receive start: setSpeed");
        let value5: ESObject = call.args;
        this.playSpeed = parseFloat(value5 as string);
        this.avPlayer?.setSpeed(this.playSpeed);
        console.log("[hdr] nodeController receive message from dart: " + this.videoUrl);
        //单例模式
        result.success(true);
        break;
      case 'getDuration':
        console.log("[hdr] nodeController receive start: getDuration");
        let value6: ESObject = call.args;
        let duration = this.avPlayer?.duration;
        console.log("[hdr] nodeController receive message from dart: " + this.videoUrl);
        //单例模式
        result.success(duration);
        break;
      case 'getCurrentPosition':
        console.log("[hdr] nodeController receive start: getPosition");
        let value7: ESObject = call.args;
        let currentPosition = this.avPlayer?.currentTime;
        console.log("[hdr] nodeController currentPosition: " + currentPosition);
        //单例模式
        result.success(currentPosition);
        break;
      case 'dispose':
        console.log("[hdr] nodeController receive start: dispose");
        this.avPlayer?.release();

    }
  }

  public sendMessage = () => {
    console.log("[hdr] nodeController sendMessage")
    //向Dart侧发送消息
    this.methodChannel.invokeMethod('getMessageFromOhosView', 'natvie - ');
  }

  public sendCurrentPosition = () => {
    console.log("[hdr] nodeController sendCurrentPosition")
    //向Dart侧发送消息
    this.methodChannel.invokeMethod('getCurrentPosition', this.avPlayer?.currentTime);
  }

  public sendPrepared = () => {
    console.log("[hdr] nodeController sendPrepared")
    //向Dart侧发送消息
    this.methodChannel.invokeMethod('getPrepared', true);
  }

  public sendNotPrepared = () => {
    console.log("[hdr] nodeController sendNotPrepared")
    //向Dart侧发送消息
    this.methodChannel.invokeMethod('getPrepared', false);
  }

  public sendToggleFullscreen = () => {
    console.log("[hdr] nodeController sendToggleFullscreen")
    //向Dart侧发送消息
    this.methodChannel.invokeMethod('toggleFullscreen', 'toggleFullscreen');
  }

  getView(): WrappedBuilder<[Params]> {
    return new WrappedBuilder(ButtonBuilder);
  }

  dispose(): void {
    this.avPlayer?.release();
  }
}