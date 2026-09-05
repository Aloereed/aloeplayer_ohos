import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/widgets/empty_state_widget.dart';

void main() {
  testWidgets('empty state renders supplied action', (tester) async {
    var clicked = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: EmptyStateWidget(icon: Icons.video_library, title: '视频库为空', message: '导入媒体后即可播放', actionLabel: '添加媒体', onActionPressed: () => clicked = true))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加媒体'));
    expect(clicked, isTrue);
  });
}
