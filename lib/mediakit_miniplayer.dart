import 'package:flutter/material.dart';
import 'mediakit_audio_service.dart';

class MediaKitMiniPlayer extends StatefulWidget {
  final VoidCallback onTap;

  const MediaKitMiniPlayer({Key? key, required this.onTap}) : super(key: key);

  @override
  _MediaKitMiniPlayerState createState() => _MediaKitMiniPlayerState();
}

class _MediaKitMiniPlayerState extends State<MediaKitMiniPlayer> {
  final MediaKitAudioService _audioService = MediaKitAudioService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaKitPlayerState>(
      stream: _audioService.playerStateStream,
      builder: (context, snapshot) {
        // If no audio is playing, don't show the mini player
        if (_audioService.player == null ||
            _audioService.currentFilePath == null ||
            !snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final state = snapshot.data!;

        IconData _getLoopModeIcon(MediaKitLoopMode mode) {
          switch (mode) {
            case MediaKitLoopMode.off:
              return Icons.repeat;
            case MediaKitLoopMode.all:
              return Icons.repeat_on_outlined;
            case MediaKitLoopMode.one:
              return Icons.repeat_one_on_outlined;
            case MediaKitLoopMode.random:
              return Icons.shuffle_on_outlined;
          }
        }

        // 获取循环模式图标颜色
        Color _getLoopModeColor(MediaKitLoopMode mode) {
          return mode == MediaKitLoopMode.off ? Colors.grey.shade600 : Colors.lightBlue;
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
                    image: state.coverBytes != null
                        ? DecorationImage(
                            image: MemoryImage(state.coverBytes!),
                            fit: BoxFit.cover,
                          )
                        : null,
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: state.coverBytes == null
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
                          state.title.isNotEmpty
                              ? state.title
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
                          state.artist.isNotEmpty
                              ? state.artist
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
                  tooltip: _audioService.loopMode == MediaKitLoopMode.off
                      ? '不循环'
                      : (_audioService.loopMode == MediaKitLoopMode.all
                          ? '全部循环'
                          : (_audioService.loopMode == MediaKitLoopMode.one
                              ? '单曲循环'
                              : '随机播放')),
                ),

                // Previous button
                IconButton(
                  icon: Icon(Icons.skip_previous, size: 24),
                  onPressed: () async {
                    await _audioService.playPrevious();
                  }
                ),

                // Play/Pause button
                IconButton(
                  icon: Icon(
                    state.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow,
                    size: 28,
                  ),
                  onPressed: () {
                    if (_audioService.player != null) {
                      if (_audioService.player!.state.playing) {
                        _audioService.player!.pause();
                      } else {
                        _audioService.player!.play();
                      }
                      _audioService.updatePlayerState();
                    }
                  },
                ),

                // Next button
                IconButton(
                  icon: Icon(Icons.skip_next, size: 24),
                  onPressed: () async {
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
