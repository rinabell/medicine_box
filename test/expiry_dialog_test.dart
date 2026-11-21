import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_box/widgets/expiry_dialog.dart';

/// 需求3：扫码后弹出保质期录入框
/// - 可输入具体年月日
/// - 有「跳过」按钮
/// - 支持一次输入多个日期（逗号分隔），只保留合法的
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String _result = '未选择';

  Future<void> open() async {
    final dates = await showExpiryDialog(context);
    if (!mounted) return;
    setState(() => _result = dates == null
        ? '取消'
        : dates.isEmpty
            ? '已跳过保质期'
            : '选择: ${dates.join(",")}');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(key: const Key('open'), onPressed: open, child: const Text('打开')),
              Text(_result),
            ],
          ),
        ),
      );
}

void main() {
  Future<void> pumpHost(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: _Host()));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }

  testWidgets('弹窗有日期输入框、确定和跳过', (tester) async {
    await pumpHost(tester);
    expect(find.byKey(const Key('expiry_field')), findsOneWidget);
    expect(find.text('确定'), findsOneWidget);
    expect(find.text('跳过'), findsOneWidget);
  });

  testWidgets('输入一个年月日点确定返回规整后的日期', (tester) async {
    await pumpHost(tester);
    await tester.enterText(find.byKey(const Key('expiry_field')), '2027/5/6');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('选择: 2027-05-06'), findsOneWidget);
  });

  testWidgets('点跳过返回空列表', (tester) async {
    await pumpHost(tester);
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();
    expect(find.text('已跳过保质期'), findsOneWidget);
  });

  testWidgets('一次输入多个日期（逗号分隔）只保留合法的', (tester) async {
    await pumpHost(tester);
    await tester.enterText(find.byKey(const Key('expiry_field')),
        '2026-12-01，2027-01-02, bad');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('选择: 2026-12-01,2027-01-02'), findsOneWidget);
  });

  testWidgets('全部非法时给出提示且不关闭', (tester) async {
    await pumpHost(tester);
    await tester.enterText(find.byKey(const Key('expiry_field')), 'abc');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.textContaining('日期格式'), findsOneWidget);
    expect(find.byKey(const Key('expiry_field')), findsOneWidget);
  });
}
