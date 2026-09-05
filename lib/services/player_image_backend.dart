import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'mpv_image_enhancement.dart';

class PlayerImageBackend implements MpvImageBackend {
  final Player player;
  final VideoController controller;
  PlayerImageBackend(this.player, this.controller);
  NativePlayer get _native => player.platform as NativePlayer;
  @override Future<String> read(String property) => _native.getProperty(property);
  @override Future<void> write(String property, String value) => _native.setProperty(property, value);
  @override Future<void> resize(int? width, int? height) => controller.setSize(width: width, height: height);
}
