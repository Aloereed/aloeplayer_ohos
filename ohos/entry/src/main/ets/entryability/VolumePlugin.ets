
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
import { BusinessError } from '@kit.BasicServicesKit';
import { common , Want } from '@kit.AbilityKit';
import { AVVolumePanel } from '@kit.AudioKit';
import { VolumeFactory } from './VolumeFactory';
import { audio } from '@kit.AudioKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
const TAG = "VolumePluginTag";

export default class VolumePlugin implements FlutterPlugin {
  private channel?: MethodChannel;
  private eventSink?: EventSink;
  private eventChannel?: EventChannel;
  private api = new VolumeApi();

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "samples.flutter.dev/volumeplugin");
    let that = this;
    this.channel.setMethodCallHandler({
      onMethodCall(call: MethodCall, result: MethodResult) {
        switch (call.method) {
          case "getVolumePermission":
            that.api.getVolumePermission(result);
            break;
          case "getMinVolume":
            that.api.getMinVolume(result);
            break;
          case "getMaxVolume":
            that.api.getMaxVolume(result);
            break;
          case "getCurrentVolume":
            that.api.getCurrentVolume(result);
            break;
          case "openFileManager":
            that.api.openFileManager(result);
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
    registerViewFactory('com.aloereed.aloeplayer/volumeView', new VolumeFactory(binding.getBinaryMessenger(), StandardMessageCodec.INSTANCE));

    // 初始化 EventChannel
    this.eventChannel = new EventChannel(binding.getBinaryMessenger(), "samples.flutter.dev/volumepluginevent");
    this.eventChannel.setStreamHandler({
      onListen(args: Any, events: EventSink): void {
        that.eventSink = events; // 将 events 赋值给外部的 eventSink
        Log.i(TAG, "onListen: " + args);
      },
      onCancel(args: Any): void {
        that.eventSink = undefined; // 取消 eventSink
        Log.i(TAG, "onCancel: " + args);
      }
    });

    // 在外部监听音量变化事件
    let audioManager = audio.getAudioManager();
    let audioVolumeManager = audioManager.getVolumeManager();
    audioVolumeManager.on('volumeChange', (volumeEvent: audio.VolumeEvent) => {
      console.info(`VolumeType of stream: ${volumeEvent.volumeType} `);
      console.info(`Volume level: ${volumeEvent.volume} `);
      console.info(`Whether to updateUI: ${volumeEvent.updateUi} `);

      // 通过 eventSink 发送音量值到 Flutter 端
      if (that.eventSink) {
        console.info(`Send volume to Flutter: ${volumeEvent.volume} `);
        that.eventSink.success(volumeEvent.volume);
      }
    });

  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    Log.i(TAG, "onDetachedFromEngine");
    this.channel?.setMethodCallHandler(null);
    this.eventChannel?.setStreamHandler(null);

  }

  getUniqueClassName(): string {
    return "VolumePlugin";
  }
}

class VolumeApi {
  max_volume: number = 15;
  min_volume: number = 0;
  getVolumePermission(result: MethodResult) {
    // // 创建文件管理器选项实例
    // const documentSaveOptions = new picker.DocumentSaveOptions();
    // // 配置保存的模式为DOWNLOAD，若配置了DOWNLOAD模式，此时配置的其他documentSaveOptions参数将不会生效。
    // documentSaveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD; 
    let uri: string = '';
    // 请确保 getContext(this) 返回结果为 UIAbilityContext
    let context = getContext(this) as common.UIAbilityContext; 
    // let voctrl = AVVolumePanel({
    //       volumeLevel: 0,
    //     })

    Log.i(TAG, "level=" + uri);
    let wrapped: Map<String, Any> = new Map<String, Any>();
    if (uri != null) {
      result.success(uri);
    } else {
      Log.i(TAG, "getVolumePermission else");
      wrapped.set("UNAVAILABLE", "Volume level not available.");
      result.error("UNAVAILABLE", "Volume level not available.", null)
    }
    Log.i(TAG, "getVolumePermission finish");
  }
  async getMinVolume(result: MethodResult) {
    // // 创建文件管理器选项实例
    // const documentSaveOptions = new picker.DocumentSaveOptions();
    // // 配置保存的模式为DOWNLOAD，若配置了DOWNLOAD模式，此时配置的其他documentSaveOptions参数将不会生效。
    // documentSaveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD; 
    
    let audioManager = audio.getAudioManager();
    let groupId: number = audio.DEFAULT_VOLUME_GROUP_ID;
    let audioVolumeGroupManager = await audioManager.getVolumeManager().getVolumeGroupManager(groupId)
    audioVolumeGroupManager.getMinVolume(audio.AudioVolumeType.MEDIA, (err: BusinessError, value: number) => {
      if (err) {
        console.error(`Failed to obtain the min volume. ${err}`);
        return;
      }
      console.info(`Callback invoked to indicate that the min volume is obtained. ${value}`);
      let minv : number;
      minv = value;
      Log.i(TAG, "level=" + minv);
      let wrapped: Map<String, Any> = new Map<String, Any>();
      if (minv != null) {
        result.success(minv);
      } else {
        Log.i(TAG, "getVolumePermission else");
        wrapped.set("UNAVAILABLE", "Volume level not available.");
        result.error("UNAVAILABLE", "Volume level not available.", null)
      }
    });
    
    Log.i(TAG, "getVolumePermission finish");
  }
  async getMaxVolume(result: MethodResult) {
    // // 创建文件管理器选项实例
    // const documentSaveOptions = new picker.DocumentSaveOptions();
    // // 配置保存的模式为DOWNLOAD，若配置了DOWNLOAD模式，此时配置的其他documentSaveOptions参数将不会生效。
    // documentSaveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD; 
    
    let audioManager = audio.getAudioManager();
    let groupId: number = audio.DEFAULT_VOLUME_GROUP_ID;
    let audioVolumeGroupManager = await audioManager.getVolumeManager().getVolumeGroupManager(groupId)
    audioVolumeGroupManager.getMaxVolume(audio.AudioVolumeType.MEDIA, (err: BusinessError, value: number) => {
      if (err) {
        console.error(`Failed to obtain the maximum volume. ${err}`);
        return;
      }
      console.info(`Callback invoked to indicate that the maximum volume is obtained. ${value}`);
      let minv : number;
      minv = value;
      Log.i(TAG, "level=" + minv);
      let wrapped: Map<String, Any> = new Map<String, Any>();
      if (minv != null) {
        result.success(minv);
      } else {
        Log.i(TAG, "getVolumePermission else");
        wrapped.set("UNAVAILABLE", "Volume level not available.");
        result.error("UNAVAILABLE", "Volume level not available.", null)
      }
    });
    
    Log.i(TAG, "getVolumePermission finish");
  }
  async getVolume(audioVolumeManager: audio.AudioVolumeManager, groupId: number): Promise<Map<string, number>> {
    let volume_list: Map<string, number> = new Map();
    return new Promise((resolve, reject) => {
      audioVolumeManager.getVolumeGroupManager(groupId,
        (err: BusinessError, audioVolumeGroupManager: audio.AudioVolumeGroupManager) => {
          if (err) {
            hilog.error(0x0000, 'AVPlayer', `Failed to obtain the volume group info list. ${err}`);
            return reject(err);
          }
          const volumePromises: Promise<void>[] = [];
          volumePromises.push(new Promise((resolveVolume, rejectVolume) => {
            audioVolumeGroupManager.getVolume(audio.AudioVolumeType.MEDIA, (err: BusinessError, volume: number) => {
              if (err) {
                hilog.error(0x0000, 'AVPlayer', `Failed to obtain the volume. ${err}`);
                return rejectVolume(err);
              }
              volume_list.set('volume', volume);
              resolveVolume();
            });
          }));
          volumePromises.push(new Promise((resolveMax, rejectMax) => {
            audioVolumeGroupManager.getMaxVolume(audio.AudioVolumeType.MEDIA,
              (err: BusinessError, maxVolume: number) => {
                if (err) {
                  hilog.error(0x0000, 'AVPlayer', `Failed to obtain the maximum volume. ${err}`);
                  return rejectMax(err);
                }
                volume_list.set('max_volume', maxVolume);
                this.max_volume = maxVolume
                resolveMax();
              });
          }));
          volumePromises.push(new Promise((resolveMin, rejectMin) => {
            audioVolumeGroupManager.getMinVolume(audio.AudioVolumeType.MEDIA,
              (err: BusinessError, minVolume: number) => {
                if (err) {
                  hilog.error(0x0000, 'AVPlayer', `Failed to obtain the minimum volume. ${err}`);
                  return rejectMin(err);
                }
                volume_list.set('min_volume', minVolume);
                this.min_volume = minVolume
                resolveMin();
              });
          }));
          Promise.all(volumePromises)
            .then(() => resolve(volume_list))// 所有音量均成功获取，返回 volume_list
            .catch(reject); // 如果有任何一个 Promise 失败，拒绝整个 Promise
        });
    });
  }
  async getCurrentVolume(result: MethodResult){
    let groupId: number = audio.DEFAULT_VOLUME_GROUP_ID;
    let audioManager = audio.getAudioManager();
    let audioVolumeManger: audio.AudioVolumeManager = audioManager.getVolumeManager();
    let volume_list = await this.getVolume(audioVolumeManger, groupId)
    let volume = volume_list.get('volume')!;
    Log.i(TAG, "level=" + volume);
    result.success(volume);
  }
  openFileManager(result: MethodResult) {
    let context = getContext(this) as common.UIAbilityContext;
    let uri = 'Open FE.';
    // 创建一个Want对象，用于描述启动系统文件管理器的意图
    let want: Want = {
      // 设置系统文件管理器的包名
      bundleName: 'com.huawei.hmos.filemanager',
      // 设置系统文件管理器的主Ability名称
      abilityName: 'MainAbility'
    };
    context.startAbility(want);
    let wrapped: Map<String, Any> = new Map<String, Any>();
    if (uri != null) {
      result.success(uri);
    } else {
      Log.i(TAG, "openFileManager else");
      wrapped.set("UNAVAILABLE", "Volume level not available.");
      result.error("UNAVAILABLE", "Volume level not available.", null)
    }
    Log.i(TAG, "openFileManager finish");
  }
}