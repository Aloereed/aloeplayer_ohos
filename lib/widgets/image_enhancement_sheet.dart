import 'package:flutter/material.dart';
import '../services/mpv_image_enhancement.dart';

Future<void> showImageEnhancementSheet(BuildContext context, MpvImageEnhancer enhancer) =>
  showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true,
    showDragHandle: true, constraints: const BoxConstraints(maxWidth: 700),
    builder: (_) => FractionallySizedBox(heightFactor: .9, child: ImageEnhancementSheet(enhancer: enhancer)));

class ImageEnhancementSheet extends StatefulWidget {
  final MpvImageEnhancer enhancer;
  const ImageEnhancementSheet({super.key, required this.enhancer});
  @override State<ImageEnhancementSheet> createState() => _ImageEnhancementSheetState();
}
class _ImageEnhancementSheetState extends State<ImageEnhancementSheet> {
  late ImageEnhancementSettings _draft = widget.enhancer.settings;
  Future<void> _apply(ImageEnhancementSettings next) async {
    await widget.enhancer.apply(next);
    if (mounted) setState(() => _draft = widget.enhancer.settings);
  }
  Widget _slider(String title, double value, ImageEnhancementSettings Function(double) update) => Column(children: [
    Row(children: [Expanded(child: Text(title)), Text(value.round().toString())]),
    Slider(value: value, min: -50, max: 50, divisions: 100,
      onChanged: widget.enhancer.busy ? null : (v) => setState(() => _draft = update(v)),
      onChangeEnd: widget.enhancer.busy ? null : (v) => _apply(update(v))),
  ]);
  @override Widget build(BuildContext context) => ListenableBuilder(listenable: widget.enhancer, builder: (context, _) {
    final enhancer = widget.enhancer, theme = Theme.of(context), colors = Theme.of(context).colorScheme;
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(24, 0, 12, 8), child: Row(children: [
        Expanded(child: Text('超分与画质', style: theme.textTheme.headlineSmall)),
        IconButton(tooltip: '关闭', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
      ])),
      if (enhancer.busy) const LinearProgressIndicator(),
      Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: [
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(
          color: colors.primaryContainer.withValues(alpha: .4), borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(enhancer.settings.mode.label, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6), Text(enhancer.error ?? enhancer.status,
              style: theme.textTheme.bodySmall?.copyWith(color: enhancer.error == null ? colors.onSurfaceVariant : colors.error)),
          ])),
        const SizedBox(height: 20),
        Text('放大低分辨率视频', style: theme.textTheme.titleSmall), const SizedBox(height: 8),
        for (final mode in UpscaleMode.values) Card(elevation: 0, margin: const EdgeInsets.only(bottom: 8),
          color: enhancer.settings.mode == mode ? colors.secondaryContainer : colors.surfaceContainerLow,
          child: ListTile(leading: Icon(enhancer.settings.mode == mode ? Icons.radio_button_checked : Icons.radio_button_unchecked),
            title: Text(mode.label), subtitle: Text(mode.description),
            onTap: enhancer.busy ? null : () => _apply(_draft.copyWith(mode: mode)))),
        Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(
          'FSR 1.0 使用空间超分与锐化，最多放大至原尺寸的 2 倍。原视频已达输出上限时不放大。HDR / RGB 视频使用高清缩放。若发热或卡顿，请切回原始画质。',
          style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant))),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('去色带'), subtitle: const Text('减轻天空、暗部渐变中的色阶条纹'),
          value: enhancer.settings.deband, onChanged: enhancer.busy ? null : (v) => _apply(_draft.copyWith(deband: v))),
        const Divider(height: 32), Text('色彩调节', style: theme.textTheme.titleSmall), const SizedBox(height: 16),
        _slider('亮度', _draft.brightness, (v) => _draft.copyWith(brightness: v)),
        _slider('对比度', _draft.contrast, (v) => _draft.copyWith(contrast: v)),
        _slider('饱和度', _draft.saturation, (v) => _draft.copyWith(saturation: v)),
        _slider('伽马', _draft.gamma, (v) => _draft.copyWith(gamma: v)),
        const SizedBox(height: 12), OutlinedButton.icon(onPressed: enhancer.busy ? null : () => _apply(const ImageEnhancementSettings()),
          icon: const Icon(Icons.restart_alt), label: const Text('恢复全部默认画质')),
        const SizedBox(height: 12), Text('设置会用于之后的视频。系统画中画使用独立播放器，不应用这些效果。',
          style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
      ])),
    ]);
  });
}
