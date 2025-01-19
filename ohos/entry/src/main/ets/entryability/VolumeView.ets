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
import { AVVolumePanel } from '@kit.AudioKit';
import audio from '@ohos.multimedia.audio';
import display from '@ohos.display';


@Component
struct ButtonComponent {
  @Prop params: Params
  volumeView: VolumeView = this.params.platformView as VolumeView
  @StorageLink('numValue') storageLink: string = "first"
  @StorageLink('volume') volume: number = 0
  @State bkColor: Color = Color.Red
  @State offsetX: number = 0
  @State offsetY: number = 0
  @State positionX: number = 0
  @State positionY: number = 0
  @State private curMediaVolume: number = 0;
  private panOption: PanGestureOptions = new PanGestureOptions({ direction: PanDirection.Left | PanDirection.Right })
  private volumePanOption: PanGestureOptions = new PanGestureOptions({ direction: PanDirection.Up | PanDirection.Down })

  // private audioManager: audio.AudioManager = audio.getAudioManager();
  // private audioVolumeManager: audio.AudioVolumeManager | undefined = undefined;

  // aboutToAppear(): void {
  //   this.audioVolumeManager = this.audioManager.getVolumeManager();
  //   this.audioVolumeManager?.on('volumeChange', async (data) => {
  //     let event: audio.VolumeEvent = data;
  //     this.curMediaVolume = event.volume;
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
          this.volumeView.sendMessage();
          console.log("nodeController button on click")
        })

      Text(`来自Flutter的数据 : ${this.storageLink}`)
        .onTouch((event: TouchEvent) => {
          console.log("nodeController text on touched")
        })


        AVVolumePanel({
          volumeLevel: this.volume,
          }).gesture(PanGesture(this.volumePanOption)
          .onActionStart((event: GestureEvent) => {
            console.info('Pan start')
          })
          .onActionUpdate((event: GestureEvent) => {
            if (event) {
              //this.offsetX = this.positionX + event.offsetX
              this.offsetY = this.positionY + event.offsetY
              this.volume = this.offsetY
              console.log("音量是：", this.volume)
            }
          })
          .onActionEnd((event: GestureEvent) => {
            this.positionX = this.offsetX
            this.positionY = this.offsetY
            console.info('Pan end')
          })
        ).backgroundColor(Color.Green)
          .width("10%").height("10%")
  
  
  
  
        Button('修改PanGesture触发条件')
          .onClick(() => {
            // 将PanGesture手势事件触发条件改为双指以任意方向拖动
            this.panOption.setDirection(PanDirection.All)
            this.panOption.setFingers(2)
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
AppStorage.setOrCreate('volume', 0)

@Observed
export class VolumeView extends PlatformView implements MethodCallHandler {
  numValue: string = "test";
  volume: number = 0;
  methodChannel: MethodChannel;
  index: number = 1;

  constructor(context: common.Context, viewId: number, args: ESObject, message: BinaryMessenger) {
    super();
    // 注册消息通道
    this.methodChannel = new MethodChannel(message, `com.aloereed.aloeplayer/volumeView${viewId}`, StandardMethodCodec.INSTANCE);
    this.methodChannel.setMethodCallHandler(this);
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    // 接受Dart侧发来的消息
    let method: string = call.method;
    let link1: SubscribedAbstractProperty<number> = AppStorage.link('volume');
    let link2: SubscribedAbstractProperty<string> = AppStorage.link('numValue');
    switch (method) {
      case 'getMessageFromFlutterView2':
        console.log("nodeController receive start");
        let value: ESObject = call.args;
        this.volume = parseFloat(value);
        link1.set(parseFloat(value));
        console.log("nodeController receive message from dart: " + this.volume);
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