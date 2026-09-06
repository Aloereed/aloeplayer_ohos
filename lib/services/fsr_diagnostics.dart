import 'dart:convert';

/// Optional diagnostics capability, separate from the rendering control API.
abstract interface class FsrDiagnosticsBackend {
  Future<Map<String, Object?>> fsrSnapshot();
}

/// Absence of introspection is not evidence that a shader failed.
Map<String, Object?> summarizeFsrPasses(Object? raw) {
  if (raw is! Map) return {'passEvidence': 'unavailable'};
  final passes = <Map<String, Object?>>[];
  final observed = <String>{};
  final listed = <String>{};
  for (final type in ['fresh', 'redraw']) {
    final frames = raw[type];
    if (frames is! List) continue;
    for (final pass in frames.take(64)) {
      if (pass is! Map) continue;
      final desc = pass['desc'];
      if (desc is! String || !desc.contains('FidelityFX Super Resolution')) continue;
      for (final stage in ['EASU', 'RCAS']) {
        if (!desc.contains(stage)) continue;
        listed.add(stage);
        num? number(String key) => pass[key] is num ? pass[key] as num : null;
        final samples = number('count'), last = number('last');
        if ((samples ?? 0) > 0 && (last ?? 0) > 0) observed.add(stage);
        passes.add({'frameType': type, 'stage': stage, 'samples': samples,
          'lastNs': last, 'avgNs': number('avg'), 'peakNs': number('peak')});
      }
    }
  }
  return {
    'passEvidence': observed.length == 2 ? 'easu_rcas_timed' : listed.length == 2
        ? 'easu_rcas_listed_no_complete_timing' : listed.isNotEmpty ? 'partial' : 'not_observed',
    'passes': passes,
  };
}

/// Report the active Anime4K chain without dumping every convolution's samples.
Map<String, Object?> summarizeAnime4kPasses(Object? raw) {
  if (raw is! Map) return {'anime4kEvidence': 'unavailable'};
  final groups = <String, Map<String, num>>{};
  var restoreOutputTimed = false, upscaleOutputTimed = false;
  for (final type in ['fresh', 'redraw']) {
    final frames = raw[type];
    if (frames is! List) continue;
    for (final pass in frames.take(64)) {
      if (pass is! Map) continue;
      final desc = pass['desc'];
      if (desc is! String || !desc.contains('Anime4K-')) continue;
      final group = desc.contains('Restore-CNN') ? 'restore'
          : desc.contains('Upscale-CNN') ? 'upscale'
          : desc.contains('AutoDownscale') ? 'downscale' : 'clamp';
      final last = pass['last'] is num ? pass['last'] as num : 0;
      final samples = pass['count'] is num ? pass['count'] as num : 0;
      final timed = last > 0 && samples > 0;
      final entry = groups.putIfAbsent(group, () => {'passes': 0, 'timedPasses': 0, 'lastNs': 0});
      entry['passes'] = entry['passes']! + 1;
      if (timed) {
        entry['timedPasses'] = entry['timedPasses']! + 1;
        entry['lastNs'] = entry['lastNs']! + last;
        if (desc.contains('Restore-CNN-(M)-Conv-3x1x1x56')) restoreOutputTimed = true;
        if (desc.contains('Upscale-CNN-x2-(M)-Depth-to-Space')) upscaleOutputTimed = true;
      }
    }
  }
  return {
    'anime4kEvidence': restoreOutputTimed && upscaleOutputTimed ? 'restore_upscale_timed'
        : groups.isEmpty ? 'not_observed' : 'partial_or_untimed',
    'anime4kPassGroups': groups,
  };
}

void writeFsrDiagnostic(String event, Map<String, Object?> data) {
  final tag = data['algorithm'] == 'anime4k' ? 'AloeAnime4K' : 'AloeFSR';
  // Release-visible SDK diagnostics are intentional.
  // ignore: avoid_print
  print('[$tag] ${jsonEncode({'event': event, ...data})}');
}
