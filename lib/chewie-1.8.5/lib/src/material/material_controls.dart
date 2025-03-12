import 'dart:async';
import 'dart:ui';

import 'package:aloeplayer/chewie-1.8.5/lib/src/center_play_button.dart';
import 'package:aloeplayer/chewie-1.8.5/lib/src/center_seek_button.dart';
import 'package:aloeplayer/chewie-1.8.5/lib/src/chewie_player.dart';
import 'package:aloeplayer/chewie-1.8.5/lib/src/chewie_progress_colors.dart';
import 'package:aloeplayer/chewie-1.8.5/lib/src/helpers/utils.dart';
import 'package:aloeplayer/chewie-1.8.5/lib/src/material/material_progress_bar.dart';
import 'package:aloeplayer/chewie-1.8.5/lib/src/material/widgets/options_dialog.dart';
import 'package:aloeplayer/chewie-1.8.5/lib/src/material/widgets/playback_speed_dialog.dart';
import 'package:aloeplayer/chewie-1.8.5/lib/src/models/option_item.dart';
import 'package:aloeplayer/chewie-1.8.5/lib/src/models/subtitle_model.dart';
import 'package:aloeplayer/chewie-1.8.5/lib/src/notifiers/index.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:aloeplayer/ass.dart';

class MaterialControls extends StatefulWidget {
  const MaterialControls({
    this.showPlayButton = true,
    super.key,
  });

  final bool showPlayButton;

  @override
  State<StatefulWidget> createState() {
    return _MaterialControlsState();
  }
}

// 在你的文件中添加这个数据类
class VideoSizeData {
  final double width;
  final double height;
  final double offsetX;
  final double offsetY;

  const VideoSizeData(
      {required this.width,
      required this.height,
      required this.offsetX,
      required this.offsetY});
}

class _MaterialControlsState extends State<MaterialControls>
    with SingleTickerProviderStateMixin {
  late PlayerNotifier notifier;
  late VideoPlayerValue _latestValue;
  double? _latestVolume;
  Timer? _hideTimer;
  Timer? _initTimer;
  late var _subtitlesPosition = Duration.zero;
  bool _subtitleOn = true;
  bool _danmakuOn = true;
  bool _assOn = true;
  Timer? _showAfterExpandCollapseTimer;
  bool _dragging = false;
  bool _displayTapped = false;
  Timer? _bufferingDisplayTimer;
  bool _displayBufferingIndicator = false;
  bool _showSettings = false; // 控制悬浮框的显示
  bool isBackgroundBlurred = true;
  // 在你的State类中添加这些字段
  Timer? _subtitleUpdateThrottler;
  VideoPlayerValue? _lastProcessedValue;

  final barHeight = 48.0 * 1.5;
  final marginSize = 5.0;

  late VideoPlayerController controller;
  ChewieController? _chewieController;

  // We know that _chewieController is set in didChangeDependencies
  ChewieController get chewieController => _chewieController!;

  @override
  void initState() {
    super.initState();
    notifier = Provider.of<PlayerNotifier>(context, listen: false);
  }

  // 在你的State类中添加这个计算方法
  VideoSizeData _calculateVideoDisplaySize(double videoWidth,
      double videoHeight, double containerWidth, double containerHeight) {
    double videoDisplayWidth, videoDisplayHeight;
    double offsetX = 0, offsetY = 0;

    if (videoWidth / videoHeight > containerWidth / containerHeight) {
      // 视频比例比容器宽，视频将填满宽度，高度居中
      videoDisplayWidth = containerWidth;
      videoDisplayHeight = containerWidth * videoHeight / videoWidth;
      offsetY = (containerHeight - videoDisplayHeight) / 2;
    } else {
      // 视频比例比容器高，视频将填满高度，宽度居中
      videoDisplayHeight = containerHeight;
      videoDisplayWidth = containerHeight * videoWidth / videoHeight;
      offsetX = (containerWidth - videoDisplayWidth) / 2;
    }

    return VideoSizeData(
        width: videoDisplayWidth,
        height: videoDisplayHeight,
        offsetX: offsetX,
        offsetY: offsetY);
  }

  @override
  Widget build(BuildContext context) {
    if (_latestValue.hasError) {
      return chewieController.errorBuilder?.call(
            context,
            chewieController.videoPlayerController.value.errorDescription!,
          ) ??
          const Center(
            child: Icon(
              Icons.error,
              color: Colors.white,
              size: 42,
            ),
          );
    }

    return Stack(children: [
      Positioned.fill(
        child: MouseRegion(
          onHover: (_) {
            if (_displayTapped) {
              setState(() {
                notifier.hideStuff = true;
                _displayTapped = false;
              });
            } else {
              _cancelAndRestartTimer();
            }
          },
          child: Container(), // 空容器，确保 MouseRegion 覆盖整个区域
        ),
      ),
      GestureDetector(
        behavior: HitTestBehavior.translucent,
        // onTap: () => _cancelAndRestartTimer(),
        onTap: () {
          if (chewieController.closePlaylist != null)
            chewieController.closePlaylist!();
          if (_displayTapped) {
            setState(() {
              notifier.hideStuff = true;
              _displayTapped = false;
            });
          } else {
            _cancelAndRestartTimer();
          }
        },
        child: AbsorbPointer(
          absorbing: notifier.hideStuff,
          child: Stack(
            children: [
              Visibility(
                visible: _danmakuOn,
                child: Positioned.fill(
                  child: Stack(
                    children: [
                      // 弹幕层
                      DanmakuScreen(
                        key: chewieController.danmuKey,
                        createdController: (DanmakuController e) {
                          chewieController.danmakuController = e;
                        },
                        option: DanmakuOption(
                          opacity: chewieController.opacity,
                          fontSize: chewieController.fontSize,
                          fontWeight: chewieController.fontWeight,
                          duration: chewieController.duration,
                          showStroke: chewieController.showStroke,
                          hideScroll: chewieController.hideScroll,
                          hideTop: chewieController.hideTop,
                          hideBottom: chewieController.hideBottom,
                        ),
                      ),

                      // 透明的覆盖层
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: () {
                            // 处理点击事件
                          },
                          child: Container(
                            color: Colors.transparent, // 完全透明
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_subtitleOn &&
                  (chewieController.assSubtitles?.isNotEmpty ?? false))
                LayoutBuilder(
                  builder: (context, constraints) {
                    return ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: chewieController.videoPlayerController,
                      builder: (context, videoValue, child) {
                        // 仅当位置发生较大变化时更新字幕
                        final positionChanged =
                            _lastProcessedValue?.position.inMilliseconds !=
                                videoValue.position.inMilliseconds;

                        if (positionChanged) {
                          _subtitleUpdateThrottler?.cancel();
                          _subtitleUpdateThrottler =
                              Timer(const Duration(milliseconds: 100), () {
                            if (mounted) {
                              setState(() {
                                _lastProcessedValue = videoValue;
                              });
                            }
                          });
                        }

                        // 计算视频显示尺寸
                        final videoSizeData = _calculateVideoDisplaySize(
                            videoValue.size.width,
                            videoValue.size.height,
                            constraints.maxWidth,
                            constraints.maxHeight);

                        return Stack(
                          children: [
                            Positioned(
                              left: videoSizeData.offsetX,
                              top: videoSizeData.offsetY,
                              width: videoSizeData.width,
                              height: videoSizeData.height,
                              child: RepaintBoundary(
                                child: AssSubtitleRenderer(
                                  subtitles: chewieController.assSubtitles!,
                                  currentPosition: videoValue.position,
                                  videoSize: Size(videoSizeData.width,
                                      videoSizeData.height),
                                  subtitleScale: 0.225 *
                                      chewieController.subtitleFontsize /
                                      18.0,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),

              if (_displayBufferingIndicator)
                _chewieController?.bufferingBuilder?.call(context) ??
                    const Center(
                      child: CircularProgressIndicator(),
                    )
              else
                Visibility(
                    visible: false, child: Container()), //_buildHitArea()),
              // 悬浮设置框
              if (_showSettings)
                Positioned(
                  bottom: 50, // 悬浮框显示在按钮上方
                  left: 0,
                  child: _buildSettingsPopup(),
                ),
              _buildActionBar(),
              Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  if (_subtitleOn &&
                      (chewieController.subtitle?.isNotEmpty ?? false) &&
                      !(chewieController.assSubtitles?.isNotEmpty ?? false))
                    Transform.translate(
                      offset: Offset(
                        0.0,
                        notifier.hideStuff ? barHeight * 0.8 : 0.0,
                      ),
                      child:
                          _buildSubtitles(context, chewieController.subtitle!),
                    ),
                  _buildBottomBar(context),
                ],
              ),
            ],
          ),
        ),
      ),
    ]);
  }

  @override
  void dispose() {
    _subtitleUpdateThrottler?.cancel();
    _dispose();
    super.dispose();
  }

  void _dispose() {
    controller.removeListener(_updateState);
    _hideTimer?.cancel();
    _initTimer?.cancel();
    _showAfterExpandCollapseTimer?.cancel();
  }

  @override
  void didChangeDependencies() {
    final oldController = _chewieController;
    _chewieController = ChewieController.of(context);
    controller = chewieController.videoPlayerController;

    if (oldController != chewieController) {
      _dispose();
      _initialize();
    }

    super.didChangeDependencies();
  }

  Widget _buildActionBar() {
    return Positioned(
      top: 0,
      right: 0,
      child: SafeArea(
        child: AnimatedOpacity(
          opacity: notifier.hideStuff ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 250),
          child: Row(
            children: [
              _buildSubtitleToggle(),
              _buildDanmakuToggle(),
              if (chewieController.showOptions) _buildOptionsButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionsButton() {
    final options = <OptionItem>[
      OptionItem(
        onTap: () async {
          Navigator.pop(context);
          _onSpeedButtonTap();
        },
        iconData: Icons.speed,
        title: chewieController.optionsTranslation?.playbackSpeedButtonText ??
            'Playback speed',
      )
    ];

    if (chewieController.additionalOptions != null &&
        chewieController.additionalOptions!(context).isNotEmpty) {
      options.addAll(chewieController.additionalOptions!(context));
    }

    return AnimatedOpacity(
      opacity: notifier.hideStuff ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 250),
      child: IconButton(
        onPressed: () async {
          _hideTimer?.cancel();

          if (chewieController.optionsBuilder != null) {
            await chewieController.optionsBuilder!(context, options);
          } else {
            await showModalBottomSheet<OptionItem>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              useRootNavigator: chewieController.useRootNavigator,
              builder: (context) => OptionsDialog(
                options: options,
                cancelButtonText:
                    chewieController.optionsTranslation?.cancelButtonText,
              ),
            );
          }

          if (_latestValue.isPlaying) {
            _startHideTimer();
          }
        },
        icon: const Icon(
          Icons.more_vert,
          // color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildSubtitles(BuildContext context, Subtitles subtitles) {
    if (!_subtitleOn || !(chewieController.subtitle?.isNotEmpty ?? false)) {
      return const SizedBox();
    }
    final currentSubtitle = subtitles.getByPosition(_subtitlesPosition);
    if (currentSubtitle.isEmpty) {
      return const SizedBox();
    }

    if (chewieController.subtitleBuilder != null) {
      return chewieController.subtitleBuilder!(
        context,
        currentSubtitle.first!.text,
      );
    }

    return Padding(
      padding: EdgeInsets.all(marginSize),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: const Color(0x96000000),
          borderRadius: BorderRadius.circular(10.0),
        ),
        child: Text(
          currentSubtitle.first!.text.toString(),
          style: const TextStyle(
            fontSize: 18,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildDanmukuSettingsButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _showSettings = !_showSettings; // 切换悬浮框的显示状态
        });
      },
      child: Stack(
        children: [
          // 弹幕设置按钮
          AnimatedOpacity(
            opacity: notifier.hideStuff ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 300),
            child: ClipRect(
              child: Container(
                height: 40,
                padding: const EdgeInsets.only(left: 6.0),
                child: Stack(
                  alignment: Alignment.bottomRight, // 将设置图标对齐到右下角
                  children: [
                    // 主图标：message
                    const Icon(
                      Icons.message,
                      color: Colors.white,
                    ),
                    // 叠加的设置图标
                    Transform.translate(
                      offset: const Offset(6, 6), // 调整设置图标的位置
                      child: const Icon(
                        Icons.settings,
                        color: Colors.white,
                        size: 12, // 设置图标的大小
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 构建悬浮设置框
  Widget _buildSettingsPopup() {
    return Container(
      width: 300, // 增加宽度以容纳两列
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          // 关闭按钮
          Positioned(
            bottom: 2,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 20),
              onPressed: () {
                setState(() {
                  _showSettings = false; // 关闭设置弹窗
                });
              },
            ),
          ),
          // 两列布局
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 第一列
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSliderSetting(
                          label: '透明度',
                          value:
                              chewieController.danmakuController.option.opacity,
                          onChanged: (value) {
                            setState(() {
                              chewieController.danmakuController.updateOption(
                                chewieController.danmakuController.option
                                    .copyWith(opacity: value),
                              );
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildSliderSetting(
                          label: '字体大小',
                          value: chewieController
                              .danmakuController.option.fontSize,
                          min: 10,
                          max: 30,
                          onChanged: (value) {
                            setState(() {
                              chewieController.danmakuController.updateOption(
                                chewieController.danmakuController.option
                                    .copyWith(fontSize: value),
                              );
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildSwitchSetting(
                          label: '显示描边',
                          value: chewieController
                              .danmakuController.option.showStroke,
                          onChanged: (value) {
                            setState(() {
                              chewieController.danmakuController.updateOption(
                                chewieController.danmakuController.option
                                    .copyWith(showStroke: value),
                              );
                            });
                          },
                        ),
                        // const SizedBox(height: 16),
                        // _buildSwitchSetting(
                        //   label: '超量弹幕模式',
                        //   value: chewieController
                        //       .danmakuController.option.massiveMode,
                        //   onChanged: (value) {
                        //     setState(() {
                        //       chewieController.danmakuController.updateOption(
                        //         chewieController.danmakuController.option
                        //             .copyWith(massiveMode: value),
                        //       );
                        //     });
                        //   },
                        // ),
                      ],
                    ),
                  ),
                  // 第二列
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSwitchSetting(
                          label: '隐藏滚动弹幕',
                          value: chewieController
                              .danmakuController.option.hideScroll,
                          onChanged: (value) {
                            setState(() {
                              chewieController.danmakuController.updateOption(
                                chewieController.danmakuController.option
                                    .copyWith(hideScroll: value),
                              );
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildSwitchSetting(
                          label: '隐藏顶部弹幕',
                          value:
                              chewieController.danmakuController.option.hideTop,
                          onChanged: (value) {
                            setState(() {
                              chewieController.danmakuController.updateOption(
                                chewieController.danmakuController.option
                                    .copyWith(hideTop: value),
                              );
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildSwitchSetting(
                          label: '隐藏底部弹幕',
                          value: chewieController
                              .danmakuController.option.hideBottom,
                          onChanged: (value) {
                            setState(() {
                              chewieController.danmakuController.updateOption(
                                chewieController.danmakuController.option
                                    .copyWith(hideBottom: value),
                              );
                            });
                          },
                        ),
                        // const SizedBox(height: 16),
                        // _buildSwitchSetting(
                        //   label: '启用安全区域',
                        //   value: chewieController
                        //       .danmakuController.option.safeArea,
                        //   onChanged: (value) {
                        //     setState(() {
                        //       chewieController.danmakuController.updateOption(
                        //         chewieController.danmakuController.option
                        //             .copyWith(safeArea: value),
                        //       );
                        //     });
                        //   },
                        // ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 构建滑块设置项
  Widget _buildSliderSetting({
    required String label,
    required double value,
    double min = 0,
    double max = 1,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white),
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }

  // 构建开关设置项
  Widget _buildSwitchSetting({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white),
        ),
        const Spacer(),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.blue, // 设置激活状态下的圆形按钮颜色
          activeTrackColor: Colors.blue.withOpacity(0.5), // 设置激活状态下的轨道颜色
          inactiveThumbColor: Colors.grey, // 设置非激活状态下的圆形按钮颜色
          inactiveTrackColor: Colors.grey.withOpacity(0.5), // 设置非激活状态下的轨道颜色
        ),
      ],
    );
  }

  AnimatedOpacity _buildBottomBar(BuildContext context) {
    final iconColor = Theme.of(context).textTheme.labelLarge!.color;
    final bool isFinished = (_latestValue.position >= _latestValue.duration) &&
        _latestValue.duration.inSeconds > 0;
    final bool showPlayButton =
        widget.showPlayButton && !_dragging && !notifier.hideStuff;

    return AnimatedOpacity(
      opacity: notifier.hideStuff ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.0), // 圆角效果
        child: BackdropFilter(
          filter: isBackgroundBlurred
              ? ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0)
              : ImageFilter.blur(sigmaX: 0.0, sigmaY: 0.0), // 高斯模糊效果
          child: Container(
            color: isBackgroundBlurred
                ? Colors.black.withOpacity(0.3)
                : Colors.transparent, // 背景透明效果
            height: barHeight +
                (chewieController.isFullScreen ? 10.0 : 0) +
                20, // 增加高度
            padding: EdgeInsets.only(
              left: 20,
              top: 10, // 增加顶部内边距
              bottom: !chewieController.isFullScreen ? 10.0 : 0,
            ),
            child: SafeArea(
              top: false,
              bottom: chewieController.isFullScreen,
              minimum: chewieController.controlsSafeAreaMinimum,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!chewieController.isLive)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.only(right: 20),
                        child: Row(
                          children: [
                            _buildProgressBar(),
                          ],
                        ),
                      ),
                    ),
                  Flexible(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        SmallPlayButton(
                          backgroundColor: Colors.black54,
                          // iconColor: Colors.white,
                          isFinished: isFinished,
                          isPlaying: controller.value.isPlaying,
                          show: showPlayButton,
                          onPressed: _playPause,
                        ),
                        if (chewieController.isLive)
                          const Expanded(child: Text('LIVE'))
                        else
                          _buildPosition(iconColor),
                        if (chewieController.playPreviousItem != null)
                          _buildPreviousButton(),
                        if (chewieController.playNextItem != null)
                          _buildNextButton(),
                        if (chewieController.allowMuting)
                          _buildMuteButton(controller),
                        if (_danmakuOn &&
                            chewieController.danmakuContents != null &&
                            chewieController.danmakuContents!.length > 0)
                          _buildDanmukuSettingsButton(context),
                        const Spacer(),
                        _buildVisibilityButton(),
                        if (chewieController.allowFullScreen)
                          _buildExpandButton(),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: chewieController.isFullScreen ? 15.0 : 0,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  GestureDetector _buildMuteButton(
    VideoPlayerController controller,
  ) {
    return GestureDetector(
      onTap: () {
        _cancelAndRestartTimer();

        if (_latestValue.volume == 0) {
          controller.setVolume(_latestVolume ?? 0.5);
        } else {
          _latestVolume = controller.value.volume;
          controller.setVolume(0.0);
        }
      },
      child: AnimatedOpacity(
        opacity: notifier.hideStuff ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          height: barHeight + (chewieController.isFullScreen ? 15.0 : 0),
          margin: const EdgeInsets.only(right: 6.0),
          padding: const EdgeInsets.only(
            left: 4.0,
            right: 4.0,
          ),
          child: Center(
              child: Stack(
            children: <Widget>[
              // 白色图标
              Icon(
                    _latestValue.volume > 0
                        ? Icons.volume_up
                        : Icons.volume_off,
                    color: Colors.white,
                    size: 24.0, // 比黑色图标稍微小一点，以形成描边效果
                  ),
            ],
          )),
        ),
      ),
    );
  }

  GestureDetector _buildNextButton() {
    return GestureDetector(
      onTap: () {
        _cancelAndRestartTimer();
        chewieController.playNextItem!();
      },
      child: AnimatedOpacity(
        opacity: notifier.hideStuff ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          height: barHeight + (chewieController.isFullScreen ? 15.0 : 0),
          margin: const EdgeInsets.only(right: 6.0),
          padding: const EdgeInsets.only(
            left: 4.0,
            right: 4.0,
          ),
          child: Center(
              child: Stack(
            children: <Widget>[
              // 白色图标
              Icon(
                    Icons.skip_next,
                    color: Colors.white,
                    size: 24.0, // 比黑色图标稍微小一点，以形成描边效果
                  ),
            ],
          )),
        ),
      ),
    );
  }

  GestureDetector _buildPreviousButton() {
    return GestureDetector(
      onTap: () {
        _cancelAndRestartTimer();
        chewieController.playPreviousItem!();
      },
      child: AnimatedOpacity(
        opacity: notifier.hideStuff ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          height: barHeight + (chewieController.isFullScreen ? 15.0 : 0),
          margin: const EdgeInsets.only(right: 6.0),
          padding: const EdgeInsets.only(
            left: 4.0,
            right: 4.0,
          ),
          child: Center(
              child: Stack(
            children: <Widget>[
              // 白色图标
              Icon(
                    Icons.skip_previous,
                    color: Colors.white,
                    size: 24.0, // 比黑色图标稍微小一点，以形成描边效果
                  ),
            ],
          )),
        ),
      ),
    );

  }

  GestureDetector _buildExpandButton() {
    return GestureDetector(
      onTap: _onExpandCollapse,
      child: AnimatedOpacity(
        opacity: notifier.hideStuff ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          height: barHeight + (chewieController.isFullScreen ? 15.0 : 0),
          margin: const EdgeInsets.only(right: 12.0),
          padding: const EdgeInsets.only(
            left: 8.0,
            right: 8.0,
          ),
          child: Center(
              child: Stack(
            children: <Widget>[
              // 黑色描边图标
              // Icon(
              //   chewieController.isFullScreen
              //       ? Icons.fullscreen_exit
              //       : Icons.fullscreen,
              //   color: Colors.black,
              //   size: 26.0, // 描边图标稍微大一点
              // ),
              // 白色图标
              Icon(
                chewieController.isFullScreen
                    ? Icons.fullscreen_exit
                    : Icons.fullscreen,
                color: Colors.white,
                size: 24.0, // 实际图标稍微小一点
              ),
            ],
          )),
        ),
      ),
    );
  }

  void _toggleBackground() {
    setState(() {
      isBackgroundBlurred = !isBackgroundBlurred;
    });
  }

  GestureDetector _buildVisibilityButton() {
    return GestureDetector(
      onTap: _toggleBackground,
      child: AnimatedOpacity(
        opacity: notifier.hideStuff ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          height: barHeight + (chewieController.isFullScreen ? 15.0 : 0),
          margin: const EdgeInsets.only(right: 6.0),
          padding: const EdgeInsets.only(
            left: 8.0,
            right: 8.0,
          ),
          child: Center(
              child: Stack(
            children: <Widget>[
              // 白色图标
              Icon(
                isBackgroundBlurred ? Icons.visibility_off : Icons.visibility,
                color: Colors.white,
                size: 24.0, // 实际图标稍微小一点
              ),
            ],
          )),
        ),
      ),
    );
  }

  Widget _buildHitArea() {
    final bool isFinished = (_latestValue.position >= _latestValue.duration) &&
        _latestValue.duration.inSeconds > 0;
    final bool showPlayButton =
        widget.showPlayButton && !_dragging && !notifier.hideStuff;

    return GestureDetector(
      onTap: () {
        if (true || _latestValue.isPlaying) {
          if (_displayTapped) {
            setState(() {
              notifier.hideStuff = true;
            });
          } else {
            _cancelAndRestartTimer();
          }
        } else {
          // TODO: this is a hack to show the player controls when the video is paused
          _playPause();

          setState(() {
            notifier.hideStuff = true;
          });
        }
      },
      child: Container(
        alignment: Alignment.center,
        color: Colors
            .transparent, // The Gesture Detector doesn't expand to the full size of the container without this; Not sure why!
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!isFinished && !chewieController.isLive)
              CenterSeekButton(
                iconData: Icons.replay_10,
                backgroundColor: Colors.black54,
                // iconColor: Colors.white,
                show: showPlayButton,
                fadeDuration: chewieController.materialSeekButtonFadeDuration,
                iconSize: chewieController.materialSeekButtonSize,
                onPressed: _seekBackward,
              ),
            Container(
              margin: EdgeInsets.symmetric(
                horizontal: marginSize,
              ),
              child: CenterPlayButton(
                backgroundColor: Colors.black54,
                // iconColor: Colors.white,
                isFinished: isFinished,
                isPlaying: controller.value.isPlaying,
                show: showPlayButton,
                onPressed: _playPause,
              ),
            ),
            if (!isFinished && !chewieController.isLive)
              CenterSeekButton(
                iconData: Icons.forward_10,
                backgroundColor: Colors.black54,
                // iconColor: Colors.white,
                show: showPlayButton,
                fadeDuration: chewieController.materialSeekButtonFadeDuration,
                iconSize: chewieController.materialSeekButtonSize,
                onPressed: _seekForward,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _onSpeedButtonTap() async {
    _hideTimer?.cancel();

    final chosenSpeed = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useRootNavigator: chewieController.useRootNavigator,
      builder: (context) => PlaybackSpeedDialog(
        speeds: chewieController.playbackSpeeds,
        selected: _latestValue.playbackSpeed,
      ),
    );

    if (chosenSpeed != null) {
      controller.setPlaybackSpeed(chosenSpeed);
    }

    if (_latestValue.isPlaying) {
      _startHideTimer();
    }
  }

  Widget _buildPosition(Color? iconColor) {
    final position = _latestValue.position;
    final duration = _latestValue.duration;

    return RichText(
      text: TextSpan(
        text: '${formatDuration(position)} ',
        children: <InlineSpan>[
          TextSpan(
            text: '/ ${formatDuration(duration)}',
            style: TextStyle(
              fontSize: 14.0,
              color: Colors.white.withOpacity(.75),
              fontWeight: FontWeight.normal,
              // shadows: [
              //   Shadow(
              //     color: Colors.black, // 描边颜色
              //     offset: Offset(-1, -1), // 描边偏移量
              //     blurRadius: 1, // 描边模糊半径
              //   ),
              //   Shadow(
              //     color: Colors.black,
              //     offset: Offset(1, -1),
              //     blurRadius: 1,
              //   ),
              //   Shadow(
              //     color: Colors.black,
              //     offset: Offset(-1, 1),
              //     blurRadius: 1,
              //   ),
              //   Shadow(
              //     color: Colors.black,
              //     offset: Offset(1, 1),
              //     blurRadius: 1,
              //   ),
              // ],
            ),
          )
        ],
        style: const TextStyle(
          fontSize: 14.0,
          color: Colors.white,
          fontWeight: FontWeight.bold,
          // shadows: [
          //   Shadow(
          //     color: Colors.black, // 描边颜色
          //     offset: Offset(-1, -1), // 描边偏移量
          //     blurRadius: 1, // 描边模糊半径
          //   ),
          //   Shadow(
          //     color: Colors.black,
          //     offset: Offset(1, -1),
          //     blurRadius: 1,
          //   ),
          //   Shadow(
          //     color: Colors.black,
          //     offset: Offset(-1, 1),
          //     blurRadius: 1,
          //   ),
          //   Shadow(
          //     color: Colors.black,
          //     offset: Offset(1, 1),
          //     blurRadius: 1,
          //   ),
          // ],
        ),
      ),
    );
  }

  Widget _buildSubtitleToggle() {
    //if don't have subtitle hiden button
    if (chewieController.subtitle?.isEmpty ?? true) {
      return const SizedBox();
    }
    return GestureDetector(
      onTap: _onSubtitleTap,
      child: Container(
        height: barHeight,
        color: Colors.transparent,
        padding: const EdgeInsets.only(
          left: 12.0,
          right: 12.0,
        ),
        child: Icon(
          _subtitleOn
              ? Icons.closed_caption
              : Icons.closed_caption_off_outlined,
          color: _subtitleOn ? Colors.white : Colors.grey[700],
        ),
      ),
    );
  }

  Widget _buildDanmakuToggle() {
    //if don't have subtitle hiden button
    if (chewieController.danmakuContents == null ||
        chewieController.danmakuContents?.length == 0) {
      return const SizedBox();
    }
    return GestureDetector(
      onTap: _onDanmakuTap,
      child: Container(
        height: barHeight,
        color: Colors.transparent,
        padding: const EdgeInsets.only(
          left: 12.0,
          right: 12.0,
        ),
        child: Icon(
          _danmakuOn ? Icons.comment : Icons.comments_disabled,
          color: _danmakuOn ? Colors.white : Colors.grey[700],
        ),
      ),
    );
  }

  void _onSubtitleTap() {
    setState(() {
      _subtitleOn = !_subtitleOn;
    });
  }

  void _onDanmakuTap() {
    setState(() {
      _danmakuOn = !_danmakuOn;
      chewieController.danmakuOn = _danmakuOn;
    });
  }

  void _cancelAndRestartTimer() {
    _hideTimer?.cancel();
    _startHideTimer();

    setState(() {
      notifier.hideStuff = false;
      _displayTapped = true;
    });
  }

  Future<void> _initialize() async {
    // _subtitleOn = chewieController.subtitle?.isNotEmpty ?? false;
    _subtitleOn = true;
    _danmakuOn = true;
    controller.addListener(_updateState);

    _updateState();

    if (controller.value.isPlaying || chewieController.autoPlay) {
      _startHideTimer();
    }

    if (chewieController.showControlsOnInitialize) {
      _initTimer = Timer(const Duration(milliseconds: 200), () {
        setState(() {
          notifier.hideStuff = false;
        });
      });
    }
  }

  void _onExpandCollapse() {
    setState(() {
      notifier.hideStuff = true;

      chewieController.toggleFullScreen();
      _showAfterExpandCollapseTimer =
          Timer(const Duration(milliseconds: 300), () {
        setState(() {
          _cancelAndRestartTimer();
        });
      });
    });
  }

  void _playPause() {
    final bool isFinished = (_latestValue.position >= _latestValue.duration) &&
        _latestValue.duration.inSeconds > 0;

    setState(() {
      if (controller.value.isPlaying) {
        notifier.hideStuff = false;
        _hideTimer?.cancel();
        controller.pause();
      } else {
        _cancelAndRestartTimer();

        if (!controller.value.isInitialized) {
          controller.initialize().then((_) {
            controller.play();
          });
        } else {
          if (isFinished) {
            controller.seekTo(Duration.zero);
          }
          controller.play();
        }
      }
    });
  }

  void _seekRelative(Duration relativeSeek) {
    _cancelAndRestartTimer();
    final position = _latestValue.position + relativeSeek;
    final duration = _latestValue.duration;

    if (position < Duration.zero) {
      controller.seekTo(Duration.zero);
    } else if (position > duration) {
      controller.seekTo(duration);
    } else {
      controller.seekTo(position);
    }
  }

  void _seekBackward() {
    _seekRelative(
      const Duration(
        seconds: -10,
      ),
    );
  }

  void _seekForward() {
    _seekRelative(
      const Duration(
        seconds: 10,
      ),
    );
  }

  void _startHideTimer() {
    final hideControlsTimer = chewieController.hideControlsTimer.isNegative
        ? ChewieController.defaultHideControlsTimer
        : chewieController.hideControlsTimer;
    _hideTimer = Timer(hideControlsTimer, () {
      setState(() {
        notifier.hideStuff = true;
        _displayTapped = false;
      });
    });
  }

  void _bufferingTimerTimeout() {
    _displayBufferingIndicator = true;
    if (mounted) {
      setState(() {});
    }
  }

  void _updateState() {
    if (!mounted) return;

    // display the progress bar indicator only after the buffering delay if it has been set
    if (chewieController.progressIndicatorDelay != null) {
      if (controller.value.isBuffering) {
        _bufferingDisplayTimer ??= Timer(
          chewieController.progressIndicatorDelay!,
          _bufferingTimerTimeout,
        );
      } else {
        _bufferingDisplayTimer?.cancel();
        _bufferingDisplayTimer = null;
        _displayBufferingIndicator = false;
      }
    } else {
      _displayBufferingIndicator = controller.value.isBuffering;
    }

    setState(() {
      _latestValue = controller.value;
      _subtitlesPosition = controller.value.position;
    });
  }

  Widget _buildProgressBar() {
    return Expanded(
      child: MaterialVideoProgressBar(
        controller,
        onDragStart: () {
          setState(() {
            _dragging = true;
          });

          _hideTimer?.cancel();
        },
        onDragUpdate: () {
          _hideTimer?.cancel();
        },
        onDragEnd: () {
          setState(() {
            _dragging = false;
          });

          _startHideTimer();
        },
        colors: chewieController.materialProgressColors ??
            ChewieProgressColors(
              playedColor: Theme.of(context).colorScheme.secondary,
              handleColor: Theme.of(context).colorScheme.secondary,
              bufferedColor:
                  Theme.of(context).colorScheme.surface.withOpacity(0.5),
              backgroundColor: Theme.of(context).disabledColor.withOpacity(.5),
            ),
        draggableProgressBar: chewieController.draggableProgressBar,
      ),
    );
  }
}
