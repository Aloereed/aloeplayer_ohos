/*
 * @Author: 
 * @Date: 2025-01-19 13:47:39
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-01-19 18:54:53
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

typedef OnViewCreated = Function(VolumeViewController);

///自定义OhosView
class VolumeOhosView extends StatefulWidget {
  final OnViewCreated onViewCreated;

  const VolumeOhosView(this.onViewCreated, {Key? key}) : super(key: key);

  @override
  State<VolumeOhosView> createState() => _VolumeOhosViewState();
}

class _VolumeOhosViewState extends State<VolumeOhosView> {
  late MethodChannel _channel;

  @override
  Widget build(BuildContext context) {
    return _getPlatformFaceView();
  }

  Widget _getPlatformFaceView() {
    return OhosView(
      viewType: 'com.aloereed.aloeplayer/volumeView',
      onPlatformViewCreated: _onPlatformViewCreated,
      creationParams: const <String, dynamic>{'initParams': 'hello world'},
      creationParamsCodec: const StandardMessageCodec(),
    );
  }

  void _onPlatformViewCreated(int id) {
    _channel = MethodChannel('com.aloereed.aloeplayer/volumeView$id');
    final controller = VolumeViewController._(
      _channel,
    );
    widget.onViewCreated(controller);
  }
}

class VolumeViewController {
  final MethodChannel _channel;
  final StreamController<String> _controller = StreamController<String>();

  VolumeViewController._(
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

  Stream<String> get volumeDataStream => _controller.stream;

  // 发送数据给native
  Future<void> sendMessageToOhosView(String method,String message) async {
    await _channel.invokeMethod(
      method,
      message,
    );
  }
}

class VolumeExample extends StatefulWidget {
  VolumeExample({Key? key}) : super(key: key);
  VolumeViewController? _controller;
  VolumeViewController? get controller => _controller;
  @override
  State<VolumeExample> createState() => _VolumeExampleState();
}

class _VolumeExampleState extends State<VolumeExample> {
  String receivedData = '';

  void _onVolumeOhosViewCreated(VolumeViewController controller) {
    widget._controller = controller;
    widget._controller?.volumeDataStream.listen((data) {
      //接收到来自OHOS端的数据
      setState(() {
        receivedData = '来自ohos的数据：$data';
      });
    });
  }

  Widget _buildOhosView() {
    return Expanded(
      child: Container(
        color: Colors.blueAccent.withAlpha(60),
        child: VolumeOhosView(_onVolumeOhosViewCreated),
      ),
      flex: 1,
    );
  }

  Widget _buildFlutterView() {
    return Expanded(
      child: Stack(
        alignment: AlignmentDirectional.bottomCenter,
        children: [

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
        _buildFlutterView(),
      ],
    );
  }
}