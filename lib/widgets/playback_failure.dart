import 'package:flutter/material.dart';

class PlaybackFailure extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback onBack;
  const PlaybackFailure(
      {super.key,
      required this.message,
      required this.onRetry,
      required this.onBack});

  @override
  Widget build(BuildContext context) => Center(
      child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                  color: Colors.black87,
                  child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(message,
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center),
                        Wrap(spacing: 12, children: [
                          TextButton(
                              onPressed: onRetry, child: const Text('重试')),
                          TextButton(
                              onPressed: onBack, child: const Text('返回')),
                        ]),
                      ]))))));
}
