import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_box/services/font_scale.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 需求1：字体四档可调（1/2/3/4），默认3档（比现状大一号左右）。
/// 2档=当前字号 1.0，3档要明显大于 1.0。
class _ScaleProbe extends StatelessWidget {
  const _ScaleProbe();

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(10);
    return Text('scale=${scale.toStringAsFixed(2)}');
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fontLevelNotifier.value = FontScaleSettings.defaultLevel;
  });

  group('FontScaleSettings 档位映射', () {
    test('只有四档，系数严格递增', () {
      expect(FontScaleSettings.levels, [1, 2, 3, 4]);
      final factors =
          FontScaleSettings.levels.map(FontScaleSettings.factorFor).toList();
      for (var i = 1; i < factors.length; i++) {
        expect(factors[i], greaterThan(factors[i - 1]));
      }
    });

    test('默认3档，且比2档（当前字号）大一号左右', () {
      expect(FontScaleSettings.defaultLevel, 3);
      final current = FontScaleSettings.factorFor(2);
      final defaultScale = FontScaleSettings.factorFor(3);
      expect(current, 1.0);
      expect(defaultScale, greaterThan(current));
      expect(defaultScale, lessThan(1.35)); // 大一两号，不要过大
    });

    test('非法档位回退默认3档', () {
      for (final bad in [0, 5, -1, 99]) {
        expect(FontScaleSettings.normalize(bad), 3);
      }
      expect(FontScaleSettings.normalize(null), 3);
      expect(FontScaleSettings.factorFor(99),
          FontScaleSettings.factorFor(FontScaleSettings.defaultLevel));
    });

    test('档位文案包含数字，默认档标注', () {
      expect(FontScaleSettings.labelOf(1), contains('1'));
      expect(FontScaleSettings.labelOf(4), contains('4'));
      expect(FontScaleSettings.labelOf(3), contains('默认'));
    });
  });

  group('FontScaleSettings 本机存储', () {
    test('保存后能读回', () async {
      await FontScaleSettings.save(4);
      expect(await FontScaleSettings.current(), 4);
    });

    test('没存过返回默认3档', () async {
      expect(await FontScaleSettings.current(), 3);
    });

    test('存储里的非法值回退默认3档', () async {
      SharedPreferences.setMockInitialValues({FontScaleSettings.storageKey: 77});
      expect(await FontScaleSettings.current(), 3);
    });
  });

  group('FontScaleScope 实际缩放', () {
    testWidgets('切档后文字真的变大', (tester) async {
      fontLevelNotifier.value = 2;
      await tester.pumpWidget(const MaterialApp(home: FontScaleScope(child: _ScaleProbe())));
      expect(find.text('scale=10.00'), findsOneWidget);

      fontLevelNotifier.value = 3;
      await tester.pump();
      expect(find.text('scale=11.50'), findsOneWidget);

      fontLevelNotifier.value = 1;
      await tester.pump();
      expect(find.text('scale=9.00'), findsOneWidget);
    });
  });
}
