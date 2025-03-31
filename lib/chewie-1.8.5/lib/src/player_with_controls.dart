import 'dart:async';
import 'dart:ui';

import 'package:aloeplayer/chewie-1.8.5/lib/src/chewie_player.dart';
import 'package:aloeplayer/chewie-1.8.5/lib/src/helpers/adaptive_controls.dart';
import 'package:aloeplayer/chewie-1.8.5/lib/src/notifiers/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:video_player/video_player.dart';
import 'package:screen/screen.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';

// Custom class for the brightness slider timer
class BrightnessSliderTimer {
  Timer? _timer;
  final VoidCallback onTimeout;

  BrightnessSliderTimer({required this.onTimeout});

  void start() {
    cancel();
    _timer = Timer(Duration(seconds: 3), onTimeout);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

class BrightnessSlider extends StatefulWidget {
  final ValueChanged<double>? onBrightnessChanged;

  const BrightnessSlider({Key? key, this.onBrightnessChanged})
      : super(key: key);

  @override
  _BrightnessSliderState createState() => _BrightnessSliderState();
}

class _BrightnessSliderState extends State<BrightnessSlider> {
  double _brightness = 0.5;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _initBrightness();
    // 创建定时器来定期检查亮度变化
    _pollingTimer = Timer.periodic(Duration(milliseconds: 50), (_) {
      _updateBrightness();
    });
  }

  void _initBrightness() async {
    try {
      final brightness = await Screen.brightness ?? 0.5;
      if (mounted) {
        setState(() {
          _brightness = brightness.clamp(0.0, 0.99);
        });
      }
    } catch (e) {
      print('初始化亮度时发生错误: $e');
    }
  }

  void _updateBrightness() async {
    try {
      final brightness = await Screen.brightness ?? 0.5;
      if (mounted && (brightness != _brightness)) {
        setState(() {
          _brightness = brightness.clamp(0.0, 0.99);
        });
      }
    } catch (e) {
      print('更新亮度时发生错误: $e');
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: _brightness,
      min: 0.0,
      max: 0.99, // 设为0.99以避免潜在的边界问题
      onChanged: (value) async {
        if (value != _brightness) {
          setState(() {
            _brightness = value;
          });

          try {
            await Screen.setBrightness(value);
            if (widget.onBrightnessChanged != null) {
              widget.onBrightnessChanged!(value);
            }
          } catch (e) {
            print('设置亮度时发生错误: $e');
          }
        }
      },
    );
  }
}

// 倍速选择器小部件
class SpeedSelectorWidget extends StatelessWidget {
  final List<double> speeds;
  final double currentSpeed;

  const SpeedSelectorWidget({
    Key? key,
    required this.speeds,
    required this.currentSpeed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 主倍速选择器
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.65),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: speeds.map((speed) {
              bool isSelected = speed == currentSpeed;
              return Container(
                margin: EdgeInsets.symmetric(horizontal: 6),
                padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withOpacity(0.25)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: isSelected
                      ? Border.all(
                          color: Colors.white.withOpacity(0.5), width: 0.5)
                      : null,
                ),
                child: Text(
                  '${speed}x',
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withOpacity(0.8),
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // 提示文字
        SizedBox(height: 4),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            "长按时左右滑动更改倍速",
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              fontSize: 10,
              fontWeight: FontWeight.w300,
            ),
          ),
        ),
      ],
    );
  }
}

class PlayerWithControls extends StatefulWidget {
  @override
  _PlayerWithControlsState createState() => _PlayerWithControlsState();
}

class _PlayerWithControlsState extends State<PlayerWithControls> {
  // 在你的类中添加这些变量
  OverlayEntry? _speedSelectorOverlay;
  double _currentSelectedSpeed = 3.0;
  final List<double> _availableSpeeds = [1.5, 3.0];
  final Stream<double?> brightnessStream = _createBrightnessStream();
  bool showBrightnessSlider = false;
  int lastSelectedIndex = 1;
  // 累计滑动距离
  double cumulativeDx = 0;
  static Stream<double?> _createBrightnessStream() async* {
    while (true) {
      yield await Screen.brightness;
      await Future.delayed(Duration(milliseconds: 100)); // 每隔 1 秒更新一次
    }
  }

  BrightnessSliderTimer? _brightnessSliderTimer;
  @override
  void initState() {
    super.initState();
    _brightnessSliderTimer = BrightnessSliderTimer(
      onTimeout: () {
        setState(() {
          showBrightnessSlider = false;
        });
      },
    );
  }

  @override
  void dispose() {
    _brightnessSliderTimer?.cancel();
    super.dispose();
  }

  void _showBrightnessSlider() {
    setState(() {
      showBrightnessSlider = true;
    });
    _brightnessSliderTimer?.start();
  }

  @override
  Widget build(BuildContext context) {
    final ChewieController chewieController = ChewieController.of(context);

    double calculateAspectRatio(BuildContext context) {
      final size = MediaQuery.of(context).size;
      final width = size.width;
      final height = size.height;

      return width > height ? width / height : height / width;
    }

    Widget buildControls(
      BuildContext context,
      ChewieController chewieController,
    ) {
      return chewieController.showControls
          ? chewieController.customControls ?? const AdaptiveControls()
          : const SizedBox();
    }

// 隐藏倍速选择器
    void hideSpeedSelector() {
      if (_speedSelectorOverlay != null) {
        _speedSelectorOverlay!.remove();
        _speedSelectorOverlay = null;
      }
    }

// 显示倍速选择器
    void showSpeedSelector(BuildContext context, double initialSpeed) {
      _currentSelectedSpeed = initialSpeed;

      // 如果已经有一个overlay，先移除它
      hideSpeedSelector();

      _speedSelectorOverlay = OverlayEntry(builder: (context) {
        return Positioned(
          top: MediaQuery.of(context).size.height * 0.05, // 位置在顶部15%处
          width: MediaQuery.of(context).size.width,
          child: Center(
            child: SpeedSelectorWidget(
              speeds: _availableSpeeds,
              currentSpeed: _currentSelectedSpeed,
            ),
          ),
        );
      });

      Overlay.of(context).insert(_speedSelectorOverlay!);
    }

// 处理长按拖动选择倍速
    void handleSpeedSelectionDrag(LongPressMoveUpdateDetails details) {
      if (_speedSelectorOverlay == null) return;

      // 获取滑动距离
      double dx = details.localOffsetFromOrigin.dx;

      // 增加滑动阈值，使每次需要更大的滑动距离才能切换到下一个倍速
      double threshold = 500.0; // 调整此值可改变灵敏度

      // 累加滑动距离
      cumulativeDx += dx;

      // 计算应该移动的索引数
      int steps = (cumulativeDx / threshold).floor(); // 根据累计距离计算步数

      if (steps != 0) {
        cumulativeDx = 0; // 重置累计距离

        // 计算新的索引
        int currentIndex = _availableSpeeds.indexOf(_currentSelectedSpeed);
        int newIndex =
            (currentIndex + steps).clamp(0, _availableSpeeds.length - 1);

        // 如果索引发生变化
        if (newIndex != currentIndex) {
          _currentSelectedSpeed = _availableSpeeds[newIndex];
          // 更新播放速度
          chewieController.videoPlayerController
              .setPlaybackSpeed(_currentSelectedSpeed);
          // 添加触觉反馈
          HapticFeedback.selectionClick();
          // 更新UI
          _speedSelectorOverlay!.markNeedsBuild();
        }
      }
    }

    Widget buildPlayerWithControls(
      ChewieController chewieController,
      BuildContext context,
    ) {
      return Stack(
        children: <Widget>[
          if (chewieController.placeholder != null)
            chewieController.placeholder!,
          InteractiveViewer(
            transformationController: chewieController.transformationController,
            maxScale: chewieController.maxScale,
            panEnabled: chewieController.zoomAndPan,
            scaleEnabled: chewieController.zoomAndPan,
            child: Center(
              child: AspectRatio(
                aspectRatio: chewieController.aspectRatio ??
                    chewieController.videoPlayerController.value.aspectRatio,
                child: (chewieController.ffmpeg == 0 ||
                        chewieController.ffmpeg == 3)
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..translate(chewieController.position.dx,
                              chewieController.position.dy)
                          ..scale(
                            chewieController.scale *
                                (chewieController.isMirrored ? -1.0 : 1.0),
                            chewieController.scale,
                          ),
                        child:
                            VideoPlayer(chewieController.videoPlayerController))
                    : Container(color: Colors.transparent),
              ),
            ),
          ),
          if (chewieController.overlay != null) chewieController.overlay!,
          if (Theme.of(context).platform != TargetPlatform.iOS)
            Consumer<PlayerNotifier>(
              builder: (
                BuildContext context,
                PlayerNotifier notifier,
                Widget? widget,
              ) =>
                  Visibility(
                visible: !notifier.hideStuff,
                child: AnimatedOpacity(
                  opacity: notifier.hideStuff ? 0.0 : 0.8,
                  duration: const Duration(
                    milliseconds: 250,
                  ),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(color: Colors.transparent),
                    child: SizedBox.expand(),
                  ),
                ),
              ),
            ),
          if (!chewieController.isFullScreen)
            buildControls(context, chewieController)
          else
            SafeArea(
              bottom: false,
              child: buildControls(context, chewieController),
            ),
        ],
      );
    }

    return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
      return Center(
        child: SizedBox(
          height: constraints.maxHeight,
          width: constraints.maxWidth,
          child: AspectRatio(
              aspectRatio: calculateAspectRatio(context),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onScaleStart: chewieController.zoomAndPan
                    ? (ScaleStartDetails details) {
                        setState(() {
                          // 记录开始缩放
                          chewieController.isScaling = true;
                          // 记录初始缩放值
                          chewieController.initialScale =
                              chewieController.scale;
                          chewieController.initialPosition =
                              chewieController.position;
                        });
                      }
                    : null,
                onScaleUpdate: chewieController.zoomAndPan
                    ? (ScaleUpdateDetails details) {
                        if (details.pointerCount >= 1) {
                          setState(() {
                            // 确保只有在缩放模式下才执行缩放操作
                            if (details.scale != 1.0 ||
                                chewieController.isScaling) {
                              // 更新缩放比例
                              chewieController.scale =
                                  (chewieController.initialScale *
                                          details.scale)
                                      .clamp(chewieController.minScale,
                                          chewieController.maxScale);

                              // 计算新的位置偏移 - 只在双指操作或确认为缩放模式时更新位置
                              if (details.pointerCount >= 2 ||
                                  chewieController.isScaling) {
                                chewieController.position =
                                    chewieController.initialPosition +
                                        details.focalPointDelta;
                              }
                            }
                          });
                        }
                      }
                    : null,
                onScaleEnd: chewieController.zoomAndPan
                    ? (ScaleEndDetails details) {
                        setState(() {
                          // 缩放操作结束
                          chewieController.isScaling = false;
                        });
                      }
                    : null,

                // 长按相关手势
                onLongPress: () {
                  // 记录当前的播放速率
                  chewieController.previousPlaybackSpeed =
                      chewieController.playbackSpeed;
                  // 默认长按开始为3倍速
                  chewieController.videoPlayerController.setPlaybackSpeed(3.0);
                  // 显示倍速选择控件
                  showSpeedSelector(context, 3.0);
                  // 标记为长按模式
                  setState(() {
                    chewieController.isLongPressing = true;
                  });
                },
                onLongPressEnd: (_) {
                  // 松开恢复到长按之前的播放速率
                  chewieController.videoPlayerController
                      .setPlaybackSpeed(chewieController.previousPlaybackSpeed);
                  // 隐藏倍速选择控件
                  hideSpeedSelector();
                  // 结束长按模式
                  setState(() {
                    chewieController.isLongPressing = false;
                  });
                },
                onLongPressMoveUpdate: (details) {
                  // 处理长按时的左右滑动来选择倍速
                  if (chewieController.isLongPressing) {
                    handleSpeedSelectionDrag(details);
                  }
                },

                // 水平滑动相关
                onHorizontalDragStart: (_) {
                  // 标记正在水平滑动
                  setState(() {
                    chewieController.isHorizontalDragging = true;
                  });
                },
                onHorizontalDragUpdate: (details) {
                  // 只有在非缩放模式下才处理水平滑动
                  if (!chewieController.isScaling &&
                      chewieController.isHorizontalDragging) {
                    // 获取屏幕宽度
                    final double screenWidth =
                        MediaQuery.of(context).size.width;
                    // 计算右侧 20% 区域的起始位置
                    final double rightZoneStart = screenWidth * 0.8;
                    // 检测滑动是否从右侧 20% 区域开始
                    if (details.globalPosition.dx >= rightZoneStart) {
                      // 检测滑动方向是否是从右往左
                      if (details.delta.dx < 0) {
                        // 执行打开播放列表的逻辑
                        if (chewieController.openPlaylist != null)
                          chewieController.openPlaylist!();
                      } else {
                        // 计算滑动的距离
                        chewieController.swipeDistance += details.delta.dx;
                        // 根据滑动距离计算快进或快退的时间
                        final double sensitivity = 10.0; // 灵敏度，可以根据需要调整
                        final Duration seekDuration = Duration(
                            milliseconds:
                                (chewieController.swipeDistance / sensitivity)
                                        .round() *
                                    1000);
                        if (seekDuration.inMilliseconds != 0) {
                          chewieController.seekTo(chewieController
                                  .videoPlayerController.value.position +
                              seekDuration);
                          chewieController.swipeDistance = 0.0; // 重置滑动距离
                        }
                      }
                    } else {
                      // 计算滑动的距离
                      chewieController.swipeDistance += details.delta.dx;
                      // 根据滑动距离计算快进或快退的时间
                      final double sensitivity = 10.0; // 灵敏度，可以根据需要调整
                      final Duration seekDuration = Duration(
                          milliseconds:
                              (chewieController.swipeDistance / sensitivity)
                                      .round() *
                                  1000);
                      if (seekDuration.inMilliseconds != 0) {
                        chewieController.seekTo(chewieController
                                .videoPlayerController.value.position +
                            seekDuration);
                        chewieController.swipeDistance = 0.0; // 重置滑动距离
                      }
                    }
                  }
                },
                onHorizontalDragEnd: (details) {
                  // 滑动结束时重置滑动距离
                  chewieController.swipeDistance = 0.0;
                  // 结束水平滑动状态
                  setState(() {
                    chewieController.isHorizontalDragging = false;
                  });
                },

                // 双击相关
                onDoubleTapDown: (details) {
                  // 只有在非缩放和非滑动模式下才处理双击
                  if (!chewieController.isScaling &&
                      !chewieController.isHorizontalDragging &&
                      !chewieController.isVerticalDragging) {
                    // Get the width of the screen
                    final double screenWidth =
                        MediaQuery.of(context).size.width;
                    // Define a range for the middle part of the screen
                    final double middleRangeStart = screenWidth * 0.2;
                    final double middleRangeEnd = screenWidth * 0.8;
                    // Determine the position of the double tap
                    if (details.globalPosition.dx < middleRangeStart) {
                      // Left part of the screen: rewind 10 seconds
                      Fluttertoast.showToast(
                        msg: '快退10秒',
                        toastLength: Toast.LENGTH_SHORT,
                        gravity: ToastGravity.CENTER,
                        timeInSecForIosWeb: 1,
                        backgroundColor: Colors.red,
                        textColor: Colors.white,
                        fontSize: 16.0,
                      );
                      chewieController.seekTo(chewieController
                              .videoPlayerController.value.position -
                          Duration(seconds: 10));
                    } else if (details.globalPosition.dx > middleRangeEnd) {
                      // Right part of the screen: fast forward 10 seconds
                      Fluttertoast.showToast(
                        msg: '快进10秒',
                        toastLength: Toast.LENGTH_SHORT,
                        gravity: ToastGravity.CENTER,
                        timeInSecForIosWeb: 1,
                        backgroundColor: Colors.red,
                        textColor: Colors.white,
                        fontSize: 16.0,
                      );
                      chewieController.seekTo(chewieController
                              .videoPlayerController.value.position +
                          Duration(seconds: 10));
                    } else {
                      chewieController.togglePause();
                    }
                  }
                },

                // 垂直滑动相关
                onVerticalDragStart: (_) {
                  // 标记正在垂直滑动
                  setState(() {
                    chewieController.isVerticalDragging = true;
                  });
                },
                onVerticalDragUpdate: (details) async {
                  // 只有在非缩放模式下才处理垂直滑动
                  if (!chewieController.isScaling &&
                      chewieController.isVerticalDragging) {
                    // 获取滑动的起始位置
                    double screenWidth = MediaQuery.of(context).size.width;
                    double touchX = details.localPosition.dx;
                    // 判断滑动区域
                    if (touchX < screenWidth / 3) {
                      // 左侧 1/3 区域：调整亮度
                      double delta = details.primaryDelta ?? 0;
                      double _brightness = (await Screen.brightness) ?? 0.5;
                      if (delta < 0) {
                        // 上滑增加亮度
                        _brightness = (_brightness + 0.005).clamp(0.0, 0.99);
                      } else if (delta > 0) {
                        // 下滑减少亮度
                        _brightness = (_brightness - 0.005).clamp(0.0, 0.99);
                      }
                      // 设置亮度
                      Screen.setBrightness(_brightness);
                      // 显示亮度滑块
                      setState(() {
                        showBrightnessSlider = true;
                      });
                      // 启动计时器
                      _brightnessSliderTimer?.start();
                    } else if (touchX > (2 * screenWidth / 3)) {
                      // 右侧 1/3 区域：调整音量
                      double delta = details.primaryDelta ?? 0;
                      double _volume = 0.0;
                      if (delta < 0) {
                        // 上滑增加音量
                        _volume = 0.005;
                      } else if (delta > 0) {
                        // 下滑减少音量
                        _volume = -0.005;
                      }
                      // 设置音量
                      double nextVolume =
                          chewieController.setSystemVolume!(_volume);
                      // 显示音量滑块
                      setState(() {
                        chewieController.showVolumeSlider = true;
                      });
                    }
                  }
                },
                onVerticalDragEnd: (_) {
                  // 结束垂直滑动状态
                  setState(() {
                    chewieController.isVerticalDragging = false;
                  });
                },
                child: Stack(children: [
                  buildPlayerWithControls(chewieController, context),

                  // Then inside your build method:
                  if (showBrightnessSlider)
                    Positioned(
                      bottom: 100,
                      left: 20,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                          child: Container(
                            height: 200,
                            width: 40,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                                width: 0.5,
                              ),
                            ),
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.brightness_6,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: RotatedBox(
                                    quarterTurns: 3,
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 4,
                                        activeTrackColor: Colors.white,
                                        inactiveTrackColor:
                                            Colors.white.withOpacity(0.3),
                                        thumbColor: Colors.white,
                                        thumbShape: RoundSliderThumbShape(
                                            enabledThumbRadius: 8),
                                        overlayShape: RoundSliderOverlayShape(
                                            overlayRadius: 12),
                                      ),
                                      child: BrightnessSlider(
                                        onBrightnessChanged: (value) {
                                          // Restart the timer when brightness changes
                                          _brightnessSliderTimer?.start();
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Icon(
                                  Icons.brightness_7,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ]),
              )),
        ),
      );
    });
  }
}
