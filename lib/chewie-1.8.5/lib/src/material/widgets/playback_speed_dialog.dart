import 'dart:ui';
import 'package:flutter/material.dart';

class PlaybackSpeedDialog extends StatelessWidget {
  const PlaybackSpeedDialog({
    super.key,
    required List<double> speeds,
    required double selected,
    this.title = '播放速率',
  })  : _speeds = speeds,
        _selected = selected;

  final List<double> _speeds;
  final double _selected;
  final String title;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color selectedColor = Theme.of(context).primaryColor;
    
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
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.5,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const BouncingScrollPhysics(),
                      itemBuilder: (context, index) {
                        final speed = _speeds[index];
                        final isSelected = speed == _selected;
                        return Column(
                          children: [
                            InkWell(
                              onTap: () {
                                Navigator.of(context).pop(speed);
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12.0,
                                  horizontal: 24.0,
                                ),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                  vertical: 2.0,
                                ),
                                decoration: isSelected
                                    ? BoxDecoration(
                                        color: selectedColor.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(10),
                                      )
                                    : null,
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 32.0,
                                      child: isSelected
                                          ? Icon(
                                              Icons.check_circle_rounded,
                                              size: 22.0,
                                              color: selectedColor,
                                            )
                                          : Container(),
                                    ),
                                    const SizedBox(width: 16.0),
                                    Text(
                                      _getSpeedText(speed),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                        color: isSelected
                                            ? selectedColor
                                            : (isDarkMode
                                                ? Colors.white
                                                : Colors.black87),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (index < _speeds.length - 1)
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
                        );
                      },
                      itemCount: _speeds.length,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Divider(
                      height: 1,
                      thickness: 0.5,
                      color: isDarkMode
                          ? Colors.white.withOpacity(0.2)
                          : Colors.black.withOpacity(0.1),
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        '取消',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: isDarkMode ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Format speed text to look nicer (e.g. "1.0x" instead of "1.0")
  String _getSpeedText(double speed) {
    String speedText = speed.toString();
    // If it's a whole number like 1.0, convert to "1.0x"
    if (speed == speed.roundToDouble() && speedText.endsWith('.0')) {
      speedText = '${speed.toStringAsFixed(1)}x';
    } else {
      // Otherwise format as "1.5x"
      speedText = '${speed}x';
    }
    
    // Optional: Special case for normal speed
    if (speed == 1.0) {
      speedText = '正常 (1.0x)';
    }
    
    return speedText;
  }
}