import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_box/models/medicine.dart';
import 'package:medicine_box/services/expiry_utils.dart';

/// 需求3：保质期核心算法（纯函数，必须单测）
/// - 解析用户输入的年月日，拒绝非法日期
/// - 多个保质期里只挑「最接近现在」的那个
/// - 过期判定：日期严格早于今天（今天当天不算过期）
/// - 过期药优先排序
void main() {
  final now = DateTime(2026, 11, 20, 15, 30); // 固定「今天」，避免测试跑飞

  Medicine med(String code, List<String> dates, {int updatedAt = 1}) => Medicine(
        code: code,
        name: '药$code',
        expiryDates: dates,
        createdAt: 1,
        updatedAt: updatedAt,
      );

  group('日期解析与格式化', () {
    test('接受 yyyy-MM-dd', () {
      expect(ExpiryUtils.parseDate('2027-05-20'), DateTime(2027, 5, 20));
    });

    test('接受 yyyy/M/d 与 yyyy.M.d 等常见写法', () {
      expect(ExpiryUtils.parseDate('2027/5/6'), DateTime(2027, 5, 6));
      expect(ExpiryUtils.parseDate('2027.5.6'), DateTime(2027, 5, 6));
    });

    test('拒绝非法日期和空串', () {
      for (final bad in ['', '  ', 'abc', '2027-13-01', '2027-02-30', '20270520']) {
        expect(ExpiryUtils.parseDate(bad), isNull, reason: '$bad 应被拒绝');
      }
    });

    test('格式化固定为 yyyy-MM-dd', () {
      expect(ExpiryUtils.format(DateTime(2027, 5, 6)), '2027-05-06');
    });

    test('normalize 把输入规整，非法返回 null', () {
      expect(ExpiryUtils.normalize('2027/5/6'), '2027-05-06');
      expect(ExpiryUtils.normalize('2027-02-30'), isNull);
    });
  });

  group('最接近现在的保质期', () {
    test('多个日期里挑距离今天最近的一个', () {
      final dates = ['2026-11-18', '2026-12-01', '2027-06-01'];
      expect(ExpiryUtils.nearest(dates, now: now), DateTime(2026, 11, 18));
    });

    test('未来的近期比遥远的过期日更近', () {
      final dates = ['2020-01-01', '2026-11-25'];
      expect(ExpiryUtils.nearest(dates, now: now), DateTime(2026, 11, 25));
    });

    test('距离相同（一前一后）时优先取未过期的', () {
      final dates = ['2026-11-19', '2026-11-21'];
      expect(ExpiryUtils.nearest(dates, now: now), DateTime(2026, 11, 21));
    });

    test('空列表、全非法、null 都返回 null', () {
      expect(ExpiryUtils.nearest([], now: now), isNull);
      expect(ExpiryUtils.nearest(['abc', ''], now: now), isNull);
      expect(ExpiryUtils.nearest(null, now: now), isNull);
    });
  });

  group('过期判定', () {
    test('早于今天算过期', () {
      expect(ExpiryUtils.isExpired('2026-11-19', now: now), isTrue);
      expect(ExpiryUtils.isExpired('2020-01-01', now: now), isTrue);
    });

    test('今天和以后都不算过期', () {
      expect(ExpiryUtils.isExpired('2026-11-20', now: now), isFalse);
      expect(ExpiryUtils.isExpired('2026-11-21', now: now), isFalse);
    });

    test('无效日期不算过期', () {
      expect(ExpiryUtils.isExpired('abc', now: now), isFalse);
      expect(ExpiryUtils.isExpired(null, now: now), isFalse);
    });

    test('按最近保质期判断整盒药是否过期', () {
      final expired = med('a', ['2026-11-01', '2026-11-19']); // 最近=19，过期
      final fresh = med('b', ['2020-01-01', '2027-01-01']); // 最近=明年，未过期
      final none = med('c', []);
      expect(ExpiryUtils.medicineExpired(expired, now: now), isTrue);
      expect(ExpiryUtils.medicineExpired(fresh, now: now), isFalse);
      expect(ExpiryUtils.medicineExpired(none, now: now), isFalse);
    });
  });

  group('首页排序：过期的药优先', () {
    test('过期药全部排在未过期药前面', () {
      final list = [
        med('fresh1', ['2027-01-01']),
        med('expired1', ['2026-01-01']),
        med('fresh2', ['2026-12-25']),
        med('expired2', ['2026-10-01']),
        med('none', []),
      ];
      final sorted = ExpiryUtils.sortForDisplay(list, now: now);
      // 组内按日期从早到晚：过期组「过期越久越靠前」（expired1 在 expired2 前）；
      // 未过期组越早到期越靠前（fresh2 在 fresh1 前）；无保质期最后。
      expect(sorted.map((m) => m.code).toList(),
          ['expired1', 'expired2', 'fresh2', 'fresh1', 'none']);
    });

    test('过期组内过期越久越靠前', () {
      final list = [
        med('near', ['2026-01-01']), // 过期约 20 天
        med('far', ['2020-01-01']),  // 过期约 7 年，应排最前
      ];
      final sorted = ExpiryUtils.sortForDisplay(list, now: now);
      expect(sorted.map((m) => m.code).toList(), ['far', 'near']);
    });

    test('不改原列表（返回新列表）', () {
      final list = [med('a', ['2020-01-01']), med('b', ['2027-01-01'])];
      ExpiryUtils.sortForDisplay(list, now: now);
      expect(list.first.code, 'a');
    });
  });
}
