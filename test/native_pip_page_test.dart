import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/pages/native_pip_page.dart';

void main() {
  const channel = MethodChannel('aloeplayer/system-pip');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() =>
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
  Future<void> native(String method, dynamic args) async {
    final done = Completer<void>();
    binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (_) => done.complete());
    await done.future;
  }

  testWidgets('native return restores latest position and playing state',
      (tester) async {
    PipPlaybackResult? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () async {
                  result = await Navigator.push<PipPlaybackResult>(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const NativePipPage(
                              uri: '/movie.mp4', positionMs: 12000)));
                },
                child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls.singleWhere((c) => c.method == 'open').arguments['positionMs'],
        12000);
    await native('closed', {'positionMs': 17000, 'playing': false});
    await tester.pumpAndSettle();
    expect(result?.positionMs, 17000);
    expect(result?.playing, false);
  });
  testWidgets('missing native callback times out instead of spinning forever',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: NativePipPage(uri: '/movie.mp4', positionMs: 0)));
    await tester.pump(const Duration(seconds: 36));
    expect(find.textContaining('准备超时'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
