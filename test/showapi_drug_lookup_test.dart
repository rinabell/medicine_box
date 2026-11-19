import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medicine_box/services/medicine_lookup.dart';
import 'package:medicine_box/services/showapi_drug_lookup.dart';

/// 依据官方 1468-4 文档返回示例精简（去掉了大量「尚不明确」字段）。
String okBody() => jsonEncode({
      'showapi_res_code': 0,
      'showapi_res_error': '',
      'showapi_res_id': 'ce135f6739294c63be0c021b76b6fbff',
      'showapi_res_body': {
        'ret_code': '0',
        'msg': '查询成功！',
        'page': 1,
        'maxResult': 10,
        'count': 1,
        'drugList': [
          {
            'drugName': '同仁堂 泻肝安神丸',
            'tymc': '泻肝安神丸',
            'spmc': '',
            'zycf': '龙胆、黄芩、栀子',
            'syz': '清肝泻火，重镇安神。用于失眠，心烦。',
            'yfyl': '口服。一次6克，一日2次。',
            'jj': '外感发热患者忌服',
            'zysx': '本品宜饭后服',
            'pzwh': '国药准字Z11020957',
            'manu': '北京同仁堂制药有限公司',
            'fl': '中成药',
            'gg': '6g*12袋',
            'blfy': '尚不明确',
            'xz': '',
            'etyy': '尚不明确',
            'zc': 'null',
          }
        ],
        'pageSize': 1,
      },
    });

http.Response jsonResponse(String body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(body), status);

void main() {
  group('1468-4 返回解析（官方 YAML 字段）', () {
    test('解析出药名、主要成分、药品分类', () {
      final o = ShowapiDrugLookup.parseResponse(okBody());
      expect(o.ok, isTrue);
      expect(o.result!.name, '同仁堂 泻肝安神丸');
      expect(o.result!.ingredient, '龙胆、黄芩、栀子');
      expect(o.result!.category, '中成药');
      expect(o.result!.isNonMedicine, isFalse);
    });

    test('说明书由官方字段拼成，能被全文搜索命中', () {
      final leaflet =
          ShowapiDrugLookup.parseResponse(okBody()).result!.leaflet;
      expect(leaflet, contains('适应症 / 功能主治：清肝泻火'));
      expect(leaflet, contains('用法用量：口服。一次6克，一日2次。'));
      expect(leaflet, contains('禁忌：外感发热患者忌服'));
      expect(leaflet, contains('批准文号：国药准字Z11020957'));
      expect(leaflet, contains('生产企业：北京同仁堂制药有限公司'));
      expect(leaflet, contains('规格：6g*12袋'));
    });

    test('空值 / null / 尚不明确 不会污染说明书', () {
      final leaflet =
          ShowapiDrugLookup.parseResponse(okBody()).result!.leaflet;
      expect(leaflet, isNot(contains('尚不明确')));
      expect(leaflet, isNot(contains('性状：')));
      expect(leaflet, isNot(contains('贮藏：null')));
    });

    test('drugName 缺失时退回通用名称 tymc', () {
      final raw = jsonDecode(okBody());
      (raw['showapi_res_body']['drugList'][0] as Map)['drugName'] = '';
      final o = ShowapiDrugLookup.parseResponse(jsonEncode(raw));
      expect(o.result!.name, '泻肝安神丸');
    });

    test('res_body 被序列化成字符串时也能解析', () {
      final raw = jsonDecode(okBody());
      final o = ShowapiDrugLookup.parseResponse(jsonEncode({
        'showapi_res_code': 0,
        'showapi_res_body': jsonEncode(raw['showapi_res_body']),
      }));
      expect(o.ok, isTrue);
    });

    test('ret_code 非 0 → 未找到，并带出 msg', () {
      final o = ShowapiDrugLookup.parseResponse(jsonEncode({
        'showapi_res_code': 0,
        'showapi_res_body': {'ret_code': '-1', 'msg': '查询失败'},
      }));
      expect(o.status, LookupStatus.notFound);
      expect(o.message, contains('查询失败'));
    });

    test('drugList 为空 → 未找到，并提示换通用名', () {
      final o = ShowapiDrugLookup.parseResponse(jsonEncode({
        'showapi_res_code': 0,
        'showapi_res_body': {'ret_code': '0', 'msg': '查询成功！', 'drugList': []},
      }));
      expect(o.status, LookupStatus.notFound);
      expect(o.hint, contains('通用名'));
    });

    test('没有药名 → 未找到', () {
      final raw = jsonDecode(okBody());
      final drug = raw['showapi_res_body']['drugList'][0] as Map;
      drug['drugName'] = '';
      drug['tymc'] = '';
      drug['spmc'] = '';
      final o = ShowapiDrugLookup.parseResponse(jsonEncode(raw));
      expect(o.status, LookupStatus.notFound);
    });

    test('-1006 未订购 → notSubscribed，指引里带 1468', () {
      final o = ShowapiDrugLookup.parseResponse(jsonEncode({
        'showapi_res_code': -1006,
        'showapi_res_error': '此应用无权调用本接口',
        'showapi_res_body': {},
      }));
      expect(o.status, LookupStatus.notSubscribed);
      expect(o.hint, contains('1468'));
    });

    test('返回 HTML → badResponse', () {
      expect(
        ShowapiDrugLookup.parseResponse('<html>502</html>').status,
        LookupStatus.badResponse,
      );
    });

    test('缺少 res_body → badResponse', () {
      expect(
        ShowapiDrugLookup.parseResponse(jsonEncode({'showapi_res_code': 0}))
            .status,
        LookupStatus.badResponse,
      );
    });
  });

  group('1468-4 请求构造（官方 cURL 示例）', () {
    test('POST /1468-4，AppKey 在查询串，searchKey 在表单', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return jsonResponse(okBody());
      });

      final o = await ShowapiDrugLookup(appKey: 'k123', client: client)
          .lookupByName('阿司匹林');

      expect(o.ok, isTrue);
      expect(captured.method, 'POST');
      expect(captured.url.path, '/1468-4');
      expect(captured.url.queryParameters['appKey'], 'k123');
      expect(captured.bodyFields['searchKey'], '阿司匹林');
      expect(captured.bodyFields['page'], '1');
      expect(captured.bodyFields['maxResult'], '5');
      expect(captured.headers['content-type'], contains('x-www-form-urlencoded'));
    });

    test('药名两端空格会被清掉', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return jsonResponse(okBody());
      });
      await ShowapiDrugLookup(appKey: 'k', client: client)
          .lookupByName('  布洛芬  ');
      expect(captured.bodyFields['searchKey'], '布洛芬');
    });

    test('药名为空不发请求', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return jsonResponse(okBody());
      });
      final o = await ShowapiDrugLookup(appKey: 'k', client: client)
          .lookupByName('   ');
      expect(o.status, LookupStatus.invalidCode);
      expect(called, isFalse);
    });

    test('没有 AppKey 不发请求', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return jsonResponse(okBody());
      });
      final o = await ShowapiDrugLookup(appKey: '  ', client: client)
          .lookupByName('布洛芬');
      expect(o.status, LookupStatus.noKey);
      expect(called, isFalse);
    });

    test('HTTP 403 但响应体带 -1007 → 精确识别为未订购', () async {
      final client = MockClient((_) async => jsonResponse(
            jsonEncode({
              'showapi_res_code': -1007,
              'showapi_res_error': '没有订购套餐',
              'showapi_res_body': {},
            }),
            403,
          ));
      final o = await ShowapiDrugLookup(appKey: 'k', client: client)
          .lookupByName('布洛芬');
      expect(o.status, LookupStatus.notSubscribed);
    });

    test('HTTP 500 非 JSON → badResponse 且带状态码', () async {
      final client = MockClient((_) async => http.Response('err', 500));
      final o = await ShowapiDrugLookup(appKey: 'k', client: client)
          .lookupByName('布洛芬');
      expect(o.status, LookupStatus.badResponse);
      expect(o.message, contains('500'));
    });

    test('网络异常 → network', () async {
      final client = MockClient((_) async {
        throw http.ClientException('connection refused');
      });
      final o = await ShowapiDrugLookup(appKey: 'k', client: client)
          .lookupByName('布洛芬');
      expect(o.status, LookupStatus.network);
      expect(o.message, contains('connection refused'));
    });
  });
}
