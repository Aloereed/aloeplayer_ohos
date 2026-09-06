import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:package_info_plus/package_info_plus.dart';

/// 启动画面
/// 应用启动时显示的品牌化界面
class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SplashScreen({
    Key? key,
    required this.onComplete,
  }) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _shimmerAnimation;
  late Animation<double> _fadeOutAnimation;
  String _version = '';

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) { /* Branding remains visible if package information is unavailable. */ }
  }

  @override
  void initState() {
    super.initState();
    _loadVersion();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack),
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _shimmerAnimation = Tween<double>(begin: -2.0, end: 2.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeInOut),
      ),
    );

    // 添加淡出动画，在最后阶段执行
    _fadeOutAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.75, 1.0, curve: Curves.easeOut),
      ),
    );

    _controller.forward().then((_) {
      // 动画完成后立即通知父组件
      widget.onComplete();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenSize = MediaQuery.of(context).size;

    return AnimatedBuilder(
      animation: _fadeOutAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeOutAnimation.value,
          child: Scaffold(
            backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
            body: Stack(
              children: [
                // 背景渐变
                AnimatedBuilder(
                  animation: _fadeAnimation,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _fadeAnimation.value * 0.3,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment.center,
                            radius: 1.0,
                            colors: [
                              Colors.lightBlue.withOpacity(0.3),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),

                // 主要内容
                Center(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Logo
                          Transform.scale(
                            scale: _scaleAnimation.value,
                            child: Opacity(
                              opacity: _fadeAnimation.value,
                              child: Container(
                                width: 140,
                                height: 140,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(32),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.lightBlue.withOpacity(0.4),
                                      blurRadius: 40,
                                      offset: const Offset(0, 20),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(32),
                                  child: Image.asset(
                                    'Assets/icon.png',
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),

                          // 应用名称
                          FadeTransition(
                            opacity: _fadeAnimation,
                            child: ShaderMask(
                              shaderCallback: (bounds) {
                                return LinearGradient(
                                  begin: Alignment(_shimmerAnimation.value - 1, 0),
                                  end: Alignment(_shimmerAnimation.value + 1, 0),
                                  colors: [
                                    Colors.lightBlue.shade300,
                                    Colors.lightBlue.shade600,
                                    Colors.lightBlue.shade300,
                                  ],
                                  stops: const [0.0, 0.5, 1.0],
                                ).createShader(bounds);
                              },
                              child: Text(
                                'AloePlayer',
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 标语
                          FadeTransition(
                            opacity: _fadeAnimation,
                            child: Text(
                              '极致流畅的播放体验',
                              style: TextStyle(
                                fontSize: 16,
                                color: isDark ? Colors.white60 : Colors.black45,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 60),

                          // 加载指示器
                          FadeTransition(
                            opacity: _fadeAnimation,
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.lightBlue,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                // 底部版本信息
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: AnimatedBuilder(
                    animation: _fadeAnimation,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _fadeAnimation.value,
                        child: Text(
                          _version.isEmpty ? '' : 'Version $_version',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white30 : Colors.black26,
                            letterSpacing: 0.5,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
