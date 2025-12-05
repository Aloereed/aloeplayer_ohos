import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:aloeplayer/privacy_policy.dart';

/// 欢迎引导页
/// 展示应用核心功能和特点
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({
    Key? key,
    required this.onComplete,
  }) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isPolicyAccepted = false;

  final List<OnboardingPage> _pages = [
    OnboardingPage(
      icon: Icons.video_library,
      title: '强大的视频播放',
      description: '支持多种视频格式，流畅播放高清视频',
      gradient: [Colors.blue.shade400, Colors.blue.shade600],
    ),
    OnboardingPage(
      icon: Icons.library_music,
      title: '音频库管理',
      description: '智能管理您的音乐收藏，支持多种音频格式和高品质播放',
      gradient: [Colors.purple.shade400, Colors.purple.shade600],
    ),
    OnboardingPage(
      icon: Icons.subtitles,
      title: '特效字幕支持',
      description: 'MPV播放器完全渲染特效字幕，支持ASS/SSA等多种字幕格式',
      gradient: [Colors.orange.shade400, Colors.orange.shade600],
    ),
    OnboardingPage(
      icon: Icons.cloud,
      title: '网络媒体库',
      description: '连接网络媒体服务器，随时随地访问您的媒体内容',
      gradient: [Colors.green.shade400, Colors.green.shade600],
    ),
  ];

  void _nextPage() {
    // 如果是第一页（隐私政策页），检查是否已接受
    if (_currentPage == 0 && !_isPolicyAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先阅读并同意隐私政策'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_currentPage < _pages.length) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      widget.onComplete();
    }
  }

  Future<void> _acceptPolicy() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrivacyPolicyVersion.acceptedKey, true);
    // 保存当前隐私协议版本
    await prefs.setInt(PrivacyPolicyVersion.versionKey, PrivacyPolicyVersion.current);
    setState(() {
      _isPolicyAccepted = true;
    });
    // 自动翻到下一页
    _nextPage();
  }

  void _declinePolicy() {
    // 用户拒绝隐私政策，退出应用
    exit(0);
  }

  void _skipToEnd() {
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalPages = _pages.length + 1; // +1 for privacy policy page

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      body: Stack(
        children: [
          // 页面内容
          PageView.builder(
            controller: _pageController,
            physics: _currentPage == 0 && !_isPolicyAccepted
                ? const NeverScrollableScrollPhysics() // 禁止滑动直到接受隐私政策
                : const PageScrollPhysics(),
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },
            itemCount: totalPages,
            itemBuilder: (context, index) {
              if (index == 0) {
                // 第一页：隐私政策页
                return _PrivacyPolicyPage(
                  isDark: isDark,
                  onAccept: _acceptPolicy,
                  onDecline: _declinePolicy,
                );
              } else {
                // 其他页：功能介绍页
                return _OnboardingPageWidget(
                  page: _pages[index - 1],
                  isDark: isDark,
                );
              }
            },
          ),

          // 顶部跳过按钮（仅在非隐私政策页显示）
          if (_currentPage > 0)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 24,
              child: TextButton(
                onPressed: _skipToEnd,
                child: Text(
                  '跳过',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

          // 底部控制区
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [
                // 页面指示器
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(totalPages, (index) {
                    Color indicatorColor;
                    if (index == 0) {
                      indicatorColor = Colors.blue; // 隐私政策页用蓝色
                    } else {
                      indicatorColor = _pages[index - 1].gradient[1];
                    }

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 8,
                      width: _currentPage == index ? 24 : 8,
                      decoration: BoxDecoration(
                        color: _currentPage == index
                            ? indicatorColor
                            : (isDark ? Colors.white30 : Colors.black26),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 40),

                // 底部按钮
                if (_currentPage == 0)
                  // 隐私政策页的按钮在页面内部显示，这里不重复
                  const SizedBox.shrink()
                else
                  // 其他页面显示"下一步"或"开始使用"按钮
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _pages[_currentPage - 1].gradient,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: _pages[_currentPage - 1].gradient[1].withOpacity(0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _nextPage,
                          borderRadius: BorderRadius.circular(16),
                          child: Center(
                            child: Text(
                              _currentPage == totalPages - 1 ? '开始使用' : '下一步',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}

class _OnboardingPageWidget extends StatelessWidget {
  final OnboardingPage page;
  final bool isDark;

  const _OnboardingPageWidget({
    Key? key,
    required this.page,
    required this.isDark,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 图标
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Opacity(
                  opacity: value,
                  child: child,
                ),
              );
            },
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: page.gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: page.gradient[1].withOpacity(0.3),
                    blurRadius: 40,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              child: Icon(
                page.icon,
                size: 70,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 60),

          // 标题
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOut,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 30 * (1 - value)),
                child: Opacity(
                  opacity: value,
                  child: child,
                ),
              );
            },
            child: Text(
              page.title,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),

          // 描述
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOut,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 30 * (1 - value)),
                child: Opacity(
                  opacity: value,
                  child: child,
                ),
              );
            },
            child: Text(
              page.description,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white70 : Colors.black54,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingPage {
  final IconData icon;
  final String title;
  final String description;
  final List<Color> gradient;

  OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.gradient,
  });
}

/// 隐私政策页面
class _PrivacyPolicyPage extends StatelessWidget {
  final bool isDark;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _PrivacyPolicyPage({
    Key? key,
    required this.isDark,
    required this.onAccept,
    required this.onDecline,
  }) : super(key: key);

  Future<String> _loadHtmlFromAssets() async {
    return await rootBundle.loadString('Assets/privacy_policy.html');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // 应用Logo
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 600),
              builder: (context, value, child) {
                return Transform.scale(
                  scale: 0.8 + (0.2 * value),
                  child: Opacity(
                    opacity: value,
                    child: child,
                  ),
                );
              },
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'Assets/icon.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),

            // 标题
            Text(
              '欢迎使用',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),

            // 副标题
            Text(
              '在开始使用前,请阅读并同意我们的隐私政策',
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.white70 : Colors.black54,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),

            // 隐私政策内容
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.1)
                      : Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.2)
                        : Colors.black.withOpacity(0.1),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: FutureBuilder<String>(
                    future: _loadHtmlFromAssets(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      } else if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Colors.red.shade300,
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                '无法加载隐私政策',
                                style: TextStyle(color: Colors.red),
                              ),
                            ],
                          ),
                        );
                      } else {
                        return WebViewWidget(
                          controller: WebViewController()
                            ..setJavaScriptMode(JavaScriptMode.unrestricted)
                            ..loadHtmlString(snapshot.data!)
                            ..setBackgroundColor(Colors.transparent),
                        );
                      }
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),

            // 按钮组
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDecline,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      side: BorderSide(
                        color: isDark ? Colors.white30 : Colors.black26,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      '拒绝',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Colors.blue, Colors.lightBlue],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onAccept,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          alignment: Alignment.center,
                          child: const Text(
                            '同意并继续',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
