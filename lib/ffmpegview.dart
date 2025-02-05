/*
 * @Author: 
 * @Date: 2025-01-19 13:47:39
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-02-05 13:14:23
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

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef OnViewCreated = Function(FfmpegViewController,String);

///自定义OhosView
class FfmpegOhosView extends StatefulWidget {
  final OnViewCreated onViewCreated;
  final String initUri;

  const FfmpegOhosView(this.onViewCreated,this.initUri, {Key? key}) : super(key: key);

  @override
  State<FfmpegOhosView> createState() => _FfmpegOhosViewState();
}

class _FfmpegOhosViewState extends State<FfmpegOhosView> {
  late MethodChannel _channel;

  @override
  Widget build(BuildContext context) {
    return _getPlatformFaceView();
  }

  Widget _getPlatformFaceView() {
    print("get platform face view");
    return OhosView(
      viewType: 'com.aloereed.aloeplayer/ffmpegView',
      onPlatformViewCreated: _onPlatformViewCreated,
      creationParams: <String, dynamic>{'initParams': widget.initUri },
      creationParamsCodec: const StandardMessageCodec(),
    );
  }

  void _onPlatformViewCreated(int id) {
    print("on platform view created");
    _channel = MethodChannel('com.aloereed.aloeplayer/ffmpegView$id');
    final controller = FfmpegViewController._(
      _channel,
    );
    widget.onViewCreated(controller,widget.initUri);
  }
}

class FfmpegViewController {
  final MethodChannel _channel;
  final StreamController<String> _controller = StreamController<String>();

  FfmpegViewController._(
    this._channel,
  ) {
    _channel.setMethodCallHandler(
      (call) async {
        switch (call.method) {
          case 'getMessageFromOhosView':
            // 从native端获取数据
            final result = call.arguments as String;
            _controller.sink.add(result);
            break;
        }
      },
    );
  }

  Stream<String> get ffmpegDataStream => _controller.stream;

  // 发送数据给native
  Future<void> sendMessageToOhosView(String method,String message) async {
    print("sending message to ohos:" + message);
    await _channel.invokeMethod(
      method,
      message,
    );
  }
}

class FfmpegExample extends StatefulWidget {
  FfmpegExample({Key? key,required this.initUri}) : super(key: key);
  FfmpegViewController? _controller;
  String initUri = '';
  FfmpegViewController? get controller => _controller;
  @override
  State<FfmpegExample> createState() => _FfmpegExampleState();
}

class _FfmpegExampleState extends State<FfmpegExample> {
  String receivedData = '';

  void _onFfmpegOhosViewCreated(FfmpegViewController controller,String initUri) {
    widget._controller = controller;
    widget._controller?.ffmpegDataStream.listen((data) {
      //接收到来自OHOS端的数据
      setState(() {
        receivedData = '来自ohos的数据：$data';
      });
    });
    widget._controller?.sendMessageToOhosView("getMessageFromFlutterView",initUri);
  }

  Widget _buildOhosView() {
    print("build ohos view");
    return Expanded(
      child: Container(
        color: Colors.blueAccent.withAlpha(60),
        child: FfmpegOhosView(_onFfmpegOhosViewCreated,widget.initUri),
      ),
      flex: 1,
    );
  }

  Widget _buildFlutterView() {
    return Expanded(
      child: Stack(
        alignment: AlignmentDirectional.bottomCenter,
        children: [
          Text("Hello",style: TextStyle(fontSize: 20,color: Colors.white ),),
        ],
      ),
      flex: 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildOhosView(),
        // 分割线
        // Container(
        //   height: 1,
        //   color: Colors.white,
        // ),
        // _buildFlutterView(),
      ],
    );
  }
}