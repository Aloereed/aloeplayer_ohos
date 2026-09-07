import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/download_manager.dart';

void main() {
  test('distinguishes notification denial from task validation and timeouts', () {
    expect(downloadBackgroundFailure(PlatformException(code: 'NOTIFICATION', details: 1600004)), contains('通知权限未开启'));
    final validation = downloadBackgroundFailure(PlatformException(code: 'BACKGROUND', details: 9800005));
    expect(validation, contains('9800005'));
    expect(validation, isNot(contains('系统未允许')));
    expect(downloadBackgroundFailure(TimeoutException('startup')), contains('响应超时'));
  });
}
