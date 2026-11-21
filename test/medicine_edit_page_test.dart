import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_box/models/medicine.dart';
import 'package:medicine_box/pages/medicine_edit_page.dart';
import 'package:medicine_box/services/medicine_lookup.dart';

/// 默认测试视口 800x600 放不下整张表单，底部「保存到药箱」会落在视口外，
/// tester.tap 会直接报找不到元素。这里换成手机长屏尺寸。
Future<void> pumpPage(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pump();
}

void main() {
  testWidgets('新建页不填药名时不能保存', (tester) async {
    await pumpPage(tester, const MedicineEditPage(code: '6901234567890'));

    await tester.tap(find.text('保存到药箱'));
    await tester.pump();

    expect(find.text('请填药名'), findsOneWidget);
  });

  testWidgets('件数填非数字时给出提示', (tester) async {
    await pumpPage(tester, const MedicineEditPage(code: '6901234567890'));

    // 先填药名，让校验走到件数那一项
    await tester.enterText(find.byType(TextFormField).first, '布洛芬');
    await tester.enterText(find.byType(TextFormField).last, '两盒');
    await tester.tap(find.text('保存到药箱'));
    await tester.pump();

    expect(find.text('请填数字'), findsOneWidget);
  });

  testWidgets('联网查到资料时会预填药名、成分和说明书', (tester) async {
    await pumpPage(
      tester,
      const MedicineEditPage(
        code: '6901234567890',
        suggestion: LookupResult(
          name: '布洛芬缓释胶囊',
          ingredient: '布洛芬',
          leaflet: '用法用量：一次1粒，一日2次',
          category: 'OTC',
        ),
      ),
    );

    expect(find.text('布洛芬缓释胶囊'), findsOneWidget);
    expect(find.text('布洛芬'), findsOneWidget);
    expect(find.text('用法用量：一次1粒，一日2次'), findsOneWidget);
    expect(find.textContaining('来源：自动查询'), findsOneWidget);
    expect(find.textContaining('OTC'), findsOneWidget);
  });

  testWidgets('查询失败原因显示在顶部，并提供「重新查询」', (tester) async {
    await pumpPage(
      tester,
      const MedicineEditPage(
        code: '6901234567890',
        lookupMessage: 'AppKey 无效，请到设置里检查',
      ),
    );

    expect(find.textContaining('AppKey 无效'), findsOneWidget);
    expect(find.text('重新查询'), findsOneWidget);
  });

  testWidgets('未订购 66-24 时显示「怎么办」指引', (tester) async {
    await pumpPage(
      tester,
      const MedicineEditPage(
        code: '6901234567890',
        lookupMessage: '[-1006] 此应用无权调用本接口\n请去 showapi 订购该接口资源包',
      ),
    );

    expect(find.textContaining('此应用无权调用本接口'), findsOneWidget);
    expect(find.textContaining('订购'), findsOneWidget);
  });

  testWidgets('提供免费的「按药名查说明书」入口', (tester) async {
    await pumpPage(tester, const MedicineEditPage(code: '6901234567890'));

    expect(find.textContaining('按药名查说明书'), findsOneWidget);
    expect(find.textContaining('免费药品库'), findsOneWidget);
  });

  testWidgets('编码为空时不显示重试入口', (tester) async {
    await pumpPage(tester, const MedicineEditPage());

    expect(find.text('重新查询'), findsNothing);
    expect(find.text('药名 *'), findsOneWidget);
    // 按药名补全不依赖编码，仍然可用
    expect(find.textContaining('按药名查说明书'), findsOneWidget);
  });

  testWidgets('扫码带来的保质期显示在编辑页，可保存', (tester) async {
    await pumpPage(
      tester,
      const MedicineEditPage(
        code: '6901234567890',
        initialExpiryDates: ['2027-05-06'],
      ),
    );

    expect(find.text('2027-05-06'), findsOneWidget);
  });

  testWidgets('编辑模式标题为「编辑药品」', (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await pumpPage(
      tester,
      MedicineEditPage(
        initial: Medicine(
          code: '6901',
          name: '布洛芬',
          createdAt: now,
          updatedAt: now,
        ),
      ),
    );

    expect(find.text('编辑药品'), findsOneWidget);
    expect(find.text('第一次见到这盒药'), findsNothing);
  });
}
