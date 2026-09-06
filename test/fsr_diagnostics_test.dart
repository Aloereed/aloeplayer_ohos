import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aloeplayer/services/fsr_diagnostics.dart';
import 'package:aloeplayer/services/member_access.dart';
import 'package:aloeplayer/services/mpv_image_enhancement.dart';
import 'mpv_image_enhancement_test.dart' show FakeImageBackend;

class DiagnosticBackend extends FakeImageBackend implements FsrDiagnosticsBackend {
  int probes = 0;
  Completer<Map<String, Object?>>? pending;
  bool fail = false;
  @override Future<Map<String, Object?>> fsrSnapshot() async {
    probes++;
    if (fail) throw StateError('unsupported');
    return pending?.future ?? Future.value({'passEvidence': 'unavailable'});
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('only both FSR stages with samples and timings count as timed evidence', () {
    Map<String, Object> pass(String name, int last) => {'desc': 'FidelityFX Super Resolution v1.0.2 ($name)', 'last': last, 'count': 4};
    expect(summarizeFsrPasses(null)['passEvidence'], 'unavailable');
    expect(summarizeFsrPasses({'fresh': []})['passEvidence'], 'not_observed');
    expect(summarizeFsrPasses({'fresh': [pass('EASU', 120)]})['passEvidence'], 'partial');
    expect(summarizeFsrPasses({'fresh': [pass('EASU', 120), pass('RCAS', 0)]})['passEvidence'], 'easu_rcas_listed_no_complete_timing');
    expect(summarizeFsrPasses({'fresh': [pass('EASU', 120), pass('RCAS', 90)]})['passEvidence'], 'easu_rcas_timed');
  });
  testWidgets('HDR bypass and renderer failures are recorded without shader paths', (tester) async {
    final events = <Map<String, Object?>>[];
    final backend = FakeImageBackend();
    final engine = MpvImageEnhancer(backend: backend, access: MemberAccess(paid: () => true),
      diagnosticLog: (event, data) => events.add({'event': event, ...data}));
    engine.videoChanged(width: 1280, height: 720, gamma: 'pq');
    await engine.apply(const ImageEnhancementSettings(mode: UpscaleMode.fsr1080));
    expect(events.where((e) => e['event'] == 'render_plan').single['reason'], 'hdr_bypass');
    expect(events.where((e) => e['event'] == 'shader_asset_ready'), isEmpty);
    backend.reject = 'deband';
    await engine.apply(const ImageEnhancementSettings(deband: true));
    expect(events.any((e) => e['event'] == 'property_rejected' && e['property'] == 'deband'), isTrue);
    expect(events.any((e) => e['event'] == 'apply_failed'), isTrue);
    expect(engine.settings.isDefault, isTrue);
    engine.dispose();
  });
  testWidgets('stale probes are discarded, unsupported probes do not alter rendering, disposal cancels timers', (tester) async {
    final events = <Map<String, Object?>>[];
    final backend = DiagnosticBackend();
    final engine = MpvImageEnhancer(backend: backend, access: MemberAccess(paid: () => true),
      diagnosticLog: (event, data) => events.add({'event': event, ...data}));
    await engine.initialize();
    backend.pending = Completer<Map<String, Object?>>();
    final probe = engine.captureDiagnostics('stale');
    await engine.apply(const ImageEnhancementSettings(mode: UpscaleMode.highQuality));
    backend.pending!.complete({'passEvidence': 'easu_rcas_timed'});
    await probe;
    expect(events.any((e) => e['reason'] == 'stale'), isFalse);
    backend.pending = null;
    backend.fail = true;
    await engine.captureDiagnostics('unsupported');
    expect(events.last['passEvidence'], 'unavailable');
    expect(engine.settings.mode, UpscaleMode.highQuality);
    final count = backend.probes;
    engine.dispose();
    await tester.pump(const Duration(seconds: 5));
    expect(backend.probes, count);
  });
}
