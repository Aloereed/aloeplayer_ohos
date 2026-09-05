import 'package:flutter/material.dart';
import '../services/sleep_timer.dart';

class SleepTimerButton extends StatelessWidget {
  final Color? color;
  const SleepTimerButton({super.key, this.color});
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: PlaybackSleepTimer.instance, builder: (_, __) => IconButton(
    tooltip: PlaybackSleepTimer.instance.active ? '定时停止已开启' : '定时停止',
    color: PlaybackSleepTimer.instance.active ? Colors.amber : color,
    icon: const Icon(Icons.bedtime_outlined), onPressed: () => showSleepTimer(context)));
}

Future<void> showSleepTimer(BuildContext context) async {
  final timer = PlaybackSleepTimer.instance;
  final selected = await showDialog<int>(context: context, builder: (context) => SimpleDialog(title: const Text('定时停止'), children: [
    if (timer.deadline != null) Padding(padding: const EdgeInsets.all(16), child: Text('将在 ${timer.deadline!.hour.toString().padLeft(2, '0')}:${timer.deadline!.minute.toString().padLeft(2, '0')} 停止')),
    for (final minutes in [15, 30, 45, 60, 90]) SimpleDialogOption(onPressed: () => Navigator.pop(context, minutes), child: Text('$minutes 分钟后')),
    SimpleDialogOption(onPressed: () => Navigator.pop(context, -1), child: const Text('当前曲目 / 本集结束后')),
    SimpleDialogOption(onPressed: () => Navigator.pop(context, 0), child: const Text('关闭定时停止')),
  ]));
  if (selected == null) return;
  if (selected == 0) { timer.cancel(); }
  else if (selected == -1) { timer.afterCurrentItem(); }
  else { timer.start(Duration(minutes: selected)); }
}
