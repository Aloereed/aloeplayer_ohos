import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail_ohos/video_thumbnail_ohos.dart';
import '../models/catalog_item.dart';
import '../services/catalog_playback.dart';
import '../services/disk_thumbnail_cache.dart';
import '../services/thumbnail_cache.dart';
import '../services/video_thumbnail_loader.dart';
import '../services/work_queue.dart';
import '../settings.dart';

class CatalogArtwork extends StatefulWidget {
  final CatalogItem item;
  final String? poster;
  final bool generate;
  const CatalogArtwork(
      {super.key, required this.item, this.poster, this.generate = true});
  @override
  State<CatalogArtwork> createState() => _CatalogArtworkState();
}

class _CatalogArtworkState extends State<CatalogArtwork> {
  static final _queue = WorkQueue(concurrency: 1);
  static final _memory = ThumbnailCache();
  static Future<DiskThumbnailCache>? _disk;
  Future<Uint8List?>? _thumbnail;
  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(CatalogArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.poster != null && oldWidget.poster == widget.poster &&
        oldWidget.item.revision != widget.item.revision) {
      ResizeImage(FileImage(File(widget.poster!)), width: 480).evict();
    }
    if (oldWidget.item.filePath != widget.item.filePath ||
        oldWidget.item.revision != widget.item.revision ||
        oldWidget.generate != widget.generate ||
        oldWidget.poster != widget.poster) {
      _prepare();
    }
  }

  void _prepare() {
    _thumbnail = null;
    if (widget.poster == null && !widget.item.isAudio && widget.generate) {
      final item = widget.item;
      bool stillCurrent() => mounted && widget.item.filePath == item.filePath &&
          widget.item.revision == item.revision;
      _thumbnail = _queue.run(() async {
        if (!stillCurrent()) return null;
        try {
          if (await SettingsService().getDisableThumbnail()) return null;
          await catalogSource(item, activate: true);
          final disk = await (_disk ??= getTemporaryDirectory().then((root) =>
              DiskThumbnailCache(
                  Directory(path.join(root.path, 'catalog-thumbnails')),
                  maxBytes: 64 * 1024 * 1024)));
          if (!stillCurrent()) return null;
          final loader = VideoThumbnailLoader(
              disk: disk,
              memory: _memory,
              library: File(item.filePath).parent,
              decode: (source) => VideoThumbnailOhos.thumbnailData(
                  video: source,
                  imageFormat: ImageFormat.JPEG,
                  maxWidth: 320,
                  quality: 70),
              fallbackDecode: (source) async {
                const platform =
                    MethodChannel('samples.flutter.dev/ffmpegplugin');
                final encoded = await platform.invokeMethod<String>(
                    'getVideoThumbnailFallback', {'path': source});
                return encoded == null || encoded.isEmpty
                    ? null
                    : base64Decode(encoded);
              });
          return await loader.load(File(item.filePath));
        } catch (_) {
          return null;
        }
      });
    }
  }

  Widget _placeholder(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
        decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colors.primaryContainer, colors.secondaryContainer])),
        child: Center(
            child: Icon(
                widget.item.isAudio
                    ? Icons.music_note_rounded
                    : widget.item.series != null
                        ? Icons.video_library_outlined
                        : Icons.movie_outlined,
                color: colors.onPrimaryContainer,
                size: 48)));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.poster != null) {
      return Image.file(File(widget.poster!),
          key: ValueKey('${widget.poster}:${widget.item.revision}'),
          fit: BoxFit.cover,
          cacheWidth: 480,
          errorBuilder: (_, __, ___) => _placeholder(context));
    }
    if (_thumbnail == null) return _placeholder(context);
    return FutureBuilder<Uint8List?>(
        future: _thumbnail,
        builder: (context, snapshot) => snapshot.data == null
            ? _placeholder(context)
            : Image.memory(snapshot.data!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _placeholder(context)));
  }
}
