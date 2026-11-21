import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_box/pages/scan_page.dart';

/// 需求2：扫码加药页面，除了「手动输入编码」，还要有「手动输入药名」。
/// 因为相机在测试环境不可用，这里只验证入口存在且文案正确；
/// 药名输入后的建档复用 MedicineEditPage（另有测试覆盖）。
void main() {
  testWidgets('扫码页同时提供手动输入编码和手动输入药名两个入口', (tester) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: ScanPage()));
    await tester.pump();

    expect(find.textContaining('手动输入编码'), findsWidgets);
    expect(find.textContaining('手动输入药名'), findsWidgets);
  });
}
