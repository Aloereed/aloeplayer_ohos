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
import { IjkMediaPlayer, InterruptEvent, InterruptHintType } from '@ohos/ijkplayer';
import { OnPreparedListener } from '@ohos/ijkplayer';
import { OnVideoSizeChangedListener } from '@ohos/ijkplayer';
import { OnCompletionListener } from '@ohos/ijkplayer';
import { OnBufferingUpdateListener } from '@ohos/ijkplayer';
import { OnErrorListener, OnTimedTextListener } from '@ohos/ijkplayer';
import { OnInfoListener } from '@ohos/ijkplayer';
import { OnSeekCompleteListener } from '@ohos/ijkplayer';
import { LogUtils } from '@ohos/ijkplayer';
import prompt from '@ohos.promptAction';
import { PlayStatus } from '../common/PlayStatus';
import { RouterParam } from './RouterParam';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import fs from '@ohos.file.fs';

@Component
struct ButtonComponent {
  @Prop params: Params
  ffmpegView: FfmpegView = this.params.platformView as FfmpegView
  @StorageLink('numValue') storageLink: string = "first"
  @StorageLink('ffmpeg') ffmpeg: number = 0
  @StorageLink('videoMode') videoMode: boolean = true
  @State bkColor: Color = Color.Red
  @State offsetX: number = 0
  @State offsetY: number = 0
  @State positionX: number = 0
  @State positionY: number = 0
  @State progressValue: number = 0;
  @State currentTime: string = "00:00";
  @State totalTime: string = "00:00";
  @State loadingVisible: Visibility = Visibility.None;
  @State replayVisible: Visibility = Visibility.None;
  @State controlsVisible: boolean = false;
  @State showSpeedMenu: boolean = false;
  @State slideEnable: boolean = false;
  @State aspRatio: number = 0.5;
  @State mContext: object | undefined = undefined;
  @State mFirst: boolean = true;
  @State mDestroyPage: boolean = false;
  @State playSpeed: string = '1f';
  @State origPlaySpeed: string = '1f';
  @State volume: number = 1.0;
  @State oldSeconds: number = 0;
  @State isSeekTo: boolean = false;
  @State isCurrentTime: boolean = false;
  @State videoWidth: string = '100%';
  @State initAspectRatio: number = 1;
  @StorageLink('videoAspectRatio') videoAspectRatio: number = this.initAspectRatio;
  @StorageLink('videoUrl') videoUrl: string = '';
  private last: number = 0;
  @State videoParentAspectRatio: number = this.initAspectRatio;
  private mIjkMediaPlayer = IjkMediaPlayer.getInstance();
  @StorageLink('CONTROL_PlayStatus') CONTROL_PlayStatus: PlayStatus = PlayStatus.INIT;
  @State PROGRESS_MAX_VALUE: number = 100;
  @State updateProgressTimer: number = 0;
  @State curIndex: number = 0;
  @State recordProgressVisible: Visibility = Visibility.None;
  @State screenshotProgressVisible: Visibility = Visibility.None;
  @State recordSaveFilePath: string = "";
  private videoUrls: string[] =
    [
    ];

  // initDelayPlay(context: object|undefined) {
  //   console.log("nodeController initDelayPlay")
  //   this.ffmpegView.mContext = context;
  // }


  // private audioManager: audio.AudioManager = audio.getAudioManager();
  // private audioFfmpegManager: audio.AudioFfmpegManager | undefined = undefined;

  // aboutToAppear(): void {
  //   this.audioFfmpegManager = this.audioManager.getFfmpegManager();
  //   this.audioFfmpegManager?.on('ffmpegChange', async (data) => {
  //     let event: audio.FfmpegEvent = data;
  //     this.curMediaFfmpeg = event.ffmpeg;
  //   })
  // }
  @Builder popupBuilder() {
    Column() {
      Button('0.5x')
        .onClick(() => {
          this.playSpeed = '0.5f';
          this.mIjkMediaPlayer.setSpeed("0.5f");
          this.showSpeedMenu = false; // 关闭菜单
        })
        .width('200px')
        .height('80px')
        .padding(10)
      Button('1x')
        .onClick(() => {
          this.playSpeed = '1f';
          this.mIjkMediaPlayer.setSpeed("1f");
          this.showSpeedMenu = false; // 关闭菜单
        })
        .width('200px')
        .height('80px')
        .padding(10)
      Button('1.5x')
        .onClick(() => {
          this.playSpeed = '1.5f';
          this.mIjkMediaPlayer.setSpeed("1.5f");
          this.showSpeedMenu = false; // 关闭菜单
        })
        .width('200px')
        .height('80px')
        .padding(10)
      Button('2x')
        .onClick(() => {
          this.playSpeed = '2f';
          this.mIjkMediaPlayer.setSpeed("2f");
          this.showSpeedMenu = false; // 关闭菜单
        })
        .width('200px')
        .height('80px')
        .padding(10)
      Button('3x')
        .onClick(() => {
          this.playSpeed = '3f';
          this.mIjkMediaPlayer.setSpeed("3f");
          this.showSpeedMenu = false; // 关闭菜单
        })
        .width('200px')
        .height('80px')
        .padding(10)
      Button('4x')
        .onClick(() => {
          this.playSpeed = '4f';
          this.mIjkMediaPlayer.setSpeed("4f");
          this.showSpeedMenu = false; // 关闭菜单
        })
        .width('200px')
        .height('80px')
        .padding(10)
    }
    .padding(10)
      .backgroundColor('#80000000') // 灰色半透明背景
      .borderRadius(10)
  }
  aboutToAppear() {
    LogUtils.getInstance().LOGI("[FFMPEG] aboutToAppear");
    this.videoUrl = this.ffmpegView.numValue;
    let event: Callback<InterruptEvent> = (event) => {
      LogUtils.getInstance().LOGI(`[FFMPEG] event: ${JSON.stringify(event)}`);
      if (event.hintType === InterruptHintType.INTERRUPT_HINT_PAUSE) {
        this.pause();
      } else if (event.hintType === InterruptHintType.INTERRUPT_HINT_RESUME) {
        this.startPlayOrResumePlay();
      } else if (event.hintType === InterruptHintType.INTERRUPT_HINT_STOP) {
        this.stop();
      }
    }
    // this.mIjkMediaPlayer.on('audioInterrupt', event);
    // let deviceChangeEvent: Callback<InterruptEvent> = (event) => {
    //   LogUtils.getInstance().LOGI(`[FFMPEG] deviceChange event: ${JSON.stringify(event)}`);
    //   if (event.reason === DeviceChangeReason.REASON_NEW_DEVICE_AVAILABLE) {
    //     this.pause();
    //   } else if (event.reason === DeviceChangeReason.REASON_OLD_DEVICE_UNAVAILABLE) {
    //     this.pause();
    //   } 
    // }
    // this.mIjkMediaPlayer.on('deviceChange', deviceChangeEvent);
  }
  xcomponentController: XComponentController = new XComponentController()
  aboutToDisappear() {
    LogUtils.getInstance().LOGI("[FFMPEG] aboutToDisappear");
    this.mDestroyPage = true;
    this.mIjkMediaPlayer.setScreenOnWhilePlaying(false);
    this.stopRecord(false);
    if (this.CONTROL_PlayStatus != PlayStatus.INIT) {
      this.stop();
    }
    this.mIjkMediaPlayer.off('audioInterrupt');
    // this.mIjkMediaPlayer.off('deviceChange');
  }
  build() {
    Column() {
      // 全屏播放器
      Stack({ alignContent: Alignment.Center }) {
        Column() {
          XComponent({
            id: 'xcomponentId',
            type: 'surface',
            libraryname: 'ijkplayer_napi'
          })
            .onLoad((event?: object) => {
              if (!!event) {
                this.initDelayPlay(event);
              }
            })
            .onDestroy(() => { })
            .width('100%')
            .aspectRatio(this.videoAspectRatio)
            .id('xcomponentId')
        }
      .aspectRatio(this.videoAspectRatio)
      .gesture(
        LongPressGesture({ repeat: false})
          // 由于repeat设置为true，长按动作存在时会连续触发，触发间隔为duration（默认值500ms）
          .onAction((event: GestureEvent) => {
            if (event ) {
              this.origPlaySpeed = this.playSpeed;
              this.playSpeed = '3f';
              this.mIjkMediaPlayer.setSpeed("3f");
            }
          })
            // 长按动作一结束触发
          .onActionEnd((event: GestureEvent) => {
            this.playSpeed = this.origPlaySpeed;
            this.mIjkMediaPlayer.setSpeed(this.origPlaySpeed);
          }))

        // 悬浮播放控件
        Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Center, justifyContent: FlexAlign.SpaceBetween }) {
          // 已播放时间
          Text(this.currentTime)
            .fontSize('25px')
            .fontColor(Color.White)

          // 播放/暂停按钮（图标形式）
          Image(this.CONTROL_PlayStatus === PlayStatus.PLAY ? $r('app.media.pause') : $r('app.media.play'))
            .width('50px')
            .height('50px')
            .onClick(() => {
              if (this.CONTROL_PlayStatus === PlayStatus.PLAY) {
                this.pause();
              } else {
                this.startPlayOrResumePlay();
              }
            })

          // 进度条
          Slider({
            value: this.progressValue,
            min: 0,
            max: this.PROGRESS_MAX_VALUE,
            step: 1,
            style: SliderStyle.OutSet
          })
            .width('45%')
            .blockColor(Color.Blue)
            .trackColor(Color.Gray)
            .selectedColor(Color.Blue)
            .showSteps(true)
            .showTips(true)
            .enabled(this.slideEnable)
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode == 2) {
                this.isSeekTo = true;
                this.mDestroyPage = false;
                this.showLoadIng();
                LogUtils.getInstance().LOGI("[FFMPEG] slider-->seekValue start:" + value);
                let seekValue = value * (this.mIjkMediaPlayer.getDuration() / 100);
                this.seekTo(seekValue + "");
                this.setProgress()
                LogUtils.getInstance().LOGI("[FFMPEG] slider-->seekValue end:" + seekValue);
                this.isSeekTo = false;
              }
            })

          // 总时间
          Text(this.totalTime)
            .fontSize('25px')
            .fontColor(Color.White)

          // 倍速播放按钮（文字形式，点击弹出菜单）
          Button(this.playSpeed.replace('f', '') + 'x')
            .fontSize('25px')
            .fontColor(Color.White)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.showSpeedMenu = !this.showSpeedMenu; // 控制菜单显示
            })
            .bindPopup(this.showSpeedMenu, {
              builder: this.popupBuilder,
              placement: Placement.Top,
            })

          // 全屏按钮（图标形式）
          Image($r('app.media.fullscreen'))
            .width('50px')
            .height('50px')
            .onClick(() => {
              this.ffmpegView.sendToggleFullscreen();
            })
        }
      .width('90%')
          .padding(10)
          .backgroundColor('#80000000') // 灰色半透明背景
          .borderRadius(10)
          .position({ x: '5%', y: '90%' }) // 悬浮控件位置
          .visibility(this.controlsVisible ? Visibility.Visible : Visibility.Hidden)

      }
    .width('100%')
        .height('100%')
        .backgroundColor(Color.Black)
        .onClick(() => {
          this.controlsVisible = true;
          setTimeout(() => {
            this.controlsVisible = false;
          }, 5000); // 5秒后隐藏
        })
    }
  .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .direction(Direction.Ltr)
      .width('100%')
      .height('100%')
  }


  private initDelayPlay(context: object) {
    this.mContext = context;
    this.ffmpegView.mContext = context;
    let that = this;
    setTimeout(() => {
      that.startPlayOrResumePlay();
      that.mFirst = false;
    }, 300)
  }

  private startPlayOrResumePlay() {
    this.mDestroyPage = false;
    LogUtils.getInstance().LOGI("[FFMPEG] startPlayOrResumePlay start this.CONTROL_PlayStatus:" + this.CONTROL_PlayStatus)
    LogUtils.getInstance().LOGI(`[FFMPEG] startPlayOrResumePlay this.videoUrl:${this.videoUrl}`);
    if (this.CONTROL_PlayStatus == PlayStatus.INIT) {
      this.stopProgressTask();
      this.startProgressTask();
      this.play(this.videoUrl.toString(), this.videoMode);
    }
    if (this.CONTROL_PlayStatus == PlayStatus.PAUSE) {
      this.mIjkMediaPlayer.start();
      this.CONTROL_PlayStatus = PlayStatus.PLAY;
      this.setProgress()
    }
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
    LogUtils.getInstance().LOGI("[FFMPEG] stringForTime hours:" + hours + ",minutes:" + minutes + ",seconds:" + newSeconds);
    hours = this.completionNum(Math.floor(Math.floor(hours * 100) / 100));
    minutes = this.completionNum(Math.floor(Math.floor(minutes * 100) / 100));
    newSeconds = Math.floor(Math.floor(newSeconds * 100) / 100)
    if (this.isCurrentTime) {
      if (this.oldSeconds < newSeconds || newSeconds === 0 || this.isSeekTo) {
        this.oldSeconds = newSeconds
      } else {
        newSeconds = this.oldSeconds
      }
    }
    newSeconds = this.completionNum(newSeconds);
    if (hours > 0) {
      return hours + ":" + minutes + ":" + newSeconds;
    } else {
      return minutes + ":" + newSeconds;
    }
  }

  private setProgress() {
    let position = this.mIjkMediaPlayer.getCurrentPosition();
    let duration = this.mIjkMediaPlayer.getDuration();
    let pos = 0;
    if (duration > 0) {
      this.slideEnable = true;
      let curPercent = position / duration;
      pos = curPercent * 100;
      if (pos > this.PROGRESS_MAX_VALUE) {
        this.progressValue = this.PROGRESS_MAX_VALUE
      } else {
        this.progressValue = pos;
      }
    }
    LogUtils.getInstance()
      .LOGI("setProgress position:" + position + ",duration:" + duration + ",progressValue:" + pos);
    this.totalTime = this.stringForTime(duration);
    if (position > duration) {
      position = duration;
    }
    this.isCurrentTime = true;
    this.currentTime = this.stringForTime(position);
    this.isCurrentTime = false
  }

  private startProgressTask() {
    let that = this;
    this.updateProgressTimer = setInterval(() => {
      LogUtils.getInstance().LOGI("[FFMPEG] startProgressTask");
      if (!that.mDestroyPage) {
        that.setProgress();
        that.ffmpegView.sendCurrentPosition();
      }
    }, 300);
  }

  private stopProgressTask() {
    LogUtils.getInstance().LOGI("[FFMPEG] stopProgressTask");
    clearInterval(this.updateProgressTimer);
  }

  private showLoadIng() {
    this.loadingVisible = Visibility.Visible;
    this.replayVisible = Visibility.None;
  }

  private hideLoadIng() {
    this.loadingVisible = Visibility.None;
    this.replayVisible = Visibility.None;
  }

  private showRePlay() {
    this.loadingVisible = Visibility.None;
    this.replayVisible = Visibility.Visible;
  }

  private play(url: string, videoMode: boolean = true) {
    let that = this;
    that.showLoadIng();
    //设置XComponent回调的context
    if (videoMode && !!this.mContext) {
      this.mIjkMediaPlayer.setContext(this.mContext, 'xcomponentId');
    }else{
      this.mIjkMediaPlayer.setContext(null, 'xcomponentId');
      this.mIjkMediaPlayer.setAudioId( 'xcomponentId');
    }
    if (this.CONTROL_PlayStatus == PlayStatus.INIT) {
      this.mIjkMediaPlayer.reset();
    }
    this.CONTROL_PlayStatus = PlayStatus.PLAY;
    //设置debug模式
    this.mIjkMediaPlayer.setDebug(true);
    //初始化配置
    this.mIjkMediaPlayer.native_setup();
    // 初始化配置后需要重新设置音频流音量，否则音量为默认值1.0
    this.mIjkMediaPlayer.setVolume(this.volume.toString(), this.volume.toString());
    //设置视频源
    this.mIjkMediaPlayer.setDataSource(url);
    //设置视频源http请求头
    let headers = new Map([
      ["user_agent", "Mozilla/5.0 BiliDroid/7.30.0 (bbcallen@gmail.com)"],
      ["referer", "https://www.bilibili.com"]
    ]);
    this.mIjkMediaPlayer.setDataSourceHeader(headers);
    //使用精确寻帧 例如，拖动播放后，会寻找最近的关键帧进行播放，很有可能关键帧的位置不是拖动后的位置，而是较前的位置.可以设置这个参数来解决问题
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "enable-accurate-seek", "1");
    //预读数据的缓冲区大小
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "max-buffer-size", "204800");
    //停止预读的最小帧数
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "min-frames", "100");
    //启动预加载
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "start-on-prepared", "1");
    // 设置无缓冲，这是播放器的缓冲区，有数据就播放
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "packet-buffering", "0");
    //跳帧处理,放CPU处理较慢时，进行跳帧处理，保证播放流程，画面和声音同步
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "framedrop", "5");
    // 最大缓冲cache是3s， 有时候网络波动，会突然在短时间内收到好几秒的数据
    // 因此需要播放器丢包，才不会累积延时
    // 这个和第三个参数packet-buffering无关。
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "max_cached_duration", "3000");
    // 无限制收流
    // this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "infbuf", "1");
    // this.mIjkMediaPlayer.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "infbuf", "1")
    // 开启h264与h265硬解码
    // this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec-all-videos", "1");
    // this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec-hevc", "1");
    // 屏幕常亮
    this.mIjkMediaPlayer.setScreenOnWhilePlaying(true);
    // 设置超时
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "timeout", "10000000");
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "connect_timeout", "10000000");
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "addrinfo_timeout", "10000000");
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "dns_cache_timeout", "10000000");
    // 变速播放
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "soundtouch", "1");
    this.mIjkMediaPlayer.setSpeed(this.playSpeed);
    let Speed = this.mIjkMediaPlayer.getSpeed()
    LogUtils.getInstance().LOGI('[FFMPEG] getSpeed--' + Speed)
    //是否开启循环播放
    this.mIjkMediaPlayer.setLoopCount(false);
    let mOnVideoSizeChangedListener: OnVideoSizeChangedListener = {
      onVideoSizeChanged: (width: number, height: number, sar_num: number, sar_den: number) => {
        if (height === 0) {
          return;
        }
        const va = width / height;
        const vpa = that.videoParentAspectRatio;
        if (vpa > va) {
          that.videoWidth = (width / (height * vpa)) * 100 + '%';
        } else {
          that.videoWidth = '100%';
        }
        if (width && height) {
          that.videoAspectRatio = width / height;
        }
        LogUtils.getInstance()
          .LOGI("setOnVideoSizeChangedListener-->go:" + width + "," + height + "," + sar_num + "," + sar_den);
        that.getVideoSize();
        that.hideLoadIng();
      }
    }
    this.mIjkMediaPlayer.setOnVideoSizeChangedListener(mOnVideoSizeChangedListener);
    let mOnPreparedListener: OnPreparedListener = {
      onPrepared: () => {
        LogUtils.getInstance().LOGI("[FFMPEG] setOnPreparedListener-->go");
      }
    }
    this.mIjkMediaPlayer.setOnPreparedListener(mOnPreparedListener);

    let mOnTimedTextListener: OnTimedTextListener = {
      onTimedText: () => {
      }
    }
    this.mIjkMediaPlayer.setOnTimedTextListener(mOnTimedTextListener)

    let mOnCompletionListener: OnCompletionListener = {
      onCompletion: () => {
        LogUtils.getInstance().LOGI("[FFMPEG] OnCompletionListener-->go")
        that.showRePlay();
        that.currentTime = that.stringForTime(this.mIjkMediaPlayer.getDuration());
        that.progressValue = this.PROGRESS_MAX_VALUE;
        that.slideEnable = false;
        // that.stop();
      }
    }
    this.mIjkMediaPlayer.setOnCompletionListener(mOnCompletionListener);

    let mOnBufferingUpdateListener: OnBufferingUpdateListener = {
      onBufferingUpdate: (percent: number) => {
        LogUtils.getInstance().LOGI("[FFMPEG] OnBufferingUpdateListener-->go:" + percent);
        let MediaInfo = this.mIjkMediaPlayer.getMediaInfo()
        LogUtils.getInstance().LOGI('[FFMPEG] getMediaInfo---' + MediaInfo);
        let VideoWidth = this.mIjkMediaPlayer.getVideoWidth()
        LogUtils.getInstance().LOGI('[FFMPEG] getVideoWidth---' + VideoWidth);

        let VideoHeight = this.mIjkMediaPlayer.getVideoHeight()
        LogUtils.getInstance().LOGI('[FFMPEG] getVideoHeight---' + VideoHeight);

        let VideoSarNum = this.mIjkMediaPlayer.getVideoSarNum()
        LogUtils.getInstance().LOGI('[FFMPEG] getVideoSarNum---' + VideoSarNum);

        let VideoSarDen = this.mIjkMediaPlayer.getVideoSarDen()
        LogUtils.getInstance().LOGI('[FFMPEG] getVideoSarDen---' + VideoSarDen);

        let AudioSessionId = this.mIjkMediaPlayer.getAudioSessionId()
        LogUtils.getInstance().LOGI('[FFMPEG] getAudioSessionId---' + AudioSessionId);

        let Looping = this.mIjkMediaPlayer.isLooping()
        LogUtils.getInstance().LOGI('[FFMPEG] isLooping---' + Looping);
      }
    }
    this.mIjkMediaPlayer.setOnBufferingUpdateListener(mOnBufferingUpdateListener);

    let mOnSeekCompleteListener: OnSeekCompleteListener = {
      onSeekComplete: () => {
        LogUtils.getInstance().LOGI("[FFMPEG] OnSeekCompleteListener-->go");
        that.startPlayOrResumePlay();
      }
    }
    this.mIjkMediaPlayer.setOnSeekCompleteListener(mOnSeekCompleteListener);

    let mOnInfoListener: OnInfoListener = {
      onInfo: (what: number, extra: number) => {
        LogUtils.getInstance().LOGI("[FFMPEG] OnInfoListener-->go:" + what + "===" + extra);
        that.hideLoadIng();
      }
    }
    this.mIjkMediaPlayer.setOnInfoListener(mOnInfoListener);


    let mOnErrorListener: OnErrorListener = {
      onError: (what: number, extra: number) => {
        this.stopProgressTask();
        LogUtils.getInstance().LOGI("[FFMPEG] OnErrorListener-->go:" + what + "===" + extra)
        that.hideLoadIng();
        prompt.showToast({
          message: getContext().resourceManager.getStringByNameSync("Honey_the_video_is_playing_errant_The_system_is_wandering")
        });
      }
    }


    this.mIjkMediaPlayer.setOnErrorListener(mOnErrorListener);

    this.mIjkMediaPlayer.setMessageListener();

    this.mIjkMediaPlayer.prepareAsync();

    this.mIjkMediaPlayer.start();
  }

  private getVideoSize() {
    let VideoWidth = this.mIjkMediaPlayer.getVideoWidth();
    LogUtils.getInstance().LOGI("[FFMPEG] getVideoWidth---" + VideoWidth);

    let VideoHeight = this.mIjkMediaPlayer.getVideoHeight();
    LogUtils.getInstance().LOGI("[FFMPEG] getVideoHeight---" + VideoHeight);
  }


  private pause() {
    if (this.mIjkMediaPlayer.isPlaying()) {
      this.mIjkMediaPlayer.pause();
      this.setProgress();
      this.mDestroyPage = true;
      this.CONTROL_PlayStatus = PlayStatus.PAUSE;
    }
  }

  private stop() {
    this.CONTROL_PlayStatus = PlayStatus.INIT;
    this.mIjkMediaPlayer.stop();
    this.mIjkMediaPlayer.release();
    this.stopProgressTask();
  }

  private seekTo(value: string) {
    this.mIjkMediaPlayer.seekTo(value);

  }

  private playNext() {
    if (!this.debounce()) {
      return;
    }
    if (this.curIndex == this.videoUrls.length - 1) {
      this.curIndex = 0;
    } else {
      this.curIndex++;
    }
    this.CONTROL_PlayStatus = PlayStatus.INIT;
    this.stop();
    this.videoUrl = this.videoUrls[this.curIndex];
    this.startPlayOrResumePlay()
  }

  debounce() {
    const delay = 600;
    let cur = new Date().getTime();
    if (cur - this.last > delay) {
      this.last = cur;
      return true;
    }
    return false;
  }

  private startRecord() {
    // let isRecord = this.mIjkMediaPlayer.isRecord()
    // if (isRecord) {
    //   prompt.showToast({
    //     message: $r('app.string.recordIng')
    //   });
    //   return
    // }
    // this.recordSaveFilePath = getContext(this).cacheDir + "/record.mp4";
    // let result = this.mIjkMediaPlayer.startRecord(this.recordSaveFilePath);
    // prompt.showToast({
    //   message: result ? $r('app.string.start_record_success') : $r('app.string.start_record_failed')
    // });
  }

  private stopRecord(isShowTip: boolean) {
    // let isRecord = this.mIjkMediaPlayer.isRecord()
    // if (!isRecord) {
    //   if (isShowTip) {
    //     prompt.showToast({
    //       message:  $r('app.string.record_not_enabled')
    //     });
    //   }
    //   return
    // }
    // this.recordProgressVisible = Visibility.Visible;
    // let that = this;
    // this.mIjkMediaPlayer.stopRecord().then((result) => {
    //   that.recordProgressVisible = Visibility.None;
    //   if(!result){
    //     prompt.showToast({
    //       message: $r('app.string.stop_record_failed')
    //     });
    //     return;
    //   }
    //   let atManager = abilityAccessCtrl.createAtManager();
    //   atManager.requestPermissionsFromUser(getContext(that), ['ohos.permission.WRITE_IMAGEVIDEO']).then(async () => {
    //     let photoType: photoAccessHelper.PhotoType = photoAccessHelper.PhotoType.VIDEO;
    //     let extension:string = 'mp4';
    //     let options: photoAccessHelper.CreateOptions = {
    //       title: "record_"+new Date().getTime()+""
    //     }
    //     let phAccessHelper = photoAccessHelper.getPhotoAccessHelper(getContext(that));
    //     phAccessHelper.createAsset(photoType, extension, options, (err, uri) => {
    //       LogUtils.getInstance().LOGI(`[FFMPEG] createAsset success uri:${uri}`)
    //       if (uri !== undefined) {
    //         let recordFile = fs.openSync(that.recordSaveFilePath);
    //         let albumFile = fs.openSync(uri,fs.OpenMode.READ_WRITE);
    //         fs.copyFileSync(recordFile.fd,albumFile.fd);
    //         fs.closeSync(recordFile);
    //         fs.closeSync(albumFile);
    //         prompt.showToast({
    //           message: $r('app.string.stop_record_success')
    //         });
    //       } else {
    //         prompt.showToast({
    //           message: $r('app.string.stop_record_failed')
    //         });
    //         LogUtils.getInstance().LOGI(`[FFMPEG] createAsset failed, error: ${err.code}, ${err.message}`)
    //       }
    //     });
    //   })
    // })
  }

  private screenshot() {
    // let that = this;
    // let saveFilePath = getContext(this).cacheDir + "/screen.jpg";
    // this.screenshotProgressVisible = Visibility.Visible;
    // this.mIjkMediaPlayer.screenshot(saveFilePath).then((result) => {
    //   that.screenshotProgressVisible = Visibility.None;
    //   if(!result) {
    //     prompt.showToast({
    //       message: $r('app.string.screenshot_failed')
    //     });
    //     return;
    //   }
    //   let atManager = abilityAccessCtrl.createAtManager();
    //   atManager.requestPermissionsFromUser(getContext(that), ['ohos.permission.WRITE_IMAGEVIDEO']).then(async () => {
    //     let photoType: photoAccessHelper.PhotoType = photoAccessHelper.PhotoType.IMAGE;
    //     let extension:string = 'jpg';
    //     let options: photoAccessHelper.CreateOptions = {
    //       title: "screenshot_"+new Date().getTime()+""
    //     }
    //     let phAccessHelper = photoAccessHelper.getPhotoAccessHelper(getContext(that));
    //     phAccessHelper.createAsset(photoType, extension, options, (err, uri) => {
    //       LogUtils.getInstance().LOGI(`[FFMPEG] createAsset success uri:${uri}`)
    //       if (uri !== undefined) {
    //         let screenshotFile = fs.openSync(saveFilePath);
    //         let albumFile = fs.openSync(uri,fs.OpenMode.READ_WRITE);
    //         fs.copyFileSync(screenshotFile.fd,albumFile.fd);
    //         fs.closeSync(screenshotFile);
    //         fs.closeSync(albumFile);
    //         prompt.showToast({
    //           message: $r('app.string.screenshot_success')
    //         });
    //       } else {
    //         prompt.showToast({
    //           message: $r('app.string.screenshot_failed')
    //         });
    //         LogUtils.getInstance().LOGI(`[FFMPEG] createAsset failed, error: ${err.code}, ${err.message}`)
    //       }
    //     });
    //   })
    // });
  }
}

@Builder
function ButtonBuilder(params: Params) {
  ButtonComponent({ params: params })
    .backgroundColor(Color.Yellow)
}

AppStorage.setOrCreate('numValue', 'test')
AppStorage.setOrCreate('ffmpeg', 0)

@Observed
export class FfmpegView extends PlatformView implements MethodCallHandler {
  numValue: string = "test";
  ffmpeg: number = 0;
  videoMode: boolean = true;
  methodChannel: MethodChannel;
  index: number = 1;
  mContext: object | undefined = undefined
  offsetX: number = 0
  offsetY: number = 0
  positionX: number = 0
  positionY: number = 0
  progressValue: number = 0;
  currentTime: string = "00:00";
  totalTime: string = "00:00";
  loadingVisible: Visibility = Visibility.None;
  replayVisible: Visibility = Visibility.None;
  controlsVisible: boolean = false;
  showSpeedMenu: boolean = false;
  slideEnable: boolean = false;
  aspRatio: number = 0.5;
  mFirst: boolean = true;
  mDestroyPage: boolean = false;
  playSpeed: string = '1f';
  volume: number = 1.0;
  oldSeconds: number = 0;
  isSeekTo: boolean = false;
  isCurrentTime: boolean = false;
  videoWidth: string = '100%';
  initAspectRatio: number = 1;
  videoAspectRatio: number = this.initAspectRatio;
  videoUrl: string = '';

  private last: number = 0;
  videoParentAspectRatio: number = this.initAspectRatio;
  // @StorageLink('CONTROL_PlayStatus') CONTROL_PlayStatus: PlayStatus = PlayStatus.INIT;
  PROGRESS_MAX_VALUE: number = 100;
  updateProgressTimer: number = 0;
  curIndex: number = 0;
  recordProgressVisible: Visibility = Visibility.None;
  screenshotProgressVisible: Visibility = Visibility.None;
  recordSaveFilePath: string = "";
  private videoUrls: string[] =
    [
    ];
  private mIjkMediaPlayer = IjkMediaPlayer.getInstance();

  constructor(context: common.Context, viewId: number, args: ESObject, message: BinaryMessenger) {
    super();
    // 注册消息通道
    this.methodChannel = new MethodChannel(message, `com.aloereed.aloeplayer/ffmpegView${viewId}`, StandardMethodCodec.INSTANCE);
    this.methodChannel.setMethodCallHandler(this);
    this.numValue = args['initParams'] as string;
    this.numValue = args['initParams'] as string;
    this.videoMode = args['videoMode'] as boolean;
    console.log(`[FFMPEG] numValue: ${this.numValue}`)
    console.log(`[FFMPEG] videoMode: ${this.videoMode}`)
  }

  private startProgressTask() {
    let that = this;
    this.updateProgressTimer = setInterval(() => {
      LogUtils.getInstance().LOGI("[FFMPEG] startProgressTask");
      if (!that.mDestroyPage) {
        // that.setProgress();
        that.sendCurrentPosition();
      }
    }, 300);
  }

  private stopProgressTask() {
    LogUtils.getInstance().LOGI("[FFMPEG] stopProgressTask");
    clearInterval(this.updateProgressTimer);
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
    LogUtils.getInstance().LOGI("[FFMPEG] stringForTime hours:" + hours + ",minutes:" + minutes + ",seconds:" + newSeconds);
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


  private play(url: string, videoMode: boolean = true) {
    let that = this;
    // that.showLoadIng();
    //设置XComponent回调的context
    if (videoMode && !!this.mContext) {
      this.mIjkMediaPlayer.setContext(this.mContext, 'xcomponentId');
    }else{
      this.mIjkMediaPlayer.setContext(null, 'xcomponentId');
      this.mIjkMediaPlayer.setAudioId( 'xcomponentId');
    }

    this.mIjkMediaPlayer.reset();

    //设置debug模式
    this.mIjkMediaPlayer.setDebug(true);
    //初始化配置
    this.mIjkMediaPlayer.native_setup();
    // 初始化配置后需要重新设置音频流音量，否则音量为默认值1.0
    this.mIjkMediaPlayer.setVolume(this.volume.toString(), this.volume.toString());
    //设置视频源
    this.mIjkMediaPlayer.setDataSource(url);
    //设置视频源http请求头
    let headers = new Map([
      ["user_agent", "Mozilla/5.0 BiliDroid/7.30.0 (bbcallen@gmail.com)"],
      ["referer", "https://www.bilibili.com"]
    ]);
    this.mIjkMediaPlayer.setDataSourceHeader(headers);
    //使用精确寻帧 例如，拖动播放后，会寻找最近的关键帧进行播放，很有可能关键帧的位置不是拖动后的位置，而是较前的位置.可以设置这个参数来解决问题
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "enable-accurate-seek", "1");
    //预读数据的缓冲区大小
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "max-buffer-size", "204800");
    //停止预读的最小帧数
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "min-frames", "100");
    //启动预加载
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "start-on-prepared", "1");
    // 设置无缓冲，这是播放器的缓冲区，有数据就播放
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "packet-buffering", "0");
    //跳帧处理,放CPU处理较慢时，进行跳帧处理，保证播放流程，画面和声音同步
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "framedrop", "5");
    // 最大缓冲cache是3s， 有时候网络波动，会突然在短时间内收到好几秒的数据
    // 因此需要播放器丢包，才不会累积延时
    // 这个和第三个参数packet-buffering无关。
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "max_cached_duration", "3000");
    // 无限制收流
    // this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "infbuf", "1");
    // this.mIjkMediaPlayer.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "infbuf", "1")
    // 开启h264与h265硬解码
    // this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec-all-videos", "1");
    // this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec-hevc", "1");
    // 屏幕常亮
    this.mIjkMediaPlayer.setScreenOnWhilePlaying(true);
    // 设置超时
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "timeout", "10000000");
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "connect_timeout", "10000000");
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "addrinfo_timeout", "10000000");
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "dns_cache_timeout", "10000000");
    // 变速播放
    this.mIjkMediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "soundtouch", "1");
    this.mIjkMediaPlayer.setSpeed(this.playSpeed);
    let Speed = this.mIjkMediaPlayer.getSpeed()
    LogUtils.getInstance().LOGI('[FFMPEG] getSpeed--' + Speed)
    //是否开启循环播放
    this.mIjkMediaPlayer.setLoopCount(false);
    let mOnVideoSizeChangedListener: OnVideoSizeChangedListener = {
      onVideoSizeChanged: (width: number, height: number, sar_num: number, sar_den: number) => {
        if (height === 0) {
          return;
        }
        const va = width / height;
        const vpa = that.videoParentAspectRatio;
        if (vpa > va) {
          that.videoWidth = (width / (height * vpa)) * 100 + '%';
        } else {
          that.videoWidth = '100%';
        }
        if (width && height) {
          that.videoAspectRatio = width / height;
          let link4: SubscribedAbstractProperty<number> = AppStorage.link('videoAspectRatio');
          link4.set(that.videoAspectRatio);
        }
        LogUtils.getInstance()
          .LOGI("setOnVideoSizeChangedListener-->go:" + width + "," + height + "," + sar_num + "," + sar_den);
        that.getVideoSize();
        // that.hideLoadIng();
      }
    }
    this.mIjkMediaPlayer.setOnVideoSizeChangedListener(mOnVideoSizeChangedListener);
    let mOnPreparedListener: OnPreparedListener = {
      onPrepared: () => {
        LogUtils.getInstance().LOGI("[FFMPEG] setOnPreparedListener-->go");
      }
    }
    this.mIjkMediaPlayer.setOnPreparedListener(mOnPreparedListener);

    let mOnTimedTextListener: OnTimedTextListener = {
      onTimedText: () => {
      }
    }
    this.mIjkMediaPlayer.setOnTimedTextListener(mOnTimedTextListener)

    let mOnCompletionListener: OnCompletionListener = {
      onCompletion: () => {
        LogUtils.getInstance().LOGI("[FFMPEG] OnCompletionListener-->go")
        // that.showRePlay();
        // that.currentTime = that.stringForTime(this.mIjkMediaPlayer.getDuration());
        // that.progressValue = this.PROGRESS_MAX_VALUE;
        // that.slideEnable = false;
        // that.stop();
      }
    }
    this.mIjkMediaPlayer.setOnCompletionListener(mOnCompletionListener);

    let mOnBufferingUpdateListener: OnBufferingUpdateListener = {
      onBufferingUpdate: (percent: number) => {
        LogUtils.getInstance().LOGI("[FFMPEG] OnBufferingUpdateListener-->go:" + percent);
        let MediaInfo = this.mIjkMediaPlayer.getMediaInfo()
        LogUtils.getInstance().LOGI('[FFMPEG] getMediaInfo---' + MediaInfo);
        let VideoWidth = this.mIjkMediaPlayer.getVideoWidth()
        LogUtils.getInstance().LOGI('[FFMPEG] getVideoWidth---' + VideoWidth);

        let VideoHeight = this.mIjkMediaPlayer.getVideoHeight()
        LogUtils.getInstance().LOGI('[FFMPEG] getVideoHeight---' + VideoHeight);

        let VideoSarNum = this.mIjkMediaPlayer.getVideoSarNum()
        LogUtils.getInstance().LOGI('[FFMPEG] getVideoSarNum---' + VideoSarNum);

        let VideoSarDen = this.mIjkMediaPlayer.getVideoSarDen()
        LogUtils.getInstance().LOGI('[FFMPEG] getVideoSarDen---' + VideoSarDen);

        let AudioSessionId = this.mIjkMediaPlayer.getAudioSessionId()
        LogUtils.getInstance().LOGI('[FFMPEG] getAudioSessionId---' + AudioSessionId);

        let Looping = this.mIjkMediaPlayer.isLooping()
        LogUtils.getInstance().LOGI('[FFMPEG] isLooping---' + Looping);
      }
    }
    this.mIjkMediaPlayer.setOnBufferingUpdateListener(mOnBufferingUpdateListener);

    let mOnSeekCompleteListener: OnSeekCompleteListener = {
      onSeekComplete: () => {
        LogUtils.getInstance().LOGI("[FFMPEG] OnSeekCompleteListener-->go");
        // that.startPlayOrResumePlay();
        that.mIjkMediaPlayer.start();
      }
    }
    this.mIjkMediaPlayer.setOnSeekCompleteListener(mOnSeekCompleteListener);

    let mOnInfoListener: OnInfoListener = {
      onInfo: (what: number, extra: number) => {
        LogUtils.getInstance().LOGI("[FFMPEG] OnInfoListener-->go:" + what + "===" + extra);
        // that.hideLoadIng();
      }
    }
    this.mIjkMediaPlayer.setOnInfoListener(mOnInfoListener);


    let mOnErrorListener: OnErrorListener = {
      onError: (what: number, extra: number) => {
        // this.stopProgressTask();
        LogUtils.getInstance().LOGI("[FFMPEG] OnErrorListener-->go:" + what + "===" + extra)
        // that.hideLoadIng();
        prompt.showToast({
          message: getContext().resourceManager.getStringByNameSync("Honey_the_video_is_playing_errant_The_system_is_wandering")
        });
      }
    }


    this.mIjkMediaPlayer.setOnErrorListener(mOnErrorListener);

    this.mIjkMediaPlayer.setMessageListener();

    this.mIjkMediaPlayer.prepareAsync();

    this.mIjkMediaPlayer.start();

    this.startProgressTask();
  }

  private getVideoSize() {
    let VideoWidth = this.mIjkMediaPlayer.getVideoWidth();
    LogUtils.getInstance().LOGI("[FFMPEG] getVideoWidth---" + VideoWidth);

    let VideoHeight = this.mIjkMediaPlayer.getVideoHeight();
    LogUtils.getInstance().LOGI("[FFMPEG] getVideoHeight---" + VideoHeight);
  }


  private pause() {
    if (this.mIjkMediaPlayer.isPlaying()) {
      this.mIjkMediaPlayer.pause();
      // this.setProgress();
      // this.mDestroyPage = true;
      // this.CONTROL_PlayStatus = PlayStatus.PAUSE;
    }
  }

  private stop() {
    // this.CONTROL_PlayStatus = PlayStatus.INIT;
    this.mIjkMediaPlayer.stop();
    this.mIjkMediaPlayer.release();
  }

  private seekTo(value: string) {
    this.mIjkMediaPlayer.seekTo(value);

  }



  onMethodCall(call: MethodCall, result: MethodResult): void {
    // 接受Dart侧发来的消息
    let method: string = call.method;
    let link1: SubscribedAbstractProperty<number> = AppStorage.link('ffmpeg');
    let link2: SubscribedAbstractProperty<string> = AppStorage.link('videoUrl');
    let link3: SubscribedAbstractProperty<PlayStatus> = AppStorage.link('CONTROL_PlayStatus');
    let link5: SubscribedAbstractProperty<boolean> = AppStorage.link('videoMode');
    // let link2: SubscribedAbstractProperty<string> = AppStorage.link('numValue');
    switch (method) {
      case 'getMessageFromFlutterView2':
        console.log(`nodeController receive start: ${method}`);
        let value: ESObject = call.args;
        this.ffmpeg = parseFloat(value);
        link1.set(parseFloat(value));
        console.log("nodeController receive message from dart: " + this.ffmpeg);
        result.success(true);
        break;
      case 'getMessageFromFlutterView':
        console.log(`nodeController receive start: ${method}`);
        let value2: ESObject = call.args;
        this.numValue = value2 as string;
        // 检查numValue是否以“!”开头
        if(this.numValue.startsWith('!')){
          this.videoMode = false;
          this.numValue = this.numValue.substring(1)
        }
        link2.set(this.numValue);
        link3.set(PlayStatus.INIT);
        link5.set(this.videoMode)
        console.log("nodeController receive message from dart: " + this.numValue);
        //单例模式
        result.success(true);
        break;
      case 'newPlay':
        console.log(`nodeController receive start: ${method}`);
        let value3: ESObject = call.args;
        this.videoUrl = value3 as string;
        link5.set(this.videoMode)
        this.play(this.videoUrl,this.videoMode);
        console.log("nodeController receive message new play: " + this.videoUrl);
        //单例模式
        result.success(true);
        break;
      case 'resume':
        console.log(`nodeController receive start: ${method}`);
        this.mIjkMediaPlayer.start();
        console.log("nodeController receive message from dart: " + this.videoUrl);
        //单例模式
        result.success(true);
        break;
      case 'pause':
        console.log(`nodeController receive start: ${method}`);
        this.mIjkMediaPlayer.pause();
        console.log("nodeController receive message from dart: " + this.videoUrl);
        //单例模式
        result.success(true);
        break; 
      case 'stop':
        console.log(`nodeController receive start: ${method}`);
        this.mIjkMediaPlayer.stop();
        console.log("nodeController receive message from dart: " + this.videoUrl);
        //单例模式
        result.success(true);
        break;
      case 'seekTo':
        console.log(`nodeController receive start: ${method}`);
        let value4: ESObject = call.args;
        this.mIjkMediaPlayer.seekTo(value4 as string);
        console.log("nodeController receive message from dart: " + this.videoUrl);
        //单例模式
        result.success(true);
        break;
      case 'setSpeed':
        console.log(`nodeController receive start: ${method}`);
        let value5: ESObject = call.args;
        this.playSpeed = value5 as string;
        this.mIjkMediaPlayer.setSpeed(this.playSpeed);
        console.log("nodeController receive message from dart: " + this.videoUrl);
        //单例模式
        result.success(true);
        break;
      case 'getDuration':
        console.log(`nodeController receive start: ${method}`);
        let value6: ESObject = call.args;
        let duration = this.mIjkMediaPlayer.getDuration();
        console.log("nodeController receive message from dart: " + this.videoUrl);
        //单例模式
        result.success(duration);
        break;
      case 'getCurrentPosition':
        console.log(`nodeController receive start: ${method}`);
        let value7: ESObject = call.args;
        let currentPosition = this.mIjkMediaPlayer.getCurrentPosition();
        console.log("nodeController currentPosition: " + currentPosition);
        //单例模式
        result.success(currentPosition);
        break;

    }
  }

  public sendMessage = () => {
    console.log("nodeController sendMessage")
    //向Dart侧发送消息
    this.methodChannel.invokeMethod('getMessageFromOhosView', 'natvie - ' + this.index++);
  }

  public sendCurrentPosition = () => {
    console.log("nodeController sendCurrentPosition")
    //向Dart侧发送消息
    this.methodChannel.invokeMethod('getCurrentPosition', this.mIjkMediaPlayer.getCurrentPosition());
  }
  public sendToggleFullscreen = () => {
    console.log("nodeController sendToggleFullscreen")
    //向Dart侧发送消息
    this.methodChannel.invokeMethod('toggleFullscreen', 'toggleFullscreen');
  }

  getView(): WrappedBuilder<[Params]> {
    return new WrappedBuilder(ButtonBuilder);
  }

  dispose(): void {
  }
}