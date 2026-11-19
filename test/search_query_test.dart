import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_box/db/search_query.dart';

void main() {
  group('SearchQuery.build - 空关键词', () {
    test('空字符串返回空查询', () {
      expect(SearchQuery.build('', exact: false).isEmpty, isTrue);
    });

    test('纯空格返回空查询', () {
      expect(SearchQuery.build('   ', exact: true).isEmpty, isTrue);
    });
  });

  group('SearchQuery.build - 模糊模式', () {
    test('覆盖 药名/成分/说明书/备注/编码 五个字段', () {
      final q = SearchQuery.build('布洛芬', exact: false);
      expect(q.where, contains('name LIKE'));
      expect(q.where, contains('ingredient LIKE'));
      expect(q.where, contains('leaflet LIKE'));
      expect(q.where, contains('note LIKE'));
      expect(q.where, contains('code LIKE'));
      expect(q.args.length, 5);
    });

    test('关键词包成 %keyword%', () {
      final q = SearchQuery.build('布洛芬', exact: false);
      expect(q.args.first, '%布洛芬%');
    });

    test('百分号被转义，不会变成通配符', () {
      final q = SearchQuery.build('50%', exact: false);
      expect(q.args.first, r'%50\%%');
    });

    test('下划线被转义，不会变成单字符通配符', () {
      final q = SearchQuery.build('a_b', exact: false);
      expect(q.args.first, r'%a\_b%');
    });

    test('反斜杠本身也会被转义', () {
      final q = SearchQuery.build(r'a\b', exact: false);
      expect(q.args.first, r'%a\\b%');
    });

    test('SQL 里声明了 ESCAPE', () {
      final q = SearchQuery.build('x', exact: false);
      expect(q.where, contains('ESCAPE'));
    });

    test('关键词两端空白会被 trim', () {
      final q = SearchQuery.build('  布洛芬  ', exact: false);
      expect(q.args.first, '%布洛芬%');
    });
  });

  group('SearchQuery.build - 精准模式', () {
    test('药名/成分/备注/编码用完全相等', () {
      final q = SearchQuery.build('布洛芬', exact: true);
      expect(q.where, contains('name = ?'));
      expect(q.where, contains('ingredient = ?'));
      expect(q.where, contains('note = ?'));
      expect(q.where, contains('code = ?'));
    });

    test('说明书用 instr 精确短语匹配', () {
      final q = SearchQuery.build('布洛芬', exact: true);
      expect(q.where, contains('instr(leaflet, ?) > 0'));
    });

    test('参数数量与占位符一致', () {
      final q = SearchQuery.build('布洛芬', exact: true);
      expect(q.args.length, 5);
      expect(q.args.every((a) => a == '布洛芬'), isTrue);
    });

    test('精准模式不加百分号', () {
      final q = SearchQuery.build('布洛芬', exact: true);
      expect(q.args.first, '布洛芬');
    });

    test('精准模式不使用 LIKE', () {
      final q = SearchQuery.build('布洛芬', exact: true);
      expect(q.where.contains('LIKE'), isFalse);
    });
  });
}
