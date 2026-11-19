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
        createdAt: (map['created_at'] as num?)?.toInt() ?? 0,
        updatedAt: (map['updated_at'] as num?)?.toInt() ?? 0,
      );

  Medicine copyWith({
    String? name,
    String? ingredient,
    String? leaflet,
    String? note,
    int? count,
    String? source,
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
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
