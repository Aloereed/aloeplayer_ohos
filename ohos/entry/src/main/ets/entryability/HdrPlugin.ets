
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

class HdrApi {
  private task1: taskpool.Task | undefined;
  private taskAudio: taskpool.Task | undefined;

  

}