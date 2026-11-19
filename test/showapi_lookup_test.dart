import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medicine_box/services/medicine_lookup.dart';
import 'package:medicine_box/services/showapi_lookup.dart';

/// 官方文档示例返回结构（精简版）
String okBody() => jsonEncode({
      'showapi_res_code': 0,
      'showapi_fee_num': 1,
      'showapi_res_error': '',
      'showapi_res_body': {
        'ret_code': 0,
        'remark': '查询成功',
        'name': '布洛芬缓释胶囊',
        'basis': '布洛芬',
        'spec': '0.3g*20粒',
        'purpose': '用于缓解轻至中度疼痛',
        'dosage': '一次1粒，一日2次',
        'taboo': '对本品过敏者禁用',
        'consideration': '饭后服用',
        'manuName': '某某制药有限公司',
        'approval': '国药准字H12345678',
        'type': 'OTC',
      },
    });

http.Response jsonResponse(String body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(body), status);

void main() {
  group('ShowapiLookup.parseResponse - 成功', () {
    test('解析出药名、成分、说明书全文', () {
      final o = ShowapiLookup.parseResponse(okBody());
      expect(o.ok, isTrue);
      expect(o.result!.name, '布洛芬缓释胶囊');
      expect(o.result!.ingredient, '布洛芬');
      expect(o.result!.category, 'OTC');
    });

    test('说明书由结构化字段拼成，便于全文搜索', () {
      final o = ShowapiLookup.parseResponse(okBody());
      expect(o.result!.leaflet, contains('功能主治：用于缓解轻至中度疼痛'));
      expect(o.result!.leaflet, contains('用法用量：一次1粒，一日2次'));
      expect(o.result!.leaflet, contains('禁忌：对本品过敏者禁用'));
      expect(o.result!.leaflet, contains('生产厂家：某某制药有限公司'));
    });

    test('空字段不会拼进说明书', () {
      final body = jsonEncode({
        'showapi_res_code': 0,
        'showapi_res_body': {
          'ret_code': 0,
          'name': '测试药',
          'basis': 'x',
          'spec': '',
          'taboo': 'null',
        },
      });
      final o = ShowapiLookup.parseResponse(body);
      expect(o.ok, isTrue);
      expect(o.result!.leaflet, isEmpty);
    });

    test('res_body 被序列化成字符串时也能解析', () {
      final inner = jsonEncode({'ret_code': 0, 'name': '测试药', 'basis': 'x'});
      final body = jsonEncode({
        'showapi_res_code': 0,
        'showapi_res_body': inner,
      });
      final o = ShowapiLookup.parseResponse(body);
      expect(o.result?.name, '测试药');
    });

    test('非药品分类能被识别', () {
      final body = jsonEncode({
        'showapi_res_code': 0,
        'showapi_res_body': {
          'ret_code': 0,
          'name': '皇后牌片仔癀珍珠膏',
          'type': '非药品',
        },
      });
      final o = ShowapiLookup.parseResponse(body);
      expect(o.result!.isNonMedicine, isTrue);
    });
  });

  group('ShowapiLookup.parseResponse - 失败分类', () {
    test('-1006「此应用无权调用本接口」→ notSubscribed，并给出订购指引', () {
      final body = jsonEncode({
        'showapi_res_code': -1006,
        'showapi_res_error': '此应用无权调用本接口',
      });
      final o = ShowapiLookup.parseResponse(body);
      expect(o.status, LookupStatus.notSubscribed);
      expect(o.message, contains('此应用无权调用本接口'));
      expect(o.hint, contains('订购'));
      expect(o.displayMessage, contains('66-24'));
    });

    test('-1007 没有订购套餐 → notSubscribed', () {
      final body = jsonEncode({
        'showapi_res_code': -1007,
        'showapi_res_error': '没有订购套餐',
      });
      expect(
        ShowapiLookup.parseResponse(body).status,
        LookupStatus.notSubscribed,
      );
    });

    test('-1004 appKey err → invalidKey（实测网关原文）', () {
      final body = jsonEncode({
        'showapi_res_code': -1004,
        'showapi_res_error': 'appKey err',
      });
      final o = ShowapiLookup.parseResponse(body);
      expect(o.status, LookupStatus.invalidKey);
      expect(o.message, contains('appKey err'));
    });

    test('-2 余额为 0 → quota', () {
      final body = jsonEncode({
        'showapi_res_code': -2,
        'showapi_res_error': '',
      });
      expect(ShowapiLookup.parseResponse(body).status, LookupStatus.quota);
    });

    test('ret_code 非 0 → 未收录，并带出 remark', () {
      final body = jsonEncode({
        'showapi_res_code': 0,
        'showapi_res_body': {'ret_code': -1, 'remark': '未查到该条码'},
      });
      final o = ShowapiLookup.parseResponse(body);
      expect(o.status, LookupStatus.notFound);
      expect(o.message, contains('未查到'));
    });

    test('showapi_res_code 非 0 → Key 无效，并带出原文', () {
      final body = jsonEncode({
        'showapi_res_code': 401,
        'showapi_res_error': 'appKey 无效',
      });
      final o = ShowapiLookup.parseResponse(body);
      expect(o.status, LookupStatus.invalidKey);
      expect(o.message, contains('appKey'));
    });

    test('余额/次数不足 → quota', () {
      final body = jsonEncode({
        'showapi_res_code': 400,
        'showapi_res_error': '调用次数已用完，请充值',
      });
      final o = ShowapiLookup.parseResponse(body);
      expect(o.status, LookupStatus.quota);
    });

    test('name 为空 → 未收录', () {
      final body = jsonEncode({
        'showapi_res_code': 0,
        'showapi_res_body': {'ret_code': 0, 'name': '', 'remark': '查询成功'},
      });
      final o = ShowapiLookup.parseResponse(body);
      expect(o.status, LookupStatus.notFound);
    });

    test('返回 HTML（网关拦截）→ badResponse', () {
      final o = ShowapiLookup.parseResponse('<html>502 Bad Gateway</html>');
      expect(o.status, LookupStatus.badResponse);
    });

    test('缺少 showapi_res_body → badResponse', () {
      final body = jsonEncode({'showapi_res_code': 0});
      final o = ShowapiLookup.parseResponse(body);
      expect(o.status, LookupStatus.badResponse);
    });
  });

  group('ShowapiLookup.lookup - 请求构造', () {
    test('POST 请求，AppKey 在查询串，code 在表单 body', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return jsonResponse(okBody());
      });

      final o = await ShowapiLookup(appKey: 'k123', client: client)
          .lookup('6906618188014');

      expect(o.ok, isTrue);
      expect(captured.method, 'POST');
      expect(captured.url.path, '/66-24');
      expect(captured.url.queryParameters['appKey'], 'k123');
      expect(captured.bodyFields['code'], '6906618188014');
      expect(captured.headers['content-type'], contains('x-www-form-urlencoded'));
    });

    test('编码里的空格会被清掉再发请求', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return jsonResponse(okBody());
      });
      await ShowapiLookup(appKey: 'k', client: client)
          .lookup(' 6906 6181 8801 4 ');
      expect(captured.bodyFields['code'], '6906618188014');
    });

    test('HTTP 500 → badResponse', () async {
      final client = MockClient((_) async => http.Response('err', 500));
      final o = await ShowapiLookup(appKey: 'k', client: client)
          .lookup('6906618188014');
      expect(o.status, LookupStatus.badResponse);
      expect(o.message, contains('500'));
    });

    test('没有 AppKey 时不发请求', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return jsonResponse(okBody());
      });
      final o =
          await ShowapiLookup(appKey: '   ', client: client).lookup('6906618188014');
      expect(o.status, LookupStatus.noKey);
      expect(called, isFalse);
    });

    test('不像条码的编码不发请求', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return jsonResponse(okBody());
      });
      final o = await ShowapiLookup(appKey: 'k', client: client).lookup('ABC-123');
      expect(o.status, LookupStatus.invalidCode);
      expect(called, isFalse);
    });

    test('网络异常 → network', () async {
      final client = MockClient((_) async {
        throw http.ClientException('connection refused');
      });
      final o = await ShowapiLookup(appKey: 'k', client: client)
          .lookup('6906618188014');
      expect(o.status, LookupStatus.network);
      expect(o.message, contains('connection refused'));
    });

    test('20 位追溯码仍然会请求（交给服务端判断）', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return jsonResponse(jsonEncode({
          'showapi_res_code': 0,
          'showapi_res_body': {'ret_code': -1, 'remark': '未查到该条码'},
        }));
      });
      final o = await ShowapiLookup(appKey: 'k', client: client)
          .lookup('81234567890123456789');
      expect(called, isTrue);
      expect(o.status, LookupStatus.notFound);
    });
  });
}
