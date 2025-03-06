
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
import libAddon from 'libentry.so'
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
          case "getVideoDurationMs":
            that.api.getVideoDurationMs(result, call.argument("path") as string);
            break;
          case "openFileManager":
            that.api.openFileManager(result);
            break;
          case "getTitle":
            console.info("gettitle start");
            that.api.getTitle(call.argument("filename") as string, result);
            break;
          case "setTitle":
            that.api.setTitle(call.argument("filename") as string, call.argument("value") as string, result);
            break;
          case "getArtist":
            that.api.getArtist(call.argument("filename") as string, result);
            break;
          case "setArtist":
            that.api.setArtist(call.argument("filename") as string, call.argument("value") as string, result);
            break;
          case "getAlbum":
            that.api.getAlbum(call.argument("filename") as string, result);
            break;
          case "setAlbum":
            that.api.setAlbum(call.argument("filename") as string, call.argument("value") as string, result);
            break;
          case "getYear":
            that.api.getYear(call.argument("filename") as string, result);
            break;
          case "setYear":
            that.api.setYear(call.argument("filename") as string, call.argument("value") as number, result);
            break;
          case "getTrack":
            that.api.getTrack(call.argument("filename") as string, result);
            break;
          case "setTrack":
            that.api.setTrack(call.argument("filename") as string, call.argument("value") as number, result);
            break;
          case "getDisc":
            that.api.getDisc(call.argument("filename") as string, result);
            break;
          case "setDisc":
            that.api.setDisc(call.argument("filename") as string, call.argument("value") as number, result);
            break;
          case "getGenre":
            that.api.getGenre(call.argument("filename") as string, result);
            break;
          case "setGenre":
            that.api.setGenre(call.argument("filename") as string, call.argument("value") as string, result);
            break;
          case "getAlbumArtist":
            that.api.getAlbumArtist(call.argument("filename") as string, result);
            break;
          case "setAlbumArtist":
            that.api.setAlbumArtist(call.argument("filename") as string, call.argument("value") as string, result);
            break;
          case "getComposer":
            that.api.getComposer(call.argument("filename") as string, result);
            break;
          case "setComposer":
            that.api.setComposer(call.argument("filename") as string, call.argument("value") as string, result);
            break;
          case "getLyricist":
            that.api.getLyricist(call.argument("filename") as string, result);
            break;
          case "setLyricist":
            that.api.setLyricist(call.argument("filename") as string, call.argument("value") as string, result);
            break;
          case "getComment":
            that.api.getComment(call.argument("filename") as string, result);
            break;
          case "setComment":
            that.api.setComment(call.argument("filename") as string, call.argument("value") as string, result);
            break;
          case "getLyrics":
            that.api.getLyrics(call.argument("filename") as string, result);
            break;
          case "setLyrics":
            that.api.setLyrics(call.argument("filename") as string, call.argument("value") as string, result);
            break;
          case "getCover":
            that.api.getCover(call.argument("filename") as string, result);
            break;
          case "setCover":
            that.api.setCover(call.argument("filename") as string, call.argument("value") as string, result);
            break;
          case "initLibass":
            that.api.initLibass(call.argument("assFilename") as string, call.argument("width") as number, call.argument("height") as number, result);
            break;
          case "getPngDataAtTime":
            that.api.getPngDataAtTime(call.argument("time") as number, call.argument("width") as number, call.argument("height") as number, result);
            break;
          case "cleanupLibass":
            that.api.cleanupLibass(result);
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

  // testNthat.api.getsrt(command);
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

  // testNthat.api.getsrt(command);
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

  // testNthat.api.getsrt(command);
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
  getVideoDurationMs(result: MethodResult, path: string) {
    let duration = 0;
    try {
      duration = libAddon.get_video_duration(path);
      result.success(duration);
    } catch (error) {
      result.error("UNAVAILABLE", "Failed to get video duration", error);
    }
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

  getTitle(filename: string, result: MethodResult) {
    console.log("getTitle start");
    libAddon.getTitle(filename).then((title: string) => {
      console.log("getTitle end: "+title);
      result.success(title);
    }).catch((error: Error) => {
      result.error("UNAVAILABLE", "Failed to get title", error);
    });
  }

  setTitle(filename: string, title: string, result: MethodResult) {
      libAddon.setTitle(filename, title).then(() => {
          console.log("setTitle end");
          result.success(null);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to set title", error);
        });
  }


    getArtist(filename: string, result: MethodResult) {
        console.log("getArtist start");
        libAddon.getArtist(filename).then((artist: string) => {
          console.log("getArtist end: " + artist);
          result.success(artist);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to get artist", error);
        });
    }

    setArtist(filename: string, artist: string, result: MethodResult) {
        console.log("setArtist start");
        libAddon.setArtist(filename, artist).then(() => {
          console.log("setArtist end");
          result.success(null);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to set artist", error);
        });
    }

    getAlbum(filename: string, result: MethodResult) {
        console.log("getAlbum start");
        libAddon.getAlbum(filename).then((album: string) => {
          console.log("getAlbum end: " + album);
          result.success(album);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to get album", error);
        });
    }

    setAlbum(filename: string, album: string, result: MethodResult) {
        console.log("setAlbum start");
        libAddon.setAlbum(filename, album).then(() => {
          console.log("setAlbum end");
          result.success(null);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to set album", error);
        });
    }

    getYear(filename: string, result: MethodResult) {
        console.log("getYear start");
        libAddon.getYear(filename).then((year: number) => {
          console.log("getYear end: " + year);
          result.success(year);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to get year", error);
        });
    }

    setYear(filename: string, year: number, result: MethodResult) {
        console.log("setYear start");
        libAddon.setYear(filename, year).then(() => {
          console.log("setYear end");
          result.success(null);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to set year", error);
        });
    }

    getTrack(filename: string, result: MethodResult) {
        console.log("getTrack start");
        libAddon.getTrack(filename).then((track: number) => {
          console.log("getTrack end: " + track);
          result.success(track);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to get track", error);
        });
    }

    setTrack(filename: string, track: number, result: MethodResult) {
        console.log("setTrack start");
        libAddon.setTrack(filename, track).then(() => {
          console.log("setTrack end");
          result.success(null);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to set track", error);
        });
    }

    getDisc(filename: string, result: MethodResult) {
        console.log("getDisc start");
        libAddon.getDisc(filename).then((disc: number) => {
          console.log("getDisc end: " + disc);
          result.success(disc);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to get disc", error);
        });
    }

    setDisc(filename: string, disc: number, result: MethodResult) {
        console.log("setDisc start");
        libAddon.setDisc(filename, disc).then(() => {
          console.log("setDisc end");
          result.success(null);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to set disc", error);
        });
    }

    getGenre(filename: string, result: MethodResult) {
        console.log("getGenre start");
        libAddon.getGenre(filename).then((genre: string) => {
          console.log("getGenre end: " + genre);
          result.success(genre);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to get genre", error);
        });
    }

    setGenre(filename: string, genre: string, result: MethodResult) {
        console.log("setGenre start");
        libAddon.setGenre(filename, genre).then(() => {
          console.log("setGenre end");
          result.success(null);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to set genre", error);
        });
    }

    getAlbumArtist(filename: string, result: MethodResult) {
        console.log("getAlbumArtist start");
        libAddon.getAlbumArtist(filename).then((albumArtist: string) => {
          console.log("getAlbumArtist end: " + albumArtist);
          result.success(albumArtist);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to get album artist", error);
        });
    }

    setAlbumArtist(filename: string, albumArtist: string, result: MethodResult) {
        console.log("setAlbumArtist start");
        libAddon.setAlbumArtist(filename, albumArtist).then(() => {
          console.log("setAlbumArtist end");
          result.success(null);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to set album artist", error);
        });
    }

    getComposer(filename: string, result: MethodResult) {
        console.log("getComposer start");
        libAddon.getComposer(filename).then((composer: string) => {
          console.log("getComposer end: " + composer);
          result.success(composer);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to get composer", error);
        });
    }

    setComposer(filename: string, composer: string, result: MethodResult) {
        console.log("setComposer start");
        libAddon.setComposer(filename, composer).then(() => {
          console.log("setComposer end");
          result.success(null);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to set composer", error);
        });
    }

    getLyricist(filename: string, result: MethodResult) {
        console.log("getLyricist start");
        libAddon.getLyricist(filename).then((lyricist: string) => {
          console.log("getLyricist end: " + lyricist);
          result.success(lyricist);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to get lyricist", error);
        });
    }

    setLyricist(filename: string, lyricist: string, result: MethodResult) {
        console.log("setLyricist start");
        libAddon.setLyricist(filename, lyricist).then(() => {
          console.log("setLyricist end");
          result.success(null);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to set lyricist", error);
        });
    }

    getComment(filename: string, result: MethodResult) {
        console.log("getComment start");
        libAddon.getComment(filename).then((comment: string) => {
          console.log("getComment end: " + comment);
          result.success(comment);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to get comment", error);
        });
    }

    setComment(filename: string, comment: string, result: MethodResult) {
        console.log("setComment start");
        libAddon.setComment(filename, comment).then(() => {
          console.log("setComment end");
          result.success(null);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to set comment", error);
        });
    }

    getLyrics(filename: string, result: MethodResult) {
        console.log("getLyrics start");
        libAddon.getLyrics(filename).then((lyrics: string) => {
          console.log("getLyrics end: " + lyrics);
          result.success(lyrics);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to get lyrics", error);
        });
    }

    setLyrics(filename: string, lyrics: string, result: MethodResult) {
        console.log("setLyrics start");
        libAddon.setLyrics(filename, lyrics).then(() => {
          console.log("setLyrics end");
          result.success(null);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to set lyrics", error);
        });
    }

    getCover(filename: string, result: MethodResult) {
        console.log("getCover start");
        libAddon.getCover(filename).then((cover: string) => {
          console.log("getCover end: " + cover);
          result.success(cover);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to get cover", error);
        });
    }

    setCover(filename: string, coverBase64: string, result: MethodResult) {
        console.log("setCover start");
        libAddon.setCover(filename, coverBase64).then(() => {
          console.log("setCover end");
          result.success(null);
        }).catch((error: Error) => {
          result.error("UNAVAILABLE", "Failed to set cover", error);
        });
    }
    // export const init_libass: (assFilename: string, width: number, height: number) => any;
    // export const get_png_data_at_time: (time: number, width: number, height: number) => any;
    // export const cleanup_libass: () => any;
    initLibass(assFilename: string, width: number, height: number, result: MethodResult) {
      console.warn("initLibass start");
      libAddon.init_libass(assFilename, width, height).then((isSuccess: boolean) => {
        console.warn("initLibass end: " + isSuccess);
        result.success(isSuccess);
      }).catch((error: Error) => {
        result.error("UNAVAILABLE", "Failed to init libass", error);
      });
    }
    getPngDataAtTime(time: number, width: number, height: number, result: MethodResult) {
      libAddon.get_png_data_at_time(time, width, height).then((pngData: string) => {
        console.warn("Png size:" + pngData.length);
        result.success(pngData);
      }).catch((error: Error) => {
        result.error("UNAVAILABLE", "Failed to get PNG data", error);
      });
    }
    cleanupLibass(result: MethodResult) {
      libAddon.cleanup_libass();
      result.success(null);
    }

}