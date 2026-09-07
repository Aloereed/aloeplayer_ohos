import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:aloeplayer/widgets/onboarding_screen.dart';

class _WebPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(PlatformWebViewControllerCreationParams params) => _Controller(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(PlatformWebViewWidgetCreationParams params) => _WebWidget(params);
}
class _Controller extends PlatformWebViewController {
  _Controller(super.params) : super.implementation();
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
}
class _WebWidget extends PlatformWebViewWidget {
  _WebWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  testWidgets('privacy accept button is unobstructed with bottom system inset', (tester) async {
    WebViewPlatform.instance = _WebPlatform();
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [const Size(320, 640), const Size(412, 892)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(padding: const EdgeInsets.only(top: 24, bottom: 34)), child: child!),
        home: OnboardingScreen(onComplete: () {})));
      await tester.pumpAndSettle();
      final accept = find.text('同意并继续');
      expect(accept.hitTestable(), findsOneWidget);
      expect(tester.getRect(accept).bottom, lessThan(size.height - 34));
      expect(find.byType(Positioned), findsNothing);
      await tester.tap(accept);
      await tester.pumpAndSettle();
      expect(find.text('下一步'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
