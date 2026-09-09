import 'package:flutter/material.dart';
import '../services/media_server_query.dart';

class MediaServerFilterDialog extends StatefulWidget {
  final MediaServerQuery initial;
  const MediaServerFilterDialog({super.key, required this.initial});
  @override
  State<MediaServerFilterDialog> createState() =>
      _MediaServerFilterDialogState();
}

class _MediaServerFilterDialogState extends State<MediaServerFilterDialog> {
  late var type = widget.initial.type;
  late var watched = widget.initial.watched;
  late var sort = widget.initial.sort;
  late var favorites = widget.initial.favorites;
  late var descending = widget.initial.descending;
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('筛选与排序'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<MediaServerTypeFilter>(
              initialValue: type,
              decoration: const InputDecoration(labelText: '媒体类型'),
              items: MediaServerTypeFilter.values
                  .map((value) => DropdownMenuItem(
                      value: value,
                      child: Text(MediaServerQuery.typeLabel(value))))
                  .toList(),
              onChanged: (value) => setState(() => type = value!)),
          DropdownButtonFormField<MediaServerWatchFilter>(
              initialValue: watched,
              decoration: const InputDecoration(labelText: '观看状态'),
              items: MediaServerWatchFilter.values
                  .map((value) => DropdownMenuItem(
                      value: value,
                      child: Text(MediaServerQuery.watchLabel(value))))
                  .toList(),
              onChanged: (value) => setState(() => watched = value!)),
          DropdownButtonFormField<MediaServerSort>(
              initialValue: sort,
              decoration: const InputDecoration(labelText: '排序方式'),
              items: MediaServerSort.values
                  .map((value) => DropdownMenuItem(
                      value: value,
                      child: Text(MediaServerQuery.sortLabel(value))))
                  .toList(),
              onChanged: (value) => setState(() {
                    sort = value!;
                    descending = sort != MediaServerSort.name;
                  })),
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('只看收藏'),
              value: favorites,
              onChanged: (value) => setState(() => favorites = value!)),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(descending ? '降序排列' : '升序排列'),
              value: descending,
              onChanged: (value) => setState(() => descending = value)),
        ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, const MediaServerQuery()),
              child: const Text('重置')),
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(
                  context,
                  MediaServerQuery(
                      type: type,
                      watched: watched,
                      sort: sort,
                      favorites: favorites,
                      descending: descending)),
              child: const Text('应用')),
        ],
      );
}
