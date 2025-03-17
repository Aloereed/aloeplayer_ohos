import 'package:flutter/material.dart';
import 'audio_player_service.dart'; // 引入上面创建的服务文件

class MiniPlayer extends StatefulWidget {
  final VoidCallback onTap;

  const MiniPlayer({Key? key, required this.onTap}) : super(key: key);

  @override
  _MiniPlayerState createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  final AudioPlayerService _audioService = AudioPlayerService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: _audioService.playerStateStream,
      builder: (context, snapshot) {
        // If no audio is playing, don't show the mini player
        if (_audioService.controller == null ||
            _audioService.currentFilePath == null) {
          return const SizedBox.shrink();
        }

        IconData _getLoopModeIcon(LoopMode mode) {
          switch (mode) {
            case LoopMode.off:
              return Icons.repeat;
            case LoopMode.all:
              return Icons.repeat_on_outlined;
            case LoopMode.one:
              return Icons.repeat_one_on_outlined;
            case LoopMode.random:
              return Icons.shuffle_on_outlined;
          }
        }

        // 获取循环模式图标颜色
        Color _getLoopModeColor(LoopMode mode) {
          return mode == LoopMode.off ? Colors.grey.shade600 : Colors.lightBlue;
        }

        return GestureDetector(
          onTap: widget.onTap,
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4.0,
                  spreadRadius: 1.0,
                ),
              ],
            ),
            child: Row(
              children: [
                // Album artwork
                Container(
                  width: 50,
                  height: 50,
                  margin: const EdgeInsets.only(left: 8.0),
                  decoration: BoxDecoration(
                    image: _audioService.coverBytes != null
                        ? DecorationImage(
                            image: MemoryImage(_audioService.coverBytes!),
                            fit: BoxFit.cover,
                          )
                        : null,
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: _audioService.coverBytes == null
                      ? Icon(Icons.music_note, color: Colors.grey.shade600)
                      : null,
                ),

                // Song info
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _audioService.title.isNotEmpty
                              ? _audioService.title
                              : 'Unknown Title',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2),
                        Text(
                          _audioService.artist.isNotEmpty
                              ? _audioService.artist
                              : 'Unknown Artist',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),

                // 循环模式按钮
                IconButton(
                  icon: Icon(
                    _getLoopModeIcon(_audioService.loopMode),
                    size: 20,
                    color: _getLoopModeColor(_audioService.loopMode),
                  ),
                  onPressed: () {
                    _audioService.toggleLoopMode();
                    setState(() {});  
                  },
                  tooltip: _audioService.loopMode == LoopMode.off
                      ? '不循环'
                      : (_audioService.loopMode== LoopMode.all ? '全部循环' : '单曲循环'),
                ),

                // Previous button
                IconButton(
                  icon: Icon(Icons.skip_previous, size: 24),
                  onPressed: () async{
                    await _audioService.playPrevious();
                  }
                ),

                // Play/Pause button
                IconButton(
                  icon: Icon(
                    snapshot.data?.isPlaying ?? false
                        ? Icons.pause
                        : Icons.play_arrow,
                    size: 28,
                  ),
                  onPressed: () {
                    if (_audioService.controller != null) {
                      if (_audioService.controller!.value.isPlaying) {
                        _audioService.controller!.pause();
                      } else {
                        _audioService.controller!.play();
                      }
                      _audioService.updatePlayerState();
                    }
                  },
                ),

                // Next button
                IconButton(
                  icon: Icon(Icons.skip_next, size: 24),
                  onPressed: () async{
                    await _audioService.playNext();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
