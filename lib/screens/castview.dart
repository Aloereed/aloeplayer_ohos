/*
 * @Author: 
 * @Date: 2025-01-19 13:47:39
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-03-14 19:02:56
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
import '../services/media_cast_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef OnViewCreated = Function(CastViewController,String);

///自定义OhosView
class CastOhosView extends StatefulWidget {
  final OnViewCreated onViewCreated;
  final String initUri;

  const CastOhosView(this.onViewCreated,this.initUri, {Key? key}) : super(key: key);

  @override
  State<CastOhosView> createState() => _CastOhosViewState();
}

class _CastOhosViewState extends State<CastOhosView> {
  late MethodChannel _channel;

  @override
  Widget build(BuildContext context) {
    return _getPlatformFaceView();
  }

  Widget _getPlatformFaceView() {
    print("get platform face view");
    return OhosView(
      viewType: 'com.aloereed.aloeplayer/castView',
      onPlatformViewCreated: _onPlatformViewCreated,
      creationParams: <String, dynamic>{'initParams': widget.initUri },
      creationParamsCodec: const StandardMessageCodec(),
    );
  }

  void _onPlatformViewCreated(int id) {
    print("on platform view created");
    _channel = MethodChannel('com.aloereed.aloeplayer/castView$id');
    final controller = CastViewController._(
      _channel,
    );
    widget.onViewCreated(controller,widget.initUri);
  }
}

class CastViewController {
  final MethodChannel _channel;
  final StreamController<String> _controller = StreamController<String>();
  Function toggleFullScreen = (){};
  int currentPosition=0;

  CastViewController._(
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
          case 'getCurrentPosition':
            // 从native端获取数据
            final result = call.arguments as int;
            print("get current position from ohos:" + result.toString());
            currentPosition = result;
            break;
          case 'toggleFullscreen':
            // 从native端获取数据
            toggleFullScreen();
            print("toggle full screen");
            break;
        }
      },
    );
  }

  Stream<String> get castDataStream => _controller.stream;

  // 发送数据给native
  Future<void> sendMessageToOhosView(String method,String message) async {
    print("sending message to ohos:" + message);
    await _channel.invokeMethod(
      method,
      message,
    );
  }
  Future<int?> sendMessageToOhosViewInt(String method,String message) async {
    print("sending message to ohos:" + message);
    await _channel.invokeMethod<int>(
      method,
      message,
    );
  }
}

class CastExample extends StatefulWidget {
  CastExample({Key? key,required this.initUri, required this.toggleFullScreen}) : super(key: key);
  CastViewController? _controller;
  String initUri = '';
  int currentPosition=0;
  Function toggleFullScreen = (){};
  CastViewController? get controller => _controller;
  @override
  State<CastExample> createState() => _CastExampleState();
}

class _CastExampleState extends State<CastExample> {
  String receivedData = '';

  void _onCastOhosViewCreated(CastViewController controller,String initUri) {
    widget._controller = controller;
    widget._controller?.toggleFullScreen = widget.toggleFullScreen;
    widget._controller?.castDataStream.listen((data) {
      //接收到来自OHOS端的数据
      setState(() {
        receivedData = '来自ohos的数据：$data';
        widget.currentPosition = int.parse(data);
      });
    });
    widget._controller?.sendMessageToOhosView("getMessageFromFlutterView",initUri);
  }

  Widget _buildOhosView() {
    print("build ohos view");
    return Expanded(
      child: Container(
        color: Colors.blueAccent.withAlpha(60),
        child: CastOhosView(_onCastOhosViewCreated,widget.initUri),
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