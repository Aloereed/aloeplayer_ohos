/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 *
 * Copyright © 2025 & onwards, Bao Han <erbws@foxmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */

import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { SurfaceTextureEntry } from '@ohos/flutter_ohos';
import { TextureUpdateCallback } from './TextureUpdateCallback';
import { TextureRegistry } from '@ohos/flutter_ohos';

const TAG = "VideoOutput";

export class VideoOutput {
  private id: number = 0;
  private wid: number = 0;
  private w: number = 0;
  private h: number = 0;
  private disposed: boolean = false;
  private textureUpdateCallback: TextureUpdateCallback;
  private textureRegistry: TextureRegistry;
  private surfaceProducer: SurfaceTextureEntry;

  constructor(textureRegistry: TextureRegistry, surfaceProducer: SurfaceTextureEntry,
    textureUpdateCallback: TextureUpdateCallback) {
    this.surfaceProducer = surfaceProducer;
    this.textureUpdateCallback = textureUpdateCallback;
    this.textureRegistry = textureRegistry;
    this.id = surfaceProducer.getTextureId();
    this.wid = surfaceProducer.getSurfaceId();
    this.setSurfaceSize(1, 1, true);
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    try {
      this.onSurfaceDestroyed();
    } catch (e) {
      Log.e(TAG, `dispose: ${e}`);
    }
  }

  setSurfaceSize(width: number, height: number, force: boolean = false): void {
    if (this.disposed || width <= 0 || height <= 0) return;
    try {
      if (!force && this.w == width && this.h == height) {
        return;
      }

      this.w = width;
      this.h = height;
      this.textureRegistry.setTextureBufferSize(this.id, width, height);
      this.onSurfaceCreated();
    } catch (e) {
      Log.e(TAG, `setSurfaceSize error: ${e}`);
    }
  }

  private onSurfaceCreated(): void {
    Log.i(TAG, "onSurfaceCreated");
    try {
      this.id = this.surfaceProducer.getTextureId();
      this.wid = this.surfaceProducer.getSurfaceId();
      this.textureUpdateCallback.onTextureUpdate(this.id, this.wid, this.w, this.h);
    } catch (e) {
      Log.e(TAG, `onSurfaceCreated error: ${e}`);
    }
  }

  private onSurfaceDestroyed(): void {
    Log.i(TAG, "onSurfaceDestroyed");
    try {
      this.textureUpdateCallback.onTextureUpdate(this.id, 0, 0, 0);
    } finally {
      // SurfaceTextureRegistryEntry.release is unimplemented in Flutter OHOS.
      this.textureRegistry.unregisterTexture(this.id);
    }
  }
}
