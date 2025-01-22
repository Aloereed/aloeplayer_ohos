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


@Component
struct ButtonComponent {
  @Prop params: Params
  ffmpegView: FfmpegView = this.params.platformView as FfmpegView
  @StorageLink('numValue') storageLink: string = "first"
  @StorageLink('ffmpeg') ffmpeg: number = 0
  @State bkColor: Color = Color.Red
  @State offsetX: number = 0
  @State offsetY: number = 0
  @State positionX: number = 0
  @State positionY: number = 0
  

  // private audioManager: audio.AudioManager = audio.getAudioManager();
  // private audioFfmpegManager: audio.AudioFfmpegManager | undefined = undefined;

  // aboutToAppear(): void {
  //   this.audioFfmpegManager = this.audioManager.getFfmpegManager();
  //   this.audioFfmpegManager?.on('ffmpegChange', async (data) => {
  //     let event: audio.FfmpegEvent = data;
  //     this.curMediaFfmpeg = event.ffmpeg;
  //   })
  // }
  build() {
    Column() {
      Button("发送数据给Flutter")
        .border({ width: 2, color: Color.Blue })
        .backgroundColor(this.bkColor)
        .onTouch((event: TouchEvent) => {
          console.log("nodeController button on touched")
        })
        .onClick((event: ClickEvent) => {
          this.ffmpegView.sendMessage();
          console.log("nodeController button on click")
        })

      Text(`来自Flutter的数据 : ${this.storageLink}`)
        .onTouch((event: TouchEvent) => {
          console.log("nodeController text on touched")
        })




    }.alignItems(HorizontalAlign.Center)
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
AppStorage.setOrCreate('ffmpeg', 0)

@Observed
export class FfmpegView extends PlatformView implements MethodCallHandler {
  numValue: string = "test";
  ffmpeg: number = 0;
  methodChannel: MethodChannel;
  index: number = 1;

  constructor(context: common.Context, viewId: number, args: ESObject, message: BinaryMessenger) {
    super();
    // 注册消息通道
    this.methodChannel = new MethodChannel(message, `com.aloereed.aloeplayer/ffmpegView${viewId}`, StandardMethodCodec.INSTANCE);
    this.methodChannel.setMethodCallHandler(this);
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    // 接受Dart侧发来的消息
    let method: string = call.method;
    let link1: SubscribedAbstractProperty<number> = AppStorage.link('ffmpeg');
    let link2: SubscribedAbstractProperty<string> = AppStorage.link('numValue');
    switch (method) {
      case 'getMessageFromFlutterView2':
        console.log("nodeController receive start");
        let value: ESObject = call.args;
        this.ffmpeg = parseFloat(value);
        link1.set(parseFloat(value));
        console.log("nodeController receive message from dart: " + this.ffmpeg);
        result.success(true);
        break;
      case 'getMessageFromFlutterView':
        console.log("nodeController receive start");
        let value2: ESObject = call.args;
        this.numValue = value2 as string;
        link2.set(value2 as string);
        console.log("nodeController receive message from dart: " + this.numValue);
        result.success(true);
        break;
    }
  }

  public sendMessage = () => {
    console.log("nodeController sendMessage")
    //向Dart侧发送消息
    this.methodChannel.invokeMethod('getMessageFromOhosView', 'natvie - ' + this.index++);
  }

  getView(): WrappedBuilder<[Params]> {
    return new WrappedBuilder(ButtonBuilder);
  }

  dispose(): void {
  }
}