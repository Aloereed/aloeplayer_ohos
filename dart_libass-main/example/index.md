```dart
File subtitle = File('./test/1.ass');
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

Image img = await dartLibass.getFrame(25001);

ByteData? pngBytes = await img.toByteData(format: ImageByteFormat.png);

File('test.png').writeAsBytesSync(
  pngBytes!.buffer.asUint8List(
    pngBytes.offsetInBytes,
    pngBytes.lengthInBytes,
  ),
);
```
