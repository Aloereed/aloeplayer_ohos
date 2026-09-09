import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/playback_media.dart';
import 'media_server_client.dart';
import 'media_server_catalog.dart';
import 'serial_executor.dart';

class MediaServerSyncResult {
  final int sent, superseded, pending;
  const MediaServerSyncResult(this.sent, this.superseded, this.pending);
}

/// Durable latest-position outbox. Contains identities and progress, never tokens.
class MediaServerProgressStore {
  static final instance = MediaServerProgressStore();
  static const storageKey = 'media-server.offline-progress.v1';
  static final _writes = SerialExecutor();
  final _running = <String, Future<MediaServerSyncResult>>{};
  String _account(MediaServerConnection c) => sha256
      .convert(utf8.encode(
          '${c.id}\n${c.userId}\n${MediaServerConnection.normalizeUrl(c.url)}'))
      .toString();

  Future<List<Map<String, dynamic>>> _read() async {
    final raw = (await SharedPreferences.getInstance()).getString(storageKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> _save(List<Map<String, dynamic>> rows) async {
    if (!await (await SharedPreferences.getInstance())
        .setString(storageKey, jsonEncode(rows))) {
      throw StateError('无法保存离线观看进度');
    }
  }

  Future<void> record(
      MediaServerConnection connection, PlaybackMedia media, int positionMs,
      {DateTime? observed}) {
    final uri = Uri.tryParse(media.id);
    if (uri?.scheme != 'aloe-server' ||
        uri!.host != connection.id ||
        uri.pathSegments.length != 1 ||
        positionMs <= 0) return Future.value();
    final row = <String, dynamic>{
      'account': _account(connection),
      'item': uri.pathSegments.single,
      'position': positionMs.clamp(0, 900719925474),
      'observed': (observed ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
      'revision': const Uuid().v4()
    };
    return _writes.run(() async {
      final rows = await _read();
      final previous = rows
          .where(
              (r) => r['account'] == row['account'] && r['item'] == row['item'])
          .firstOrNull;
      if (previous != null &&
          (previous['observed'] as int) > (row['observed'] as int)) return;
      rows.removeWhere(
          (r) => r['account'] == row['account'] && r['item'] == row['item']);
      rows.add(row);
      await _save(rows);
    });
  }

  Future<void> acknowledge(MediaServerConnection connection,
          PlaybackMedia media, DateTime observed) =>
      _writes.run(() async {
        final uri = Uri.tryParse(media.id);
        if (uri?.scheme != 'aloe-server' ||
            uri!.host != connection.id ||
            uri.pathSegments.length != 1) return;
        final rows = await _read();
        final count = rows.length;
        final account = _account(connection);
        rows.removeWhere((row) =>
            row['account'] == account &&
            row['item'] == uri.pathSegments.single &&
            (row['observed'] as int) <= observed.millisecondsSinceEpoch);
        if (rows.length != count) await _save(rows);
      });

  Future<MediaServerSyncResult> sync(MediaServerClient client) {
    final account = _account(client.connection);
    return _running[account] ??= _sync(client, account).whenComplete(() {
      _running.remove(account);
    });
  }

  Future<void> syncConnection(MediaServerConnection connection) async {
    final client = MediaServerClient(connection);
    try {
      await sync(client);
    } finally {
      await client.close();
    }
  }

  Future<MediaServerSyncResult> _sync(
      MediaServerClient client, String account) async {
    final rows = await _writes.run(_read).timeout(const Duration(seconds: 3));
    var sent = 0, superseded = 0;
    final cancel = CancelToken();
    final deadline = Timer(const Duration(seconds: 12),
        () => cancel.cancel('Offline sync deadline'));
    try {
      for (final row in rows.where((r) => r['account'] == account)) {
        try {
          final applied = await client.syncOfflineProgress(
              row['item'] as String,
              row['position'] as int,
              DateTime.fromMillisecondsSinceEpoch(row['observed'] as int,
                  isUtc: true),
              actionId: row['revision'] as String,
              cancelToken: cancel);
          await _writes.run(() async {
            final latest = await _read();
            latest.removeWhere((r) => r['revision'] == row['revision']);
            await _save(latest);
          });
          if (applied) {
            sent++;
          } else {
            superseded++;
          }
        } catch (error) {
          // Keep failed and unsent entries for the next connection; never spin offline.
          if (error is DioException && error.response?.statusCode == 404)
            continue;
          break;
        }
      }
    } finally {
      deadline.cancel();
    }
    final remaining = await _writes.run(_read);
    return MediaServerSyncResult(sent, superseded,
        remaining.where((r) => r['account'] == account).length);
  }
}
