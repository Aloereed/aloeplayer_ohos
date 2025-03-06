/*
 * @Author: 
 * @Date: 2025-02-09 17:55:36
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-03-06 14:21:14
 * @Description: file content
 */
import 'dart:ui';

import 'package:aloeplayer/chewie-1.8.5/lib/src/models/option_item.dart';
import 'package:flutter/material.dart';

class OptionsDialog extends StatefulWidget {
  const OptionsDialog({
    super.key,
    required this.options,
    this.cancelButtonText,
  });

  final List<OptionItem> options;
  final String? cancelButtonText;

  @override
  // ignore: library_private_types_in_public_api
  _OptionsDialogState createState() => _OptionsDialogState();
}

class _OptionsDialogState extends State<OptionsDialog> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.0), // 圆角效果
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0), // 高斯模糊效果
          child: Container(
            color: Theme.of(context).brightness == Brightness.light
                ? Colors.white.withOpacity(0.5) // 亮色模式：白色半透明
                : Colors.black.withOpacity(0.5), // 暗色模式：黑色半透明
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.options.length,
                  itemBuilder: (context, i) {
                    return ListTile(
                      onTap: widget.options[i].onTap,
                      leading: Icon(widget.options[i].iconData),
                      title: Text(widget.options[i].title),
                      subtitle: widget.options[i].subtitle != null
                          ? Text(widget.options[i].subtitle!)
                          : null,
                    );
                  },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(
                    thickness: 1.0,
                  ),
                ),
                ListTile(
                  onTap: () => Navigator.pop(context),
                  leading: const Icon(Icons.close),
                  title: Text(
                    widget.cancelButtonText ?? 'Cancel',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
