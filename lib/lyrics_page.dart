// lyrics_page.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_lyric/lyrics_reader.dart';
import 'package:flutter_lyric/lyrics_reader_model.dart';
import 'audio_player_service.dart';

class LyricsPage extends StatefulWidget {
  final dynamic metadata;
  final Uint8List? coverBytes;
  final AudioPlayerService playerService;
  final VoidCallback onBackToPlayer;
  
  const LyricsPage({
    Key? key,
    required this.metadata,
    required this.coverBytes,
    required this.playerService,
    required this.onBackToPlayer,
  }) : super(key: key);

  @override
  State<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<LyricsPage> {
  String? _lyricsText;
  bool _isLoadingLyrics = true;
  LyricsReaderModel? _lyricsModel;

  @override
  void initState() {
    super.initState();
    _loadLyrics();
  }

  Future<void> _loadLyrics() async {
    setState(() => _isLoadingLyrics = true);
    
    try {
      // 在实际应用中，需要从文件或API获取歌词
      final lyrics = await widget.playerService.getLyrics(widget.metadata?.path ?? '');
      
      if (lyrics != null && lyrics.isNotEmpty) {
        setState(() {
          _lyricsText = lyrics;
          _lyricsModel = LyricsModelBuilder.create()
              .bindLyricToMain(lyrics)
              .getModel();
        });
      } else {
        // 如果没有歌词，使用一个示例歌词或通知用户没有歌词
        setState(() {
          _lyricsText = "[00:00.00]暂无歌词";
          _lyricsModel = LyricsModelBuilder.create()
              .bindLyricToMain("[00:00.00]暂无歌词")
              .getModel();
        });
      }
    } catch (e) {
      print("加载歌词错误: $e");
      setState(() {
        _lyricsText = "[00:00.00]加载歌词失败";
        _lyricsModel = LyricsModelBuilder.create()
            .bindLyricToMain("[00:00.00]加载歌词失败")
            .getModel();
      });
    }
    
    setState(() => _isLoadingLyrics = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity! > 0) {
          // 向右滑动返回播放界面
          widget.onBackToPlayer();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black,
              Colors.grey[900]!,
              Colors.black,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 头部
              _buildHeader(),
              
              // 歌词内容
              Expanded(
                child: _isLoadingLyrics
                    ? const Center(child: CircularProgressIndicator())
                    : _buildLyricsContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 歌词页头部
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // 专辑封面小图
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 5,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: widget.coverBytes != null
                  ? Image.memory(widget.coverBytes!, fit: BoxFit.cover)
                  : Container(
                      color: Colors.grey[800],
                      child: const Icon(Icons.music_note, color: Colors.white),
                    ),
            ),
          ),
          
          const SizedBox(width: 16),
          
          // 标题和艺术家
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.metadata.title ?? 'Unknown Title',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.metadata.artist ?? 'Unknown Artist',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          
          // 返回按钮
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
            onPressed: widget.onBackToPlayer,
          ),
        ],
      ),
    );
  }

  // 歌词内容
  Widget _buildLyricsContent() {
    if (_lyricsModel == null) {
      return Center(
        child: Text(
          "暂无歌词",
          style: TextStyle(color: Colors.white.withOpacity(0.6)),
        ),
      );
    }
    
    return StreamBuilder<Duration>(
      stream: widget.playerService.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data?.inMilliseconds ?? 0;
        
        return LyricsReader(
          model: _lyricsModel!,
          position: position,
          lyricUi: UINetease(
            // defaultSize: 18,
            // defaultExtSize: 14,
            // // highlightSize: 18,
            // // highlightExtSize: 14,
            // playingColor: Colors.white,
            // playingExtColor: Colors.white.withOpacity(0.7),
            // otherColor: Colors.white.withOpacity(0.5),
            // otherExtColor: Colors.white.withOpacity(0.3),
            // lineGap: 30,
            // inlineGap: 10,
          ),
          playing: true,
          padding: const EdgeInsets.symmetric(horizontal: 26),
        );
      },
    );
  }
}