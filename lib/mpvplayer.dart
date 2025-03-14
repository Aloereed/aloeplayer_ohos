import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';  // 媒体播放核心
import 'package:media_kit_video/media_kit_video.dart';  // 视频播放界面

class MPVPlayer extends StatefulWidget {
  final String filePath;

  const MPVPlayer({Key? key, required this.filePath}) : super(key: key);

  @override
  _MPVPlayerState createState() => _MPVPlayerState();
}

class _MPVPlayerState extends State<MPVPlayer> {
  late final Player player;
  late final VideoController controller;

  @override
  void initState() {
    super.initState();
    MediaKit.ensureInitialized();

    // 初始化播放器
    player = Player();
    controller = VideoController(player);
    
    // 打开媒体文件
    player.open(Media(widget.filePath));
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Media Kit Player'),
      ),
      body: Center(
        child: Video(
          controller: controller,
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (player.state.playing) {
            player.pause();
          } else {
            player.play();
          }
        },
        child: Icon(
          player.state.playing ? Icons.pause : Icons.play_arrow,
        ),
      ),
    );
  }
}