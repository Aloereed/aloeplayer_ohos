
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
import { common, Want } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { fileShare } from '@kit.CoreFileKit';
const TAG = "DownloadPluginTag";

export default class DownloadPlugin implements FlutterPlugin {
  private channel?: MethodChannel;
  private eventSink?: EventSink;
  private eventChannel?: EventChannel;
  private api = new DownloadApi();

  sendWant(uri: string): void {
    if (this.eventSink) {
      this.eventSink.success(uri);
    }
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "samples.flutter.dev/downloadplugin");
    let that = this;
    this.channel.setMethodCallHandler({
      onMethodCall(call: MethodCall, result: MethodResult) {
        switch (call.method) {
          case "getDownloadPermission":
            that.api.getDownloadPermission(result);
            break;
          case "openFileManager":
            that.api.openFileManager(result);
            break;
          case "startBgTask":
            that.api.startBgTask(result);
            break;
          case "persistPermission":
            that.api.persistPermission(call.argument("exts") as string,result);
            break;
          case "activatePermission":
            that.api.activatePermission(call.argument("uri") as string,result);
            break
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
    this.eventChannel = new EventChannel(binding.getBinaryMessenger(), "com.example.app/events");
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


  }



  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    Log.i(TAG, "onDetachedFromEngine");
    this.channel?.setMethodCallHandler(null);

  }

  getUniqueClassName(): string {
    return "DownloadPlugin";
  }
}

class DownloadApi {
  getDownloadPermission(result: MethodResult) {
    // // 创建文件管理器选项实例
    // const documentSaveOptions = new picker.DocumentSaveOptions();
    // // 配置保存的模式为DOWNLOAD，若配置了DOWNLOAD模式，此时配置的其他documentSaveOptions参数将不会生效。
    // documentSaveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD; 
    let uri: string = '';
    // 请确保 getContext(this) 返回结果为 UIAbilityContext
    let context = getContext(this) as common.UIAbilityContext;
    const documentViewPicker = new picker.DocumentViewPicker(context);
    const documentSaveOptions = new picker.DocumentSaveOptions();
    documentSaveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
    documentViewPicker.save(documentSaveOptions).then((documentSaveResult: Array<string>) => {
      uri = documentSaveResult[0];
      console.info('documentViewPicker.save succeed and uri is:' + uri);
    }).catch((err: BusinessError) => {
      console.error(`Invoke documentViewPicker.save failed, code is ${err.code}, message is ${err.message}`);
    })
    Log.i(TAG, "level=" + uri);
    let wrapped: Map<String, Any> = new Map<String, Any>();
    if (uri != null) {
      result.success(uri);
    } else {
      Log.i(TAG, "getDownloadPermission else");
      wrapped.set("UNAVAILABLE", "Download level not available.");
      result.error("UNAVAILABLE", "Download level not available.", null)
    }
    Log.i(TAG, "getDownloadPermission finish");
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
      wrapped.set("UNAVAILABLE", "Download level not available.");
      result.error("UNAVAILABLE", "Download level not available.", null)
    }
    Log.i(TAG, "openFileManager finish");
  }
  startBgTask(result: MethodResult) {
    let context = getContext(this) as common.UIAbilityContext;
    let uri = 'Start BG Task.';
    let wantAgentInfo: wantAgent.WantAgentInfo = {
      // 点击通知后，将要执行的动作列表
      // 添加需要被拉起应用的bundleName和abilityName
      wants: [
        {
          bundleName: "com.aloereed.aloeplayer",
          abilityName: "com.aloereed.aloeplayer.EntryAbility"
        }
      ],
      // 指定点击通知栏消息后的动作是拉起ability
      actionType: wantAgent.OperationType.START_ABILITY,
      // 使用者自定义的一个私有值
      requestCode: 0,
      // 点击通知后，动作执行属性
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    // 通过wantAgent模块下getWantAgent方法获取WantAgent对象
    wantAgent.getWantAgent(wantAgentInfo).then((wantAgentObj: WantAgent) => {
      backgroundTaskManager.startBackgroundRunning(context,
        backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, wantAgentObj).then(() => {
          console.info(`Succeeded in operationing startBackgroundRunning.`);
        }).catch((err: BusinessError) => {
          console.error(`Failed to operation startBackgroundRunning. Code is ${err.code}, message is ${err.message}`);
        });
    });
    let wrapped: Map<String, Any> = new Map<String, Any>();
    if (uri != null) {
      result.success(uri);
    } else {
      Log.i(TAG, "startBgTask else");
      wrapped.set("UNAVAILABLE", "Download level not available.");
      result.error("UNAVAILABLE", "Download level not available.", null)
    }
    console.info("startBgTask finish");
    Log.i(TAG, "startBgTask finish");
  }

  async persistPermission(exts: string,result: MethodResult) {
  try {
    let DocumentSelectOptions : picker.DocumentSelectOptions = {fileSuffixFilters: [exts]};
    let documentPicker = new picker.DocumentViewPicker();
    let uris = await documentPicker.select(DocumentSelectOptions);
    let policyInfo: fileShare.PolicyInfo = {
      uri: uris[0],
      operationMode: fileShare.OperationMode.READ_MODE,
    };
    let policies: Array<fileShare.PolicyInfo> = [policyInfo];
    fileShare.persistPermission(policies).then(() => {
      console.info("persistPermission successfully");
      result.success(uris[0]);
    }).catch((err: BusinessError<Array<fileShare.PolicyErrorResult>>) => {
      console.error("persistPermission failed with error message: " + err.message + ", error code: " + err.code);
      result.success("");
      if (err.code == 13900001 && err.data) {
        for (let i = 0; i < err.data.length; i++) {
          console.error("error code : " + JSON.stringify(err.data[i].code));
          console.error("error uri : " + JSON.stringify(err.data[i].uri));
          console.error("error reason : " + JSON.stringify(err.data[i].message));
        }
      }
    });
  } catch (error) {
    let err: BusinessError = error as BusinessError;
    console.error('persistPermission failed with err: ' + JSON.stringify(err));
    result.success("");
  }
}

async activatePermission(uri: string,result: MethodResult) {
  try {
    let policyInfo: fileShare.PolicyInfo = {
      uri: uri,
      operationMode: fileShare.OperationMode.READ_MODE,
    };
    let policies: Array<fileShare.PolicyInfo> = [policyInfo];
    fileShare.activatePermission(policies).then(() => {
      result.success(uri);
      console.info("activatePermission successfully");
    }).catch((err: BusinessError<Array<fileShare.PolicyErrorResult>>) => {
      result.success("");
      console.error("activatePermission failed with error message: " + err.message + ", error code: " + err.code);
      if (err.code == 13900001 && err.data) {
        for (let i = 0; i < err.data.length; i++) {
          console.error("error code : " + JSON.stringify(err.data[i].code));
          console.error("error uri : " + JSON.stringify(err.data[i].uri));
          console.error("error reason : " + JSON.stringify(err.data[i].message));
          if (err.data[i].code == fileShare.PolicyErrorCode.PERMISSION_NOT_PERSISTED) {
            //可以选择进行持久化后再激活。
          }
        }
      }
    });
  } catch (error) {
    let err: BusinessError = error as BusinessError;
    result.success("");
    console.error('activatePermission failed with err: ' + JSON.stringify(err));
  }
}
}