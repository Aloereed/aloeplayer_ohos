/*
 * @Author: 
 * @Date: 2025-02-17 13:28:54
 * @LastEditors: 
 * @LastEditTime: 2025-03-14 18:31:39
 * @Description: file content
 */
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
import { fileIo as fs, ReadOptions } from "@kit.CoreFileKit"
import { common } from "@kit.AbilityKit"
import { buffer } from "@kit.ArkTS"
import { FlutterAbility, FlutterEngine } from "@ohos/flutter_ohos"
import { GeneratedPluginRegistrant } from "../plugins/GeneratedPluginRegistrant"
import { UIAbility, AbilityConstant, Want } from "@kit.AbilityKit"
import DownloadPlugin from "./DownloadPlugin"
import VolumePlugin from "./VolumePlugin"
import FfmpegPlugin from "./FfmpegPlugin"
import CastPlugin from "./CastPlugin"
let wantInfo: Want

function createFile(openuri: string): void {
    // 文件不存在时创建并打开文件，文件存在时打开文件
    let file = fs.openSync(
        "/data/storage/el2/base/openuri.txt",
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE
    )
    // 写入一段内容至文件
    let writeLen = fs.writeSync(file.fd, openuri)
    console.info("The length of str is: " + writeLen)
    // 创建一个大小为1024字节的ArrayBuffer对象，用于存储从文件中读取的数据
    let arrayBuffer = new ArrayBuffer(1024)
    // 设置读取的偏移量和长度
    let readOptions: ReadOptions = {
        offset: 0,
        length: arrayBuffer.byteLength,
    }
    // 读取文件内容到ArrayBuffer对象中，并返回实际读取的字节数
    let readLen = fs.readSync(file.fd, arrayBuffer, readOptions)
    // 将ArrayBuffer对象转换为Buffer对象，并转换为字符串输出
    let buf = buffer.from(arrayBuffer, 0, readLen)
    console.info("the content of file: " + buf.toString())
    // 关闭文件
    fs.closeSync(file)
}

export default class EntryAbility extends FlutterAbility {
    private myDownloadPlugin?: DownloadPlugin

    configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GeneratedPluginRegistrant.registerWith(flutterEngine)
        this.myDownloadPlugin = new DownloadPlugin()
        this.addPlugin(this.myDownloadPlugin)
        this.addPlugin(new VolumePlugin())
        this.addPlugin(new FfmpegPlugin())
        this.addPlugin(new CastPlugin())
    }
    onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam) {
        let uri = want.uri
        if (uri == null || uri == undefined) {
            console.info("The length of str")
            return
        } else {
            // createFile(uri)
            this.myDownloadPlugin?.sendWant(uri)
        }
    }
    async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
        super.onCreate(want, launchParam)
        let uri = want.uri
        if (uri == null || uri == undefined) {
            console.info("The length of str")
            return
        } else {
            createFile(uri)
            this.myDownloadPlugin?.sendWant(uri)
        }
    }
}
