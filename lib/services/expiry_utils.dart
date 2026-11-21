import '../models/medicine.dart';

/// 需求3：保质期核心算法（纯函数，便于单测）。
///
/// 数据用 'yyyy-MM-dd' 字符串存（SQLite 里以逗号分隔的一段文本保存）。
/// 用户可能在多个日期里录入，界面只显示「最接近今天」的那一个：
/// 先按与今天的绝对距离排序，距离相同优先未过期的。
class ExpiryUtils {
  ExpiryUtils._();

  /// 解析用户手输的年月日。支持 2027-5-6 / 2027/5/6 / 2027.5.6。
  /// 拒绝 8 位纯数字等含糊写法，避免把 20270506 误当成别的含义。
  static DateTime? parseDate(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    final match = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$').firstMatch(s);
    if (match == null) return null;
    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);
    if (year == null || month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    // 回读校验，排除 2-30、4-31 这类不存在的日期
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  static String format(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// 把输入规整为 'yyyy-MM-dd'，非法返回 null。
  static String? normalize(String input) {
    final date = parseDate(input);
    return date == null ? null : format(date);
  }

  /// 从一串逗号分隔的日期里挑出合法的，去重后返回。
  static List<String> parseMany(String input) {
    final parts = input.split(RegExp(r'[,，;；\s]+'));
    final result = <String>[];
    for (final part in parts) {
      final normalized = normalize(part);
      if (normalized != null && !result.contains(normalized)) {
        result.add(normalized);
      }
    }
    return result;
  }

  static DateTime? _dateOf(String? value) =>
      value == null ? null : parseDate(value);

  /// 多个保质期里「最接近现在」的那个。
  /// [now] 可注入以便测试固定日期；生产用当前时间。
  static DateTime? nearest(Iterable<String?>? dates, {DateTime? now}) {
    if (dates == null || dates.isEmpty) return null;
    final today = _dayOnly(now ?? DateTime.now());
    DateTime? best;
    int? bestDistance;
    for (final value in dates) {
      final date = _dateOf(value);
      if (date == null) continue;
      final distance = _dayOnly(date).difference(today).inDays.abs();
      final expired = _dayOnly(date).isBefore(today);
      final bestExpired =
          best != null && _dayOnly(best).isBefore(today);
      // 距离更近；距离相同时未过期优先
      if (best == null ||
          distance < bestDistance! ||
          (distance == bestDistance && expired != bestExpired && !expired)) {
        best = date;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// 只取日期部分（去掉时分秒），避免今天下午被当成「已过期」。
  static DateTime _dayOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// 单个日期是否过期：严格早于今天才算，今天当天有效。
  static bool isExpired(String? date, {DateTime? now}) {
    final parsed = _dateOf(date);
    if (parsed == null) return false;
    final today = _dayOnly(now ?? DateTime.now());
    return _dayOnly(parsed).isBefore(today);
  }

  /// 整盒药是否过期：以「最近的那个保质期」为准。
  static bool medicineExpired(Medicine m, {DateTime? now}) {
    final near = nearest(m.expiryDates, now: now);
    return near == null ? false : isExpired(format(near), now: now);
  }

  /// 首页标签文案。
  static String labelFor(Medicine m, {DateTime? now}) {
    final near = nearest(m.expiryDates, now: now);
    return near == null ? '' : '有效期至 ${format(near)}';
  }

  /// 首页排序：过期的药全部排前面；组内按保质期日期从早到晚排序
  /// （过期组＝过期越久越靠前；未过期组＝越早到期越靠前）；无保质期的最后。
  /// 返回新列表，不改动入参。
  static List<Medicine> sortForDisplay(List<Medicine> items, {DateTime? now}) {
    final effectiveNow = now ?? DateTime.now();
    final indexed = List<Medicine>.from(items);
    // Dart 的 sort 不稳定，用插入排序保证组内原顺序稳定
    final result = <Medicine>[];
    for (final item in indexed) {
      var insertAt = result.length;
      for (var i = 0; i < result.length; i++) {
        if (_comesBefore(item, result[i], effectiveNow)) {
          insertAt = i;
          break;
        }
      }
      result.insert(insertAt, item);
    }
    return result;
  }

  static bool _comesBefore(Medicine a, Medicine b, DateTime now) {
    final aNear = nearest(a.expiryDates, now: now);
    final bNear = nearest(b.expiryDates, now: now);
    final aExpired = aNear != null && isExpired(format(aNear), now: now);
    final bExpired = bNear != null && isExpired(format(bNear), now: now);
    if (aExpired != bExpired) return aExpired; // 过期优先
    if (aNear == null || bNear == null) {
      // 都没过期：有保质期的排在没有的前面
      if (aNear == null && bNear == null) return false;
      return aNear != null;
    }
    // 组内按保质期日期升序：过期药里过期越久（日期越早）越靠前；
    // 未过期药里越早到期（日期越早）越靠前。
    return _dayOnly(aNear).compareTo(_dayOnly(bNear)) <= 0;
  }
}
