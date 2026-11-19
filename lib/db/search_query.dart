/// 搜索条件的纯函数构造器。
///
/// 抽出来是为了能单测「模糊 / 精准」两套 SQL 以及 `%`/`_` 转义，
/// 不需要真的打开数据库。
class SearchQuery {
  final String where;
  final List<Object?> args;

  const SearchQuery(this.where, this.args);

  bool get isEmpty => where.isEmpty;

  /// 需求④：
  /// - 模糊：药名 / 成分 / 说明书 / 备注 / 编码 包含关键词即命中。
  /// - 精准：药名 / 成分 / 备注 / 编码 完全一致；说明书用 instr 做
  ///   「精确连续短语」匹配（说明书很长，要求全文相等并不现实）。
  static SearchQuery build(String keyword, {required bool exact}) {
    final kw = keyword.trim();
    if (kw.isEmpty) return const SearchQuery('', <Object?>[]);

    if (exact) {
      return SearchQuery(
        '(name = ? OR ingredient = ? OR note = ? OR code = ? '
        'OR instr(leaflet, ?) > 0)',
        <Object?>[kw, kw, kw, kw, kw],
      );
    }

    // 先把用户输入的 % 和 _ 转义，防止被 SQLite 当成通配符
    final escaped = kw
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    final like = '%$escaped%';

    return SearchQuery(
      "("
      "name LIKE ? ESCAPE '\\' OR "
      "ingredient LIKE ? ESCAPE '\\' OR "
      "leaflet LIKE ? ESCAPE '\\' OR "
      "note LIKE ? ESCAPE '\\' OR "
      "code LIKE ? ESCAPE '\\'"
      ")",
      <Object?>[like, like, like, like, like],
    );
  }
}
