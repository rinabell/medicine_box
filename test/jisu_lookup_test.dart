import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' show MockClient;
import 'package:medicine_box/services/jisu_lookup.dart';
import 'package:medicine_box/services/medicine_lookup.dart';

/// 选项4 极速数据：纯解析 + 错误分类 + 缓存，不依赖真实网络。
void main() {
  setUp(() => JisuLookup.clearCache());

  group('parseResponse - 详情', () {
    test('完整字段：药名/成分/说明书各就各位', () {
      const body = '''
      {"status":0,"msg":"ok","result":{
        "name":"蒙脱石散 (泻利停)",
        "ingredients":"本品每袋含蒙脱石3g，辅料为葡萄糖、香兰素。",
        "spec":"3g*12袋",
        "type":"散剂",
        "indication":"用于成人及儿童急、慢性腹泻。",
        "usage":"口服，成人每次1袋，一日3次。",
        "adverse_reaction":"少数人可产生轻度便秘。",
        "taboo":"尚不明确。",
        "attention":"治疗急性腹泻应注意纠正脱水。",
        "manufacturer":"哈药集团中药二厂",
        "approval_num":"国药准字H20093375",
        "instruction":"【成份】蒙脱石3g【适应症】急慢性腹泻",
        "prescription":2
      }}
      ''';
      final outcome = JisuLookup.parseResponse(body);
      expect(outcome.ok, true);
      expect(outcome.result!.name, '蒙脱石散 (泻利停)');
      expect(outcome.result!.ingredient, contains('蒙脱石3g'));
      expect(outcome.result!.leaflet, contains('适应症：用于成人及儿童急、慢性腹泻'));
      expect(outcome.result!.leaflet, contains('用法用量：口服'));
      expect(outcome.result!.leaflet, contains('批准文号：国药准字H20093375'));
      expect(outcome.result!.leaflet, contains('【成份】蒙脱石3g'));
      expect(outcome.result!.category, 'OTC');
    });

    test('result 是数组时取第一条', () {
      const body = '''
      {"status":0,"msg":"ok","result":[
        {"name":"布洛芬缓释胶囊","ingredients":"布洛芬"},
        {"name":"另一条"}
      ]}
      ''';
      final outcome = JisuLookup.parseResponse(body);
      expect(outcome.ok, true);
      expect(outcome.result!.name, '布洛芬缓释胶囊');
      expect(outcome.result!.ingredient, '布洛芬');
    });

    test('兼容英文别名 key（composition / instruction / dosage）', () {
      const body = '''
      {"status":0,"result":{
        "drug_name":"阿司匹林肠溶片",
        "composition":"乙酰水杨酸",
        "dosage":"一次1片",
        "manual":"饭前服用"
      }}
      ''';
      final outcome = JisuLookup.parseResponse(body);
      expect(outcome.result!.name, '阿司匹林肠溶片');
      expect(outcome.result!.ingredient, '乙酰水杨酸');
      expect(outcome.result!.leaflet, contains('用法用量：一次1片'));
      expect(outcome.result!.leaflet, contains('饭前服用'));
    });

    test('status 是字符串 "0" 也算成功', () {
      const body = '{"status":"0","result":{"name":"某药"}}';
      expect(JisuLookup.parseResponse(body).ok, true);
    });

    test('prescription=1 归为处方药', () {
      const body = '{"status":0,"result":{"name":"某药","prescription":1}}';
      expect(JisuLookup.parseResponse(body).result!.category, '处方药');
    });

    test('没有药名 → notFound', () {
      final outcome = JisuLookup.parseResponse('{"status":0,"result":{}}');
      expect(outcome.status, LookupStatus.notFound);
    });

    test('result 为空数组 → notFound', () {
      final outcome = JisuLookup.parseResponse(
        '{"status":0,"result":[]}',
      );
      expect(outcome.status, LookupStatus.notFound);
    });

    test('空结果字段不产生多余的"："', () {
      final outcome = JisuLookup.parseResponse(
        '{"status":0,"result":{"name":"某药","spec":"","attention":null}}',
      );
      expect(outcome.result!.leaflet, '');
    });

    test('非 JSON / 网关拦截的 HTML → badResponse', () {
      final outcome = JisuLookup.parseResponse('<html>验证</html>');
      expect(outcome.status, LookupStatus.badResponse);
    });
  });

  group('classifyError - 官方错误码', () {
    LookupOutcome err(String status, String msg) =>
        JisuLookup.classifyError({'status': status, 'msg': msg})!;

    test('101/102 AppKey 问题 → invalidKey，带控制台指引', () {
      expect(err('101', 'APPKEY为空').status, LookupStatus.invalidKey);
      final expired = err('102', 'APPKEY已过期');
      expect(expired.status, LookupStatus.invalidKey);
      expect(expired.hint, contains('jisuapi.com'));
    });

    test('103 无权限 → notSubscribed，提示实名认证', () {
      final outcome = err('103', 'APPKEY无请求此数据权限');
      expect(outcome.status, LookupStatus.notSubscribed);
      expect(outcome.hint, contains('实名'));
    });

    test('104/106 超次数 → quota', () {
      expect(err('104', '请求超过次数限制').status, LookupStatus.quota);
      final ip = err('106', 'IP请求超过限制');
      expect(ip.status, LookupStatus.quota);
      expect(ip.hint, contains('100'));
    });

    test('105 IP被禁止 → network', () {
      expect(err('105', 'IP被禁止').status, LookupStatus.network);
    });

    test('107/108 接口维护 → unknown', () {
      expect(err('107', '接口维护中').status, LookupStatus.unknown);
      expect(err('108', '接口已停用').status, LookupStatus.unknown);
    });

    test('201/202 参数错误 → badResponse', () {
      expect(err('201', '参数错误').status, LookupStatus.badResponse);
      expect(err('202', '详情ID为空').status, LookupStatus.badResponse);
    });

    test('203 没有信息 → notFound', () {
      expect(err('203', '没有信息').status, LookupStatus.notFound);
    });

    test('未知错误码按文案兜底', () {
      expect(err('999', '暂未收录').status, LookupStatus.notFound);
      expect(err('999', '服务器内部错误').status, LookupStatus.badResponse);
    });

    test('status=0 不报错', () {
      expect(
        JisuLookup.classifyError({'status': 0, 'msg': 'ok'}),
        isNull,
      );
    });
  });

  group('lookup - 请求构造与缓存', () {
    test('按条码查走 /medicine/detail，参数 appkey + barcode', () async {
      late Uri requested;
      final client = MockClient((request) async {
        requested = request.url;
        return http.Response(
          '{"status":0,"result":{"name":"蒙脱石散","ingredients":"蒙脱石"}}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final lookup = JisuLookup(appKey: 'k123', client: client);
      final outcome = await lookup.lookup(' 6920729170096 ');

      expect(outcome.ok, true);
      expect(outcome.result!.name, '蒙脱石散');
      expect(requested.path, '/medicine/detail');
      expect(requested.queryParameters['appkey'], 'k123');
      expect(requested.queryParameters['barcode'], '6920729170096');
    });

    test('没有 AppKey 不发请求', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      });
      final outcome = await JisuLookup(appKey: '', client: client).lookup(
        '6900388311184',
      );
      expect(outcome.status, LookupStatus.noKey);
      expect(called, false);
    });

    test('命中缓存时第二次不再发请求', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response(
          '{"status":0,"result":{"name":"缓存药"}}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final lookup = JisuLookup(appKey: 'k1', client: client);
      await lookup.lookup('6900388311184');
      await lookup.lookup('6900388311184');
      expect(calls, 1);
    });

    test('失败结果不缓存', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response(
          '{"status":203,"msg":"没有信息"}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final lookup = JisuLookup(appKey: 'k1', client: client);
      await lookup.lookup('6900388311184');
      await lookup.lookup('6900388311184');
      expect(calls, 2);
    });

    test('HTTP 500 → badResponse', () async {
      final client = MockClient(
        (_) async => http.Response('server error', 500),
      );
      final outcome = await JisuLookup(appKey: 'k1', client: client).lookup(
        '6900388311184',
      );
      expect(outcome.status, LookupStatus.badResponse);
    });
  });

  group('lookupByName - 两步查询', () {
    test('先 search 拿 medicine_id，再 detail 取说明书', () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/query')) {
          return http.Response(
            '{"status":0,"result":[{"medicine_id":"59","name":"阿司匹林肠溶片"}]}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          '{"status":0,"result":{"name":"阿司匹林肠溶片","instruction":"抗血小板"}}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final outcome = await JisuLookup(appKey: 'k1', client: client)
          .lookupByName('阿司匹林');
      expect(outcome.ok, true);
      expect(outcome.result!.name, '阿司匹林肠溶片');
      expect(outcome.result!.leaflet, contains('抗血小板'));
      expect(paths, ['/medicine/query', '/medicine/detail']);
    });

    test('空药名被拦下', () async {
      final outcome = await JisuLookup(appKey: 'k1').lookupByName('  ');
      expect(outcome.status, LookupStatus.invalidCode);
    });

    test('搜索无结果 → notFound，不发第二步', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response(
          '{"status":0,"result":[]}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final outcome = await JisuLookup(appKey: 'k1', client: client)
          .lookupByName('不存在的药XYZ');
      expect(outcome.status, LookupStatus.notFound);
      expect(calls, 1);
    });
  });

  test('真实案例：6920729170096 蒙脱石散能被解析（模拟接口返回）', () async {
    final body = jsonEncode({
      'status': 0,
      'msg': 'ok',
      'result': {
        'barcode': '6920729170096',
        'name': '蒙脱石散 (泻利停)',
        'ingredients': '本品每袋含蒙脱石3g，辅料为葡萄糖、香兰素、糖精钠。',
        'spec': '3g*12袋',
        'approval_num': '国药准字H20093375',
        'manufacturer': '哈药集团中药二厂',
        'indication': '用于成人及儿童急、慢性腹泻。',
      },
    });
    final outcome = JisuLookup.parseResponse(body);
    expect(outcome.ok, true);
    expect(outcome.result!.name, '蒙脱石散 (泻利停)');
    expect(outcome.result!.ingredient, contains('蒙脱石3g'));
  });
}
