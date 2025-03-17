/*
 * @Author: 
 * @Date: 2025-01-19 13:47:39
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-03-16 18:07:01
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

typedef OnViewCreated = Function(HdrViewController,String);

///自定义OhosView
class HdrOhosView extends StatefulWidget {
  final OnViewCreated onViewCreated;
  final String initUri;

  const HdrOhosView(this.onViewCreated,this.initUri, {Key? key}) : super(key: key);

  @override
  State<HdrOhosView> createState() => _HdrOhosViewState();
}

class _HdrOhosViewState extends State<HdrOhosView> {
  late MethodChannel _channel;

  @override
  Widget build(BuildContext context) {
    return _getPlatformFaceView();
  }

  Widget _getPlatformFaceView() {
    print("get platform face view");
    return OhosView(
      viewType: 'com.aloereed.aloeplayer/hdrView',
      onPlatformViewCreated: _onPlatformViewCreated,
      creationParams: <String, dynamic>{'initParams': widget.initUri },
      creationParamsCodec: const StandardMessageCodec(),
    );
  }

  void _onPlatformViewCreated(int id) {
    print("on platform view created");
    _channel = MethodChannel('com.aloereed.aloeplayer/hdrView$id');
    final controller = HdrViewController._(
      _channel,
    );
    widget.onViewCreated(controller,widget.initUri);
  }
}

class HdrViewController {
  final MethodChannel _channel;
  final StreamController<String> _controller = StreamController<String>();
  Function toggleFullScreen = (){};
  int currentPosition=0;
  bool prepared = false;

  HdrViewController._(
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
          case 'getPrepared':
            // 从native端获取数据
            final result = call.arguments as bool;
            print("get current prepared from ohos:" + result.toString());
            prepared = result;
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

  Stream<String> get hdrDataStream => _controller.stream;

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

class HdrExample extends StatefulWidget {
  HdrExample({Key? key,required this.initUri, required this.toggleFullScreen}) : super(key: key);
  HdrViewController? _controller;
  String initUri = '';
  int currentPosition=0;
  Function toggleFullScreen = (){};
  HdrViewController? get controller => _controller;
  @override
  State<HdrExample> createState() => _HdrExampleState();
}

class _HdrExampleState extends State<HdrExample> {
  String receivedData = '';

  void _onHdrOhosViewCreated(HdrViewController controller,String initUri) {
    widget._controller = controller;
    widget._controller?.toggleFullScreen = widget.toggleFullScreen;
    widget._controller?.hdrDataStream.listen((data) {
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
        child: HdrOhosView(_onHdrOhosViewCreated,widget.initUri),
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