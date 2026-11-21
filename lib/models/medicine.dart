/// 一条药品档案。
///
/// 【核心设计】code 是数据库主键：扫到的编码就是这款药唯一不变的「身份证」。
/// 同一个码第二次被扫到时只做 count + 1，不再新建档案（需求②）。
/// 药名、成分、说明书、备注都属于这份档案，同款药共用，只填一次。
class Medicine {
  final String code;
  final String name;
  final String ingredient;
  final String leaflet;
  final String note;
  final int count;
  final String source; // 'remote' 联网查询 / 'manual' 手动填写

  /// 需求3：保质期列表，元素为 'yyyy-MM-dd'。
  /// 同一盒药可多次扫码录入多个日期，界面只显示最接近现在的一个。
  final List<String> expiryDates;

  final int createdAt;
  final int updatedAt;

  const Medicine({
    required this.code,
    required this.name,
    this.ingredient = '',
    this.leaflet = '',
    this.note = '',
    this.count = 1,
    this.source = 'manual',
    this.expiryDates = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        'code': code,
        'name': name,
        'ingredient': ingredient,
        'leaflet': leaflet,
        'note': note,
        'count': count,
        'source': source,
        // 逗号分隔存储；简单、可读、向后兼容（旧库没有这一列时由迁移补上）
        'expiry_dates': expiryDates.join(','),
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Medicine.fromMap(Map<String, Object?> map) => Medicine(
        code: map['code'] as String? ?? '',
        name: map['name'] as String? ?? '',
        ingredient: map['ingredient'] as String? ?? '',
        leaflet: map['leaflet'] as String? ?? '',
        note: map['note'] as String? ?? '',
        count: (map['count'] as num?)?.toInt() ?? 1,
        source: map['source'] as String? ?? 'manual',
        expiryDates: _parseExpiry(map['expiry_dates']),
        createdAt: (map['created_at'] as num?)?.toInt() ?? 0,
        updatedAt: (map['updated_at'] as num?)?.toInt() ?? 0,
      );

  static List<String> _parseExpiry(Object? raw) {
    if (raw == null) return const [];
    final value = raw.toString().trim();
    if (value.isEmpty) return const [];
    return value
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  Medicine copyWith({
    String? name,
    String? ingredient,
    String? leaflet,
    String? note,
    int? count,
    String? source,
    List<String>? expiryDates,
    int? updatedAt,
  }) =>
      Medicine(
        code: code,
        name: name ?? this.name,
        ingredient: ingredient ?? this.ingredient,
        leaflet: leaflet ?? this.leaflet,
        note: note ?? this.note,
        count: count ?? this.count,
        source: source ?? this.source,
        expiryDates: expiryDates ?? this.expiryDates,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
