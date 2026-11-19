import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_box/pages/api_source_config_page.dart';
import 'package:medicine_box/services/data_source.dart';
import 'package:medicine_box/services/medicine_lookup.dart';
import 'package:medicine_box/services/web_barcode_lookup.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('选项1 二级页回填已保存的 AppKey', (tester) async {
    SharedPreferences.setMockInitialValues({
      'medicine_lookup_appkey': 'abc123',
    });
    await tester.pumpWidget(const MaterialApp(
      home: ApiSourceConfigPage(source: DataSource.showapi),
    ));
    await pumpFrames(tester);

    expect(find.byKey(const Key('showapi_key_field')), findsOneWidget);
    expect(find.text('abc123'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    expect(find.text('测试条码接口'), findsOneWidget);
  });

  testWidgets('选项1 测试成功时显示查到的药名', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ApiSourceConfigPage(
        source: DataSource.showapi,
        onTest: (_) async => LookupOutcome.success(
          const LookupResult(name: '阿司匹林肠溶片', category: '药品'),
        ),
      ),
    ));
    await pumpFrames(tester);

    await tester.tap(find.byKey(const Key('test_primary_button')));
    await pumpFrames(tester);

    expect(find.text('测试成功'), findsOneWidget);
    expect(find.textContaining('阿司匹林肠溶片'), findsWidgets);
    expect(find.textContaining('1468 药品信息查询'), findsWidgets);
  });

  testWidgets('选项1 失败时显示原因与「怎么办」', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ApiSourceConfigPage(
        source: DataSource.showapi,
        onTest: (_) async => const LookupOutcome(
          LookupStatus.noKey,
          message: '还没有填写 AppKey',
          hint: '到 showapi 控制台复制 AppKey',
        ),
      ),
    ));
    await pumpFrames(tester);

    await tester.tap(find.byKey(const Key('test_primary_button')));
    await pumpFrames(tester);

    expect(find.text('测试未通过'), findsOneWidget);
    expect(find.textContaining('还没有填写 AppKey'), findsOneWidget);
    expect(find.textContaining('showapi 控制台'), findsWidgets);
  });

  testWidgets('选项1 两个测试按钮走不同的测试动作', (tester) async {
    final actions = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: ApiSourceConfigPage(
        source: DataSource.showapi,
        onTest: (action) async {
          actions.add(action);
          return const LookupOutcome(LookupStatus.notFound, message: '未收录');
        },
      ),
    ));
    await pumpFrames(tester);

    await tester.tap(find.byKey(const Key('test_primary_button')));
    await pumpFrames(tester);
    await tester.tap(find.text('测试条码接口'));
    await pumpFrames(tester);

    expect(actions, ['primary', 'barcode']);
  });

  testWidgets('选项2 二级页有接口地址 / AppKey 输入并回填默认地址', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ApiSourceConfigPage(source: DataSource.web),
    ));
    await pumpFrames(tester);

    expect(find.byKey(const Key('web_endpoint_field')), findsOneWidget);
    expect(find.byKey(const Key('web_key_field')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('web_endpoint_field')),
        matching: find.text(WebBarcodeLookup.defaultEndpoint),
      ),
      findsWidgets,
    );
    expect(find.text('测试查询'), findsOneWidget);
  });

  testWidgets('选项2 能填入自定义接口地址和 Key', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ApiSourceConfigPage(source: DataSource.web),
    ));
    await pumpFrames(tester);

    await tester.enterText(
        find.byKey(const Key('web_endpoint_field')),
        'https://example.com/drug?code={code}&key={key}');
    await tester.enterText(find.byKey(const Key('web_key_field')), 'my-token');
    await pumpFrames(tester);

    expect(find.text('https://example.com/drug?code={code}&key={key}'),
        findsOneWidget);
    expect(find.text('my-token'), findsOneWidget);
  });

  testWidgets('选项2 说明里如实提示 68api 的反爬', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ApiSourceConfigPage(source: DataSource.web),
    ));
    await pumpFrames(tester);
    await tester.scrollUntilVisible(
      find.textContaining('滑块验证'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('滑块验证'), findsWidgets);
    expect(find.textContaining('JSON 接口'), findsWidgets);
  });

  testWidgets('选项3 二级页展示本地库信息与测试 / 重建入口', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ApiSourceConfigPage(source: DataSource.local),
    ));
    await pumpFrames(tester);

    expect(find.text('本地药品条码库'), findsWidgets);
    expect(find.textContaining('47,722'), findsWidgets);
    expect(find.text('测试本地库'), findsOneWidget);
    expect(find.text('测试补充条目'), findsOneWidget);
    expect(find.text('重建本地库'), findsOneWidget);
    expect(find.text('设为当前数据源并返回'), findsOneWidget);
  });

  testWidgets('选项3 测试补充条目走 supplement 动作并显示蒙脱石散', (tester) async {
    final actions = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: ApiSourceConfigPage(
        source: DataSource.local,
        onTest: (action) async {
          actions.add(action);
          return LookupOutcome.success(
            const LookupResult(name: '蒙脱石散 (泻利停)', category: '药品'),
          );
        },
      ),
    ));
    await pumpFrames(tester);

    await tester.tap(find.byKey(const Key('test_supplement_button')));
    await pumpFrames(tester);

    expect(actions, ['supplement']);
    expect(find.text('测试成功'), findsOneWidget);
    expect(find.textContaining('蒙脱石散'), findsWidgets);
  });

  testWidgets('选项4 二级页有 AppKey 输入、回填与两个测试按钮', (tester) async {
    SharedPreferences.setMockInitialValues({
      'medicine_jisu_appkey': 'jisu-abc',
    });
    await tester.pumpWidget(const MaterialApp(
      home: ApiSourceConfigPage(source: DataSource.jisu),
    ));
    await pumpFrames(tester);

    expect(find.byKey(const Key('jisu_key_field')), findsOneWidget);
    expect(find.text('jisu-abc'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    expect(find.text('测试条码'), findsOneWidget);
  });

  testWidgets('选项4 两个测试按钮分别走 primary 与 jisu_barcode 动作',
      (tester) async {
    final actions = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: ApiSourceConfigPage(
        source: DataSource.jisu,
        onTest: (action) async {
          actions.add(action);
          return const LookupOutcome(
            LookupStatus.notFound,
            message: '未收录',
          );
        },
      ),
    ));
    await pumpFrames(tester);

    await tester.tap(find.byKey(const Key('test_primary_button')));
    await pumpFrames(tester);
    await tester.tap(find.byKey(const Key('jisu_barcode_button')));
    await pumpFrames(tester);

    expect(actions, ['primary', 'jisu_barcode']);
  });

  testWidgets('选项4 保存 AppKey 后返回并显示成功', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ApiSourceConfigPage(source: DataSource.jisu),
    ));
    await pumpFrames(tester);

    await tester.enterText(
      find.byKey(const Key('jisu_key_field')),
      'my-jisu-key',
    );
    await pumpFrames(tester);
    await tester.tap(find.text('保存并返回'));
    await pumpFrames(tester);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('medicine_jisu_appkey'), 'my-jisu-key');
  });
}
