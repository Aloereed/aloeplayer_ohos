import 'package:chewie/src/chewie_player.dart';
import 'package:chewie/src/helpers/adaptive_controls.dart';
import 'package:chewie/src/notifiers/index.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:video_player/video_player.dart';
import 'package:screen/screen.dart';

class PlayerWithControls extends StatefulWidget {
  @override
  _PlayerWithControlsState createState() => _PlayerWithControlsState();
}

class _PlayerWithControlsState extends State<PlayerWithControls> {
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
                child: VideoPlayer(chewieController.videoPlayerController),
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
                    decoration: BoxDecoration(color: Colors.black54),
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
                onLongPress: () {
                  // 记录当前的播放速率
                  chewieController.previousPlaybackSpeed =
                      chewieController.playbackSpeed; // 假设有一个方法可以获取当前的播放速率
                  // 使用 fluttertoast 显示消息
                  // 背景半透明
                  Fluttertoast.showToast(
                    msg: '长按3倍速播放',
                    toastLength: Toast.LENGTH_SHORT,
                    gravity: ToastGravity.CENTER,
                    timeInSecForIosWeb: 1,
                    backgroundColor: Colors.grey,
                    textColor: Colors.white,
                    fontSize: 16.0,
                  );

                  chewieController.videoPlayerController
                      .setPlaybackSpeed(3.0); // 长按三倍速播放
                },
                onLongPressEnd: (_) {
                  chewieController.videoPlayerController.setPlaybackSpeed(
                      chewieController.previousPlaybackSpeed); // 松开恢复到长按之前的播放速率
                },
                onHorizontalDragUpdate: (details) {
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
                    chewieController.seekTo(
                        chewieController.videoPlayerController.value.position +
                            seekDuration);
                    chewieController.swipeDistance = 0.0; // 重置滑动距离
                  }
                },
                onHorizontalDragEnd: (details) {
                  // 滑动结束时重置滑动距离
                  chewieController.swipeDistance = 0.0;
                },
                onDoubleTapDown: (details) {
                  // Get the width of the screen
                  final double screenWidth = MediaQuery.of(context).size.width;

                  // Define a range for the middle part of the screen
                  final double middleRangeStart = screenWidth * 0.4;
                  final double middleRangeEnd = screenWidth * 0.6;

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
                    chewieController.seekTo(
                        chewieController.videoPlayerController.value.position -
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
                    chewieController.seekTo(
                        chewieController.videoPlayerController.value.position +
                            Duration(seconds: 10));
                  } else {
                    // Middle part of the screen: toggle fullscreen
                    Fluttertoast.showToast(
                      msg: '切换全屏模式',
                      toastLength: Toast.LENGTH_SHORT,
                      gravity: ToastGravity.CENTER,
                      timeInSecForIosWeb: 1,
                      backgroundColor: Colors.blue,
                      textColor: Colors.white,
                      fontSize: 16.0,
                    );
                    chewieController.toggleFullScreen();
                  }
                },
                onVerticalDragUpdate: (details) async {
                  // 获取滑动的起始位置
                  double screenWidth = MediaQuery.of(context).size.width;
                  double touchX = details.localPosition.dx;

                  // 判断滑动区域
                  if (touchX < screenWidth / 3) {
                    // 左侧 1/3 区域：调整亮度
                    double delta = details.primaryDelta ?? 0;
                    double _brightness =  await Screen.brightness;

                    if (delta < 0) {
                      // 上滑增加亮度
                      _brightness = (_brightness + 0.01).clamp(0.0, 1.0);
                    } else if (delta > 0) {
                      // 下滑减少亮度
                      _brightness = (_brightness - 0.01).clamp(0.0, 1.0);
                    }

                    // 设置亮度
                    Screen.setBrightness(_brightness);

                    // 显示亮度变化提示
                    Fluttertoast.showToast(
                      msg: '亮度: ${(_brightness * 100).toStringAsFixed(0)}%',
                      toastLength: Toast.LENGTH_SHORT,
                      gravity: ToastGravity.CENTER,
                      timeInSecForIosWeb: 1,
                      backgroundColor: Colors.black.withOpacity(0.7),
                      textColor: Colors.white,
                      fontSize: 16.0,
                    );
                    // 显示音量滑块
                    setState(() {
                      chewieController.showBrightnessSlider = true;
                    });
                    chewieController.startBrightnessSliderTimer();
                  } else if (touchX > (2 * screenWidth / 3)) {
                    // 右侧 1/3 区域：调整音量
                    double delta = details.primaryDelta ?? 0;
                    double _volume =
                        chewieController.videoPlayerController.value.volume;

                    if (delta < 0) {
                      // 上滑增加音量
                      _volume = (_volume + 0.01).clamp(0.0, 1.0);
                    } else if (delta > 0) {
                      // 下滑减少音量
                      _volume = (_volume - 0.01).clamp(0.0, 1.0);
                    }

                    // 设置音量
                    chewieController.setVolume(_volume);

                    // 显示音量变化提示
                    Fluttertoast.showToast(
                      msg: '音量: ${(_volume * 100).toStringAsFixed(0)}%',
                      toastLength: Toast.LENGTH_SHORT,
                      gravity: ToastGravity.CENTER,
                      timeInSecForIosWeb: 1,
                      backgroundColor: Colors.black.withOpacity(0.7),
                      textColor: Colors.white,
                      fontSize: 16.0,
                    );

                    // 显示音量滑块
                    setState(() {
                      chewieController.showVolumeSlider = true;
                    });
                    chewieController.startVolumeSliderTimer();
                  }
                },
                child: Stack(children: [
                  buildPlayerWithControls(chewieController, context),
                  if (chewieController.showVolumeSlider)
                    Positioned(
                      bottom: 100, // 悬浮在音量按钮上方
                      right: 20, // 靠近音量按钮
                      child: Container(
                        height: 200, // 增加高度
                        width: 40,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: RotatedBox(
                          quarterTurns: 3, // 旋转270度，使Slider变为纵向
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4, // 调整轨道高度
                              thumbShape: RoundSliderThumbShape(
                                  enabledThumbRadius: 8), // 调整滑块大小
                              overlayShape: RoundSliderOverlayShape(
                                  overlayRadius: 12), // 调整滑块点击区域大小
                            ),
                            child: Slider(
                              value: chewieController
                                  .videoPlayerController.value.volume,
                              min: 0.0,
                              max: 1.0,
                              onChanged: (value) {
                                chewieController.setVolume(value);
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (chewieController.showBrightnessSlider)
                    Positioned(
                      bottom: 100, // 悬浮在按钮上方
                      left: 20, // 靠近音量按钮
                      child: Container(
                        height: 200, // 增加高度
                        width: 40,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: RotatedBox(
                          quarterTurns: 3, // 旋转270度，使Slider变为纵向
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4, // 调整轨道高度
                              thumbShape: RoundSliderThumbShape(
                                  enabledThumbRadius: 8), // 调整滑块大小
                              overlayShape: RoundSliderOverlayShape(
                                  overlayRadius: 12), // 调整滑块点击区域大小
                            ),
                            child: BrightnessSlider(),
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


class BrightnessSlider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<double>(
      future: Screen.brightness, // 获取亮度值
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return CircularProgressIndicator(); // 加载中显示进度条
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}'); // 出错时显示错误信息
        } else {
          // 数据加载完成后显示 Slider
          return Slider(
            value: snapshot.data!, // 使用 Future 的结果
            min: 0.0,
            max: 1.0,
            onChanged: (value) async {
              await Screen.setBrightness(value); // 设置亮度值
            },
          );
        }
      },
    );
  }
}
