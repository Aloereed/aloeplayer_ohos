import 'package:aloeplayer/widgets/library_toolbar_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('compact toolbar searches and clears within one row', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var searching = false;
    var query = '';
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: StatefulBuilder(builder: (context, setState) => Scaffold(
        appBar: AppBar(leading: const BackButton(), title: LibraryToolbarTitle(
          title: '文件夹名称很长的音频库', hint: '搜索音频', searching: searching,
          controller: controller, onChanged: (value) => query = value,
          onSearchChanged: (value) => setState(() => searching = value)),
          actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.add))]),
        body: const Text('文件内容'),
      )),
    )));
    final contentTop = tester.getTopLeft(find.text('文件内容')).dy;
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '中文歌曲');
    expect(query, '中文歌曲');
    expect(tester.getTopLeft(find.text('文件内容')).dy, contentTop);
    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pumpAndSettle();
    expect(query, isEmpty);
    expect(controller.text, isEmpty);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
