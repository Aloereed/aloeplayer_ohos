
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

import {
  Any,
  BasicMessageChannel,
  EventChannel,
  FlutterManager,
  FlutterPlugin,
  Log,
  MethodCall,
  MethodChannel,
  StandardMessageCodec
} from '@ohos/flutter_ohos';
import { FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { EventSink } from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';
import { picker } from '@kit.CoreFileKit';
import { BusinessError, emitter } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { taskpool } from '@kit.ArkTS';
import { common, Want } from '@kit.AbilityKit';
import { HdrFactory } from './HdrFactory';
import { audio } from '@kit.AudioKit';
import { image } from '@kit.ImageKit';
import { buffer } from '@kit.ArkTS';
import media from "@ohos.multimedia.media"
import fs from "@ohos.file.fs"
import libAddon from 'libentry.so'
// import testNapi from 'libentry.so';
import { FFMpegUtils, FFmpegCommandOptions } from './FFmpegUtils';


const TAG = "HdrPluginTag";

export default class HdrPlugin implements FlutterPlugin {
  private channel?: MethodChannel;
  private eventSink?: EventSink;
  private eventChannel?: EventChannel;
  private api = new HdrApi();

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "samples.flutter.dev/hdrplugin");
    let that = this;
    this.channel.setMethodCallHandler({
      onMethodCall(call: MethodCall, result: MethodResult) {
        switch (call.method) {
          case "createSubWindow":
            that.api.CreateSubWindow(result);
            break;
            case "createNewWindow":
              that.api.CreateNewWindow(result,  call.argument("path") as string,  call.argument("uris") as string);
              break;
          case "callEvent":
            that.eventSink?.success("Success at " + new Date());
            break;
            break;
          default:
            result.notImplemented();
            break;
        }
      }
    })
    binding.getPlatformViewRegistry()?.
      registerViewFactory('com.aloereed.aloeplayer/hdrView', new HdrFactory(binding.getBinaryMessenger(), StandardMessageCodec.INSTANCE));

    // 初始化 EventChannel
    // this.eventChannel = new EventChannel(binding.getBinaryMessenger(), "samples.flutter.dev/hdrpluginevent");
    // this.eventChannel.setStreamHandler({
    //   onListen(args: Any, events: EventSink): void {
    //     that.eventSink = events; // 将 events 赋值给外部的 eventSink
    //     Log.i(TAG, "onListen: " + args);
    //   },
    //   onCancel(args: Any): void {
    //     that.eventSink = undefined; // 取消 eventSink
    //     Log.i(TAG, "onCancel: " + args);
    //   }
    // });
    //
    // // 在外部监听音量变化事件
    // let audioManager = audio.getAudioManager();
    // let audioHdrManager = audioManager.getHdrManager();
    // audioHdrManager.on('hdrChange', (hdrEvent: audio.HdrEvent) => {
    //   console.info(`HdrType of stream: ${hdrEvent.hdrType} `);
    //   console.info(`Hdr level: ${hdrEvent.hdr} `);
    //   console.info(`Whether to updateUI: ${hdrEvent.updateUi} `);
    //
    //   // 通过 eventSink 发送音量值到 Flutter 端
    //   if (that.eventSink) {
    //     console.info(`Send hdr to Flutter: ${hdrEvent.hdr} `);
    //     that.eventSink.success(hdrEvent.hdr);
    //   }
    // });

  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    Log.i(TAG, "onDetachedFromEngine");
    this.channel?.setMethodCallHandler(null);
    this.eventChannel?.setStreamHandler(null);

  }

  getUniqueClassName(): string {
    return "HdrPlugin";
  }
  
}
function uriToPath(uri: string): string {
  if (!uri.startsWith('file://')) {
    throw new Error('The provided URI is not a file URI.');
  }

  let path = uri.slice(7);

  if (path[0] === '/' && /^[a-zA-Z]:/.test(path.slice(1, 3))) {
    path = path.slice(1);
  }

  if (path.startsWith('docs/')) {
    path = path.slice(4);
  } else if (path.startsWith('media/')) {
    path = path.slice(5);
  }

  path = decodeURIComponent(path);

  return path;
}
let windowStage_: window.WindowStage | undefined = undefined;
let sub_windowClass: window.Window | undefined = undefined;
class HdrApi {
  private task1: taskpool.Task | undefined;
  private taskAudio: taskpool.Task | undefined;

  CreateSubWindow(result: MethodResult){
    // 获取windowStage
    windowStage_ = AppStorage.get('windowStage2');
    // 1.创建应用子窗口。
    if (windowStage_ == null) {
      console.error('Failed to create the subwindow. Cause: windowStage_ is null');
    }
    else {
      windowStage_.createSubWindow("mySubWindow", (err: BusinessError, data) => {
        let errCode: number = err.code;
        if (errCode) {
          console.error('Failed to create the subwindow. Cause: ' + JSON.stringify(err));
          return;
        }
        sub_windowClass = data;
        console.info('Succeeded in creating the subwindow. Data: ' + JSON.stringify(data));
        // 2.子窗口创建成功后，设置子窗口的位置、大小及相关属性等。
        sub_windowClass.moveWindowTo(0, 0, (err: BusinessError) => {
          let errCode: number = err.code;
          if (errCode) {
            console.error('Failed to move the window. Cause:' + JSON.stringify(err));
            return;
          }
          console.info('Succeeded in moving the window.');
        });
        sub_windowClass.resize(500, 500, (err: BusinessError) => {
          let errCode: number = err.code;
          if (errCode) {
            console.error('Failed to change the window size. Cause:' + JSON.stringify(err));
            return;
          }
          console.info('Succeeded in changing the window size.');
        });
        // 3.为子窗口加载对应的目标页面。
        sub_windowClass.setUIContent("pages/Player", (err: BusinessError) => {
          let errCode: number = err.code;
          if (errCode) {
            console.error('Failed to load the content. Cause:' + JSON.stringify(err));
            return;
          }
          console.info('Succeeded in loading the content.');
          // 3.显示子窗口。
          (sub_windowClass as window.Window).showWindow((err: BusinessError) => {
            let errCode: number = err.code;
            if (errCode) {
              console.error('Failed to show the window. Cause: ' + JSON.stringify(err));
              return;
            }
            console.info('Succeeded in showing the window.');
          });
        });
      })
    }
  }

  CreateNewWindow(result: MethodResult, path: string,uris: string){
    let context = getContext(this) as common.UIAbilityContext;
    let want: Want
    want = {
      bundleName: 'com.aloereed.aloeplayer',
      abilityName: 'HDRAbility',
      parameters: {
        'url': path,
        'urls': uris
      }
    }
    context.startAbility(want)
    result.success(true);
  }
  

}