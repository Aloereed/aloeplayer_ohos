/**
 * Copyright (C) 2024 Huawei Device Co., Ltd.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 * */
import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import HashMap from '@ohos.util.HashMap';
import media from '@ohos.multimedia.media'
import image from '@ohos.multimedia.image'
import fs from "@ohos.file.fs"
/** VideoThumbnaiOhosPlugin **/
export default class VideoThumbnaiOhosPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;

  constructor() {
  }

  getUniqueClassName(): string {
    return "VideoThumbnaiOhosPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "plugins.justsoft.xyz/video_thumbnail");
    this.channel.setMethodCallHandler(this)
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null)
    }
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    let video: string = call.args.get("video");
    let format: number = call.args.get("format");
    let maxh: number = call.args.get("maxh");
    let maxw: number = call.args.get("maxw");
    let timeMs: number = call.args.get("timeMs");
    let quality: number = call.args.get("quality");
    let headers: HashMap<string, string> = call.args.get("headers");
    let method = call.method;
    let thumbnail: ESObject = null;
    let handled: boolean = false;
    let exc = "";
    try {
      if (method == "file") {
        let path: string = call.args.get("path");
        thumbnail = await buildThumbnailFile(video, headers, path, format, maxh, maxw, timeMs, quality);
        handled = true;
      } else if (method == "data") {
        thumbnail = await buildThumbnailData(video, headers, format, maxh, maxw, timeMs, quality);
        handled = true;
      }
    } catch (e) {
      exc = e.message.toString() ;
    }
    this.onResult(result, thumbnail, handled, exc, method);
  }
  onResult(result: MethodResult, thumbnail: null, handled: boolean, exc: string, method: string) {
    if (exc != "" ) {
      result.error("", exc, "");
      return;
    }
    if (method == "file") {
      result.success(thumbnail);
    } else if (method == "data") {
      result.success(setDataThumbnail(thumbnail));
    }
  }
}

function setDataThumbnail(thumbnail: ESObject): Uint8Array {
  let uint8Array = new Uint8Array(thumbnail);
  return uint8Array;
}

async function createVideoThumbnail(video: string, headers: HashMap<string, string>, maxh: number, maxw: number,
  timeMs: number): Promise<image.PixelMap> {
  let param: media.PixelMapParams = {
    width: maxw,
    height: maxh
  }
  let avImageGenerator: media.AVImageGenerator = await media.createAVImageGenerator();
  let file: fs.File | undefined;
  try {
    file = await fs.open(video, fs.OpenMode.READ_ONLY);
    avImageGenerator.fdSrc = { fd: file.fd };
    return await avImageGenerator.fetchFrameByTime(timeMs * 1000,
      media.AVImageQueryOptions.AV_IMAGE_QUERY_CLOSEST_SYNC, param);
  } finally {
    // Release the decoder before closing the descriptor it still owns.
    try { await avImageGenerator.release(); } catch (error) {}
    if (file) { try { await fs.close(file); } catch (error) {} }
  }
}

async function buildThumbnailFile(vidPath: string, headers: HashMap<string, string>, path: string, format: number,
  maxh: number, maxw: number, timeMs: number, quality: number): Promise<string> {
  let pickImageBuffer = await buildThumbnailData(vidPath, headers, format, maxh, maxw, timeMs, quality);
  let ext = formatExt(format);
  let i = vidPath.lastIndexOf(".");
  let fullpath = vidPath.substring(0, i + 1) + ext;
  let isLocalFile = (vidPath.startsWith("/") || vidPath.startsWith("file://"));
  if (path == null && !isLocalFile) {
    path = ""
  }
  if (path != null) {
    if (path.endsWith(ext)) {
      fullpath = path;
    } else {
      let j = fullpath.lastIndexOf("/");
      if (path.endsWith("/")) {
        fullpath = path + fullpath.substring(j + 1);
      } else {
        fullpath = path + fullpath.substring(j);
      }
    }
  }
  let outputFile: fs.File;
  outputFile = fs.openSync(fullpath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
  try {
    await fs.write(outputFile.fd, pickImageBuffer);
    await fs.close(outputFile);
  } catch (e) {
  }
  return fullpath;
}

async function buildThumbnailData(video: string, headers: HashMap<string, string>, format: number, maxh: number,
  maxw: number, timeMs: number, mQuality: number): Promise<ArrayBuffer | null> {
  let mPixelMap: image.PixelMap = await createVideoThumbnail(video, headers, maxh, maxw, timeMs);
  let data: ArrayBuffer | null = null;
  if (mPixelMap != null) {
    const imagePackerApi: image.ImagePacker = image.createImagePacker();
    try {
      let packOpts: image.PackingOption = { format: 'image/' + formatExt(format), quality: mQuality };
      data = await imagePackerApi.packing(mPixelMap, packOpts);
    } finally {
      try { await imagePackerApi.release(); } catch (error) {}
      try { await mPixelMap.release(); } catch (error) {}
    }
  }
  return data
}

function formatExt(format: number): string {
  switch (format) {
    case 0:
    default:
      return "jpeg";
    case 1:
      return "png";
    case 2:
      return "webp";
  }
}
