
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
import { common , Want } from '@kit.AbilityKit';
import { FfmpegFactory } from './FfmpegFactory';
import { audio } from '@kit.AudioKit';
// import testNapi from 'libentry.so';
import { FFMpegUtils, FFmpegCommandOptions } from './FFmpegUtils';


const TAG = "FfmpegPluginTag";

export default class FfmpegPlugin implements FlutterPlugin {
  private channel?: MethodChannel;
  private eventSink?: EventSink;
  private eventChannel?: EventChannel;
  private api = new FfmpegApi();

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "samples.flutter.dev/ffmpegplugin");
    let that = this;
    this.channel.setMethodCallHandler({
      onMethodCall(call: MethodCall, result: MethodResult) {
        switch (call.method) {
          case "getassold":
            console.info("getassold start");
            that.api.getassold(result, call.argument("path") as string,call.argument("type") as string,call.argument("output"));
            break;
          case "getsrtold":
            console.info("getsrtold start");
            that.api.getsrtold(result, call.argument("path") as string,call.argument("type") as string);
            break;
          case "getsrt":
            console.info("getsrt start");
            that.api.getsrt(result, call.argument("path") as string,call.argument("type") as string);
            break;
          case "getass":
            console.info("getassstart");
            that.api.getass(result, call.argument("path") as string,call.argument("type") as string,call.argument("output"));
            break;
          case "tomp4":
            console.info("tomp4 start");
            that.api.tomp4(result, call.argument("path") as string);
            break;
          case "getFfmpegPermission":
            that.api.getFfmpegPermission(result);
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
    registerViewFactory('com.aloereed.aloeplayer/ffmpegView', new FfmpegFactory(binding.getBinaryMessenger(), StandardMessageCodec.INSTANCE));

    // 初始化 EventChannel
    // this.eventChannel = new EventChannel(binding.getBinaryMessenger(), "samples.flutter.dev/ffmpegpluginevent");
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
    // let audioFfmpegManager = audioManager.getFfmpegManager();
    // audioFfmpegManager.on('ffmpegChange', (ffmpegEvent: audio.FfmpegEvent) => {
    //   console.info(`FfmpegType of stream: ${ffmpegEvent.ffmpegType} `);
    //   console.info(`Ffmpeg level: ${ffmpegEvent.ffmpeg} `);
    //   console.info(`Whether to updateUI: ${ffmpegEvent.updateUi} `);
    //
    //   // 通过 eventSink 发送音量值到 Flutter 端
    //   if (that.eventSink) {
    //     console.info(`Send ffmpeg to Flutter: ${ffmpegEvent.ffmpeg} `);
    //     that.eventSink.success(ffmpegEvent.ffmpeg);
    //   }
    // });

  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    Log.i(TAG, "onDetachedFromEngine");
    this.channel?.setMethodCallHandler(null);
    this.eventChannel?.setStreamHandler(null);

  }

  getUniqueClassName(): string {
    return "FfmpegPlugin";
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
@Concurrent
async function StartExtractAss(command: string,typ:string,output:string): Promise<void> {
  emitter.on({ eventId: 1 }, () => {
    emitter.off(1)
  });
  const onFFmpegProgress = (progress: number) => {
  console.log(`FFmpeg progress: ${progress}%`);
  };

  const onFFmpegFail = (code: number, msg: string) => {
    console.error(`FFmpeg failed with code ${code}: ${msg}`);
  };

  const onFFmpegSuccess = () => {
    console.log('FFmpeg command executed successfully!');
  };

  const options: FFmpegCommandOptions = {
    cmds:['ffmpeg', '-i', command , '-map', '0:s:0', output+"."+typ], // 替换为实际的 FFmpeg 命令
    onFFmpegProgress,
    onFFmpegFail,
    onFFmpegSuccess,
  };

  try {
      const exitCode = await FFMpegUtils.executeFFmpegCommand(options);
      console.log(`FFmpeg command exited with code: ${exitCode}`);
    } catch (error) {
      console.error('Failed to execute FFmpeg command:', error);
    }

  // testNapi.getsrt(command);
}
@Concurrent
async function StartExtractSrt(command: string,typ:string): Promise<void> {
  // emitter.on({ eventId: 1 }, () => {
  //   emitter.off(1)
  // });
  const onFFmpegProgress = (progress: number) => {
  console.log(`FFmpeg progress: ${progress}%`);
  };

  const onFFmpegFail = (code: number, msg: string) => {
    console.error(`FFmpeg failed with code ${code}: ${msg}`);
  };

  const onFFmpegSuccess = () => {
    console.log('FFmpeg command executed successfully!');
  };

  const options: FFmpegCommandOptions = {
    cmds:['ffmpeg', '-i', command , '-map', '0:s:0', command+"_1."+typ], // 替换为实际的 FFmpeg 命令
    onFFmpegProgress,
    onFFmpegFail,
    onFFmpegSuccess,
  };

  try {
      const exitCode = await FFMpegUtils.executeFFmpegCommand(options);
      console.log(`FFmpeg command exited with code: ${exitCode}`);
    } catch (error) {
      console.error('Failed to execute FFmpeg command:', error);
    }
}
@Concurrent
async function StartExtractAssOld(command: string,typ:string,output:string): Promise<void> {
  // emitter.on({ eventId: 1 }, () => {
  //   emitter.off(1)
  // });
  const onFFmpegProgress = (progress: number) => {
  console.log(`FFmpeg progress: ${progress}%`);
  };

  const onFFmpegFail = (code: number, msg: string) => {
    console.error(`FFmpeg failed with code ${code}: ${msg}`);
  };

  const onFFmpegSuccess = () => {
    console.log('FFmpeg command executed successfully!');
  };
  console.log("command:"+ command+" "+" "+output);
  const options: FFmpegCommandOptions = {
    cmds:['ffmpeg', command , output], // 替换为实际的 FFmpeg 命令
    onFFmpegProgress,
    onFFmpegFail,
    onFFmpegSuccess,
  };

  try {
      const exitCode = await FFMpegUtils.executeFFmpegCommand2(options);
      console.log(`FFmpeg command exited with code: ${exitCode}`);
    } catch (error) {
      console.error('Failed to execute FFmpeg command:', error);
    }

  // testNapi.getsrt(command);
}
@Concurrent
async function StartExtractSrtOld(command: string,typ:string): Promise<void> {
  // emitter.on({ eventId: 1 }, () => {
  //   emitter.off(1)
  // });
  const onFFmpegProgress = (progress: number) => {
  console.log(`FFmpeg progress: ${progress}%`);
  };

  const onFFmpegFail = (code: number, msg: string) => {
    console.error(`FFmpeg failed with code ${code}: ${msg}`);
  };

  const onFFmpegSuccess = () => {
    console.log('FFmpeg command executed successfully!');
  };

  const options: FFmpegCommandOptions = {
    cmds:['ffmpeg', command , command], // 替换为实际的 FFmpeg 命令
    onFFmpegProgress,
    onFFmpegFail,
    onFFmpegSuccess,
  };

  try {
      const exitCode = await FFMpegUtils.executeFFmpegCommand2(options);
      console.log(`FFmpeg command exited with code: ${exitCode}`);
    } catch (error) {
      console.error('Failed to execute FFmpeg command:', error);
    }
}
@Concurrent
async function StartToMp4(command: string): Promise<void> {
  emitter.on({ eventId: 1 }, () => {
    emitter.off(1)
  });
  const onFFmpegProgress = (progress: number) => {
  console.log(`FFmpeg progress: ${progress}%`);
  };

  const onFFmpegFail = (code: number, msg: string) => {
    console.error(`FFmpeg failed with code ${code}: ${msg}`);
  };

  const onFFmpegSuccess = () => {
    console.log('FFmpeg command executed successfully!');
  };

  const options: FFmpegCommandOptions = {
    cmds:[
    'ffmpeg',
    '-i', command,       
    '-map', '0:v',          
    '-map', '0:a:0',        
    '-c:v', 'copy',         
    '-c:a', 'copy',        
    command+'.mp4'            
]   , // 替换为实际的 FFmpeg 命令
    onFFmpegProgress,
    onFFmpegFail,
    onFFmpegSuccess,
  };

  try {
      const exitCode = await FFMpegUtils.executeFFmpegCommand(options);
      console.log(`FFmpeg command exited with code: ${exitCode}`);
    } catch (error) {
      console.error('Failed to execute FFmpeg command:', error);
    }

  // testNapi.getsrt(command);
}
class FfmpegApi {
  private task1: taskpool.Task | undefined;
  getass(result:MethodResult, path:string, typ:string,output:string){
    let command = `./getsrt "${path}" "${path}"`;
    this.task1 = new taskpool.Task(StartExtractAss, path,typ,output);
    taskpool.execute(this.task1, taskpool.Priority.LOW);
    let uri: string = '';
    // 请确保 getContext(this) 返回结果为 UIAbilityContext
    let context = getContext(this) as common.UIAbilityContext; 
    // let voctrl = AVFfmpegPanel({
    //       ffmpegLevel: 0,
    //     })

    Log.i(TAG, "level=" + uri);
    let wrapped: Map<String, Any> = new Map<String, Any>();
    if (uri != null) {
      result.success(uri);
    } else {
      Log.i(TAG, "getFfmpegPermission else");
      wrapped.set("UNAVAILABLE", "Ffmpeg level not available.");
      result.error("UNAVAILABLE", "Ffmpeg level not available.", null)
    }
    Log.i(TAG, "getFfmpegPermission finish");
  }
  getassold(result:MethodResult, path:string, typ:string,output:string){
    let command = `./getsrt "${path}" "${path}"`;
    this.task1 = new taskpool.Task(StartExtractAssOld, path,typ,output);
    taskpool.execute(this.task1, taskpool.Priority.LOW);
    let uri: string = '';
    // 请确保 getContext(this) 返回结果为 UIAbilityContext
    let context = getContext(this) as common.UIAbilityContext; 
    // let voctrl = AVFfmpegPanel({
    //       ffmpegLevel: 0,
    //     })

    Log.i(TAG, "level=" + uri);
    let wrapped: Map<String, Any> = new Map<String, Any>();
    if (uri != null) {
      result.success(uri);
    } else {
      Log.i(TAG, "getFfmpegPermission else");
      wrapped.set("UNAVAILABLE", "Ffmpeg level not available.");
      result.error("UNAVAILABLE", "Ffmpeg level not available.", null)
    }
    Log.i(TAG, "getFfmpegPermission finish");
  }
  getsrtold(result:MethodResult, path:string, typ:string){
    let command = `./getsrt "${path}" "${path}"`;
    this.task1 = new taskpool.Task(StartExtractSrtOld, path,typ);
    taskpool.execute(this.task1, taskpool.Priority.LOW);
    let uri: string = '';
    // 请确保 getContext(this) 返回结果为 UIAbilityContext
    let context = getContext(this) as common.UIAbilityContext; 
    // let voctrl = AVFfmpegPanel({
    //       ffmpegLevel: 0,
    //     })

    Log.i(TAG, "level=" + uri);
    let wrapped: Map<String, Any> = new Map<String, Any>();
    if (uri != null) {
      result.success(uri);
    } else {
      Log.i(TAG, "getFfmpegPermission else");
      wrapped.set("UNAVAILABLE", "Ffmpeg level not available.");
      result.error("UNAVAILABLE", "Ffmpeg level not available.", null)
    }
    Log.i(TAG, "getFfmpegPermission finish");
  }
  getsrt(result:MethodResult, path:string, typ:string){
    let command = `./getsrt "${path}" "${path}"`;
    this.task1 = new taskpool.Task(StartExtractSrt, path,typ);
    taskpool.execute(this.task1, taskpool.Priority.LOW);
    let uri: string = '';
    // 请确保 getContext(this) 返回结果为 UIAbilityContext
    let context = getContext(this) as common.UIAbilityContext; 
    // let voctrl = AVFfmpegPanel({
    //       ffmpegLevel: 0,
    //     })

    Log.i(TAG, "level=" + uri);
    let wrapped: Map<String, Any> = new Map<String, Any>();
    if (uri != null) {
      result.success(uri);
    } else {
      Log.i(TAG, "getFfmpegPermission else");
      wrapped.set("UNAVAILABLE", "Ffmpeg level not available.");
      result.error("UNAVAILABLE", "Ffmpeg level not available.", null)
    }
    Log.i(TAG, "getFfmpegPermission finish");
  }
  tomp4(result:MethodResult, path:string){
    let command = `./getsrt "${path}" "${path}"`;
    this.task1 = new taskpool.Task(StartToMp4, path);
    taskpool.execute(this.task1, taskpool.Priority.LOW);
    let uri: string = '';
    // 请确保 getContext(this) 返回结果为 UIAbilityContext
    let context = getContext(this) as common.UIAbilityContext; 
    // let voctrl = AVFfmpegPanel({
    //       ffmpegLevel: 0,
    //     })

    Log.i(TAG, "level=" + uri);
    let wrapped: Map<String, Any> = new Map<String, Any>();
    if (uri != null) {
      result.success(uri);
    } else {
      Log.i(TAG, "getFfmpegPermission else");
      wrapped.set("UNAVAILABLE", "Ffmpeg level not available.");
      result.error("UNAVAILABLE", "Ffmpeg level not available.", null)
    }
    Log.i(TAG, "getFfmpegPermission finish");
  }
  getFfmpegPermission(result: MethodResult) {
    // // 创建文件管理器选项实例
    // const documentSaveOptions = new picker.DocumentSaveOptions();
    // // 配置保存的模式为DOWNLOAD，若配置了DOWNLOAD模式，此时配置的其他documentSaveOptions参数将不会生效。
    // documentSaveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD; 
    let uri: string = '';
    // 请确保 getContext(this) 返回结果为 UIAbilityContext
    let context = getContext(this) as common.UIAbilityContext; 
    // let voctrl = AVFfmpegPanel({
    //       ffmpegLevel: 0,
    //     })

    Log.i(TAG, "level=" + uri);
    let wrapped: Map<String, Any> = new Map<String, Any>();
    if (uri != null) {
      result.success(uri);
    } else {
      Log.i(TAG, "getFfmpegPermission else");
      wrapped.set("UNAVAILABLE", "Ffmpeg level not available.");
      result.error("UNAVAILABLE", "Ffmpeg level not available.", null)
    }
    Log.i(TAG, "getFfmpegPermission finish");
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
      wrapped.set("UNAVAILABLE", "Ffmpeg level not available.");
      result.error("UNAVAILABLE", "Ffmpeg level not available.", null)
    }
    Log.i(TAG, "openFileManager finish");
  }
}