import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:dart_libass/dart_libass.dart';

void main() {
  test('init', () async {
    File subtitle = File('./test/1.ass');
    File subtitle2 = File('./test/2.ass');
    File defaultFont = File('./test/Montserrat-Bold.ttf');

    DartLibass dartLibass = DartLibass(
      subtitle: subtitle,
      defaultFont: defaultFont,
      defaultFamily: 'Montserrat-Bold',
      width: 1920,
      height: 1080,
      fonts: [defaultFont],
    );

    await dartLibass.init();

    dartLibass.setTrack(subtitle2);

    Image img = await dartLibass.getFrame(25001);

    dartLibass.dispose();

    ByteData? pngBytes = await img.toByteData(format: ImageByteFormat.png);

    File('test.png').writeAsBytesSync(
      pngBytes!.buffer.asUint8List(
        pngBytes.offsetInBytes,
        pngBytes.lengthInBytes,
      ),
    );
  });
}
