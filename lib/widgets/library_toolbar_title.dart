import 'package:flutter/material.dart';

/// A single-row title that gives its space to search when requested.
class LibraryToolbarTitle extends StatelessWidget {
  final String title, hint;
  final bool searching;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<bool> onSearchChanged;

  const LibraryToolbarTitle({super.key, required this.title, required this.hint,
    required this.searching, required this.controller, this.focusNode,
    required this.onChanged, required this.onSearchChanged});

  @override
  Widget build(BuildContext context) {
    if (!searching) {
      return Row(children: [
        Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
        IconButton(tooltip: '搜索', onPressed: () => onSearchChanged(true),
          icon: const Icon(Icons.search_rounded)),
      ]);
    }
    return TextField(controller: controller, focusNode: focusNode, autofocus: true,
      onChanged: onChanged, textInputAction: TextInputAction.search,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(hintText: hint, isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        suffixIcon: IconButton(tooltip: '关闭搜索', onPressed: () {
          controller.clear();
          onChanged('');
          onSearchChanged(false);
        }, icon: const Icon(Icons.close_rounded))));
  }
}
