import 'member_badge.dart';
import 'package:flutter/material.dart';
import '../services/file_service.dart';

Future<List<FileItem>?> selectBatchDownloads(BuildContext context, List<FileItem> files) =>
  showModalBottomSheet<List<FileItem>>(context: context, isScrollControlled: true,
    showDragHandle: true, useSafeArea: true, constraints: const BoxConstraints(maxWidth: 620),
    builder: (_) => _BatchDownloads(files: files));

class _BatchDownloads extends StatefulWidget {
  final List<FileItem> files;
  const _BatchDownloads({required this.files});
  @override State<_BatchDownloads> createState() => _BatchDownloadsState();
}
class _BatchDownloadsState extends State<_BatchDownloads> {
  final Set<String> _selected = {};
  @override Widget build(BuildContext context) => FractionallySizedBox(heightFactor: .8,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: MemberFeatureLabel('批量下载', style: Theme.of(context).textTheme.titleLarge)),
      const Padding(padding: EdgeInsets.fromLTRB(24, 8, 24, 8), child: Text('选择当前列表中的文件，每批最多 100 个。加入后按顺序下载，后台运行取决于系统授权。')),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
        TextButton(onPressed: () => setState(() { _selected.clear(); _selected.addAll(widget.files.take(100).map((f) => f.path)); }), child: Text(widget.files.length > 100 ? '选择前 100 个' : '全选')),
        TextButton(onPressed: () => setState(_selected.clear), child: const Text('清空选择')),
        Text('已选 ${_selected.length} 个'),
      ])),
      Expanded(child: ListView.builder(itemCount: widget.files.length, itemBuilder: (_, index) {
        final file = widget.files[index];
        return CheckboxListTile(title: Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          value: _selected.contains(file.path), onChanged: !_selected.contains(file.path) && _selected.length >= 100 ? null : (checked) => setState(() {
            if (checked == true) { _selected.add(file.path); } else { _selected.remove(file.path); }
          }));
      })),
      SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(16), child: FilledButton(
        onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, widget.files.where((f) => _selected.contains(f.path)).toList()),
        child: Text('加入下载队列（${_selected.length}）')))),
    ]));
}
