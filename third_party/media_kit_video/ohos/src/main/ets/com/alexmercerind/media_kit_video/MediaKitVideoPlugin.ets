/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 *
 * Copyright © 2025 & onwards, Bao Han <erbws@foxmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */

import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  AbilityAware,
  AbilityPluginBinding
} from '@ohos/flutter_ohos';
import { TextureUpdateCallback } from './TextureUpdateCallback';
import { Rect, SizeData, Utils } from './Utils';
import { VideoOutputManager } from './VideoOutputManager';
import { common } from '@kit.AbilityKit';
import { NativeVideoHost } from './NativeVideoHost';

export default class MediaKitVideoPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;
  private videoOutputManager: VideoOutputManager | null = null;
  binding: FlutterPluginBinding | null = null;
  context: common.UIAbilityContext | null = null;

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.videoOutputManager = new VideoOutputManager(this.binding!.getTextureRegistry());
    this.context = binding.getAbility().context;
  }

  onDetachedFromAbility(): void {
    return;
  }

  getUniqueClassName(): string {
    return "MediaKitVideoPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "com.alexmercerind/media_kit_video");
    this.channel.setMethodCallHandler(this);
    this.binding = binding;
    NativeVideoHost.channel = this.channel;
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    NativeVideoHost.dispose(NativeVideoHost.state.handle, NativeVideoHost.state.viewId);
    NativeVideoHost.channel = null;
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
    }
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'NativeSurface.Create': {
        try {
          NativeVideoHost.create(call.argument('handle'), call.argument('viewId'));
          result.success(null);
        } catch (error) {
          result.error('native_surface_unavailable', `${error}`, null);
        }
        break;
      }
      case 'NativeSurface.SetRect': {
        const state = NativeVideoHost.state;
        if (state.handle === (call.argument('handle') as string) && state.viewId === (call.argument('viewId') as number)) {
          state.left = call.argument('left') as number;
          state.top = call.argument('top') as number;
          state.width = Math.max(1, call.argument('width') as number);
          state.height = Math.max(1, call.argument('height') as number);
        }
        result.success(null);
        break;
      }
      case 'NativeSurface.Dispose': {
        NativeVideoHost.dispose(call.argument('handle'), call.argument('viewId'));
        result.success(null);
        break;
      }
      case "VideoOutputManager.Create": {
        const handle = parseInt(call.argument("handle"));
        const textureUpdateCallback: TextureUpdateCallback = {
          onTextureUpdate: (id: number, wid: number, width: number, height: number): void => {
            const rect: Rect = {
              left: 0,
              top: 0,
              width: width,
              height: height,
            }
            const args: SizeData = {
              handle: handle,
              id: id,
              wid: wid,
              rect: rect,
            }
            this.channel?.invokeMethod("VideoOutput.Resize", args);
          }
        }
        this.videoOutputManager?.create(handle, textureUpdateCallback);
        result.success(null);
        break;
      }
      case "VideoOutputManager.SetSurfaceSize": {
        const handle = parseInt(call.argument("handle"));
        const width = parseInt(call.argument("width"));
        const height = parseInt(call.argument("height"));
        this.videoOutputManager?.setSurfaceSize(handle, width, height);
        result.success(null);
        break;
      }
      case "VideoOutputManager.Dispose": {
        const handle = parseInt(call.argument("handle"));
        this.videoOutputManager?.dispose(handle);
        result.success(null);
        break;
      }
      case "Utils.IsEmulator": {
        result.success(Utils.isEmulator());
        break;
      }
      case "Utils.EnterNativeFullscreen": {
        Utils.enterFullScreen(this.context!);
        result.success(null);
        break;
      }
      case "Utils.ExitNativeFullscreen": {
        Utils.exitFullScreen(this.context!);
        result.success(null);
        break;
      }
      default: {
        result.notImplemented();
        break;
      }
    }
  }
}
