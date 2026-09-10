import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Own the request for the lifetime of a visible tile, including a missing cover.
/// Fast scrolling defers file probing until the scroll velocity has settled.
class AudioArtworkBuilder extends StatefulWidget {
  final String source;
  final Future<Uint8List?> Function() load;
  final AsyncWidgetBuilder<Uint8List?> builder;
  const AudioArtworkBuilder({super.key, required this.source, required this.load, required this.builder});

  @override
  State<AudioArtworkBuilder> createState() => _AudioArtworkBuilderState();
}

class _AudioArtworkBuilderState extends State<AudioArtworkBuilder> {
  Future<Uint8List?>? _future;
  Timer? _retry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _request();
  }

  @override
  void didUpdateWidget(AudioArtworkBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _future = null;
      _retry?.cancel();
      _retry = null;
      _request();
    }
  }

  void _request() {
    if (_future != null || _retry != null) return;
    if (Scrollable.recommendDeferredLoadingForContext(context)) {
      _retry = Timer(const Duration(milliseconds: 100), () {
        _retry = null;
        if (mounted) setState(_request);
      });
    } else {
      _future = Future.sync(widget.load);
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _future, builder: widget.builder);
}
