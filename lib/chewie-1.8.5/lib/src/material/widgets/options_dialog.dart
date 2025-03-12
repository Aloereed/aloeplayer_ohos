/*
 * @Author: 
 * @Date: 2025-02-09 17:55:36
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-03-12 14:14:11
 * @Description: Elegant options dialog with blur effect
 */
import 'dart:ui';
import 'package:aloeplayer/chewie-1.8.5/lib/src/models/option_item.dart';
import 'package:flutter/material.dart';

class OptionsDialog extends StatefulWidget {
  const OptionsDialog({
    super.key,
    required this.options,
    this.cancelButtonText,
    this.title,
  });

  final List<OptionItem> options;
  final String? cancelButtonText;
  final String? title;

  @override
  State<OptionsDialog> createState() => _OptionsDialogState();
}

class _OptionsDialogState extends State<OptionsDialog> {
  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20.0),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
            child: Container(
              decoration: BoxDecoration(
                color: isDarkMode
                    ? Colors.grey[900]!.withOpacity(0.7)
                    : Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(20.0),
                border: Border.all(
                  color: isDarkMode
                      ? Colors.white.withOpacity(0.1)
                      : Colors.black.withOpacity(0.1),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDarkMode
                        ? Colors.black.withOpacity(0.3)
                        : Colors.grey.withOpacity(0.2),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.title != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                      child: Text(
                        widget.title!,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.6,
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          widget.options.length,
                          (i) => Column(
                            children: [
                              ListTile(
                                onTap: widget.options[i].onTap,
                                leading: Icon(
                                  widget.options[i].iconData,
                                  color: isDarkMode ? Colors.white70 : Colors.black87,
                                ),
                                title: Text(
                                  widget.options[i].title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: isDarkMode ? Colors.white : Colors.black87,
                                  ),
                                ),
                                subtitle: widget.options[i].subtitle != null
                                    ? Text(
                                        widget.options[i].subtitle!,
                                        style: TextStyle(
                                          color: isDarkMode
                                              ? Colors.white60
                                              : Colors.black54,
                                        ),
                                      )
                                    : null,
                                dense: false,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                  vertical: 4.0,
                                ),
                              ),
                              if (i < widget.options.length - 1)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                                  child: Divider(
                                    height: 1,
                                    thickness: 0.5,
                                    color: isDarkMode
                                        ? Colors.white.withOpacity(0.1)
                                        : Colors.black.withOpacity(0.05),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Divider(
                      height: 1,
                      thickness: 0.5,
                      color: isDarkMode
                          ? Colors.white.withOpacity(0.2)
                          : Colors.black.withOpacity(0.1),
                    ),
                  ),
                  ListTile(
                    onTap: () => Navigator.pop(context),
                    leading: Icon(
                      Icons.close,
                      color: isDarkMode ? Colors.white70 : Colors.black87,
                    ),
                    title: Text(
                      widget.cancelButtonText ?? 'Cancel',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 4.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}