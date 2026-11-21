import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_box/models/medicine.dart';
import 'package:medicine_box/services/medicine_lookup.dart';

void main() {
  group('Medicine 数据模型', () {
    test('toMap / fromMap 往返一致', () {
      const m = Medicine(
        code: '6901234567890',
        name: '布洛芬缓释胶囊',
        ingredient: '布洛芬',
        leaflet: '功能主治：发热',
        note: '放在客厅抽屉',
        count: 3,
        source: 'remote',
        expiryDates: ['2026-12-01', '2027-06-15'],
        createdAt: 1000,
        updatedAt: 2000,
      );

      final restored = Medicine.fromMap(m.toMap());
      expect(restored.code, '6901234567890');
      expect(restored.name, '布洛芬缓释胶囊');
      expect(restored.ingredient, '布洛芬');
      expect(restored.leaflet, '功能主治：发热');
      expect(restored.note, '放在客厅抽屉');
      expect(restored.count, 3);
      expect(restored.source, 'remote');
      expect(restored.expiryDates, ['2026-12-01', '2027-06-15']);
      expect(restored.createdAt, 1000);
      expect(restored.updatedAt, 2000);
    });

    test('fromMap 对缺失字段给出安全默认值', () {
      final m = Medicine.fromMap({'code': '6901', 'name': '测试药'});
      expect(m.code, '6901');
      expect(m.name, '测试药');
      expect(m.ingredient, '');
      expect(m.leaflet, '');
      expect(m.note, '');
      expect(m.count, 1);
      expect(m.source, 'manual');
      expect(m.expiryDates, isEmpty);
      expect(m.createdAt, 0);
      expect(m.updatedAt, 0);
    });

    test('旧数据没有 expiry_dates 字段时安全退化为空', () {
      final m = Medicine.fromMap({
        'code': '6901',
        'name': '老药',
        'expiry_dates': null,
      });
      expect(m.expiryDates, isEmpty);
    });

    test('count 存成 double 也能转回 int', () {
      final m = Medicine.fromMap({
        'code': '6901',
        'name': '测试药',
        'count': 2.0,
        'created_at': 1.0,
        'updated_at': 2.0,
      });
      expect(m.count, 2);
      expect(m.createdAt, 1);
      expect(m.updatedAt, 2);
    });

    test('copyWith 只改指定字段，code 保持不变', () {
      const m = Medicine(
        code: '6901',
        name: '旧名字',
        note: '旧备注',
        count: 1,
        createdAt: 100,
        updatedAt: 100,
      );
      final updated = m.copyWith(
          name: '新名字', count: 5, updatedAt: 200,
          expiryDates: const ['2028-01-01']);
      expect(updated.code, '6901');
      expect(updated.name, '新名字');
      expect(updated.note, '旧备注');
      expect(updated.count, 5);
      expect(updated.createdAt, 100);
      expect(updated.updatedAt, 200);
      expect(updated.expiryDates, ['2028-01-01']);
    });
  });

  group('LookupResult / LookupOutcome', () {
    test('默认分类为空，不被当成非药品', () {
      const r = LookupResult(name: '布洛芬');
      expect(r.category, '');
      expect(r.isNonMedicine, isFalse);
    });

    test('分类含「非药品」时给出提示标记', () {
      const r = LookupResult(name: '某珍珠膏', category: '非药品');
      expect(r.isNonMedicine, isTrue);
    });

    test('OTC 药品不会被误判为非药品', () {
      const r = LookupResult(name: '布洛芬', category: 'OTC');
      expect(r.isNonMedicine, isFalse);
    });

    test('success 工厂会带上药名提示', () {
      final o = LookupOutcome.success(const LookupResult(name: '布洛芬'));
      expect(o.ok, isTrue);
      expect(o.result?.name, '布洛芬');
      expect(o.message, contains('布洛芬'));
    });

    test('失败状态 ok 为 false', () {
      const o = LookupOutcome(LookupStatus.notFound, message: '未收录');
      expect(o.ok, isFalse);
      expect(o.result, isNull);
      expect(o.message, '未收录');
    });

    test('noKey 属于正常降级，不是异常', () {
      const o = LookupOutcome(LookupStatus.noKey, message: '未配置');
      expect(o.ok, isFalse);
      expect(o.status, LookupStatus.noKey);
    });
  });
}
