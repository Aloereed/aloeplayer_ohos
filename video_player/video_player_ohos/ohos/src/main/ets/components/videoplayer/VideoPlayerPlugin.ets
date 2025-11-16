// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on VideoPlayerPlugin.java originally written by
// Copyright 2013 The Flutter Authors.

import AbilityAware from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityAware';
import { AbilityPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityPluginBinding';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { TextureRegistry } from '@ohos/flutter_ohos/src/main/ets/view/TextureRegistry';
import { VideoPlayerApi } from './VideoPlayerApi';
import { VideoPlayerApiImpl } from './VideoPlayerApiImpl';
import { MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
const TAG: string = "VideoPlayerPlugin";
export class VideoPlayerPlugin implements FlutterPlugin, AbilityAware {
  private pluginBinding: FlutterPluginBinding | null = null;
  private videoPlayerApi: VideoPlayerApiImpl | null = null;
  private flutterState: FlutterState | null = null;
  private channel?: MethodChannel;

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.pluginBinding = binding;
    Log.i(TAG, "VideoPlayer onAttachedToEngine");
    this.flutterState = new FlutterState(this.pluginBinding.getBinaryMessenger(), this.pluginBinding.getTextureRegistry());
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "samples.flutter.dev/videoplayerplugin");
    let that = this;
    this.channel.setMethodCallHandler({
      onMethodCall(call: MethodCall, result: MethodResult) {
        switch (call.method) {
          case "getAudioTracks":
            that.videoPlayerApi?.naiveAudioTracks(call.argument("tid") as number, (tracks) => {
                console.log(`getAudioTracks: ${tracks}`)
                result.success(tracks);
            });
            break;
            break;
          case "setAudioTrack":
            that.videoPlayerApi?.naiveSetAudioTrack(call.argument("tid") as number, call.argument("track") as string)
            result.success(null);
            break;
          case "callEvent":
            break;
            break;
          default:
            result.notImplemented();
            break;
        }
      }
    })
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    Log.i(TAG, "VideoPlayer onDetachedFromEngine");
    this.pluginBinding = null;
    if (this.videoPlayerApi != null) {
      this.videoPlayerApi.detach();
      this.videoPlayerApi = null;
    }
    this.channel?.setMethodCallHandler(null);
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    Log.i(TAG, "VideoPlayer onAttachedToAbility");
    if (this.flutterState != null && this.pluginBinding != null && this.videoPlayerApi == null) {
      this.videoPlayerApi = new VideoPlayerApiImpl(this.flutterState, binding);
      this.videoPlayerApi.setup(this.pluginBinding.getBinaryMessenger());
    }
  }
  onDetachedFromAbility(): void {
    Log.i(TAG, "VideoPlayer onDetachedFromAbility");
  }
}

export class FlutterState {
  private binaryMessenger: BinaryMessenger;
  private textureRegistry: TextureRegistry;

  constructor(binaryMessenger: BinaryMessenger, textureRegistry: TextureRegistry) {
    this.binaryMessenger = binaryMessenger;
    this.textureRegistry = textureRegistry;
  }

  getBinaryMessenger(): BinaryMessenger {
    return this.binaryMessenger;
  }

  getTextureRegistry(): TextureRegistry {
    return this.textureRegistry;
  }
}