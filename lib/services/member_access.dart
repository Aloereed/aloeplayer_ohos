import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'membership_service.dart';
import 'serial_executor.dart';

enum MemberFeature { imageQuality, multipleSources, batchDownload }

extension MemberFeatureDescription on MemberFeature {
  String get title => switch (this) {
    MemberFeature.imageQuality => '高级画质',
    MemberFeature.multipleSources => '更多媒体来源',
    MemberFeature.batchDownload => '批量离线下载',
  };
  String get description => switch (this) {
    MemberFeature.imageQuality => '使用 Anime4K 动漫超分、FSR 高画质、去色带和画质预设。原始画质、高清缩放、FSR 均衡和手动色彩调节免费使用。',
    MemberFeature.multipleSources => 'SMB 和 WebDAV 不限数量。免费版可分别添加 1 个 Jellyfin 和 1 个 Emby，会员可添加更多；已有来源继续保留。',
    MemberFeature.batchDownload => '在 SMB 或 WebDAV 文件夹中选择多个文件，一次加入下载队列。单文件下载、断点续传和后台下载继续免费。',
  };
}

class MemberAccessRequired implements Exception {
  final MemberFeature feature;
  const MemberAccessRequired(this.feature);
  @override String toString() => '${feature.title}需要会员或免费体验';
}

/// Local, voluntary product trial. It never creates a store subscription.
/// Paid access still derives from the existing server-verified membership.
class MemberAccess extends ChangeNotifier {
  static final instance = MemberAccess();
  static final sourceWrites = SerialExecutor();
  static const _key = 'member.access.v1';
  final DateTime Function() now;
  final bool Function() paid;
  final SerialExecutor _writes = SerialExecutor();
  MemberAccess({DateTime Function()? now, bool Function()? paid})
      : now = now ?? DateTime.now,
        paid = paid ?? (() {
          final member = MembershipService();
          return member.isPremium && member.expiryDate != null && member.expiryDate!.isAfter(DateTime.now());
        });
  Future<void>? _initializing;
  bool initialized = false;
  DateTime? _trialStarted;
  bool legacyFsr4k = false, legacyDeband = false;
  bool get canStartTrial => _trialStarted == null && !paid();
  DateTime? get trialEnds => _trialStarted?.add(const Duration(days: 7));
  bool get trialActive => _trialStarted != null && !now().isBefore(_trialStarted!) && now().isBefore(trialEnds!);
  bool get unlocked => paid() || trialActive;

  Future<void> initialize() => _initializing ??= _load().then((_) { initialized = true; }).catchError((Object error, StackTrace stack) {
    _initializing = null;
    Error.throwWithStackTrace(error, stack);
  });
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _trialStarted = DateTime.tryParse(data['trialStarted'] as String? ?? '');
      legacyFsr4k = data['legacyFsr4k'] == true;
      legacyDeband = data['legacyDeband'] == true;
      return;
    }
    final oldImage = prefs.getString('mpv.image-enhancement.v1');
    if (oldImage != null) {
      try {
        final image = jsonDecode(oldImage) as Map<String, dynamic>;
        legacyFsr4k = image['mode'] == 'fsr4k';
        legacyDeband = image['deband'] == true;
      } catch (_) { /* Invalid old settings grant no additional access. */ }
    }
    await _save();
  }
  Future<void> _save() async {
    final ok = await (await SharedPreferences.getInstance()).setString(_key, jsonEncode({
      'trialStarted': _trialStarted?.toIso8601String(),
      'legacyFsr4k': legacyFsr4k, 'legacyDeband': legacyDeband,
    }));
    if (!ok) throw StateError('无法保存体验状态，请稍后重试');
  }
  Future<bool> startTrial() => _writes.run(() async {
    await initialize();
    if (!canStartTrial) return unlocked;
    _trialStarted = now();
    try { await _save(); } catch (_) { _trialStarted = null; rethrow; }
    notifyListeners();
    return true;
  });
  Future<void> require(MemberFeature feature) async {
    await initialize();
    if (!unlocked) throw MemberAccessRequired(feature);
  }
  Future<bool> canAddSource({required String kind, String? existingId}) async {
    final protocol = kind.toLowerCase();
    if (protocol == 'smb' || protocol == 'webdav') return true;
    if (protocol != 'emby' && protocol != 'jellyfin') throw ArgumentError.value(kind, 'kind');
    await initialize();
    if (unlocked) return true;
    final prefs = await SharedPreferences.getInstance();
    final rows = jsonDecode(prefs.getString('media-server.connections') ?? '[]') as List;
    bool sameKind(dynamic row) => (row['kind'] as String? ?? '').toLowerCase() == protocol;
    // Existing connections can be edited even when grandfathered over quota.
    // Changing protocol must pass the destination protocol's quota.
    if (existingId != null && rows.any((row) => row['id'] == existingId && sameKind(row))) return true;
    return !rows.any((row) => sameKind(row));
  }
  Future<void> requireNewSource({required String kind, String? existingId}) async {
    if (!await canAddSource(kind: kind, existingId: existingId)) {
      throw const MemberAccessRequired(MemberFeature.multipleSources);
    }
  }
}
