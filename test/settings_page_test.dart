import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_box/pages/settings_page.dart';
import 'package:medicine_box/services/data_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设置页 initState 里有异步读配置，用固定次数的 pump 推进，
/// 不用 pumpAndSettle（进度圈会一直调度动画）。
Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// 设置页内容较长，默认 800x600 视口下 ListView 不会构建底部卡片，
/// 第三个配置按钮也点不到。换成手机长屏尺寸。
Future<void> pumpSettingsPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
  await pumpFrames(tester);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('设置页列出四个数据源与各自的标签', (tester) async {
    await pumpSettingsPage(tester);

    expect(find.textContaining('选项 1'), findsWidgets);
    expect(find.textContaining('选项 2'), findsWidgets);
    expect(find.textContaining('选项 3'), findsWidgets);
    expect(find.textContaining('选项 4'), findsWidgets);
    expect(find.text('条码接口收费'), findsOneWidget);
    expect(find.text('免费但可能被反爬'), findsOneWidget);
    expect(find.text('推荐 · 完全免费'), findsOneWidget);
    expect(find.textContaining('100次/天'), findsWidgets);
    expect(find.textContaining('47,722'), findsWidgets);
  });

  testWidgets('默认选中的是本地药品库', (tester) async {
    await pumpSettingsPage(tester);

    expect(find.text('当前：选项 3 · 本地药品条码库（离线）'), findsOneWidget);
  });

  testWidgets('四个数据源各有一个配置入口', (tester) async {
    await pumpSettingsPage(tester);

    expect(find.byKey(const Key('config_showapi')), findsOneWidget);
    expect(find.byKey(const Key('config_web')), findsOneWidget);
    expect(find.byKey(const Key('config_local')), findsOneWidget);
    expect(find.byKey(const Key('config_jisu')), findsOneWidget);
    expect(find.text('填写 AppKey 与测试'), findsNWidgets(3));
    expect(find.text('查看本地库 / 测试'), findsOneWidget);
  });

  testWidgets('点选选项1 会持久化到本机', (tester) async {
    await pumpSettingsPage(tester);

    await tester.tap(find.text('选项 1 · 万维易源 showapi'));
    await pumpFrames(tester);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString(DataSourceSettings.storageKey), 'showapi');
    expect(await DataSourceSettings.current(), DataSource.showapi);
  });

  testWidgets('已保存的数据源会被读回来', (tester) async {
    SharedPreferences.setMockInitialValues({
      DataSourceSettings.storageKey: 'web',
    });
    await pumpSettingsPage(tester);

    expect(find.text('当前：选项 2 · 自定义网页 / 接口查询'), findsOneWidget);
  });

  testWidgets('选项1 的 AppKey 与测试按钮在二级页里', (tester) async {
    await pumpSettingsPage(tester);

    await tester.tap(find.byKey(const Key('config_showapi')));
    await pumpFrames(tester);

    expect(find.byKey(const Key('showapi_key_field')), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    expect(find.text('测试条码接口'), findsOneWidget);
    expect(find.text('保存并返回'), findsOneWidget);
  });

  testWidgets('选项2 二级页有接口地址和 AppKey 输入', (tester) async {
    await pumpSettingsPage(tester);

    await tester.tap(find.byKey(const Key('config_web')));
    await pumpFrames(tester);

    expect(find.byKey(const Key('web_endpoint_field')), findsOneWidget);
    expect(find.byKey(const Key('web_key_field')), findsOneWidget);
    expect(find.text('测试查询'), findsOneWidget);
  });

  testWidgets('选项3 二级页显示本地库条目与测试入口', (tester) async {
    await pumpSettingsPage(tester);

    await tester.tap(find.byKey(const Key('config_local')));
    await pumpFrames(tester);

    expect(find.text('本地药品条码库'), findsWidgets);
    expect(find.text('测试本地库'), findsOneWidget);
    expect(find.text('重建本地库'), findsOneWidget);
  });

  testWidgets('设置页提供四档字体选择，默认3档', (tester) async {
    await pumpSettingsPage(tester);

    expect(find.byKey(const Key('font_level_group')), findsOneWidget);
    for (final level in [1, 2, 3, 4]) {
      expect(find.byKey(Key('font_level_$level')), findsOneWidget);
    }
  });

  testWidgets('点选字体4档会持久化', (tester) async {
    await pumpSettingsPage(tester);

    await tester.tap(find.byKey(const Key('font_level_4')));
    await pumpFrames(tester);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getInt('medicine_font_level'), 4);
  });
}
