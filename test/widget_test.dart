import 'package:flutter_test/flutter_test.dart';

import 'package:medicine_box/models/medicine.dart';

void main() {
  test('药品档案序列化后字段保持一致', () {
    const m = Medicine(
      code: '6901234567890',
      name: '示例药',
      ingredient: '布洛芬',
      leaflet: '功能主治：发热',
      note: '放在客厅抽屉',
      count: 3,
      createdAt: 1000,
      updatedAt: 2000,
    );

    final restored = Medicine.fromMap(m.toMap());
    expect(restored.code, '6901234567890');
    expect(restored.name, '示例药');
    expect(restored.count, 3);
    expect(restored.note, '放在客厅抽屉');
  });
}
