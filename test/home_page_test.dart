import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_box/models/medicine.dart';
import 'package:medicine_box/pages/home_page.dart';

/// 需求3：一级页面（首页列表）显示保质期
/// - 显示在药品数量旁边
/// - 过期：红色 + 加粗；未过期：黑色
/// - 排序：过期的药全部排前面，组内过期越久越靠前
void main() {
  Medicine med(String code, String name, List<String> dates, {int updatedAt = 1}) =>
      Medicine(
        code: code,
        name: name,
        expiryDates: dates,
        createdAt: 1,
        updatedAt: updatedAt,
      );

  Future<void> pumpHome(WidgetTester tester, List<Medicine> meds) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(itemsOverride: meds)),
    );
    await tester.pump();
  }

  List<String> titles(WidgetTester tester) => tester.widgetList<Text>(find.byType(Text))
      .map((w) => w.data)
      .where((s) => s != null)
      .cast<String>()
      .toList();

  testWidgets('过期药排在列表最前面', (tester) async {
    // updated_at 故意打乱，证明排序是按保质期而不是按更新时间
    await pumpHome(tester, [
      med('fresh', '未过期药', ['2027-12-01'], updatedAt: 500),
      med('expired', '已过期药', ['2020-01-01'], updatedAt: 100),
      med('none', '无保质期药', [], updatedAt: 900),
    ]);

    final list = titles(tester);
    final expiredAt = list.indexOf('已过期药');
    expect(expiredAt, greaterThanOrEqualTo(0));
    expect(expiredAt, lessThan(list.indexOf('未过期药')));
    expect(expiredAt, lessThan(list.indexOf('无保质期药')));
  });

  testWidgets('过期越久的药排在过期较近的药前面', (tester) async {
    await pumpHome(tester, [
      med('recent', '刚过期药', ['2026-10-01']),
      med('ancient', '过期很久药', ['2020-01-01']),
    ]);

    final list = titles(tester);
    expect(list.indexOf('过期很久药'), lessThan(list.indexOf('刚过期药')));
  });

  testWidgets('过期保质期红色加粗，未过期黑色普通', (tester) async {
    await pumpHome(tester, [
      med('expired', '已过期药', ['2020-01-01']),
      med('fresh', '未过期药', ['2027-12-01']),
    ]);

    final expired = tester.widget<Text>(find.byKey(const Key('expiry_expired')));
    final fresh = tester.widget<Text>(find.byKey(const Key('expiry_fresh')));

    expect(expired.style?.color, Colors.red);
    expect(expired.style?.fontWeight, FontWeight.bold);
    expect(fresh.style?.color, Colors.black);
    expect(fresh.style?.fontWeight, isNot(FontWeight.bold));
  });

  testWidgets('显示的日期是多个保质期里最接近今天的一个', (tester) async {
    await pumpHome(tester, [
      med('multi', '多保质期药', ['2020-01-01', '2027-01-15']),
    ]);

    final text = tester.widget<Text>(find.byKey(const Key('expiry_multi')));
    // 当前时间附近，2027-01-15 一定是最近的未来日期
    expect(text.data, '有效期至 2027-01-15');
  });

  testWidgets('没有保质期的药不显示保质期标签', (tester) async {
    await pumpHome(tester, [med('none', '无保质期药', [])]);

    expect(find.byKey(const Key('expiry_none')), findsNothing);
  });
}
