enum DownloadStatus { queued, downloading, paused, completed, failed, canceled }

class DownloadTask {
  final String id;
  final String serverId;
  final String remotePath;
  final String name;
  final String destination;
  final int size;
  final int? modifiedMs;
  int received;
  DownloadStatus status;
  String? error;
  DownloadTask({required this.id, required this.serverId, required this.remotePath, required this.name, required this.destination,
    required this.size, this.modifiedMs, this.received = 0, this.status = DownloadStatus.queued, this.error});
  String get partialPath => '$destination.aloe-part-$id';
  Map<String, dynamic> toJson() => {'id': id, 'serverId': serverId, 'remotePath': remotePath, 'name': name, 'destination': destination,
    'size': size, 'modifiedMs': modifiedMs, 'received': received, 'status': status.name, 'error': error};
  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    var status = DownloadStatus.values.firstWhere((s) => s.name == json['status'], orElse: () => DownloadStatus.paused);
    // A killed process cannot leave a task pretending to be downloading.
    if (status == DownloadStatus.downloading || status == DownloadStatus.queued) status = DownloadStatus.paused;
    return DownloadTask(id: json['id'] as String, serverId: json['serverId'] as String, remotePath: json['remotePath'] as String,
      name: json['name'] as String, destination: json['destination'] as String, size: json['size'] as int,
      modifiedMs: json['modifiedMs'] as int?, received: json['received'] as int? ?? 0, status: status, error: json['error'] as String?);
  }
}
